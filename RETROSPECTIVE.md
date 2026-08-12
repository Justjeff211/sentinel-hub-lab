# Session Retrospective — 12 August 2026

## What this is

A single, long build session that took the network and identity layer from broken Terraform to a genuinely working lab: hub-and-spoke networking, a real Active Directory forest, a domain-joined member server, and a live telemetry pipeline into Log Analytics. This document is the honest close-out — what got built and verified, why it was torn down, and what the next phase would have looked like with more runway.

## What's real and verified, not just deployed

- **Network**: Hub VNet (Firewall, Bastion), Identity Spoke, Production Workloads spoke — all peered, all working.
- **Identity**: DC1 promoted to a real domain controller (`Get-ADDomain`, service checks, `Get-ADDomainController` all confirmed it). AADCONNECT domain-joined and verified with `nltest /sc_query` showing a healthy secure channel.
- **Telemetry**: A Log Analytics workspace, a Data Collection Rule correctly configured against Microsoft's own documented schema (`Microsoft-Event`, not the more intuitive-but-wrong `Microsoft-WindowsEvent`), and Azure Monitor Agent deployed to both Windows VMs.
- **Infrastructure as code**: Every fix — three separate real bugs, a remote state backend, the telemetry resources, a Production Workloads spoke with an Ubuntu VM — is committed and pushed. Cloning this repo fresh today gets you a working configuration, not a repeat of tonight's debugging.

## Why it's not staying up

Running Firewall, Bastion, and multiple VMs continuously costs real money — this is a self-funded lab, not something with a company card behind it. Leaving infrastructure running because it's *interesting* rather than because it's *actively being used* is exactly the kind of waste a real SOC would flag. So: `terraform destroy` once this session ended, same discipline the project's README already commits to ("stood up and torn down"). Confirmed clean — 37 resources destroyed, resource group gone, billing stopped.

## What I'd have built next, with more budget and time

The infrastructure was the prerequisite. The actual point of a SOC lab — detection, investigation, response — needs real attack activity to detect. Here's what that phase looks like, concretely:

**Scenario 1 — Brute-force detection.** A Kali box attempts repeated RDP/SSH logons against a workload VM. Suricata flags the connection pattern; Sysmon/Windows Security logs capture the failed logon attempts on the target. A Sentinel analytics rule correlates the two signals into a single incident, rather than two disconnected alerts.

**Scenario 2 — Living-off-the-land detection.** A foothold on a workload VM runs PowerShell to enumerate the domain. Sysmon Event ID 1 (process creation) captures the exact command line. The interesting part isn't detecting PowerShell running — it's writing a KQL query specific enough to catch *this* pattern without alerting on every legitimate admin script.

**Scenario 3 — Lateral movement toward the DC.** A compromised workload attempts LDAP enumeration or SMB connections toward DC1. Network flow logs plus AD auditing together show the movement — this is where the hub-and-spoke segmentation actually earns its place.

**Scenario 4 — DNS-based C2 or tunneling.** Zeek's `dns.log` shows abnormal query patterns from a workload — genuinely hard to fake convincingly and genuinely satisfying to hunt for by hand in KQL.

Each of these turns into a real `incidents/` write-up once actually run: what happened, how it was found, what the KQL looked like, what the response would be.

## What's still genuinely unresolved

- **AMA service registration** — the extension reports success on both Windows VMs, but the underlying Windows service never actually starts. Documented in `incidents/2026-08-12-first-deployment.md`. A known pattern, not something wrong with the Terraform or DCR config (both verified correct).
- **Zeek/Suricata on the Ubuntu workload** — installed but not fully configured/verified before the session closed.
- **No Kali attacker yet** — every scenario above needs something actually generating the activity to detect.

## The honest summary

This session was mostly debugging, not building — three real Terraform bugs, a state backend built from scratch mid-session, an AMA quirk that never fully resolved. That's a genuine reflection of what infrastructure-as-code work actually looks like, not a polished tutorial where everything works first try. The project's own philosophy says it plainly: *Build → Test → Break → Investigate → Fix → Document.* Tonight was that cycle, repeated more times than planned, ending in something real rather than something abandoned.
