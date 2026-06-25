# Platform / Tenant Separation — Design

**Date:** 2026-06-25
**Status:** Approved (design), pending implementation plan
**Repos affected:** `tf-platform` (common), `fatto-erp/tf-infra` (tenant)

## Goal

Separate project-specific configuration from common ("platform") infrastructure so
that **a project can be fully removed in the future** (`terraform destroy` in its own
repo) **without impact on common infra or other projects**.

Concretely:
- `tf-platform` must contain **no `fatto` references** (one accepted exception below).
- Everything whose lifecycle is tied to a project lives in that project's repo
  (`fatto-erp/tf-infra`) so destroying the project removes it cleanly.

**Accepted exception:** the Nexus npm `@fatto-erp` hosted repo stays in `tf-platform`.
Packages must NOT be deleted together with the project. Its comment may be generalized.

## Guiding principle — lifecycle-based ownership

If destroying the project should remove a resource, it belongs to the project state.
If the resource survives and serves all tenants, it stays in `tf-platform` and is generic.

## Ownership map

### Stays in `tf-platform` (common, generic, tenant-agnostic)
| Component | Change |
|-----------|--------|
| CNPG operator + `shared-db` cluster | none (shared DB server) |
| Keycloak **server** (StatefulSet, Service, its DB) | remove fatto realm/theme/labels; serve on platform domain; mount a generic shared themes volume; publish `keycloak-admin` handoff secret |
| MinIO **server** | none; project buckets removed |
| Nexus, Zot (registry servers) | none; reword comments (npm `@fatto-erp` repo stays — exception) |
| Observability (Prometheus/Grafana/Loki/Alertmanager) | parameterize/remove loki dashboard `fatto-erp-dev` default |
| pgAdmin, Mailpit | serve on platform domain |
| Gateway infra (namespace, MetalLB pool, cert-manager, ClusterIssuer) | see Ingress section |
| ARC **controller** + CRDs | none (shared) |
| Platform-domain wildcard cert (`*.klucovsky.com`) | moves to platform terminating Gateway ns |

### Moves to `fatto-erp/tf-infra` (project-owned, removable)
| Component | Currently in |
|-----------|--------------|
| ARC **runner** scale set `fatto-runners` + `github-app-secret` + ns `arc-runners` | `arc.tf` |
| MinIO buckets `fatto-attachments`, `fatto-cad-files`, `fatto-exports` | `minio.tf` |
| Keycloak realm `fatto` + clients (`fatto-web`/`fatto-bff`) + roles + users + login theme content | `keycloak.tf`, `keycloak-realm/`, `keycloak-theme/` |
| Project domain: terminating Gateway + listeners `*.dev/test.fatto.online` + their TLS certs + project HTTPRoutes + SNI TLSRoute | `gateway.tf`, `certificates.tf` |
| Project DBs (already there) | — |

### Cosmetic cleanup (across `tf-platform`)
- Labels `app.kubernetes.io/part-of: fatto` → generic (e.g. `platform`).
- Comments / descriptions mentioning FATTO / fatto-erp → generic.
- `main.tf` header and Gateway name → generic (`platform-*`).

## Ingress architecture (decision: **B2 — generic TLS-passthrough front**)

### Constraint
Single-host, single NIC, single public IP. The router NATs `:443` to one internal IP
(`172.16.1.11`) and cannot route by SNI/host. LoadBalancer IPs come from **MetalLB L2**
(Canonical K8s `load-balancer` feature); the pool currently holds only `172.16.1.11/32`.
A second internal IP is reachable only over VPN, not from the internet — so all public
traffic must funnel through `.11`. Cilium is **1.17.12**, Gateway API enabled, `TLSRoute`
CRD present (TLS passthrough supported).

### Target topology
```
Internet → router:443 ─┐
VPN ───────────────────┤
                       ▼
        FRONT Gateway (.11)  [PLATFORM, generic]
        • :443  protocol TLS, mode=Passthrough, no hostname/cert, allowedRoutes TLSRoute from All
        • :80   HTTP → 301 https (generic redirect, no hostname)
                       │  (SNI routing via TLSRoute)
         ┌─────────────┴───────────────┐
         ▼                              ▼
 PLATFORM terminating Gateway    PROJECT terminating Gateway   [fatto-erp/tf-infra]
 • *.klucovsky.com + cert        • *.dev/test.fatto.online + fatto certs
 • HTTPRoutes: platform tools    • HTTPRoutes: fatto apps
 • TLSRoute SNI *.klucovsky.com  • TLSRoute SNI *.fatto.online  ← owned by project
```

### Ownership
- **Platform:** front passthrough Gateway (generic), platform terminating Gateway
  (`*.klucovsky.com`), platform's TLSRoute, platform wildcard cert, MetalLB pool,
  cert-manager + ClusterIssuer.
- **Project:** its terminating Gateway, fatto wildcard certs, its TLSRoute (SNI
  `*.fatto.online`), its app HTTPRoutes.

### Implications
- Shared dev tools move off the fatto domain to `*.klucovsky.com`: **Keycloak
  (`auth.`), Mailpit (`mail.`), MinIO console**. ~12 platform HTTPRoutes re-point to the
  platform terminating Gateway.
- Backend terminating Gateways need internal MetalLB IPs (e.g. `.12`, `.13`) used only
  for in-cluster front→backend forwarding — **not public**. Platform widens the MetalLB
  pool accordingly (`k8s set load-balancer.cidrs=...`, L2 mode).
- One extra in-cluster hop + second Envoy (L4 front → L7 backend). Negligible latency at
  this scale. Front has no L7 visibility (logs/metrics live at backend gateways).
- TLS terminates per-tenant at the backend gateway → per-tenant certs, clean isolation.
- DNS: `*.dev.fatto.online` continues to resolve to `.11` (public via router / VPN);
  SNI routing at the front sends it to the project gateway. No second public IP needed.

### Risk / validation
`TLSRoute` + passthrough is less-trodden than HTTPRoute in Cilium. Front is a single
point of failure — same as today's single Gateway, no regression.

### PoC outcome (2026-06-25) — **B2 validated** with two constraints
A throwaway in-cluster PoC (passthrough front + terminating backend + `TLSRoute`,
`*.poc.test`) confirmed: front Gateway `Programmed`, `TLSRoute` `Accepted/ResolvedRefs`
True with **wildcard SNI**, end-to-end SNI passthrough returns the backend response, the
**backend** presents the cert (termination at backend), non-matching SNI is rejected,
and a hostname-less `:80` HTTP→HTTPS 301 redirect works. Two constraints MUST be carried
into Plan 1 / Plan 6:

1. **TLSRoute backend cannot reference `cilium-gateway-<backend>` directly.** Cilium's
   Envoy→Envoy chaining fails (EDS sentinel `192.192.192.192:9999` is only intercepted
   for pod-origin traffic, not Envoy-origin). **Fix:** the front `TLSRoute` `backendRef`
   must point at a **relay ClusterIP Service with explicit `Endpoints`** (or headless
   service) targeting the backend Gateway's ClusterIP:443 — not the cilium-gateway
   Service directly.
2. **Passthrough and HTTP-redirect listeners cannot share one Gateway.** Cilium refuses
   to attach an `HTTPRoute` to a Gateway that also has a `TLS/Passthrough` listener.
   **Fix:** the platform front is **two Gateways** sharing the one IP — one `:443` TLS
   passthrough, one `:80` HTTP redirect (shared-IP via MetalLB sharing annotation or a
   single fronting LB service).

## Keycloak realm / theme

- **Server:** stays in `tf-platform`, vanilla (no realm import, no fatto theme, generic
  labels), served at `auth.klucovsky.com`.
- **Handoff:** `tf-platform` publishes a generic `keycloak-admin` Secret in the
  `keycloak` namespace (mirrors `minio-admin` / `cnpg-superuser` handoff).
- **Realm + clients + roles + users:** managed by the **Keycloak Terraform provider**
  (`keycloak/keycloak`) in `fatto-erp/tf-infra`, against the shared Keycloak admin API.
  Fully declarative and `destroy`-able. Existing realm/clients are imported into project
  state (realm data persists in the Keycloak DB regardless).
- **Theme (decision: shared themes volume, project populates):**
  - Platform Keycloak mounts a **generic shared themes directory** (RWX/hostPath volume,
    no fatto content) at `/opt/keycloak/themes`.
  - Project writes its theme into a subdirectory (`<project>/login/...`) via a
    Job/ConfigMap it owns, and sets the realm `loginTheme` to `<project>`.
  - `start-dev` runs with theme caching off → hot reload, no Keycloak restart needed.
  - Removal: the project deletes its theme subdir + realm; platform mechanism untouched.

## ARC runner

- `tf-platform` keeps the ARC **controller** + CRDs (shared).
- `fatto-erp/tf-infra` gets the runner scale set `fatto-runners`, the `github-app-secret`,
  and the `arc-runners` namespace, plus the `arc_*` / `github_app_*` variables. The Helm
  provider is added to the project repo.
- Runner registers as `runnerScaleSetName = "fatto-erp"` against the Fatto-ERP org.
- The cross-repo dependency on the controller becomes a runtime ordering assumption
  (controller applied first in `tf-platform`).

## MinIO project buckets

- `fatto-attachments`, `fatto-cad-files`, `fatto-exports` move to `fatto-erp/tf-infra`,
  provisioned with the existing MinIO provider + `minio-admin` handoff (already used by
  the tenant repo for its scoped bucket).

## State migration

| Resource | Strategy |
|----------|----------|
| MinIO project buckets | **Preserve data**: `terraform state rm` in `tf-platform`, `terraform import` in `fatto-erp/tf-infra`. Do NOT destroy. |
| Keycloak realm/clients/users | Realm data persists in Keycloak DB. Import existing realm/clients into project state via Keycloak provider. |
| ARC runner + github-app secret + ns | Recreate (no persistent data) — destroy in platform, create in project. Brief CI runner gap acceptable. |
| Gateway / certs / routes | Recreate as new objects (front + platform + project gateways). Cutover window for ingress; PoC first. |

## Sequencing (phases)

1. **MetalLB pool widen** (platform) — add internal IPs for backend gateways.
2. **Ingress PoC** — validate passthrough front + TLSRoute SNI on a throwaway hostname.
3. **Ingress cutover** (platform) — front passthrough Gateway + platform terminating
   Gateway + move shared tools to `*.klucovsky.com` + platform TLSRoute.
4. **Keycloak** — vanilla-ize server, add themes volume, publish `keycloak-admin`;
   project creates realm/clients/theme via Keycloak provider.
5. **ARC runner** — move to project repo (controller stays).
6. **MinIO buckets** — move to project repo (import).
7. **Project gateway + domain** — project terminating Gateway + fatto certs + TLSRoute +
   app HTTPRoutes in project repo.
8. **Cosmetic cleanup** — labels, comments, names, gateway rename.

Each phase is independently appliable; ingress (1–3) must precede tool/domain moves.

## Out of scope
- Multi-tenant onboarding automation (templating a new tenant).
- BGP / multiple public IPs.
- Migrating away from Canonical K8s bundled MetalLB/Cilium.
- prod environment (this design targets `dev/`; `test`/prod follow the same pattern).

## Open questions / to confirm during planning
- Exact generic name for the platform Gateway(s) and `part-of` label value.
- Whether the platform terminating Gateway and front share the `gateway` namespace.
- Theme volume backing (hostPath vs local PVC) on the single node.
- Keycloak admin credential scope for the project provider (master admin vs dedicated
  realm-management service account).
