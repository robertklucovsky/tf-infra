# Home-lab security risk assessment — design / spec

**Date:** 2026-07-14
**Repo:** `tf-platform` (shared platform infrastructure)
**Status:** Draft for review
**Author:** Robert Klucovsky (with Claude)

> **Revision (2026-07-14):** Added *Current operational state* — the OpenStack /
> Ceph / Juju cluster (9 servers, 10G/40G switches) is currently powered off;
> only `cwwk` + the MAAS/Omada box + switches are live. Scenario 2 now separates
> current-state from latent (powered-on) blast radius.

## Goal

Produce a security risk assessment of the home lab as reached through the
TP-Link ER605 perimeter, evaluated in **two access scenarios**:

1. **Without WireGuard** — a client from the internet, which per the perimeter
   should reach only the ports the router exposes.
2. **With WireGuard** — an authorized WireGuard client, plus the
   **compromised/lost-client** sub-case (stolen laptop or leaked peer key).

The deliverable is a single **assessment report** (threat-model style, approach
"A + part B"): scenario-driven attack-path analysis as the core, with a
CIS-style hardening checklist appended for tracking over time. This document is
the **design/spec** for that report — scope, methodology, the verified baseline
that grounds it, and the report's structure. The report itself is authored in
the implementation step that follows.

## Deliverable parameters

- **Report file:** `docs/security/2026-07-14-home-lab-risk-assessment.md`
  (new `docs/security/` directory).
- **Report language:** Slovak (matches the operator). Technical terms in English.
  Changeable during spec review.
- **Format:** Markdown. Findings tagged `[verified]` or `[assumption]`.

## Scope

### In scope

- The two access scenarios above, including the compromised-client sub-case.
- The perimeter enforcement on the ER605 (port-forwarding, NAT, WireGuard,
  VLANs, ACL/firewall).
- The Kubernetes node `172.16.1.11` (`cwwk`): host firewall posture, listening
  services, NodePorts, control-plane exposure, NFS.
- Internet-exposed applications served via the in-cluster Cilium Gateway on
  `*.klucovsky.com`, and their authentication posture.
- Network segmentation across VLAN 1 / 10 / 20.
- **MAAS + Omada controller box (`172.16.1.2`)**, managed bare-metal servers,
  and BMC/IPMI — assessed for **reachability, criticality, and blast radius**
  (full inclusion per operator decision). The 9 managed bare-metal servers are
  **currently powered off** (see Current operational state); assessed as latent
  blast radius.
- OpenStack (VLAN 10) and Ceph (VLAN 20) — assessed for **reachability and
  blast radius** only (see out-of-scope for their internals). **Currently
  powered off / no live hosts** — treated as latent blast radius.

### Out of scope (noted, not audited in depth)

- Internal vulnerability audit of OpenStack and Ceph components (separate
  follow-up). We assess that they are reachable and what their compromise means,
  not their internal CVEs/config.
- Source-code audit of individual exposed applications. We assess exposure and
  authentication, not application logic.
- Wi-Fi and physical security.
- Container image supply-chain (brief mention only).
- DigitalOcean cloud account/DNS security beyond how it affects exposure.

## Methodology

- **Attack-path analysis per scenario** (attacker-goal oriented): for each
  scenario, enumerate the reachable attack surface, walk concrete attack paths,
  state impact, rate risk, and give remediation.
- **Risk rating:** Likelihood × Impact → **Critical / High / Medium / Low**.
  - Likelihood considers exposure, authentication, exploit availability, and
    (for scenario 2) the realism of client/key compromise.
  - Impact considers data loss, control-plane/infra takeover, and blast radius.
- **Evidence tagging:** every finding is `[verified]` (confirmed this
  engagement — Omada read-only API, node SSH, TCP connect tests) or
  `[assumption]` (stated, with what would confirm it).

## Verified environment baseline

All facts below were verified during this engagement unless marked otherwise.
Sources: Omada controller read-only API (`172.16.1.2:8043`), read-only SSH to
`cwwk`, and TCP connect tests from the node.

### Current operational state (2026-07-14)

The lab is currently a **scaled-down** version of a larger private cloud that is
powered off:

- **Live now:** only `cwwk` (`172.16.1.11`, the k8s node), the combined
  MAAS + Omada box (`172.16.1.2`), and the Omada-managed switches.
- **Powered off:** the OpenStack / Ceph / Juju cluster — 9 servers (6× HP
  ProLiant DL3xx + 3 unbranded), plus a 10 GbE switch and a **40 GbE switch not
  managed by the Omada controller** (hence absent from this recon).
- **VLAN 10 (OpenStack, `172.16.2.0/24`) and VLAN 20 (Ceph, `172.16.3.0/24`)
  therefore have no live hosts right now** — routed and unfiltered by config, but
  currently empty.

The report distinguishes **current-state** risk (what is live and reachable
today) from **latent / designed-state** risk (the blast radius that returns when
the full cloud is powered back on). The flat-network / no-ACL findings apply to
both; the difference is how many hosts are exposed.

### Perimeter — TP-Link ER605 (`172.16.1.1`, firmware 2.3.3)

- WAN1: DHCP public IPv4; **IPv6 disabled on WAN**. Second port WAN/LAN2.
- **Port forwarding (the entire inbound internet surface):**
  - TCP **80** → `172.16.1.11:80`
  - TCP **443** → `172.16.1.11:443`
  - No other rules. No DMZ. No one-to-one NAT.
- **WireGuard** runs on the ER605 as a **Site-to-Site VPN** (name `RACK`,
  enabled), used for remote access:
  - Listen port **UDP 51820** (bound on the router's WAN — needs no
    port-forward, which is why 51820 is absent from the NAT table).
  - Tunnel subnet `10.172.16.0/24`, router `10.172.16.1`, MTU 1420.
  - 3 peers, each pinned to a `/32`: MacBook `10.172.16.2`, Motorola
    `10.172.16.3`, MacBookProM5 `10.172.16.4`; keepalive 25; roaming (no static
    endpoint). Peers are personal end-user devices.
  - Note: the device reports `serverClientWireguard: false`; road-warrior access
    is implemented via the site-to-site feature with per-client `/32` peers.
- **VLANs / subnets (all with `isolation=false`):**
  - VLAN 1 "Default" → `172.16.1.0/24` (k8s node, MAAS/Omada, switches)
  - VLAN 10 "OpenStack VLAN" → `172.16.2.0/24`
  - VLAN 20 "Ceph VLAN" → `172.16.3.0/24`
- **Gateway ACL: disabled, 0 rules.** No inter-VLAN filtering; the network is
  flat and freely routed between all three subnets.
- Router DHCP disabled on all VLANs (MAAS serves DHCP). ALG for
  FTP/H323/PPTP/SIP/IPsec enabled (defaults).

### WireGuard client reach (scenario 2 ground truth)

The per-peer `/32` "Allowed Address" on the router only pins each client's
tunnel source IP; it does **not** restrict LAN destinations. With no ACL and a
flat routed network, an authorized WireGuard client can reach **all three
subnets on all ports** — the entire lab. The only client-side limit is each
client's own `AllowedIPs`, which the router does not enforce.

### Node `172.16.1.11` (`cwwk`)

- Ubuntu 24.04 (kernel 6.8), cloud-init/MAAS-provisioned; Canonical Kubernetes
  (`k8s-snap`) with **Cilium** (eBPF, kube-proxy replacement) and MetalLB.
- **Host firewall: none** — `ufw inactive`, iptables `INPUT` policy `ACCEPT`.
- DNS: `172.16.1.2` (MAAS) + `8.8.8.8`; search domains `klucovsky.com`,
  `fatto.online`.
- **Reachable from LAN/VPN (verified open via TCP connect):**
  - `22` SSH, `6443` k8s API, `10250` kubelet, `2379`/`2380` etcd,
    `9100` node_exporter, `4244` Hubble.
  - `2049` NFS, `111` rpcbind.
  - NodePorts: `30432` **PostgreSQL (plaintext, `sslmode=disable`)**,
    `30910`/`30911` RustFS (S3/console), `30417`/`30418` Tempo OTLP.
- **NFS export:** `/data` exported to `10.172.16.0/24` (WireGuard tunnel) **and**
  `172.16.1.0/24` (LAN). The VPN subnet is explicitly trusted for storage.

### `172.16.1.2` — combined MAAS + Omada box

- **MAAS** (region+rack): DNS `53`, API `5240`, HTTPS `5443`, proxy `3128`.
  Controls bare-metal provisioning (PXE, re-image, commissioning) and typically
  BMC/IPMI power control; also serves DHCP and internal DNS.
- **Omada controller** `8043` (manages the ER605 and switches — i.e., the
  network control plane), plus SSH `22`.
- Single-host concentration of provisioning + network control + DHCP/DNS =
  highest-value target; fully reachable from VPN.

### Switches (management reachable on LAN/VPN)

- SX3016F `172.16.1.24`, TL-SG2428P `172.16.1.23`, SG3210X-M2 `172.16.1.25`.

### Internet-exposed applications (via in-cluster Cilium Gateway)

TLS is terminated **in-cluster** (wildcard `*.klucovsky.com`, Let's Encrypt
production); the router only forwards TCP 80/443 to the node. Hostnames →
backends and auth posture (from repo; auth behavior `[assumption]` pending
per-app confirmation):

- SSO via Keycloak (`auth.klucovsky.com`): **only RustFS** (`s3.klucovsky.com`).
- Standalone auth: ArgoCD, Grafana, pgAdmin (`db`), Nexus, Zot (`registry`).
- **No authentication:** Mailpit (`mail`), Prometheus, Alertmanager.
- Keycloak runs in **`start-dev`** mode.
- `fatto-aac.klucovsky.com` is a 302 redirect into the RustFS OIDC flow.

## Report structure (the assessment document)

1. **Executive summary** — headline risks for both scenarios and top priorities,
   one page.
2. **Verified environment baseline** — the facts above, condensed, as the
   agreed ground truth (perimeter, VLANs/ACL, WireGuard, node exposure, MAAS,
   exposed-app auth matrix).
3. **Scenario 1 — without WireGuard (internet-facing):** attack surface
   (TCP 80/443 → Cilium/Envoy → apps; Keycloak `start-dev`; TLS; the UDP 51820
   WireGuard listener on the router), attack paths (unauthenticated
   Prometheus/Alertmanager/Mailpit; brute-force on standalone logins; known-CVE
   surface of exposed versions; gateway/Envoy exposure), risk ratings.
4. **Scenario 2 — authorized WireGuard client (+ compromised client):** what the
   tunnel grants (full L3 to all subnets), attack paths (plaintext Postgres
   30432; k8s API/kubelet/etcd; NFS `/data` mount; other NodePorts; MAAS/Omada
   box takeover incl. BMC/provisioning and network-control; switch management;
   lateral movement to OpenStack/Ceph **when powered on**), **current vs latent**
   blast radius on key/device compromise, risk ratings.
5. **Cross-cutting findings** — no network segmentation despite VLANs; single
   box concentrating MAAS+Omada+DNS/DHCP; plaintext Postgres; no auth on
   monitoring; Keycloak dev mode; no host firewall; secrets in exposed etcd;
   VPN peers are personal roaming devices; NFS export scope.
6. **Prioritized remediations** — P1/P2/P3.
7. **Appendix A — Authentication matrix** of exposed services.
8. **Appendix B — CIS-style hardening checklist** (network segmentation & ACL,
   VPN least-privilege `AllowedIPs`, host firewall, NodePort exposure,
   plaintext/TLS, k8s control-plane exposure, exposed-app authn, Keycloak prod
   mode, MAAS/BMC hardening, NFS export scoping, secrets management, monitoring)
   with pass/fail/NA.

## Scenario definitions (precise)

- **Scenario 1 (no VPN):** attacker on the internet with knowledge of the public
  IP and hostnames, no WireGuard credentials. Reachable: TCP 80/443 to the
  in-cluster gateway (all `*.klucovsky.com` apps) and UDP 51820 (WireGuard,
  authenticated by key — silent to unauthenticated probes). Goal: gain a foothold
  or exfiltrate data via the exposed HTTP apps.
- **Scenario 2 (authorized VPN client):** possesses a valid WireGuard peer key.
  Reachable: full L3 to `172.16.1.0/24`, `172.16.2.0/24`, `172.16.3.0/24` on all
  ports; NFS `/data`. **Today** only `172.16.1.0/24` has live hosts (`cwwk`,
  MAAS/Omada, switches); the OpenStack/Ceph subnets are routable but currently
  empty. Sub-case **compromised client**: an attacker who obtains a peer key or a
  peer device — same reach, adversarial intent. Current blast radius = `cwwk`
  (incl. k8s control plane, etcd, NFS `/data`, plaintext Postgres) + the
  MAAS/Omada control box + switches; **latent blast radius = the whole private
  cloud** once the 9 servers / OpenStack / Ceph are powered back on.

## Open items / assumptions

- **Per-app authentication behavior** of the exposed apps is taken from repo
  config `[assumption]`; the report will confirm the high-impact ones
  (unauthenticated Prometheus/Alertmanager/Mailpit) where feasible.
- **BMC/IPMI network:** no dedicated out-of-band VLAN was observed (only VLAN
  1/10/20). The report assumes BMCs are reachable on a routed subnet unless the
  operator confirms otherwise `[assumption]`.
- **OpenStack/Ceph host inventory** was not enumerated and is **currently
  powered off**; the report treats their subnets as routable and unfiltered
  `[verified: routing/ACL]`, empty today `[verified: operator + no live hosts]`,
  and a latent blast radius when powered on.
- **Exact exposed software versions/CVEs** will be gathered during report
  authoring where accessible.

## Success criteria

- Both scenarios have an explicit, evidence-tagged attack-surface map and at
  least the concrete attack paths listed above, each with a risk rating.
- Every material claim is `[verified]` or a clearly labelled `[assumption]`.
- A prioritized remediation list (P1/P2/P3) and a reusable CIS-style checklist
  are included.
- The report is understandable to the operator and actionable without further
  reconnaissance.
