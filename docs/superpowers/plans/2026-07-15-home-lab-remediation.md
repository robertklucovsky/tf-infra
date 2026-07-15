# Home-lab Security Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the approved remediations — split the ingress so only `s3`/`auth`/`fatto-aac` are internet-reachable, put Keycloak in production mode, enforce Postgres TLS, tighten the NFS export, and add a least-privilege VPN ACL — safely, with rollback and verification at every step.

**Architecture:** In-repo Terraform changes (applied by the agent via `terraform plan` → review → `apply`) plus live Omada (API) and host (SSH) changes with before/after capture and rollback. A new **direct terminating** gateway on `172.16.1.12` serves only the 3 public hosts; the router's 80/443 forward is repointed to it last, leaving the existing all-hosts path (`172.16.1.11`) intranet-only.

**Tech Stack:** Terraform v1.15.5 (providers: kubernetes, helm, kubectl, postgresql, nexus, digitalocean), Cilium Gateway API, CloudNativePG, Keycloak 26.6.4, Omada Controller v6 API, WireGuard on ER605.

## Global Constraints

- **Working dir:** all `terraform` commands run in `dev/` (`/Users/robert.klucovsky/Developer/private-projects/tf-platform/dev`).
- **State backend is `local`** (post-teardown migration). **Task 1 gates everything**: no `apply` until `terraform plan` is reviewed and shows no unexpected destroys/creates.
- **Exposure model:** internet-public = `s3.klucovsky.com`, `auth.klucovsky.com`, `fatto-aac.klucovsky.com`, WireGuard UDP 51820. Everything else intranet-only.
- **MetalLB pool** `172.16.1.11-172.16.1.13`; **`.12` is free**; public gateway uses `.12`. `[verified]`
- **Wildcard cert secret** to reuse: `klucovsky-wildcard-tls` in namespace `gateway`. `[verified]`
- **LAN-first ordering:** apply order A (Terraform) → C (NFS) → B (Omada). Do B (router repoint + ACL) **only while connected on LAN**, revert-ready.
- **VPN ACL policy:** deny tunnel `10.172.16.0/24` → node on `2379`, `10250`, `9100`; allow `443`, `22`, `6443`, `30432`, `2049`, `111`, `53`.
- **NFS:** export `/data` only to `10.172.16.2/32`, `10.172.16.3/32`, `10.172.16.4/32` (peers) + `172.16.1.0/24` (LAN), option `secure`, keep `rw,root_squash,all_squash`.
- **Postgres TLS:** enforce `hostssl` (server rejects plaintext) only after all consumers use `sslmode=require`; tenants (out-of-repo, e.g. `fatto-erp`) must be switched by the operator in lockstep.
- **Commits:** `feat(security):`/`chore(security):` as fits; end with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Omada API base:** `https://172.16.1.2:8043/911e6d163a1e7e9e20ae3728e4ae7cc3/api/v2` (login `POST /api/v2/login`, `Csrf-Token` header + cookie). Site id `67fe23d9da5d1c5ac5a98a71`. Read-modify-write; capture original JSON for rollback.

---

## File Structure

- Create: `dev/gateway-public.tf` — the internet-facing gateway (`.12`) + its HTTP-redirect gateway + MetalLB pinning + the 3 public HTTPRoutes. New file, one responsibility (public ingress), keeps `gateway-platform.tf` (internal ingress) untouched.
- Modify: `dev/keycloak.tf` — production mode args.
- Modify: `dev/cnpg.tf` — CNPG `pg_hba` hostssl enforcement.
- Modify: `dev/main.tf` — `postgresql` provider `sslmode`.
- Modify: `dev/postgresql.tf` — Keycloak JDBC URL `sslmode=require`.
- Modify: `README.md` — update the `PG_CONN_STR` example to `sslmode=require`.
- Live (no repo file): Omada port-forward + ACL + VLAN isolation; `cwwk:/etc/exports.d/` NFS export.

---

### Task 1: Baseline — init, plan, and drift review (SAFETY GATE)

**Files:** none (read-only gate).

- [ ] **Step 1: Init and plan**

Run:
```bash
cd /Users/robert.klucovsky/Developer/private-projects/tf-platform/dev
terraform init -input=false
terraform plan -no-color -out=/tmp/tf-baseline.plan 2>&1 | tee /tmp/tf-baseline.txt
```

- [ ] **Step 2: Review the plan for drift**

Read `/tmp/tf-baseline.txt`. Expected: **no changes**, or only benign in-place updates.
STOP and escalate to the operator if the plan proposes to **destroy** or **recreate** any of: `kubectl_manifest.cnpg_cluster`, `kubernetes_service.cnpg_nodeport`, any `platform_*` gateway/route, `kubernetes_stateful_set.keycloak`, `postgresql_database.*`. A post-teardown local state may not match the running cluster; do not proceed with a destructive baseline.

- [ ] **Step 3: Record the clean baseline**

Only when the plan is non-destructive, proceed. No commit (read-only).

---

### Task 2 (A1): Public gateway on `.12` serving only s3/auth/fatto-aac

**Files:**
- Create: `dev/gateway-public.tf`

**Interfaces:**
- Produces: Gateway `platform-public` (ns `gateway`) that later HTTPRoutes and the router repoint (Task 7) depend on; MetalLB IP `172.16.1.12`.

- [ ] **Step 1: Write `dev/gateway-public.tf`**

```hcl
# -----------------------------------------------------------------------------
# PUBLIC INGRESS — internet-facing gateway on 172.16.1.12
#
# Serves ONLY s3/auth/fatto-aac (the intentionally-public hosts). The router's
# 80/443 forward is repointed here (see remediation plan Task 7), leaving the
# all-hosts path on 172.16.1.11 intranet-only. Direct-terminating on its own LB
# IP (verified working against the existing terminating gateway's .13).
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "platform_public_gw" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: platform-public
      namespace: gateway
      annotations:
        metallb.io/allow-shared-ip: "platform-public"
        metallb.io/loadBalancerIPs: "172.16.1.12"
    spec:
      gatewayClassName: ck-gateway
      listeners:
        - name: https-public
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

resource "kubectl_manifest" "platform_public_http_gw" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: platform-public-http
      namespace: gateway
      annotations:
        metallb.io/allow-shared-ip: "platform-public"
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

# HTTP -> HTTPS 301 redirect on the public IP.
resource "kubectl_manifest" "platform_public_http_redirect" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: platform-public-http-redirect
      namespace: gateway
    spec:
      parentRefs:
        - name: platform-public-http
          sectionName: http
      rules:
        - filters:
            - type: RequestRedirect
              requestRedirect:
                scheme: https
                statusCode: 301
  YAML

  depends_on = [kubectl_manifest.platform_public_http_gw]
}

# Pin MetalLB IP on the generated cilium-gateway-* Services (annotations on the
# Gateway are not propagated by Cilium — same reason as gateway-platform.tf).
resource "kubernetes_annotations" "public_https_lb_ip" {
  api_version = "v1"
  kind        = "Service"
  metadata {
    name      = "cilium-gateway-platform-public"
    namespace = "gateway"
  }
  annotations = {
    "metallb.io/allow-shared-ip" = "platform-public"
    "metallb.io/loadBalancerIPs" = "172.16.1.12"
  }
  force      = true
  depends_on = [kubectl_manifest.platform_public_gw]
}

resource "kubernetes_annotations" "public_http_lb_ip" {
  api_version = "v1"
  kind        = "Service"
  metadata {
    name      = "cilium-gateway-platform-public-http"
    namespace = "gateway"
  }
  annotations = {
    "metallb.io/allow-shared-ip" = "platform-public"
    "metallb.io/loadBalancerIPs" = "172.16.1.12"
  }
  force      = true
  depends_on = [kubectl_manifest.platform_public_http_gw]
}

# Public HTTPRoutes — one per public host, in the backend's namespace
# (cross-namespace parentRef is allowed by allowedRoutes.namespaces.from=All).
resource "kubectl_manifest" "s3_public_route" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: s3-public
      namespace: rustfs
    spec:
      parentRefs:
        - name: platform-public
          namespace: gateway
          sectionName: https-public
      hostnames:
        - "s3.klucovsky.com"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: rustfs
              port: 9001
  YAML

  depends_on = [kubectl_manifest.platform_public_gw]
}

resource "kubectl_manifest" "auth_public_route" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: auth-public
      namespace: keycloak
    spec:
      parentRefs:
        - name: platform-public
          namespace: gateway
          sectionName: https-public
      hostnames:
        - "auth.klucovsky.com"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: keycloak
              port: 80
  YAML

  depends_on = [kubectl_manifest.platform_public_gw]
}

resource "kubectl_manifest" "fatto_aac_public_redirect" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: fatto-aac-public
      namespace: rustfs
    spec:
      parentRefs:
        - name: platform-public
          namespace: gateway
          sectionName: https-public
      hostnames:
        - "fatto-aac.klucovsky.com"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          filters:
            - type: RequestRedirect
              requestRedirect:
                scheme: https
                hostname: s3.klucovsky.com
                path:
                  type: ReplaceFullPath
                  replaceFullPath: /rustfs/admin/v3/oidc/authorize/default
                statusCode: 302
  YAML

  depends_on = [kubectl_manifest.platform_public_gw]
}
```

- [ ] **Step 2: Plan and review**

Run: `terraform plan -no-color 2>&1 | tee /tmp/tf-a1.txt`
Expected: only **additions** (the new gateways, routes, annotations). No destroys.

- [ ] **Step 3: Apply**

Run: `terraform apply -auto-approve 2>&1 | tee /tmp/tf-a1-apply.txt`
Expected: apply complete, resources added.

- [ ] **Step 4: Verify the public gateway serves the 3 hosts on `.12` (router NOT yet repointed)**

Run:
```bash
kubectl get svc -n gateway cilium-gateway-platform-public -o jsonpath='{.status.loadBalancer.ingress[0].ip}'; echo   # expect 172.16.1.12
for h in s3 auth fatto-aac; do
  curl -sk --max-time 8 --resolve $h.klucovsky.com:443:172.16.1.12 https://$h.klucovsky.com/ -o /dev/null -w "$h via .12 -> %{http_code}\n"
done
# a NON-public host must NOT be served by the public gateway:
curl -sk --max-time 8 --resolve prometheus.klucovsky.com:443:172.16.1.12 https://prometheus.klucovsky.com/ -o /dev/null -w "prometheus via .12 -> %{http_code} (expect 404)\n"
```
Expected: `s3` → 403/200, `auth` → 302/200, `fatto-aac` → 302; `prometheus` → 404 (no route on the public gateway).

- [ ] **Step 5: Commit**

```bash
git add dev/gateway-public.tf
git commit -m "feat(security): add internet-facing gateway on .12 for s3/auth/fatto-aac only"
```

---

### Task 3 (A2): Keycloak production mode

**Files:**
- Modify: `dev/keycloak.tf:88`

- [ ] **Step 1: Change the start command**

In `dev/keycloak.tf`, replace line 88:
```hcl
          args = ["start-dev", "--health-enabled=true"]
```
with:
```hcl
          # Production mode: `start` builds with KC_DB=postgres on boot and
          # enforces KC_HOSTNAME. TLS is terminated at the gateway, so HTTP stays
          # enabled behind the proxy (KC_HTTP_ENABLED + KC_PROXY_HEADERS below).
          args = ["start", "--health-enabled=true"]
```
Leave the existing env vars as-is: `KC_HOSTNAME=https://auth.klucovsky.com`, `KC_HTTP_ENABLED=true`, `KC_PROXY_HEADERS=xforwarded` are already correct for production behind a TLS-terminating proxy.

- [ ] **Step 2: Plan and apply**

Run:
```bash
terraform plan -no-color 2>&1 | tee /tmp/tf-a2.txt   # expect in-place update of the StatefulSet only
terraform apply -auto-approve 2>&1 | tee /tmp/tf-a2-apply.txt
```

- [ ] **Step 3: Verify Keycloak comes up in production mode and serves auth**

Run:
```bash
kubectl -n keycloak rollout status statefulset/keycloak --timeout=180s
kubectl -n keycloak logs statefulset/keycloak --tail=30 | grep -iE "started|profile|listening" | head
curl -sk --max-time 8 --resolve auth.klucovsky.com:443:172.16.1.12 https://auth.klucovsky.com/realms/master/.well-known/openid-configuration -o /dev/null -w "OIDC discovery -> %{http_code} (expect 200)\n"
```
Expected: rollout complete; logs show production profile (not "dev"); OIDC discovery 200.

- [ ] **Step 4: Verify the S3 OIDC login flow still works**

Manual/operator check: browse `https://fatto-aac.klucovsky.com` (via the public gateway) → Keycloak login → RustFS console. If the realm login page renders and authentication redirects back to S3, pass. (RustFS realm is `fatto-aac`; if login fails, check `KC_HOSTNAME` and the client redirect URIs — do not proceed to Task 7 until this works.)

- [ ] **Step 5: Commit**

```bash
git add dev/keycloak.tf
git commit -m "feat(security): run Keycloak in production mode (start)"
```

---

### Task 4 (A3a): Switch all DB consumers to `sslmode=require` (server still permissive)

**Files:**
- Modify: `dev/main.tf:78`
- Modify: `dev/postgresql.tf:82`
- Modify: `README.md` (PG_CONN_STR example)

- [ ] **Step 1: Provider to require TLS**

In `dev/main.tf`, in the `provider "postgresql"` block, change line 78:
```hcl
  sslmode  = "disable"
```
to:
```hcl
  sslmode  = "require"
```

- [ ] **Step 2: Keycloak JDBC URL to require TLS**

In `dev/postgresql.tf`, change the `keycloak-url` value (line 82):
```hcl
    "keycloak-url"      = "jdbc:postgresql://${local.pg_rw_host}:${local.pg_port}/keycloak"
```
to:
```hcl
    "keycloak-url"      = "jdbc:postgresql://${local.pg_rw_host}:${local.pg_port}/keycloak?sslmode=require"
```

- [ ] **Step 3: Update the README PG_CONN_STR examples**

In `README.md`, replace every `sslmode=disable` in the `PG_CONN_STR` examples with `sslmode=require` (lines ~26, ~43, ~53 and the `main.tf` comment block referenced in `dev/main.tf:42`).

- [ ] **Step 4: Plan, apply, verify clients still connect (over TLS)**

Run:
```bash
terraform plan -no-color 2>&1 | tee /tmp/tf-a3a.txt   # provider config + keycloak secret update
terraform apply -auto-approve 2>&1 | tee /tmp/tf-a3a-apply.txt
kubectl -n keycloak rollout status statefulset/keycloak --timeout=180s
# Confirm the postgresql provider can still read (roles/db exist) — a no-op refresh:
terraform plan -no-color 2>&1 | tail -5   # expect "No changes"
```
Expected: apply succeeds using `sslmode=require`; Keycloak reconnects over TLS; follow-up plan clean.

- [ ] **Step 5: Commit**

```bash
git add dev/main.tf dev/postgresql.tf README.md
git commit -m "chore(security): move Postgres consumers to sslmode=require"
```

---

### Task 5 (A3b): Enforce `hostssl` on CNPG (server rejects plaintext)

**Files:**
- Modify: `dev/cnpg.tf` (the `cnpg_cluster` YAML, `spec.postgresql`)

**Interfaces:**
- Consumes: all consumers already on `sslmode=require` (Task 4). **Do not run this task until Task 4 is verified and the operator has switched any tenant repos.**

- [ ] **Step 1: Add pg_hba TLS enforcement**

In `dev/cnpg.tf`, inside the `postgresql:` block of the `cnpg_cluster` manifest (after the `parameters:` block, around line 107), add a `pg_hba` list that rejects non-TLS TCP before CNPG's default permissive `host` rule (pg_hba is first-match):
```yaml
        pg_hba:
          # Reject all non-TLS TCP connections; TLS ones fall through to the
          # CNPG default host rule. local/replication rules are unaffected.
          - hostnossl all all 0.0.0.0/0 reject
          - hostnossl all all ::/0 reject
```
So the block reads:
```yaml
      postgresql:
        shared_preload_libraries:
          - age
          - pg_stat_statements
        parameters:
          max_connections: "200"
          shared_buffers: "256MB"
          log_statement: "ddl"
        pg_hba:
          - hostnossl all all 0.0.0.0/0 reject
          - hostnossl all all ::/0 reject
```

- [ ] **Step 2: Plan and apply**

Run:
```bash
terraform plan -no-color 2>&1 | tee /tmp/tf-a3b.txt   # in-place update of cnpg_cluster manifest
terraform apply -auto-approve 2>&1 | tee /tmp/tf-a3b-apply.txt
# CNPG reloads pg_hba without a restart; give it a few seconds.
sleep 10
```

- [ ] **Step 3: Verify plaintext is rejected and TLS works**

Run (uses the superuser password from `dev/secrets.auto.tfvars` — read it into `PGPASSWORD`, do not print it):
```bash
export PGPASSWORD=$(grep -E '^postgres_superuser_password' /Users/robert.klucovsky/Developer/private-projects/tf-platform/dev/secrets.auto.tfvars | sed -E 's/.*=\s*"?([^"]*)"?/\1/')
# plaintext must FAIL:
psql "host=172.16.1.11 port=30432 user=postgres dbname=postgres sslmode=disable connect_timeout=5" -c 'select 1' 2>&1 | tail -2   # expect: no pg_hba entry / SSL required
# TLS must SUCCEED:
psql "host=172.16.1.11 port=30432 user=postgres dbname=postgres sslmode=require connect_timeout=5" -c 'select 1' 2>&1 | tail -2   # expect: 1 row
unset PGPASSWORD
```
Expected: `sslmode=disable` rejected ("no pg_hba.conf entry ... no encryption" / "SSL required"); `sslmode=require` returns `1`. Also confirm Keycloak still healthy: `kubectl -n keycloak rollout status statefulset/keycloak --timeout=120s`.

- [ ] **Step 4: Commit**

```bash
git add dev/cnpg.tf
git commit -m "feat(security): enforce hostssl on CNPG (reject plaintext Postgres)"
```

**Rollback (if any consumer is locked out):** remove the two `hostnossl ... reject` lines, `terraform apply`, then fix the consumer.

---

### Task 6 (C1): Narrow the NFS `/data` export (host `cwwk`, via SSH)

**Files:** none in repo (host config: `cwwk:/etc/exports` or `/etc/exports.d/*.exports`).

- [ ] **Step 1: Capture the current export (rollback baseline)**

Run:
```bash
ssh cwwk 'sudo -n exportfs -v; echo "--- files ---"; sudo -n grep -RH "/data" /etc/exports /etc/exports.d/ 2>/dev/null'
```
Record the exact current line(s) and their source file. Save to `/tmp/nfs-exports-before.txt`.

- [ ] **Step 2: Replace the broad export with peer-scoped, `secure` entries**

Identify the file that defines the `/data` export (from Step 1). Edit that file so the `/data` line(s) become:
```
/data 172.16.1.0/24(rw,sync,no_subtree_check,root_squash,all_squash,secure)
/data 10.172.16.2/32(rw,sync,no_subtree_check,root_squash,all_squash,secure)
/data 10.172.16.3/32(rw,sync,no_subtree_check,root_squash,all_squash,secure)
/data 10.172.16.4/32(rw,sync,no_subtree_check,root_squash,all_squash,secure)
```
(Remove the old `10.172.16.0/24` and `insecure` variants.) Apply with:
```bash
ssh cwwk 'sudo -n exportfs -ra && sudo -n exportfs -v | grep /data'
```

- [ ] **Step 3: Verify**

Run:
```bash
ssh cwwk 'sudo -n exportfs -v | grep /data'   # expect only the 3 peer /32s + LAN, with secure
ssh cwwk 'showmount -e localhost 2>/dev/null | grep /data || true'
```
Operator check from a real WireGuard peer (`10.172.16.2/3/4`): `mount` of `172.16.1.11:/data` still works.

- [ ] **Step 4: Record (no repo commit; host change)**

Note the change and the rollback line in `/tmp/nfs-exports-after.txt`. **Rollback:** restore the original line from `/tmp/nfs-exports-before.txt` + `sudo exportfs -ra`.

---

### Task 7 (B1): Repoint the router 80/443 forward `.11` → `.12` (Omada API)

**Preconditions:** Tasks 2–5 applied and verified; operator is on the LAN.

- [ ] **Step 1: Log in and capture the current port-forward rules (rollback baseline)**

Run (uses admin creds; do not print the password):
```bash
python3 - <<'PY'
import json,ssl,os,urllib.request as u
from http.cookiejar import CookieJar
H="https://172.16.1.2:8043";O="911e6d163a1e7e9e20ae3728e4ae7cc3";S="67fe23d9da5d1c5ac5a98a71"
ctx=ssl.create_default_context();ctx.check_hostname=False;ctx.verify_mode=ssl.CERT_NONE
op=u.build_opener(u.HTTPSHandler(context=ctx),u.HTTPCookieProcessor(CookieJar()))
def call(p,b=None,tok=None,m="GET"):
    r=u.Request(H+p,data=(json.dumps(b).encode() if b else None),method=m,
                headers={"Content-Type":"application/json",**({"Csrf-Token":tok} if tok else {})})
    return json.loads(op.open(r,timeout=20).read().decode())
import getpass
tok=call("/api/v2/login",{"username":"admin","password":open('/dev/stdin').readline().strip()})["result"]["token"]
d=call(f"/{O}/api/v2/sites/{S}/setting/transmission/portForwardings?currentPage=1&currentPageSize=100",tok=tok)
json.dump(d,open("/tmp/omada-portforward-before.json","w"),indent=2)
for row in d["result"]["data"]:
    print(row.get("id"),row.get("name"),row.get("externalPort"),"->",row.get("forwardIp"),row.get("forwardPort"),"status",row.get("status"))
PY
```
(Provide the admin password on stdin when prompted; it is not stored.) Expect two rules `HTTP` (80) and `HTTPS` (443) → `172.16.1.11`. Confirm `/tmp/omada-portforward-before.json` is written.

- [ ] **Step 2: Update both rules' `forwardIp` to `172.16.1.12`**

For each of the two rules, PATCH/PUT the rule with `forwardIp` changed to `172.16.1.12` (keep every other field identical, using the object captured in Step 1). Endpoint: `PATCH /{O}/api/v2/sites/{S}/setting/transmission/portForwardings/{id}` with the full modified rule body. Verify each call returns `errorCode: 0`.

- [ ] **Step 3: Verify the public path now serves only the 3 hosts, internal path unchanged**

Run (using the real public IP if reachable, else confirm via the LB mapping):
```bash
# internal path (.11) still serves all hosts:
curl -sk --max-time 8 --resolve grafana.klucovsky.com:443:172.16.1.11 https://grafana.klucovsky.com/ -o /dev/null -w "grafana via .11 -> %{http_code} (expect 200/302)\n"
# public gateway (.12) serves the 3, 404s others (already verified in Task 2):
curl -sk --max-time 8 --resolve s3.klucovsky.com:443:172.16.1.12 https://s3.klucovsky.com/ -o /dev/null -w "s3 via .12 -> %{http_code}\n"
```
Operator check from the internet (phone off-Wi-Fi): `https://s3.klucovsky.com` works; `https://grafana.klucovsky.com` does NOT resolve/serve (no public DNS + public gateway 404s it).

- [ ] **Step 4: Record. Rollback:** re-PATCH both rules' `forwardIp` back to `172.16.1.11` from `/tmp/omada-portforward-before.json`.

---

### Task 8 (B2): VPN least-privilege ACL (Omada API)

**Preconditions:** operator on LAN; Task 7 done.

- [ ] **Step 1: Capture current gateway ACLs (rollback baseline)**

Run: `GET /{O}/api/v2/sites/{S}/setting/firewall/acls?type=0&currentPage=1&currentPageSize=100` (and `type=1`, `type=2`) with the login helper from Task 7; save to `/tmp/omada-acls-before.json`.

- [ ] **Step 2: Add deny rules VPN → node sensitive ports**

Create gateway ACL rules (default-permit network, so add explicit **deny** rules) from source `10.172.16.0/24` to destination `172.16.1.11` for TCP `2379`, `10250`, `9100`, placed above any allow. Use the Omada ACL create endpoint (`POST /{O}/api/v2/sites/{S}/setting/firewall/acls`) mirroring the structure of an existing rule from Step 1. Leave `443/22/6443/30432/2049/111/53` unrestricted (default permit). Verify each POST returns `errorCode: 0`.

- [ ] **Step 3: Verify (operator, from a real WireGuard peer)**

From a connected peer:
```bash
for p in 443 22 6443 30432 2049; do timeout 4 bash -c "echo > /dev/tcp/172.16.1.11/$p" 2>/dev/null && echo "$p OPEN (expected)" || echo "$p blocked (UNEXPECTED)"; done
for p in 2379 10250 9100; do timeout 4 bash -c "echo > /dev/tcp/172.16.1.11/$p" 2>/dev/null && echo "$p OPEN (UNEXPECTED)" || echo "$p blocked (expected)"; done
```
Also confirm a real internal app (443), SSH, `kubectl get nodes`, `terraform plan`, and an NFS mount still work from the peer.

- [ ] **Step 4: Record. Rollback:** delete the added ACL rules (by id) to restore the state in `/tmp/omada-acls-before.json`.

---

### Task 9 (B3): Inter-VLAN isolation for VLAN 10 / 20 (Omada API)

**Preconditions:** operator on LAN.

- [ ] **Step 1: Capture current LAN network settings**

`GET /{O}/api/v2/sites/{S}/setting/lan/networks?currentPage=1&currentPageSize=100`; save to `/tmp/omada-lan-before.json`. Note VLAN 10 (`172.16.2.0/24`) and VLAN 20 (`172.16.3.0/24`) currently have `isolation=false`.

- [ ] **Step 2: Enable network isolation on VLAN 10 and 20**

For each of the two network objects, set `isolation=true` (keep all other fields from Step 1) and PUT it back via `PATCH /{O}/api/v2/sites/{S}/setting/lan/networks/{id}`. These VLANs are currently empty, so no live traffic is affected. Verify `errorCode: 0`.

- [ ] **Step 3: Verify**

`GET` the LAN networks again; confirm VLAN 10/20 now report `isolation=true`. (Full effect is validated when the OpenStack/Ceph cloud is powered on — out of scope now.)

- [ ] **Step 4: Record. Rollback:** set `isolation=false` from `/tmp/omada-lan-before.json`.

---

## Self-Review (plan vs spec)

- **Spec coverage:** A1 public gateway (Task 2), A2 Keycloak prod (Task 3), A3 Postgres TLS enforced — staged clients (Task 4) + hostssl enforce (Task 5), B1 router repoint (Task 7), B2 VPN ACL (Task 8), B3 inter-VLAN isolation (Task 9), C1 NFS narrow (Task 6). Baseline drift gate (Task 1). All spec workstreams mapped. ✓
- **Apply order** matches the spec (A → C → B, LAN-first, Omada last). ✓
- **Rollback** present for every risky task (A: git revert / hostssl revert; B: restore captured JSON; C: restore exports). ✓
- **Verification** is concrete per task (curl --resolve, psql sslmode, TCP reachability, OIDC). ✓
- **No placeholders:** exact HCL and commands given; Omada write payloads use read-modify-write against the captured objects (ids only known at runtime — the safe pattern for a live controller, not a placeholder). ✓
- **Consistency:** resource names (`platform-public`, `platform-public-http`, `s3-public`/`auth-public`/`fatto-aac-public`), IP `.12`, cert secret `klucovsky-wildcard-tls`, and the VPN ACL port list match the spec's Global Constraints throughout. ✓
- **Secrets:** superuser password and admin password are read at runtime (stdin/tfvars) and never printed or committed. ✓
