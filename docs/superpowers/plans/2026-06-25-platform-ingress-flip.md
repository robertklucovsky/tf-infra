# Platform Ingress Flip (B2 completion) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Complete the B2 ingress migration so `tf-platform` is fatto-free at the ingress layer: move `auth`/`mail`/`minio` from `*.dev.fatto.online` to `*.klucovsky.com`, centralize all platform-tool routes on `platform-terminating`, then **flip** — remove `fatto-gateway` and move the front gateways onto `172.16.1.11` (the router's public target).

**Architecture:** All `*.klucovsky.com` tool routes live in `dev/routes-platform.tf` (attached to `platform-terminating`, behind the passthrough fronts). `auth`/`mail`/`minio` join them with klucovsky hostnames (Keycloak's `KC_HOSTNAME` switches to `auth.klucovsky.com`). The original per-service route resources and `fatto-gateway` + fatto wildcard certs are removed. The fronts' shared MetalLB IP moves `172.16.1.12 → 172.16.1.11` once `fatto-gateway` frees it.

**Tech Stack:** Terraform (`alekc/kubectl`, `hashicorp/kubernetes`), Cilium Gateway API, MetalLB, `ssh cwwk` for any node ops (none expected).

**Prerequisites:** Plans 0–2 done; WIP baseline committed (`93010c8`); branch `design/platform-tenant-separation`.

**DNS note (why downtime is brief):** `*.klucovsky.com` already resolves to `172.16.1.11`. The flip keeps `.11` as the serving IP — only its owner changes from `fatto-gateway` to the front gateways. So no DNS change is needed; downtime is just the MetalLB reassignment window of `.11`.

**Downtime:** A short window (seconds–~2 min) during Task 5 when `fatto-gateway` is deleted and the fronts take `.11`. All platform tools (grafana, nexus, etc.) blip during that window. The fatto domain (`*.dev.fatto.online`) stops being served permanently — it has no live consumers (tenant undeployed; `auth`/`mail`/`minio` move to klucovsky).

**Apply discipline:** Working tree is clean post-baseline; still prefer `-target` for control. Never a bare `terraform apply` without reviewing the plan first.

---

### Task 1: Add auth/mail/minio routes (klucovsky) to routes-platform.tf

**Files:** Modify `dev/routes-platform.tf`

- [ ] **Step 1: Add three entries to the `platform_tool_routes` map**

Insert into the `locals.platform_tool_routes` map in `dev/routes-platform.tf`:

```hcl
    keycloak = {
      namespace = "keycloak"
      hostname  = "auth.klucovsky.com"
      backend   = "keycloak"
      port      = 80
    }
    mailpit = {
      namespace = "mailpit"
      hostname  = "mail.klucovsky.com"
      backend   = "mailpit"
      port      = 8025
    }
    minio = {
      namespace = "minio"
      hostname  = "minio.klucovsky.com"
      backend   = "minio"
      port      = 9001
    }
```

- [ ] **Step 2: Apply (targeted) — creates 3 new routes on platform-terminating**

Run: `cd dev && terraform apply -target=kubectl_manifest.platform_tool_route -auto-approve`
Expected: `Apply complete! Resources: 3 added` (keycloak/mailpit/minio `-platform` routes).

- [ ] **Step 3: Verify the 3 new routes Accepted**

Run:
```bash
kubectl get httproute keycloak-platform -n keycloak -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}{"\n"}'
kubectl get httproute mailpit-platform -n mailpit -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}{"\n"}'
kubectl get httproute minio-platform -n minio -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}{"\n"}'
```
Expected: `True` for each.

- [ ] **Step 4: Commit**

```bash
cd .. && git add dev/routes-platform.tf && git commit -m "feat(ingress): add auth/mail/minio klucovsky routes on platform-terminating"
```

---

### Task 2: Switch Keycloak KC_HOSTNAME to auth.klucovsky.com

Keycloak 26 strictly enforces `KC_HOSTNAME`; serving on `auth.klucovsky.com` requires this change. No live OIDC clients depend on the old issuer (tenant undeployed).

**Files:** Modify `dev/keycloak.tf:176`

- [ ] **Step 1: Change the env value**

In `dev/keycloak.tf`, the `KC_HOSTNAME` env:
```hcl
          env {
            name  = "KC_HOSTNAME"
            value = "https://auth.klucovsky.com"
          }
```
(was `"https://auth.${var.domain}"`)

- [ ] **Step 2: Apply (targeted) — triggers a Keycloak rollout**

Run: `cd dev && terraform apply -target=kubernetes_stateful_set.keycloak -auto-approve`
Expected: `1 changed`; Keycloak pod restarts.

- [ ] **Step 3: Wait for Keycloak ready, then verify it serves on the new hostname via .12**

Run:
```bash
kubectl rollout status statefulset/keycloak -n keycloak --timeout=180s
curl -sS -k --max-time 15 --resolve auth.klucovsky.com:443:172.16.1.12 https://auth.klucovsky.com/realms/master -o /dev/null -w "HTTP %{http_code}\n"
```
Expected: rollout complete; HTTP `200` (master realm endpoint).

- [ ] **Step 4: Commit**

```bash
cd .. && git add dev/keycloak.tf && git commit -m "feat(keycloak): serve on auth.klucovsky.com (off the fatto domain)"
```

---

### Task 3: Validate auth/mail/minio end-to-end on .12

- [ ] **Step 1: Curl each via the new ingress (.12)**

Run:
```bash
for pair in auth.klucovsky.com:/realms/master mail.klucovsky.com:/ minio.klucovsky.com:/; do
  h=${pair%%:*}; p=${pair#*:}
  code=$(curl -sS -k --max-time 15 --resolve $h:443:172.16.1.12 https://$h$p -o /dev/null -w "%{http_code}" 2>/dev/null)
  echo "$h$p -> $code"
done
```
Expected: `auth` → 200; `mail` → 200; `minio` → 200 or 3xx (console redirect). Re-run any `000` once (fresh-IP ARP settle).

---

### Task 4: Remove the original per-service routes + fatto-gateway + fatto certs

All tools are now served via `platform-terminating` (routes-platform.tf). Remove the now-redundant originals and the fatto-domain ingress objects.

**Files:** Modify `dev/observability.tf`, `dev/nexus.tf`, `dev/zot.tf`, `dev/sonarqube.tf`, `dev/pgadmin.tf`, `dev/argocd.tf`, `dev/keycloak.tf`, `dev/mailpit.tf`, `dev/minio.tf`, `dev/gateway.tf`, `dev/certificates.tf`

- [ ] **Step 1: Destroy the 11 original route resources + fatto-gateway + fatto certs (targeted, before editing files)**

Run from `dev/`:
```bash
cd dev && terraform destroy -auto-approve \
  -target=kubectl_manifest.route_grafana \
  -target=kubectl_manifest.route_prometheus \
  -target=kubectl_manifest.route_alertmanager \
  -target=kubectl_manifest.nexus_route \
  -target=kubectl_manifest.zot_route \
  -target=kubectl_manifest.sonarqube_route \
  -target=kubectl_manifest.pgadmin_route \
  -target=kubectl_manifest.argocd_route \
  -target=kubectl_manifest.route_keycloak \
  -target=kubectl_manifest.route_mailpit \
  -target=kubectl_manifest.route_minio \
  -target=kubectl_manifest.cert_dev_wildcard \
  -target=kubectl_manifest.cert_test_wildcard \
  -target=kubectl_manifest.gateway
```
Expected: `14 destroyed`. After this, `fatto-gateway` is gone and `172.16.1.11` is free.

- [ ] **Step 2: Remove the corresponding resource blocks from the files**

Delete these resource blocks so config matches state:
- `dev/observability.tf`: `route_grafana`, `route_prometheus`, `route_alertmanager`
- `dev/nexus.tf`: `nexus_route`
- `dev/zot.tf`: `zot_route`
- `dev/sonarqube.tf`: `sonarqube_route`
- `dev/pgadmin.tf`: `pgadmin_route`
- `dev/argocd.tf`: `argocd_route`
- `dev/keycloak.tf`: `route_keycloak`
- `dev/mailpit.tf`: `route_mailpit`
- `dev/minio.tf`: `route_minio`
- `dev/gateway.tf`: the `kubectl_manifest.gateway` resource (the whole `fatto-gateway`)
- `dev/certificates.tf`: `cert_dev_wildcard`, `cert_test_wildcard`

- [ ] **Step 3: Validate config is consistent (no dangling references)**

Run: `cd dev && terraform validate`
Expected: `Success! The configuration is valid.` (If any resource still references `var.domain` or the removed routes, fix it — see Task 6 for `var.domain` cleanup.)

- [ ] **Step 4: Confirm fatto-gateway is gone and .11 is free**

Run:
```bash
kubectl get gateway -n gateway
kubectl get svc -n gateway -o jsonpath='{range .items[*]}{.metadata.name}={.status.loadBalancer.ingress[0].ip}{"\n"}{end}' | grep cilium-gateway
```
Expected: only `platform-front-tls`, `platform-front-http`, `platform-terminating` remain; no service holds `172.16.1.11`.

- [ ] **Step 5: Commit**

```bash
cd .. && git add -A dev/ && git commit -m "feat(ingress): remove fatto-gateway, original routes, and fatto wildcard certs"
```

---

### Task 5: Flip the fronts onto 172.16.1.11

**Files:** Modify `dev/gateway-platform.tf` (the two front annotation resources)

- [ ] **Step 1: Change both fronts' loadBalancerIPs to 172.16.1.11**

In `dev/gateway-platform.tf`, in `kubernetes_annotations.front_tls_lb_ip` and `kubernetes_annotations.front_http_lb_ip`, change:
```hcl
    "metallb.io/loadBalancerIPs" = "172.16.1.11"
```
(was `172.16.1.12`; keep `allow-shared-ip = "platform-front"` on both.)

- [ ] **Step 2: Apply (targeted)**

Run:
```bash
cd dev && terraform apply \
  -target=kubernetes_annotations.front_tls_lb_ip \
  -target=kubernetes_annotations.front_http_lb_ip -auto-approve
```
Expected: `2 changed`.

- [ ] **Step 3: Nudge MetalLB if the fronts don't pick up .11 within ~30s**

Run:
```bash
for i in $(seq 1 6); do
  a=$(kubectl get svc cilium-gateway-platform-front-tls -n gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  b=$(kubectl get svc cilium-gateway-platform-front-http -n gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  echo "front-tls=$a front-http=$b"; [ "$a" = "172.16.1.11" ] && [ "$b" = "172.16.1.11" ] && break; sleep 5
done
```
If still not `.11` (MetalLB no-retry): nudge with a throwaway annotation toggle:
```bash
kubectl annotate svc cilium-gateway-platform-front-tls cilium-gateway-platform-front-http -n gateway nudge=1 --overwrite
sleep 3
kubectl annotate svc cilium-gateway-platform-front-tls cilium-gateway-platform-front-http -n gateway nudge-
```
Then re-check until both show `172.16.1.11`.

- [ ] **Step 4: Commit**

```bash
cd .. && git add dev/gateway-platform.tf && git commit -m "feat(ingress): flip front gateways onto 172.16.1.11"
```

---

### Task 6: Drop the now-unused var.domain from the platform (if unreferenced)

After the flip, nothing in `tf-platform` should reference the fatto domain.

**Files:** Modify `dev/variables.tf`, `dev/terraform.tfvars` (and any stragglers)

- [ ] **Step 1: Find remaining references**

Run: `cd dev && grep -rnE "var\.domain|fatto\.online|\$\{var.domain\}" *.tf terraform.tfvars`
Expected (goal): no functional references remain. If `var.domain` is unused, remove the variable from `variables.tf` and its value from `terraform.tfvars`. If something still uses it, note it for the cosmetic plan rather than forcing removal here.

- [ ] **Step 2: Validate**

Run: `cd dev && terraform validate`
Expected: `Success!`

- [ ] **Step 3: Commit (if changes made)**

```bash
cd .. && git add dev/variables.tf dev/terraform.tfvars && git commit -m "chore: drop unused var.domain (fatto) from platform"
```

---

### Task 7: Full validation on 172.16.1.11

- [ ] **Step 1: Curl every platform hostname via .11**

Run:
```bash
for h in grafana.klucovsky.com prometheus.klucovsky.com alertmanager.klucovsky.com \
         nexus.klucovsky.com registry.klucovsky.com sonar.klucovsky.com \
         db.klucovsky.com argocd.klucovsky.com auth.klucovsky.com \
         mail.klucovsky.com minio.klucovsky.com; do
  code=$(curl -sS -k --max-time 15 --resolve $h:443:172.16.1.11 https://$h/ -o /dev/null -w "%{http_code}" 2>/dev/null)
  echo "$h -> $code"
done
```
Expected: every host returns a real response (2xx/3xx/401) — none `000`/`404`/`5xx`. `auth.klucovsky.com/` may be 302/404; use `/realms/master` → 200 to confirm Keycloak.

- [ ] **Step 2: HTTP→HTTPS redirect on .11**

Run: `curl -sS -i --max-time 15 --resolve grafana.klucovsky.com:80:172.16.1.11 http://grafana.klucovsky.com/ | head -3`
Expected: `301` → `https://grafana.klucovsky.com/`.

- [ ] **Step 3: Confirm fatto domain no longer served (expected)**

Run: `curl -sS -k --max-time 8 --resolve auth.dev.fatto.online:443:172.16.1.11 https://auth.dev.fatto.online/ -o /dev/null -w "%{http_code}\n" 2>&1 || true`
Expected: failure/`000`/no route — the fatto domain is intentionally gone.

- [ ] **Step 4: Report results.** If all klucovsky hosts pass on `.11`, the platform ingress flip is complete.

---

## Self-Review

**Spec coverage:** Completes the "shared tools on `*.klucovsky.com`" move and the `.11` flip from the design's ingress section (the platform-only path agreed when the tenant was found undeployed). Project gateway / fatto-domain serving is correctly deferred to tenant deployment. ✅

**Placeholder scan:** Exact files, resource names, hostnames, ports, and commands throughout. Task 6 is conditional (remove `var.domain` only if unreferenced) with an explicit fallback. ✅

**Name/type consistency:** Route resource names match those discovered live (`route_grafana`/`route_prometheus`/`route_alertmanager`/`nexus_route`/`zot_route`/`sonarqube_route`/`pgadmin_route`/`argocd_route`/`route_keycloak`/`route_mailpit`/`route_minio`); annotation resources and IPs (`.11`) match Plan 1/2. ✅

## Risks / rollback
- **Downtime window (Task 4–5):** between `fatto-gateway` removal and the fronts taking `.11`. Mitigate by running Task 4 Step 1 and Task 5 back-to-back. If the fronts fail to take `.11`, the nudge (Task 5 Step 3) resolves the MetalLB no-retry; worst case, temporarily re-create `fatto-gateway` (it's in git history) to restore `.11` while debugging.
- **Keycloak hostname:** switching `KC_HOSTNAME` is one-way for this environment; fine since no live clients. If the tenant is later deployed, its OIDC clients must use `auth.klucovsky.com`.
- **MetalLB no-retry:** known from Plan 1 — the nudge is the remedy.
- This plan does not touch the (undeployed) tenant repo or any tenant-owned resource.
