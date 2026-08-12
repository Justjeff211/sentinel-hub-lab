# Everything Not Yet Built — A Beginner's Walkthrough

This is a plain-language guide to every piece of the architecture that's still missing, why it matters, and what actually building it would involve. Written for someone who wasn't in the weeds of tonight's session and might not already know these tools.

---

## Kali Linux (the attacker)

**What it is:** A Linux distribution built specifically for security testing — it comes with hundreds of pre-installed tools for scanning networks, cracking passwords, and simulating attacks (Nmap, Hydra, Metasploit, and dozens more).

**Why it matters here:** Without something actively generating attack-like activity, Sentinel would just be watching silence — there'd be nothing for any of the detection tooling to actually catch. Kali's job in this lab isn't to be a real threat; it's a controlled traffic generator, entirely contained within the lab's own private network.

**What building it takes:** Deploy another VM, same pattern as `vm-ubuntu` — a new NIC, a VM resource in Terraform, network access via Bastion. Then deliberately run things like a brute-force login attempt against the Ubuntu workload, or a port scan against the hub, and watch whether the rest of the pipeline actually notices.

---

## Sysmon

**What it is:** A free Microsoft tool (part of "Sysinternals") that installs on a Windows machine and logs far more detail than Windows tracks by default — every process that starts, every network connection made, every file created, every registry key changed. Normal Windows event logs are comparatively shallow; Sysmon is what actually lets someone reconstruct exactly what a machine did.

**Why it matters here:** The Data Collection Rule built tonight is already configured to pull from Sysmon's log channel — but Sysmon itself, the actual software, was never installed on any VM. It's like wiring a room for a smoke detector and never mounting the detector.

**What building it takes:** Download Sysmon from Microsoft's Sysinternals page, install it with a solid baseline configuration (the community-maintained "SwiftOnSecurity" config is the standard starting point most people use), and it immediately starts writing to `Microsoft-Windows-Sysmon/Operational` — which the DCR is already set up to collect from. This is genuinely one of the smaller remaining pieces.

---

## Zeek and Suricata — installed, not yet verified or wired up

**What each does:** Zeek watches network traffic and writes a detailed diary of what it saw — a DNS lookup, a web request, an SSH connection — without necessarily judging any of it as "bad." Suricata is different: it's an Intrusion Detection System that compares traffic against a huge library of known attack signatures and raises alerts when something matches. Zeek tells the story; Suricata flags the dangerous parts of it.

**Where it stands:** Install commands were run against `vm-ubuntu` tonight, but the session ended before confirming both actually installed correctly.

**What's still needed beyond that:** Even once confirmed installed, their logs don't automatically reach Log Analytics — tonight's DCR only collects *Windows* Event Logs. Getting Zeek/Suricata data into the same pipeline needs a second, Linux-specific Data Collection Rule and the Linux version of Azure Monitor Agent — genuinely new Terraform work, not just a leftover step.

---

## Microsoft Sentinel

**What it actually is:** Sentinel isn't a separate resource deployed from scratch — it's a set of extra capabilities turned on *on top of* an existing Log Analytics workspace. Right now, `law-soc-hub-lab` is just a plain log warehouse; Sentinel has never been switched on over it.

**What it adds once enabled:** Analytics rules (automated KQL queries that scan incoming logs and create incidents when something matches), a proper incident-investigation interface, workbooks for visual dashboards, and the ability to pull in Microsoft's own threat intelligence.

**What building it takes:** In the Azure Portal, search "Microsoft Sentinel" → Create → point it at the existing workspace. Genuinely a few clicks — deliberately left undone tonight because turning it on without immediately building real analytics rules behind it isn't especially useful, and that's a session in itself.

---

## Microsoft Defender XDR

**What it is:** A separate Microsoft product family (Defender for Endpoint, Defender for Identity, and others) that generates its own detection signals using Microsoft's own threat intelligence — richer than what you'd get from just querying raw logs yourself. These signals can feed into Sentinel alongside your own data.

**Why it's a bigger separate step:** Defender products need licensing/enablement at the tenant level, and endpoint protection specifically needs its own agent installed per VM — a genuinely separate onboarding flow from anything built tonight.

---

## Storage Account and Logic Apps

**Storage Account:** Cheap, durable storage. In a SOC context, this is typically where you export older logs for cheap long-term retention once they age out of Log Analytics (which is fast to query but not cheap to hold years of data in), or where incident evidence gets archived.

**Logic Apps:** Azure's no-code automation tool. In a Sentinel context, these are called "Playbooks" — for example, "when a high-severity incident is created, automatically post to Teams" or "automatically disable the compromised account." This is the *Response* step of the whole pipeline.

**Why neither exists yet:** There's nothing yet to automate a response *to* — no active detections are happening, since Sentinel isn't on and nothing is generating attacks. Both are meaningful only once the rest of the chain exists.

---

## Actual KQL hunting

**What it is:** The query language used to search through everything sitting in Log Analytics — similar in spirit to SQL, but purpose-built for fast searching across huge volumes of time-stamped log data.

**Where it stands:** The only query run tonight (`Heartbeat | take 10`) was a connectivity check, not real threat hunting.

**What real hunting looks like:** Once Sysmon/Zeek/Suricata are genuinely producing data, queries like "show every process spawned from Word or Excel in the last 24 hours" (a classic way to catch malicious macro documents) or "show failed logons followed by a success within 5 minutes from the same source" (a classic brute-force pattern) become possible — and genuinely interesting to write by hand.

---

## Detection, Investigation, Response — the whole planned workflow

These three stages, laid out in the README's own roadmap, don't exist yet as concrete work, because each depends on the layer below it:

- **Detection** needs Sentinel turned on, with real analytics rules written against real telemetry.
- **Investigation** needs actual incidents to have fired, so there's something to pivot through and build a timeline around.
- **Response** needs Logic Apps playbooks, which only make sense once there's something worth automating a response to.

None of it is hard individually — it's sequential. Each piece unlocks the next.

---

## Windows 11 endpoint and a standalone Windows Server

The architecture diagram lists these separately from DC1 and AADCONNECT, which are identity-layer infrastructure, not user-facing machines. A Windows 11 VM specifically matters because it represents what a real employee's desktop looks like — and the kinds of attacks that target a workstation (phishing, malicious downloads, macro documents) look meaningfully different from attacks against a server. Neither was built tonight; Ubuntu is currently the only genuine "workload" in the lab.

---

## A real network-wide sensor, not just host-based monitoring

Tonight's Zeek/Suricata setup, once verified, only sees traffic *to and from the Ubuntu VM itself* — not the network as a whole. A proper network-wide sensor needs Azure's Virtual Network TAP feature (which mirrors traffic from other VMs' network interfaces to a monitoring VM) plus route tables to actually direct traffic through it. This is a real architectural step up in complexity from what exists now, and was deliberately scoped out of tonight's build.

---

## The honest shape of what's left

Everything above builds on everything before it — network, then identity, then telemetry, then detection tooling, then actual attacks to detect, then Sentinel to catch them, then automation to respond. Tonight covered the first two layers solidly and made a real start on the third. The rest is genuinely a second project's worth of work, not a small addition — which is exactly why it's written down here rather than rushed through at the end of an already long session.
