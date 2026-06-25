# Platform Tool Route Migration (B2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the 8 `*.klucovsky.com` platform-tool HTTPRoutes onto the new `platform-terminating` Gateway (served via the passthrough front on `172.16.1.12`) using **additional, parallel routes** (dual-serve), and make the MetalLB shared-IP assignment **durable in Terraform** — all reversible, with `fatto-gateway` on `.11` still live.

**Architecture:** For each klucovsky tool, add a second `HTTPRoute` (named `<tool>-platform`) whose `parentRef` is `platform-terminating` (cross-namespace, `gateway` ns), pointing at the same backend Service. The existing routes on `fatto-gateway` stay untouched, so both ingress paths serve simultaneously. Three `kubernetes_annotations` resources codify the MetalLB IPs (`.12` shared on both fronts, `.13` on terminating) that were previously set imperatively. Validation compares each tool's response via `.12` (new) against `.11` (live).

**Tech Stack:** Terraform (`alekc/kubectl`, `hashicorp/kubernetes`), Cilium Gateway API, MetalLB.

**Prerequisites:** Plan 1 complete (foundation on `.12`/`.13`). Branch `design/platform-tenant-separation`.

**Explicitly OUT of scope (later plans):**
- Moving `auth`/`mail`/`minio` off `*.dev.fatto.online` to `*.klucovsky.com` — coupled with the Keycloak/Mailpit/MinIO changes (those services need hostname/config changes).
- Removing the old `fatto-gateway` routes (the WIP-modified service `.tf` files own them; cleanup happens at the final flip).
- The `.11` flip (front → `.11`, remove `fatto-gateway`) — only possible after the project Gateway (Plan 6) takes over the fatto domain; otherwise fatto apps go dark.

**WIP caveat:** The existing per-tool routes live in service `.tf` files that currently have uncommitted working-tree changes (not owned by this work). This plan deliberately does NOT edit those files — it adds parallel routes in a dedicated new file `dev/routes-platform.tf`. Always apply with `-target` (never a bare `terraform apply`, which would sweep the unrelated WIP changes into the cluster).

---

## The 8 klucovsky tools to migrate (discovered from live HTTPRoutes)

| Route ns/name | Hostname | Backend |
|---------------|----------|---------|
| `argocd/argocd` | argocd.klucovsky.com | `argocd-server:80` |
| `cnpg-system/pgadmin` | db.klucovsky.com | `pgadmin:80` |
| `nexus/nexus` | nexus.klucovsky.com | `nexus-nexus-repository-manager:8081` |
| `observability/alertmanager` | alertmanager.klucovsky.com | `prometheus-kube-prometheus-alertmanager:9093` |
| `observability/grafana` | grafana.klucovsky.com | `prometheus-grafana:80` |
| `observability/prometheus` | prometheus.klucovsky.com | `prometheus-kube-prometheus-prometheus:9090` |
| `sonarqube/sonarqube` | sonar.klucovsky.com | `sonarqube-sonarqube:9000` |
| `zot/zot` | registry.klucovsky.com | `zot:5000` |

---

## File Structure

- Modify: `dev/gateway-platform.tf` — append three `kubernetes_annotations` resources (durable MetalLB IPs).
- Create: `dev/routes-platform.tf` — eight parallel `HTTPRoute`s attached to `platform-terminating`.

---

### Task 1: Make the MetalLB shared-IP assignment durable in Terraform

The IPs were set imperatively in Plan 1 (`kubectl annotate`) and are not in TF state. Codify them so a gateway/service recreation re-applies them.

**Files:**
- Modify: `dev/gateway-platform.tf`

- [ ] **Step 1: Append the annotation resources**

Append to `dev/gateway-platform.tf`:

```hcl
# -----------------------------------------------------------------------------
# DURABLE METALLB IP ASSIGNMENT
# Cilium does not propagate Gateway annotations to the generated cilium-gateway-*
# Service, so MetalLB shared-IP must be set on those Services. Manage it in TF so
# it survives gateway/service recreation. (Set imperatively during Plan 1.)
#   - both fronts share 172.16.1.12 (ports 443 + 80 do not overlap)
#   - terminating is reached internally via the relay; its .13 external IP is
#     unused but MetalLB assigns one anyway, so we pin it off the fronts' IP.
# -----------------------------------------------------------------------------

resource "kubernetes_annotations" "front_tls_lb_ip" {
  api_version = "v1"
  kind        = "Service"
  metadata {
    name      = "cilium-gateway-platform-front-tls"
    namespace = "gateway"
  }
  annotations = {
    "metallb.io/allow-shared-ip" = "platform-front"
    "metallb.io/loadBalancerIPs" = "172.16.1.12"
  }
  force = true

  depends_on = [kubectl_manifest.platform_front_tls_gw]
}

resource "kubernetes_annotations" "front_http_lb_ip" {
  api_version = "v1"
  kind        = "Service"
  metadata {
    name      = "cilium-gateway-platform-front-http"
    namespace = "gateway"
  }
  annotations = {
    "metallb.io/allow-shared-ip" = "platform-front"
    "metallb.io/loadBalancerIPs" = "172.16.1.12"
  }
  force = true

  depends_on = [kubectl_manifest.platform_front_http_gw]
}

resource "kubernetes_annotations" "terminating_lb_ip" {
  api_version = "v1"
  kind        = "Service"
  metadata {
    name      = "cilium-gateway-platform-terminating"
    namespace = "gateway"
  }
  annotations = {
    "metallb.io/loadBalancerIPs" = "172.16.1.13"
  }
  force = true

  depends_on = [kubectl_manifest.platform_terminating_gw]
}
```

- [ ] **Step 2: Apply (targeted) and confirm no IP churn**

Run:
```bash
cd dev && terraform apply \
  -target=kubernetes_annotations.front_tls_lb_ip \
  -target=kubernetes_annotations.front_http_lb_ip \
  -target=kubernetes_annotations.terminating_lb_ip -auto-approve
```
Expected: `Apply complete! Resources: 3 added` (or `0 added, 3 changed` if it adopts) — and **no error**.

- [ ] **Step 3: Verify the IPs are unchanged**

Run:
```bash
kubectl get svc -n gateway -o jsonpath='{range .items[*]}{.metadata.name}={.status.loadBalancer.ingress[0].ip}{"\n"}{end}' | grep cilium-gateway
```
Expected:
```
cilium-gateway-fatto-gateway=172.16.1.11
cilium-gateway-platform-front-http=172.16.1.12
cilium-gateway-platform-front-tls=172.16.1.12
cilium-gateway-platform-terminating=172.16.1.13
```

- [ ] **Step 4: Commit**

```bash
cd .. && git add dev/gateway-platform.tf && git commit -m "feat(ingress): make MetalLB shared-IP assignment durable in terraform"
```

---

### Task 2: Add the 8 parallel platform-tool routes on platform-terminating

**Files:**
- Create: `dev/routes-platform.tf`

- [ ] **Step 1: Write the routes file**

Create `dev/routes-platform.tf`:

```hcl
# -----------------------------------------------------------------------------
# PLATFORM TOOL ROUTES (B2) — parallel routes on platform-terminating
#
# Dual-serve: each *.klucovsky.com tool also gets a route on the new terminating
# Gateway (reached via the passthrough front on 172.16.1.12). The original routes
# on fatto-gateway stay live. Cross-namespace parentRef (gateway ns) is allowed by
# platform-terminating's allowedRoutes.namespaces.from=All.
#
# Removing the old fatto-gateway routes + the .11 flip happen at the final cutover
# (after the project Gateway / Plan 6 takes over the fatto domain).
# -----------------------------------------------------------------------------

locals {
  platform_tool_routes = {
    argocd = {
      namespace = "argocd"
      hostname  = "argocd.klucovsky.com"
      backend   = "argocd-server"
      port      = 80
    }
    pgadmin = {
      namespace = "cnpg-system"
      hostname  = "db.klucovsky.com"
      backend   = "pgadmin"
      port      = 80
    }
    nexus = {
      namespace = "nexus"
      hostname  = "nexus.klucovsky.com"
      backend   = "nexus-nexus-repository-manager"
      port      = 8081
    }
    alertmanager = {
      namespace = "observability"
      hostname  = "alertmanager.klucovsky.com"
      backend   = "prometheus-kube-prometheus-alertmanager"
      port      = 9093
    }
    grafana = {
      namespace = "observability"
      hostname  = "grafana.klucovsky.com"
      backend   = "prometheus-grafana"
      port      = 80
    }
    prometheus = {
      namespace = "observability"
      hostname  = "prometheus.klucovsky.com"
      backend   = "prometheus-kube-prometheus-prometheus"
      port      = 9090
    }
    sonarqube = {
      namespace = "sonarqube"
      hostname  = "sonar.klucovsky.com"
      backend   = "sonarqube-sonarqube"
      port      = 9000
    }
    zot = {
      namespace = "zot"
      hostname  = "registry.klucovsky.com"
      backend   = "zot"
      port      = 5000
    }
  }
}

resource "kubectl_manifest" "platform_tool_route" {
  for_each = local.platform_tool_routes

  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: ${each.key}-platform
      namespace: ${each.value.namespace}
    spec:
      parentRefs:
        - name: platform-terminating
          namespace: gateway
          sectionName: https-klucovsky
      hostnames:
        - "${each.value.hostname}"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: ${each.value.backend}
              port: ${each.value.port}
  YAML

  depends_on = [kubectl_manifest.platform_terminating_gw]
}
```

- [ ] **Step 2: Validate and apply (targeted)**

Run:
```bash
cd dev && terraform validate && terraform apply -target=kubectl_manifest.platform_tool_route -auto-approve
```
Expected: `Apply complete! Resources: 8 added`.

- [ ] **Step 3: Verify all 8 routes were Accepted by platform-terminating**

Run:
```bash
for t in argocd pgadmin nexus alertmanager grafana prometheus sonarqube zot; do
  case $t in
    argocd) ns=argocd;; pgadmin) ns=cnpg-system;; nexus) ns=nexus;; zot) ns=zot;;
    sonarqube) ns=sonarqube;; *) ns=observability;;
  esac
  st=$(kubectl get httproute ${t}-platform -n $ns -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}' 2>/dev/null)
  echo "$t-platform ($ns): Accepted=$st"
done
```
Expected: every line `Accepted=True`.

- [ ] **Step 4: Commit**

```bash
cd .. && git add dev/routes-platform.tf && git commit -m "feat(ingress): add parallel platform-tool routes on platform-terminating"
```

---

### Task 3: Validate every tool via the new ingress (.12) matches the live path (.11)

- [ ] **Step 1: Compare each hostname's HTTP status via .12 (new) vs .11 (live)**

Run:
```bash
declare -A H=(
  [argocd.klucovsky.com]=1 [db.klucovsky.com]=1 [nexus.klucovsky.com]=1
  [alertmanager.klucovsky.com]=1 [grafana.klucovsky.com]=1 [prometheus.klucovsky.com]=1
  [sonar.klucovsky.com]=1 [registry.klucovsky.com]=1
)
for h in "${!H[@]}"; do
  new=$(curl -sS -k --max-time 15 --resolve $h:443:172.16.1.12 https://$h/ -o /dev/null -w "%{http_code}" 2>/dev/null)
  live=$(curl -sS -k --max-time 15 --resolve $h:443:172.16.1.11 https://$h/ -o /dev/null -w "%{http_code}" 2>/dev/null)
  flag=$([ "$new" = "$live" ] && echo OK || echo DIFF)
  echo "$flag  $h  new(.12)=$new  live(.11)=$live"
done
```
Expected: every line `OK` with matching non-`000`, non-`5xx` codes (2xx/3xx/401 are all acceptable as long as `.12` matches `.11`). The first request to a freshly-announced IP can be slow — re-run any `DIFF`/`000` once before treating it as a failure.

- [ ] **Step 2: Verify each serves the real `*.klucovsky.com` cert via .12 (spot-check grafana + nexus)**

Run:
```bash
for h in grafana.klucovsky.com nexus.klucovsky.com; do
  echo -n "$h: "; echo | openssl s_client -connect 172.16.1.12:443 -servername $h 2>/dev/null | openssl x509 -noout -subject
done
```
Expected: both `subject=CN=*.klucovsky.com`.

- [ ] **Step 3: Record results.** If any tool is `DIFF` after a retry, capture the route status and the terminating Gateway logs; do not proceed to the flip plan until all 8 match.

---

## Self-Review

**Spec coverage:** Implements the platform-side "shared tools on `*.klucovsky.com` via the new ingress" portion of the design, plus the Plan 1 follow-up finding #1 (durable MetalLB annotations). The auth/mail/minio domain move (finding-adjacent) and the `.11` flip are explicitly deferred with reasons. ✅

**Placeholder scan:** All 8 routes are concrete (exact ns/hostname/backend/port discovered from the live cluster). Commands are complete. The validation tolerance (2xx/3xx/401, match `.11`) is explicit. ✅

**Name/type consistency:** Routes named `<tool>-platform`; parentRef `platform-terminating` / `gateway` / `https-klucovsky` (matches the listener created in Plan 1); annotation resources target the exact `cilium-gateway-*` Service names; IPs `.12`/`.13` consistent with Plan 1. ✅

## Risks / notes
- Dual-serving means a hostname briefly resolves to the same backend via two gateways — harmless (clients only hit whichever IP DNS/`--resolve` gives).
- `kubernetes_annotations` with `force = true` takes field-manager ownership of those annotations; values match what is live, so no disruption.
- This plan does not change DNS. Real user traffic still flows via `.11` until the final flip plan. Validation uses `--resolve`.
- Final flip plan (after Plan 6) will: remove the old `fatto-gateway` per-tool routes (editing the now-hopefully-committed service files), delete `fatto-gateway`, and move the fronts' shared IP from `.12` to `.11`.
