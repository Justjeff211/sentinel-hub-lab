# Sentinel Hub Lab

A small hub-and-spoke network in Azure that I built to get properly hands-on with SOC work rather than just reading on it.

## What this actually is

I wanted somewhere I could watch real attack traffic and see whether Sentinel actually catches it and not just read on detection engineering but build and tune it myself. So this is a hub-and-spoke VNet sitting in Azure's South Africa North region with a domain controller, a handful of Windows and Linux endpoints and a Kali box that sits there generating the kind of noise a SOC actually has to deal with. Everything gets logged through Sysmon, Zeek and Suricata, funnelled into Log Analytics and surfaced through Microsoft Sentinel and Defender XDR. The whole thing is stood up (and torn down) with Terraform, run through GitHub Actions, so I'm not clicking through the Azure portal every time I want to rebuild it.

## Architecture

​```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart LR

    %% ===========================
    %% External
    %% ===========================
    Internet((Internet))
    GitHub[GitHub]
    Entra[Microsoft Entra ID]

    %% ===========================
    %% Azure Subscription
    %% ===========================
    subgraph Azure["Azure Subscription - South Africa North"]

        %% -----------------------
        %% Hub Network
        %% -----------------------
        subgraph Hub["Hub VNet (10.10.0.0/24)"]

            Bastion[Azure Bastion]
            Firewall[Azure Firewall]
            Gateway[VPN Gateway]
            Mgmt[Shared Management Subnet]

        end

        %% -----------------------
        %% Identity
        %% -----------------------
        subgraph Identity["Identity Spoke"]

            DC1[Windows Server<br/>Active Directory]
            DNS[DNS]
            AADConnect[Entra Connect]

        end

        %% -----------------------
        %% SOC
        %% -----------------------
        subgraph SOC["SOC Tools Spoke"]

            Sentinel[Microsoft Sentinel]
            LAW[Log Analytics]
            Defender[Microsoft Defender XDR]
            Storage[Storage Account]
            Automation[Logic Apps]
            KQL[KQL Analytics]

        end

        %% -----------------------
        %% Workloads
        %% -----------------------
        subgraph Workloads["Production Workloads"]

            Win11[Windows 11 Endpoint]
            WinServer[Windows Server]
            Ubuntu[Ubuntu Server]
            Kali[Kali Attacker]

        end

        %% -----------------------
        %% Monitoring
        %% -----------------------
        subgraph Monitor["Network Monitoring"]

            AMA[Azure Monitor Agent]
            Sysmon[Sysmon]
            Zeek[Zeek]
            Suricata[Suricata]
        end

    end

    %% ===========================
    %% CI/CD
    %% ===========================
    subgraph DevOps["Infrastructure as Code"]

        Terraform[Terraform]
        Actions[GitHub Actions]

    end

    %% ===========================
    %% Connections
    %% ===========================

    Internet --> Firewall
    Firewall --> Hub

    Hub --> Identity
    Hub --> SOC
    Hub --> Workloads
    Hub --> Monitor

    Bastion --> WinServer
    Bastion --> DC1
    Bastion --> Ubuntu

    Win11 --> AMA
    WinServer --> AMA
    Ubuntu --> AMA

    AMA --> LAW
    Sysmon --> LAW
    Zeek --> LAW
    Suricata --> LAW

    LAW --> Sentinel
    Defender --> Sentinel
    KQL --> Sentinel

    DC1 --> AADConnect
    AADConnect --> Entra

    GitHub --> Actions
    Actions --> Terraform
    Terraform --> Azure
​```

GitHub renders Mermaid in Markdown, so this diagram just shows up as-is on the repo page ...nothing else to install to view it.

## What's in each part

**Hub VNet (10.10.0.0/24)** is the centre of it all ...Azure Firewall and Bastion sit here along with the VPN Gateway and a management subnet, so nothing gets to the rest of the network without going through them first.

**Network Monitoring** is where Suricata, Zeek and Sysmon quietly watch everything and pass it along to the Azure Monitor Agent.

**Production Workloads** is what I'm defending; a Windows 11 endpoint, a Windows Server and an Ubuntu box, alongside a Kali VM that generates attack traffic against them so there's something real for Sentinel to pick up.

**Identity Spoke** is a small on-prem-style setup: a domain controller running AD DS and DNS, synced up to Microsoft Entra ID via Entra Connect.

**SOC Tools Spoke** is where it all lands; Log Analytics feeds Microsoft Sentinel and Defender XDR, with KQL Analytics for hunting, and a Storage Account plus Logic Apps handling retention and automation.

**Infrastructure as Code** is just GitHub Actions running Terraform against the subscription whenever I push a change.


## If you want to change the diagram

Edit `diagrams/architecture.mmd` directly. You can paste it into the [Mermaid Live Editor](https://mermaid.live) to preview before committing or just push to `main` ...the GitHub Action will render it to SVG and PNG automatically.

## Licence

See [LICENSE](./LICENSE).
