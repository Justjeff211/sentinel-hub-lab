# First deployment: network + identity layer

**Date:** 12 August 2026
**Scope:** Hub-and-spoke network, Azure Firewall, Bastion, VPN Gateway, DC1, AADCONNECT

## What I set out to do

Run `terraform apply` for the first time against the network and identity Terraform, then promote DC1 to a domain controller and domain-join AADCONNECT — the first real infrastructure this project has stood up, not just designed.

## What actually happened

The plan looked clean (24 resources, reviewed before applying), but `apply` surfaced three separate real bugs, one after another:

**1. VPN Gateway public IP — zone configuration error**
`ZRStandardIpNeeded: Standard IP Address requires zones configured.` My first fix (switching the IP to Basic SKU) turned out to be based on stale information — Azure retired Basic SKU public IPs for new deployments back in March 2025. The actual fix: keep the IP on Standard SKU, but explicitly set `zones = ["1", "2", "3"]` rather than leaving it unset. South Africa North does support Availability Zones, which is what made this fixable.

**2. VM size — capacity, then quota**
`Standard_B2ms` came back `SkuNotAvailable` — genuinely out of stock in this region for that SKU. Tried `Standard_D2s_v3`, then `Standard_D2s_v5` — both failed too, the second one on a *different* error: `OperationNotAllowed... Current Limit: 0` — a quota problem, not a stock problem. Used `az vm list-skus` and `az vm list-usage` to check both capacity *and* quota properly instead of guessing a third time, and found `Standard_DS2_v2` had both: no stock restriction, and existing quota headroom on the subscription. That's what finally deployed successfully.

**3. Credential entry**
Multiple rounds of `admin_password` failing Azure's complexity check, and one case where a long password ended up in the `admin_username` field instead — Windows local usernames have a 20-character limit and no complexity requirement, so a long complex string in that field fails outright.

## Fixes, verified and committed

Both real fixes (VPN Gateway zones, VM size) are now the actual defaults in `terraform/main.tf` and `terraform/variables.tf` — pushed to `main`, so this shouldn't repeat on a future deployment in this region.

## Second pass: clean deploy

With both fixes in place, `terraform apply` completed cleanly: 24 resources, 0 errors. Firewall (~7 min), Bastion (~10 min), and the VPN Gateway (~14 min, the slowest piece both nights) all built successfully.

## Identity layer: built and verified

- **DC1 promoted** via `Install-ADDSForest` — verified with `Get-ADDomain`, `Get-Service DNS,NTDS,Netlogon` (all running), and `Get-ADDomainController -Filter *` (confirmed IP matches Terraform's static assignment).
- **AADCONNECT domain-joined** to `sentinelhub.local` — verified with `Get-CimInstance Win32_ComputerSystem` (`PartOfDomain: True`) and `nltest /sc_query` (`NERR_Success`, trusted DC correctly identified).

Bastion login also failed intermittently on both VMs even with a freshly-reset password — fixed by using `.\Justjeff` (explicit local-account prefix) instead of just `Justjeff`.

## Cost management

Realised partway through that the VPN Gateway wasn't actually being used for anything (no site-to-site or point-to-site connection configured) and was the single most expensive idle resource in the stack. Removed it directly via `az network vnet-gateway delete` / `az network public-ip delete` once the identity work was done, rather than leaving it running unused.

## What I'd do differently next time

- Set `terraform.tfvars` immediately, before the first `plan` — avoids retyping credentials at every interactive prompt.
- Check `az vm list-skus` *and* `az vm list-usage` before picking a VM size, not after a failure.
- Cloud Shell sessions are ephemeral — don't assume `terraform.tfstate` survives a disconnect; treat every new session as potentially starting from zero.

## Known open issue: AMA service not registering on Windows VMs

The `AzureMonitorWindowsAgent` extension reports `Succeeded` at the Azure control-plane level on both DC1 and AADCONNECT, and the extension's own status file confirms `"status":"success"` — but `Get-Service -Name AzureMonitorAgent` finds no such service on either VM, and no local agent logs are being written under `C:\Resources\Azure Monitor Agent`.

Tried:
- Rebooting both VMs, then reinstalling the extension fresh (via `az vm extension delete` + `terraform apply`) — no change.
- Checked for the service under alternate names — nothing matching.
- Confirmed the extension's package files exist on disk (`C:\Packages\Plugins\Microsoft.Azure.Monitor.AzureMonitorWindowsAgent`) — they do.

This matches a documented pattern (not unique to this lab) where the AMA installer executable exits cleanly without the underlying Windows service ever actually registering — the ARM-level "success" only confirms the installer ran, not that the agent is functioning.

Not currently blocking anything else — DC1, AADCONNECT, the domain, and the rest of the infrastructure are all working correctly. The Terraform and DCR configuration are confirmed correct (verified against Microsoft's own documented example). Left open for a future session rather than continuing to troubleshoot live tonight.
