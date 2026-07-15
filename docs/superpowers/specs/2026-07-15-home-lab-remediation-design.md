# Home-lab security remediation — design / spec

**Date:** 2026-07-15
**Repo:** `tf-platform` (shared platform infrastructure)
**Status:** Draft for review
**Author:** Robert Klucovsky (with Claude)
**Source assessment:** `docs/security/2026-07-14-home-lab-risk-assessment.md`

## Goal

Implement the remediations from the risk assessment that can be applied safely,
across three subsystems: in-repo Terraform (cluster), the Omada network, and the
`cwwk` host. The organizing principle is the operator's chosen exposure model:
**only `s3` + `auth` + `fatto-aac` (and the WireGuard endpoint) are reachable
from the internet; every other service is intranet-only (LAN/VPN).**

## Decisions (locked)

- **Exposure model:** internet-public = `s3.klucovsky.com`, `auth.klucovsky.com`,
  `fatto-aac.klucovsky.com`, WireGuard UDP 51820. Everything else LAN/VPN-only.
- **Domain naming:** keep `*.klucovsky.com` for both internal and public
  services, separated by split-horizon DNS (MAAS internal + DigitalOcean public).
  No new subdomain, no `.local` (reserved TLD; no public CA issues certs for it;
  mDNS conflicts). Internal services already have publicly-trusted certs via the
  existing Let's Encrypt wildcard.
- **Enforcement mechanism:** a two-gateway split (below), **not** source-IP
  filtering — the terminating gateway cannot see the client source IP because the
  front gateway does TLS passthrough (new TCP connection to the backend), so
  per-route source-IP ACLs there are not viable.
- **Host firewall on `cwwk`: out of scope** — raw nft/ufw on a Cilium node risks
  iptables conflicts and SSH lockout; its goal (containing VPN → node) is met by
  the network-layer VPN ACL instead.
- **Apply authorization:** the agent applies Terraform (`plan` → review →
  `apply`), NFS changes via SSH, and Omada changes via API — all with safeguards.
  The operator verifies VPN from a real peer after the network changes.
- **Basic-auth for Prometheus/Alertmanager/Mailpit is dropped** — once those apps
  are internet-unreachable (intranet-only), per-app auth is not required for P1.

## Verified enabling facts (2026-07-15)

- MetalLB pool `172.16.1.11–172.16.1.13`; **`.12` is free** (`.11` = front,
  `.13` = terminating). `[verified: kubectl]`
- Router currently forwards TCP 80/443 → `172.16.1.11`. `[verified: Omada]`
- Cluster reachable (context `k8s`, `cwwk` Ready, k8s v1.32); Terraform v1.15.5;
  `terraform.tfvars` + `secrets.auto.tfvars` present locally. `[verified]`
- **State backend is currently `local`** (temporarily migrated off `pg` for a
  teardown that did not complete — platform is running). First action is
  `terraform init` + `plan` to confirm no drift before any apply. `[verified: main.tf]`
- k8s API/kubelet/etcd enforce auth; NFS `/data` is `rw,root_squash,all_squash,
  insecure` to LAN + VPN. `[verified: earlier recon]`
- Operator needs over VPN: internal web apps (443), SSH (22), k8s API (6443),
  Postgres NodePort (30432, for Terraform), **and NFS**. `[operator]`

## Architecture — two-gateway split

- **New public gateway** on **`172.16.1.12`**: a terminating gateway (HTTP :80
  redirect + HTTPS :443 terminate, reusing the `klucovsky-wildcard-tls` secret)
  that serves HTTPRoutes for **only** `s3`, `auth`, `fatto-aac`. Any other Host →
  404. This is a standard terminating gateway on its own MetalLB IP; it does not
  need the passthrough/relay bridge.
- **Router repoint:** change the Omada port-forward 80/443 target from
  `172.16.1.11` → `172.16.1.12`. This is the single cutover and is trivially
  reversible.
- **Existing gateway path (`.11` front → relay → `.13` terminating, all hosts)
  is left untouched** and becomes intranet-only: once the router no longer
  forwards to `.11`, internal apps are unreachable from the internet. Internal
  clients (MAAS DNS `*.klucovsky.com` → `172.16.1.11`) keep working exactly as
  now.
- **DNS unchanged:** DigitalOcean keeps only `s3/auth/fatto-aac/vpn`; MAAS keeps
  `*.klucovsky.com → 172.16.1.11`.
- `s3`/`auth`/`fatto-aac` HTTPRoutes gain the public gateway as an additional
  `parentRef` (so they serve on both the internal path and the public gateway);
  all other routes remain attached only to the internal gateway.

Why this is low-risk: the internal path is untouched (internal access cannot
break from this change); the public gateway is additive; the only cutover is one
reversible port-forward edit.

## Workstreams

### A. In-repo Terraform (agent applies: `plan` → review → `apply`)

- **A1 — Public gateway + routes.** New Gateway on `.12` + attach `s3`/`auth`/
  `fatto-aac` routes to it. Files: `dev/gateway-platform.tf`,
  `dev/routes-platform.tf` (extend the `local.platform_tool_routes` /
  parentRef pattern). Closes the "internal apps reachable from internet" root
  cause (S1-01, S1-02 for internet exposure).
- **A2 — Keycloak production mode.** `dev/keycloak.tf`: `args` `start-dev` →
  `start` with `--optimized` (or a build step), keep `KC_HOSTNAME=
  https://auth.klucovsky.com`, `KC_PROXY_HEADERS=xforwarded`, add
  `KC_HOSTNAME_STRICT=true`, review `KC_HTTP_ENABLED` (HTTP stays on behind the
  TLS-terminating gateway; health on :9000). Closes S1-03 / C-06. Must be
  verified against the public S3 OIDC login after apply.
- **A3 — PostgreSQL TLS enforced server-side.** `dev/cnpg.tf`: the CNPG Cluster
  presents server TLS (CNPG auto-generates a server cert); configure the cluster
  so the **server refuses plaintext** — `postgresql.parameters.ssl = "on"` and a
  `postgresql.pg_hba` that requires `hostssl` (no plaintext `host` fallback) for
  external/TCP connections. Then switch **every consumer** to `sslmode=require`
  (encryption; no CA distribution needed):
  - `postgresql` Terraform provider (`dev/main.tf`, `sslmode=disable` → `require`);
  - Keycloak in-cluster DB connection (`dev/keycloak.tf` / `dev/postgresql.tf`:
    add `?sslmode=require` to `KC_DB_URL`);
  - the `pg` state backend (when restored) and the `terraform_data.cnpg_ready`
    readiness check (`dev/cnpg.tf`);
  - **tenants** (e.g. `fatto-erp`) — must switch their DB connections to
    `sslmode=require` in lockstep (see coordination note below).
  NodePort 30432 stays (operator needs it for Terraform) but is now intranet-only.
  Closes S2-04 / C-04 (plaintext).

  **Coordination / breakage risk:** once `hostssl` is enforced, any consumer still
  connecting without TLS is refused. All in-repo consumers are updated in this
  plan; **tenant repos that use this DB must be updated to `sslmode=require`
  before (or at) the cutover** or they will fail to connect. `verify-full` (CA
  verification) is deferred (see Out of scope).

### B. Network — Omada (agent applies via API, with safeguards)

- **B1 — Router port-forward repoint** 80/443: `172.16.1.11` → `172.16.1.12`.
  Depends on A1 being applied and the public gateway healthy. Reversible in one
  edit. Verify public S3/auth reachable and internal apps no longer internet-
  reachable.
- **B2 — VPN ACL.** Gateway ACL on the tunnel `10.172.16.0/24`: **deny** to the
  node on `2379` (etcd), `10250` (kubelet), `9100` (node_exporter); **allow** the
  operator's needs — `443` (internal gateway), `22` (SSH), `6443` (k8s API),
  `30432` (Postgres/Terraform), `2049`+`111` (NFS), `53` (DNS). Mitigates the
  compromised-client blast radius (S2-01, S2-02, S2-07) without breaking the
  operator's workflow.
- **B3 — Inter-VLAN isolation** for VLAN 10 / 20 (currently empty) — prepare
  containment for when the OpenStack/Ceph cloud is powered back on (S2-09).

### C. Host — `cwwk` (agent applies via SSH)

- **C1 — NFS `/data` least-privilege.** The operator needs NFS over VPN, so keep
  VPN access but tighten: export to the **specific peer /32s** (`10.172.16.2`,
  `10.172.16.3`, `10.172.16.4`) instead of the whole `10.172.16.0/24`; set
  `secure` (require privileged source port) instead of `insecure`; use `ro` if
  the operator confirms read-only suffices (default keep `rw`). Keep the existing
  `root_squash,all_squash`. Partially closes S2-05.
- Host firewall: explicitly **not** implemented (see Decisions).

## Apply order & safety

1. **A (Terraform):** `terraform init` + `plan`; review the plan for drift
   (state is local/post-teardown). Apply A1 (public gateway) first; verify the
   public gateway serves the 3 hosts (`curl --resolve s3.klucovsky.com:443:172.16.1.12`)
   and returns 404 for a non-public host. Then A2 (Keycloak) and A3 (Postgres
   TLS), verifying each. **A3 enforcement (`hostssl`) is applied only after all
   consumers — including tenant repos — are confirmed on `sslmode=require`;**
   update in-repo consumers and the client side first, then flip `hostssl`.
2. **C1 (NFS):** low risk; apply and verify a mount from an allowed peer IP.
3. **B (Omada) last, while the operator is on LAN** (so LAN/SSH access survives
   even if the VPN path breaks), with a prepared revert:
   - B1 router repoint → verify public + internal reachability.
   - B2 VPN ACL → operator verifies from a real WireGuard peer that internal
     apps (443), SSH, kubectl, Terraform, and NFS still work, and that
     etcd/kubelet are now blocked.
   - B3 inter-VLAN isolation.
- An out-of-band path (LAN + SSH to `cwwk`) is kept open throughout. Every Omada
  change is captured before/after so it can be reverted.

## Rollback

- **A:** `git revert` + `terraform apply` (state-tracked, reversible). For A3, if
  a consumer is locked out, revert the `pg_hba` `hostssl` line back to `host` and
  re-apply to restore plaintext acceptance while the consumer is fixed.
- **B1:** repoint the port-forward back to `172.16.1.11`.
- **B2/B3:** delete the added ACL / disable isolation in Omada.
- **C1:** restore the prior `/etc/exports` line + `exportfs -r`.

## Verification (success criteria)

- Public gateway on `.12` serves `s3`/`auth`/`fatto-aac` and 404s other hosts.
- Internet reaches only the 3 public hosts + WireGuard; internal apps resolve/
  serve for LAN/VPN clients unchanged.
- S3 OIDC login works end-to-end with Keycloak in production mode.
- Postgres **refuses plaintext** (a `sslmode=disable` connection is rejected) and
  accepts `sslmode=require`; `terraform plan`, Keycloak, and any tenants still
  connect over TLS.
- From a real WireGuard peer: 443/22/6443/30432/NFS/DNS work; `2379`/`10250`/
  `9100` are blocked.
- NFS `/data` mounts only from the three peer /32s (+ LAN); other tunnel IPs
  cannot mount.
- No loss of LAN/SSH access at any point.

## Out of scope / deferred

- **SSO (oauth2-proxy + Keycloak) for admin apps** — not needed now that admin
  apps are intranet-only; a possible future P2 (its own spec/plan).
- **OpenStack/Ceph and BMC hardening** — the cloud is powered off; revisit before
  powering on (S2-09; inter-VLAN isolation prepared in B3).
- **Raw host firewall on `cwwk`** — replaced by the network-layer VPN ACL.
- **Postgres `verify-full` / CA distribution** — `sslmode=require` (encryption)
  is the P1 fix; certificate verification is a later hardening step.
