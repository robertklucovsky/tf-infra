# Platform Ingress Foundation (B2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the B2 platform ingress (TLS-passthrough front + HTTP-redirect front + `*.klucovsky.com` terminating Gateway, wired with the PoC-validated relay-Endpoints pattern) **in parallel on a second IP**, validate it end-to-end with a real platform tool, **without touching the live `fatto-gateway`** — so the change is fully reversible. The traffic flip and mass HTTPRoute migration are deferred to Plan 2.

**Architecture:** New Terraform resources in `tf-platform/dev` create three Gateways on a new MetalLB IP (`172.16.1.12`): `platform-front-tls` (`:443` passthrough), `platform-front-http` (`:80` redirect), `platform-terminating` (`:443` HTTPS terminate, `*.klucovsky.com`). A relay `Service`+`Endpoints` bridges the front `TLSRoute` to the terminating Gateway's ClusterIP (PoC constraint 1). The two front Gateways share one IP via MetalLB shared-IP annotation (validated early — PoC constraint 2). Grafana's HTTPRoute is duplicated onto the new terminating Gateway as the end-to-end proof; the original stays live.

**Tech Stack:** Terraform (`alekc/kubectl` `kubectl_manifest`, `hashicorp/kubernetes`), Cilium 1.17.12 Gateway API (`ck-gateway`), MetalLB (Canonical K8s `load-balancer` feature), Gateway API `TLSRoute` v1alpha2.

**Prerequisites:** Plan 0 (ingress PoC) complete and B2 validated. Branch `design/platform-tenant-separation` checked out.

**Reversibility:** Every resource here is additive and lives on `172.16.1.12`. `fatto-gateway` on `.11` and all current routes are untouched. Rollback = `terraform destroy` the new resources (or `kubectl delete` them) + shrink the MetalLB pool back.

---

## File Structure

- Create: `dev/gateway-platform.tf` — the three platform Gateways, relay svc/endpoints, platform TLSRoute, redirect HTTPRoute. One file: these objects change together and form the platform ingress unit.
- Modify (validation only, reverted at end of plan): temporarily add a second HTTPRoute for grafana attached to `platform-terminating`. This proof route is added in Task 6 and removed in Task 8.
- Out of band (node, not Terraform): MetalLB pool widening via Canonical K8s `k8s set`.

---

### Task 1: Widen the MetalLB address pool (node, out of band)

The MetalLB pool is managed by the Canonical K8s `load-balancer` feature, not Terraform. It currently holds only `172.16.1.11/32`. We add a small range so new Gateways can get `172.16.1.12`+.

**Files:** none (node-level config).

- [ ] **Step 1: Inspect current load-balancer feature config (on the node)**

Run (on the cluster node, e.g. via `! ssh ...` or directly): `sudo k8s get load-balancer`
Expected: shows `enabled: true`, `l2-mode: true`, `bgp-mode: false`, and a `cidrs` list containing `172.16.1.11/32`.

- [ ] **Step 2: Widen the CIDR range**

Run: `sudo k8s set load-balancer.cidrs="172.16.1.11-172.16.1.13"`
Expected: command succeeds (no error). This reconciles the MetalLB `IPAddressPool`.

- [ ] **Step 3: Verify the pool was updated (from the workstation kubectl)**

Run: `kubectl get ipaddresspool -n metallb-system -o jsonpath='{.items[*].spec.addresses}{"\n"}'`
Expected: addresses now include the `172.16.1.11-172.16.1.13` range (exact rendering may be a range or list).

- [ ] **Step 4: Confirm the live gateway still holds .11 (no disruption)**

Run: `kubectl get svc cilium-gateway-fatto-gateway -n gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}{"\n"}'`
Expected: `172.16.1.11`

---

### Task 2: Validate two Gateways can share one MetalLB IP (critical gate)

This is the make-or-break unknown: `:443` passthrough and `:80` redirect must live on **separate** Gateways (PoC constraint 2) yet share the **one** public IP. We validate the MetalLB shared-IP mechanism with two throwaway LB Services before building the real thing.

**Files:** none (throwaway kubectl).

- [ ] **Step 1: Create two LoadBalancer Services sharing one IP via annotation**

```bash
cat > /tmp/share-test.yaml <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: share-a
  namespace: default
  annotations:
    metallb.io/allow-shared-ip: "share-test"
    metallb.io/loadBalancerIPs: "172.16.1.12"
spec:
  type: LoadBalancer
  ports: [{ name: p443, port: 443, targetPort: 443 }]
  selector: { app: nonexistent-a }
---
apiVersion: v1
kind: Service
metadata:
  name: share-b
  namespace: default
  annotations:
    metallb.io/allow-shared-ip: "share-test"
    metallb.io/loadBalancerIPs: "172.16.1.12"
spec:
  type: LoadBalancer
  ports: [{ name: p80, port: 80, targetPort: 80 }]
  selector: { app: nonexistent-b }
YAML
kubectl apply -f /tmp/share-test.yaml
```
Expected: both services created.

- [ ] **Step 2: Verify BOTH got 172.16.1.12**

Run: `kubectl get svc share-a share-b -n default -o jsonpath='{range .items[*]}{.metadata.name}={.status.loadBalancer.ingress[0].ip}{"\n"}{end}'`
Expected: `share-a=172.16.1.12` and `share-b=172.16.1.12`

- [ ] **Step 3: Record the verdict and clean up**

```bash
kubectl delete -f /tmp/share-test.yaml && rm -f /tmp/share-test.yaml
```
- If both got `.12`: MetalLB shared-IP works → proceed; the real Gateways will use `metallb.io/allow-shared-ip: "platform-front"` + `metallb.io/loadBalancerIPs: "172.16.1.12"`.
- **If they did NOT share** (one Pending, or different IPs): STOP and report BLOCKED. The B2 `:80`+`:443` split on one IP is not achievable via MetalLB sharing; we must choose an alternative (e.g. drop the `:80` redirect Gateway and serve HTTPS-only, or front both ports with a single hostNetwork LB). Escalate to the human before continuing.

> **Note on annotation propagation:** Cilium creates the `cilium-gateway-<name>` Service. Whether it copies these MetalLB annotations from the Gateway is verified in Task 4 Step 3. If Cilium does NOT propagate them, the fallback (documented in Task 4) is to annotate the generated Services directly via a `kubernetes_annotations` resource.

---

### Task 3: Create the platform terminating Gateway (`*.klucovsky.com`)

**Files:**
- Create: `dev/gateway-platform.tf`

- [ ] **Step 1: Write the terminating Gateway resource**

Create `dev/gateway-platform.tf` with this content:

```hcl
# -----------------------------------------------------------------------------
# PLATFORM INGRESS (B2) — parallel build on 172.16.1.12
#
# Front (passthrough :443) + Front (redirect :80) + Terminating (*.klucovsky.com).
# Wired with the PoC-validated relay-Endpoints pattern (a TLSRoute backendRef
# cannot target a cilium-gateway-* Service directly). Built alongside the live
# fatto-gateway (.11); no existing route is touched here.
# -----------------------------------------------------------------------------

# Terminating Gateway: terminates TLS for platform tools on *.klucovsky.com.
resource "kubectl_manifest" "platform_terminating_gw" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: platform-terminating
      namespace: gateway
    spec:
      gatewayClassName: ck-gateway
      listeners:
        - name: https-klucovsky
          port: 443
          protocol: HTTPS
          hostname: "*.klucovsky.com"
          tls:
            mode: Terminate
            certificateRefs:
              - kind: Secret
                name: klucovsky-wildcard-tls
          allowedRoutes:
            namespaces:
              from: All
  YAML

  depends_on = [kubernetes_namespace.gateway, kubectl_manifest.cert_klucovsky_wildcard]
}
```

- [ ] **Step 2: Validate and apply (targeted)**

Run:
```bash
cd dev && terraform validate && terraform apply -target=kubectl_manifest.platform_terminating_gw -auto-approve
```
Expected: `Apply complete! Resources: 1 added`. (If `terraform validate` flags provider config, run `terraform init` first.)

- [ ] **Step 3: Verify it is Programmed and learn its ClusterIP**

Run: `kubectl get gateway platform-terminating -n gateway -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}{"\n"}'`
Expected: `True` (retry up to ~30s)

Run: `kubectl get svc cilium-gateway-platform-terminating -n gateway -o jsonpath='{.spec.clusterIP}{"\n"}'`
Expected: a ClusterIP (recorded for the relay in Task 5).

- [ ] **Step 4: Commit**

```bash
cd .. && git add dev/gateway-platform.tf && git commit -m "feat(ingress): add platform terminating gateway (*.klucovsky.com)"
```

---

### Task 4: Create the two front Gateways (passthrough :443 + redirect :80) sharing 172.16.1.12

**Files:**
- Modify: `dev/gateway-platform.tf`

- [ ] **Step 1: Append the front Gateways + redirect HTTPRoute**

Append to `dev/gateway-platform.tf`:

```hcl
# Front Gateway A: generic TLS passthrough on :443 (no hostname, no cert).
resource "kubectl_manifest" "platform_front_tls_gw" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: platform-front-tls
      namespace: gateway
      annotations:
        metallb.io/allow-shared-ip: "platform-front"
        metallb.io/loadBalancerIPs: "172.16.1.12"
    spec:
      gatewayClassName: ck-gateway
      listeners:
        - name: tls-passthrough
          port: 443
          protocol: TLS
          tls:
            mode: Passthrough
          allowedRoutes:
            kinds:
              - kind: TLSRoute
            namespaces:
              from: All
  YAML

  depends_on = [kubernetes_namespace.gateway]
}

# Front Gateway B: generic HTTP -> HTTPS redirect on :80 (separate Gateway —
# Cilium refuses to attach an HTTPRoute to a Gateway that has a passthrough
# listener). Shares 172.16.1.12 with the passthrough Gateway via MetalLB.
resource "kubectl_manifest" "platform_front_http_gw" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: platform-front-http
      namespace: gateway
      annotations:
        metallb.io/allow-shared-ip: "platform-front"
        metallb.io/loadBalancerIPs: "172.16.1.12"
    spec:
      gatewayClassName: ck-gateway
      listeners:
        - name: http
          port: 80
          protocol: HTTP
          allowedRoutes:
            namespaces:
              from: All
  YAML

  depends_on = [kubernetes_namespace.gateway]
}

# Generic HTTP -> HTTPS 301 redirect (no hostname).
resource "kubectl_manifest" "platform_http_redirect_route" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: platform-http-redirect
      namespace: gateway
    spec:
      parentRefs:
        - name: platform-front-http
          sectionName: http
      rules:
        - filters:
            - type: RequestRedirect
              requestRedirect:
                scheme: https
                statusCode: 301
  YAML

  depends_on = [kubectl_manifest.platform_front_http_gw]
}
```

- [ ] **Step 2: Apply (targeted)**

Run:
```bash
cd dev && terraform apply \
  -target=kubectl_manifest.platform_front_tls_gw \
  -target=kubectl_manifest.platform_front_http_gw \
  -target=kubectl_manifest.platform_http_redirect_route -auto-approve
```
Expected: `Apply complete! Resources: 3 added`.

- [ ] **Step 3: Verify both fronts are Programmed AND share 172.16.1.12**

Run:
```bash
kubectl get svc cilium-gateway-platform-front-tls cilium-gateway-platform-front-http -n gateway \
  -o jsonpath='{range .items[*]}{.metadata.name}={.status.loadBalancer.ingress[0].ip}{"\n"}{end}'
```
Expected: both print `...=172.16.1.12`.

**If the generated Services did NOT inherit the MetalLB annotations** (e.g. EXTERNAL-IP `<pending>` or different IPs), apply the annotations directly to the generated Services and re-check:
```bash
kubectl annotate svc cilium-gateway-platform-front-tls cilium-gateway-platform-front-http -n gateway \
  metallb.io/allow-shared-ip=platform-front metallb.io/loadBalancerIPs=172.16.1.12 --overwrite
```
Then re-run the verification. If they still won't share, STOP (see Task 2 Step 3 fallback).

- [ ] **Step 4: Verify the redirect HTTPRoute attached**

Run: `kubectl get httproute platform-http-redirect -n gateway -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}{"\n"}'`
Expected: `True`

- [ ] **Step 5: Commit**

```bash
cd .. && git add dev/gateway-platform.tf && git commit -m "feat(ingress): add passthrough + redirect front gateways sharing 172.16.1.12"
```

---

### Task 5: Relay Service + Endpoints bridging front TLSRoute → terminating Gateway

The front `TLSRoute` cannot target `cilium-gateway-platform-terminating` directly (PoC constraint 1: Cilium Envoy→Envoy via the EDS sentinel fails). We create a plain `Service` with manual `Endpoints` pointing at the terminating Gateway's ClusterIP:443.

**Files:**
- Modify: `dev/gateway-platform.tf`

- [ ] **Step 1: Append the relay Service + Endpoints (ClusterIP sourced via data source)**

Append to `dev/gateway-platform.tf`:

```hcl
# The terminating Gateway's auto-created Envoy Service. We read its ClusterIP
# to build a relay the front TLSRoute can target.
data "kubernetes_service" "platform_terminating_envoy" {
  metadata {
    name      = "cilium-gateway-platform-terminating"
    namespace = "gateway"
  }

  depends_on = [kubectl_manifest.platform_terminating_gw]
}

# Relay Service (no selector) + manual Endpoints → terminating Gateway ClusterIP:443.
resource "kubernetes_service" "platform_terminating_relay" {
  metadata {
    name      = "platform-terminating-relay"
    namespace = "gateway"
  }
  spec {
    port {
      name        = "https"
      port        = 443
      target_port = 443
    }
  }
}

resource "kubernetes_endpoints" "platform_terminating_relay" {
  metadata {
    name      = "platform-terminating-relay"
    namespace = "gateway"
  }
  subset {
    address {
      ip = data.kubernetes_service.platform_terminating_envoy.spec[0].cluster_ip
    }
    port {
      name = "https"
      port = 443
    }
  }
}
```

- [ ] **Step 2: Apply (targeted)**

Run:
```bash
cd dev && terraform apply \
  -target=kubernetes_service.platform_terminating_relay \
  -target=kubernetes_endpoints.platform_terminating_relay -auto-approve
```
Expected: `Apply complete! Resources: 2 added`.

- [ ] **Step 3: Verify the relay Endpoints points at the terminating ClusterIP**

Run: `kubectl get endpoints platform-terminating-relay -n gateway -o jsonpath='{.subsets[0].addresses[0].ip}:{.subsets[0].ports[0].port}{"\n"}'`
Expected: `<terminating-clusterIP>:443` (matches the ClusterIP from Task 3 Step 3).

- [ ] **Step 4: Commit**

```bash
cd .. && git add dev/gateway-platform.tf && git commit -m "feat(ingress): add relay service+endpoints for front->terminating TLSRoute"
```

---

### Task 6: Platform TLSRoute + Grafana proof route, end-to-end validation

**Files:**
- Modify: `dev/gateway-platform.tf`

- [ ] **Step 1: Append the platform TLSRoute (SNI *.klucovsky.com → relay) and a Grafana proof HTTPRoute on the terminating Gateway**

Append to `dev/gateway-platform.tf`:

```hcl
# SNI route: *.klucovsky.com on the passthrough front -> relay -> terminating GW.
resource "kubectl_manifest" "platform_tls_route" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1alpha2
    kind: TLSRoute
    metadata:
      name: platform-klucovsky
      namespace: gateway
    spec:
      parentRefs:
        - name: platform-front-tls
          sectionName: tls-passthrough
      hostnames:
        - "*.klucovsky.com"
      rules:
        - backendRefs:
            - name: platform-terminating-relay
              port: 443
  YAML

  depends_on = [
    kubectl_manifest.platform_front_tls_gw,
    kubernetes_endpoints.platform_terminating_relay,
  ]
}

# PROOF route (removed in Task 8): grafana via the new terminating Gateway.
# The original grafana route on fatto-gateway stays live and untouched.
resource "kubectl_manifest" "proof_grafana_route" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: proof-grafana
      namespace: observability
    spec:
      parentRefs:
        - name: platform-terminating
          namespace: gateway
          sectionName: https-klucovsky
      hostnames:
        - "grafana.klucovsky.com"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: kube-prometheus-stack-grafana
              port: 80
  YAML

  depends_on = [kubectl_manifest.platform_terminating_gw]
}
```

> Confirm the grafana Service name/namespace/port before applying:
> `kubectl get svc -A | grep -i grafana`. Adjust `name`, `namespace`, and the
> HTTPRoute `namespace` to match (the example assumes `observability/kube-prometheus-stack-grafana:80`).

- [ ] **Step 2: Apply (targeted)**

Run:
```bash
cd dev && terraform apply \
  -target=kubectl_manifest.platform_tls_route \
  -target=kubectl_manifest.proof_grafana_route -auto-approve
```
Expected: `Apply complete! Resources: 2 added`.

- [ ] **Step 3: Verify the TLSRoute resolved its (relay) backend**

Run: `kubectl get tlsroute platform-klucovsky -n gateway -o jsonpath='{range .status.parents[*]}{.conditions[?(@.type=="Accepted")].status}{" "}{.conditions[?(@.type=="ResolvedRefs")].status}{"\n"}{end}'`
Expected: `True True`

- [ ] **Step 4: End-to-end test through the NEW ingress on 172.16.1.12**

Run from the workstation (VPN reaches `.12`):
```bash
curl -sS -k --resolve grafana.klucovsky.com:443:172.16.1.12 https://grafana.klucovsky.com/login -o /dev/null -w "%{http_code}\n"
```
Expected: `200` (or `302` to the Grafana login) — proving SNI passthrough → relay → terminating Gateway → grafana works on the new IP.

- [ ] **Step 5: Verify the served cert is the real klucovsky wildcard (terminated at platform-terminating)**

Run:
```bash
echo | openssl s_client -connect 172.16.1.12:443 -servername grafana.klucovsky.com 2>/dev/null | openssl x509 -noout -subject
```
Expected: subject for `*.klucovsky.com` (the real cert-manager cert, not self-signed).

- [ ] **Step 6: Verify the live path is still intact (no regression)**

Run:
```bash
curl -sS -k --resolve grafana.klucovsky.com:443:172.16.1.11 https://grafana.klucovsky.com/login -o /dev/null -w "%{http_code}\n"
```
Expected: same success as before — `fatto-gateway` on `.11` still serves grafana.

- [ ] **Step 7: Commit**

```bash
cd .. && git add dev/gateway-platform.tf && git commit -m "feat(ingress): add platform TLSRoute + grafana e2e proof route"
```

---

### Task 7: Verify HTTP→HTTPS redirect on the new front

- [ ] **Step 1: Curl :80 on 172.16.1.12**

Run:
```bash
curl -sS -i --resolve grafana.klucovsky.com:80:172.16.1.12 http://grafana.klucovsky.com/ | head -5
```
Expected: `HTTP/1.1 301 Moved Permanently` and `location: https://grafana.klucovsky.com/`

---

### Task 8: Remove the proof route (leave foundation in place, ready for Plan 2)

The Grafana proof route was only for validation. Remove it so Plan 2 can migrate routes cleanly. The three Gateways + relay + platform TLSRoute REMAIN (they are the foundation).

**Files:**
- Modify: `dev/gateway-platform.tf`

- [ ] **Step 1: Delete the `proof_grafana_route` resource block from `dev/gateway-platform.tf`**

Remove the entire `resource "kubectl_manifest" "proof_grafana_route" { ... }` block (and its explanatory comment) added in Task 6.

- [ ] **Step 2: Apply (destroys only the proof route)**

Run: `cd dev && terraform apply -auto-approve`
Expected: `Apply complete! Resources: 0 added, 0 changed, 1 destroyed.` (only `proof_grafana_route` destroyed).

- [ ] **Step 3: Confirm the proof route is gone and grafana on .11 still works**

Run: `kubectl get httproute proof-grafana -n observability 2>&1`
Expected: `Error from server (NotFound)`

Run: `curl -sS -k --resolve grafana.klucovsky.com:443:172.16.1.11 https://grafana.klucovsky.com/login -o /dev/null -w "%{http_code}\n"`
Expected: success (unchanged).

- [ ] **Step 4: Commit**

```bash
cd .. && git add dev/gateway-platform.tf && git commit -m "chore(ingress): remove grafana proof route (foundation validated)"
```

---

## Self-Review

**Spec coverage:** Implements the spec's "Ingress architecture (B2)" platform side and bakes in both PoC constraints (relay Endpoints; separate passthrough/redirect Gateways sharing one IP). Phase 1 (MetalLB widen) = Task 1; platform front + terminating + TLSRoute = Tasks 3-6. The shared tool hostname moves (auth/mail/minio → klucovsky) and the ~12-route migration + `.11` flip + `fatto-gateway` removal are explicitly **out of scope → Plan 2**. ✅

**Placeholder scan:** No TBDs. All YAML/commands complete. The two "if it didn't work" branches (Task 2 Step 3, Task 4 Step 3) are explicit, bounded fallbacks with concrete commands, not placeholders. ✅

**Name/type consistency:** Gateways `platform-terminating` / `platform-front-tls` / `platform-front-http`; Services `cilium-gateway-platform-terminating` / `cilium-gateway-platform-front-tls` / `cilium-gateway-platform-front-http`; relay `platform-terminating-relay`; TLSRoute `platform-klucovsky`; shared-IP key `platform-front`; IP `172.16.1.12`; TLSRoute is `v1alpha2`, Gateway/HTTPRoute `v1`. Consistent across tasks. ✅

## Risks / notes
- **Task 2 is a hard gate.** If MetalLB cannot share one IP across the two front Gateways, the `:80`+`:443` split is infeasible on a single public IP — escalate before proceeding.
- The grafana Service name in Task 6 is an assumption (`kube-prometheus-stack-grafana`); verify and adjust before applying.
- `kubernetes_endpoints` is the legacy Endpoints API; acceptable here (single static target). If the terminating Gateway's ClusterIP ever changes (Gateway recreated), re-apply to refresh the relay Endpoints.
- All work is on `.12`; `fatto-gateway` on `.11` remains the live ingress until Plan 2.
