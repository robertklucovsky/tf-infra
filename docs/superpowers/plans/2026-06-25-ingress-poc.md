# Ingress PoC (B2 passthrough + TLSRoute) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove on this cluster that a generic TLS-passthrough front Gateway can route by wildcard SNI (via `TLSRoute`) to a terminating backend Gateway that owns the cert — the foundation of the B2 ingress design — with zero impact on the live `fatto-gateway`.

**Architecture:** A throwaway `poc` namespace holds an echo app, a self-signed cert, a terminating backend Gateway (HTTPS, owns cert, host-routes to echo), and a front Gateway (`:443` TLS passthrough + `:80` HTTP→HTTPS redirect) with a `TLSRoute` matching `*.poc.test` SNI and forwarding to the backend Gateway service. Validation is done in-cluster against the front Gateway's ClusterIP (no MetalLB IP, no DNS, no router involvement). Everything is torn down at the end.

**Tech Stack:** Cilium 1.17.12 Gateway API (`ck-gateway` class), Gateway API `TLSRoute` (`v1alpha2`), cert-manager self-signed Issuer, `hashicorp/http-echo`, raw `kubectl` (PoC is throwaway — not Terraform, not committed).

**Why this is safe:** Cilium creates a dedicated `cilium-gateway-<name>` Envoy Deployment + Service per Gateway, so the PoC gateways are fully isolated from `fatto-gateway`. The PoC LB Services will show `EXTERNAL-IP <pending>` (MetalLB pool has no free IP) — **this is expected and irrelevant**; all checks use the ClusterIP.

---

## File Structure

All manifests live in a scratch dir (not the repo, not committed):

- `/tmp/ingress-poc/01-app.yaml` — namespace + echo Deployment + Service
- `/tmp/ingress-poc/02-cert.yaml` — self-signed Issuer + Certificate (`*.poc.test`)
- `/tmp/ingress-poc/03-backend-gw.yaml` — terminating backend Gateway + HTTPRoute
- `/tmp/ingress-poc/04-front-gw.yaml` — passthrough front Gateway + TLSRoute + `:80` redirect HTTPRoute

---

### Task 1: Echo app in isolated namespace

**Files:**
- Create: `/tmp/ingress-poc/01-app.yaml`

- [ ] **Step 1: Write the manifest**

```bash
mkdir -p /tmp/ingress-poc
cat > /tmp/ingress-poc/01-app.yaml <<'YAML'
apiVersion: v1
kind: Namespace
metadata:
  name: poc
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo
  namespace: poc
spec:
  replicas: 1
  selector:
    matchLabels: { app: echo }
  template:
    metadata:
      labels: { app: echo }
    spec:
      containers:
        - name: echo
          image: hashicorp/http-echo:1.0
          args: ["-text=poc-ok", "-listen=:5678"]
          ports:
            - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: echo
  namespace: poc
spec:
  selector: { app: echo }
  ports:
    - name: http
      port: 80
      targetPort: 5678
YAML
```

- [ ] **Step 2: Apply**

Run: `kubectl apply -f /tmp/ingress-poc/01-app.yaml`
Expected: `namespace/poc created`, `deployment.apps/echo created`, `service/echo created`

- [ ] **Step 3: Verify the pod is running**

Run: `kubectl rollout status deploy/echo -n poc --timeout=60s`
Expected: `deployment "echo" successfully rolled out`

---

### Task 2: Self-signed wildcard cert for `*.poc.test`

**Files:**
- Create: `/tmp/ingress-poc/02-cert.yaml`

- [ ] **Step 1: Write the manifest**

```bash
cat > /tmp/ingress-poc/02-cert.yaml <<'YAML'
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: poc-selfsigned
  namespace: poc
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: poc-tls-cert
  namespace: poc
spec:
  secretName: poc-tls-cert
  issuerRef:
    name: poc-selfsigned
    kind: Issuer
  commonName: "*.poc.test"
  dnsNames:
    - "*.poc.test"
YAML
```

- [ ] **Step 2: Apply**

Run: `kubectl apply -f /tmp/ingress-poc/02-cert.yaml`
Expected: `issuer.cert-manager.io/poc-selfsigned created`, `certificate.cert-manager.io/poc-tls-cert created`

- [ ] **Step 3: Verify the TLS secret was issued**

Run: `kubectl get secret poc-tls-cert -n poc -o jsonpath='{.type}{"\n"}'`
Expected: `kubernetes.io/tls`

(If empty, wait a few seconds and retry — cert-manager issuance is async.)

---

### Task 3: Terminating backend Gateway + HTTPRoute

**Files:**
- Create: `/tmp/ingress-poc/03-backend-gw.yaml`

- [ ] **Step 1: Write the manifest**

```bash
cat > /tmp/ingress-poc/03-backend-gw.yaml <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: poc-backend
  namespace: poc
spec:
  gatewayClassName: ck-gateway
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      hostname: "*.poc.test"
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: poc-tls-cert
      allowedRoutes:
        namespaces:
          from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: poc-echo
  namespace: poc
spec:
  parentRefs:
    - name: poc-backend
      sectionName: https
  hostnames:
    - "app.poc.test"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: echo
          port: 80
YAML
```

- [ ] **Step 2: Apply**

Run: `kubectl apply -f /tmp/ingress-poc/03-backend-gw.yaml`
Expected: `gateway.gateway.networking.k8s.io/poc-backend created`, `httproute.gateway.networking.k8s.io/poc-echo created`

- [ ] **Step 3: Verify the backend Gateway is Programmed**

Run: `kubectl get gateway poc-backend -n poc -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}{"\n"}'`
Expected: `True` (may take 10-20s; retry if empty)

- [ ] **Step 4: Verify the backend Envoy Service exists**

Run: `kubectl get svc cilium-gateway-poc-backend -n poc -o jsonpath='{.spec.clusterIP}{"\n"}'`
Expected: a ClusterIP address (e.g. `10.152.x.x`). EXTERNAL-IP being `<pending>` is fine.

---

### Task 4: Passthrough front Gateway + TLSRoute + `:80` redirect

**Files:**
- Create: `/tmp/ingress-poc/04-front-gw.yaml`

- [ ] **Step 1: Write the manifest**

```bash
cat > /tmp/ingress-poc/04-front-gw.yaml <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: poc-front
  namespace: poc
spec:
  gatewayClassName: ck-gateway
  listeners:
    # Generic L4 passthrough — no hostname, no cert
    - name: tls-passthrough
      protocol: TLS
      port: 443
      tls:
        mode: Passthrough
      allowedRoutes:
        kinds:
          - kind: TLSRoute
        namespaces:
          from: Same
    # Generic HTTP -> HTTPS redirect — no hostname
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: Same
---
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: TLSRoute
metadata:
  name: poc-tls
  namespace: poc
spec:
  parentRefs:
    - name: poc-front
      sectionName: tls-passthrough
  hostnames:
    - "*.poc.test"
  rules:
    - backendRefs:
        - name: cilium-gateway-poc-backend
          port: 443
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: poc-redirect
  namespace: poc
spec:
  parentRefs:
    - name: poc-front
      sectionName: http
  rules:
    - filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
YAML
```

- [ ] **Step 2: Apply**

Run: `kubectl apply -f /tmp/ingress-poc/04-front-gw.yaml`
Expected: `gateway.../poc-front created`, `tlsroute.../poc-tls created`, `httproute.../poc-redirect created`

- [ ] **Step 3: Verify the front Gateway is Programmed**

Run: `kubectl get gateway poc-front -n poc -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}{"\n"}'`
Expected: `True` (retry for up to ~30s if empty)

- [ ] **Step 4: Verify the TLSRoute was Accepted and resolved its backend**

Run: `kubectl get tlsroute poc-tls -n poc -o jsonpath='{range .status.parents[*]}{.conditions[?(@.type=="Accepted")].status}{" "}{.conditions[?(@.type=="ResolvedRefs")].status}{"\n"}{end}'`
Expected: `True True`

**This is the critical gate.** If `Accepted` is not `True`, Cilium is rejecting the passthrough/TLSRoute config — capture the message:
Run: `kubectl get tlsroute poc-tls -n poc -o jsonpath='{.status.parents[0].conditions}{"\n"}'`
and STOP — the B2 approach needs reassessment (fall back to B1).

---

### Task 5: End-to-end SNI passthrough test (the core proof)

- [ ] **Step 1: Capture the front Gateway ClusterIP**

Run: `FRONT_IP=$(kubectl get svc cilium-gateway-poc-front -n poc -o jsonpath='{.spec.clusterIP}') && echo "$FRONT_IP"`
Expected: a ClusterIP printed (e.g. `10.152.x.x`)

- [ ] **Step 2: Curl through the front via SNI `app.poc.test` (wildcard match) from inside the cluster**

Run:
```bash
kubectl run poc-curl -n poc --image=curlimages/curl:8.11.1 --restart=Never --rm -i --quiet -- \
  curl -sS -k --resolve app.poc.test:443:$FRONT_IP https://app.poc.test/
```
Expected: response body `poc-ok`

**Interpretation:** the front (passthrough, no cert) matched SNI `app.poc.test` against the `*.poc.test` TLSRoute, forwarded the encrypted stream to the backend Gateway, which terminated TLS with the self-signed cert and routed to echo. This proves the full B2 path including wildcard SNI.

- [ ] **Step 3: Verify the served cert is the BACKEND's cert (termination happens at backend, not front)**

Run:
```bash
kubectl run poc-curl -n poc --image=curlimages/curl:8.11.1 --restart=Never --rm -i --quiet -- \
  sh -c "echo | openssl s_client -connect $FRONT_IP:443 -servername app.poc.test 2>/dev/null | openssl x509 -noout -subject"
```
Expected: subject contains `CN=*.poc.test` (the backend's self-signed cert)

- [ ] **Step 4: Negative test — non-matching SNI gets no route**

Run:
```bash
kubectl run poc-curl -n poc --image=curlimages/curl:8.11.1 --restart=Never --rm -i --quiet -- \
  curl -sS -k --max-time 10 --resolve nope.example.com:443:$FRONT_IP https://nope.example.com/ ; echo "exit=$?"
```
Expected: a connection failure / reset (non-zero exit). Confirms the front only forwards SNI that a TLSRoute matches.

---

### Task 6: HTTP→HTTPS redirect test (generic `:80` listener)

- [ ] **Step 1: Curl the `:80` listener and inspect the redirect**

Run:
```bash
kubectl run poc-curl -n poc --image=curlimages/curl:8.11.1 --restart=Never --rm -i --quiet -- \
  curl -sS -i --resolve app.poc.test:80:$FRONT_IP http://app.poc.test/
```
Expected: status line `HTTP/1.1 301 Moved Permanently` and a `location: https://app.poc.test/` header

**Interpretation:** a hostname-less `:80` redirect listener works generically — no project domain needed on the platform front.

---

### Task 7: Record findings

- [ ] **Step 1: Write a short result note**

```bash
cat > /tmp/ingress-poc/RESULT.md <<'EOF'
# Ingress PoC result (2026-06-25)
- Front Gateway Programmed: <True/False>
- TLSRoute Accepted/ResolvedRefs: <True True / details>
- Wildcard SNI passthrough (app.poc.test -> echo): <poc-ok / fail>
- Cert served by backend (CN=*.poc.test): <yes/no>
- Non-matching SNI rejected: <yes/no>
- HTTP :80 -> 301 https redirect: <yes/no>
- Verdict: B2 viable? <YES / NO + reason>
EOF
echo "Fill in /tmp/ingress-poc/RESULT.md with observed values"
```

- [ ] **Step 2: Report the verdict to the user** (paste the filled RESULT.md). If any critical check failed (Programmed, TLSRoute Accepted, or the SNI curl), recommend revisiting B1 before proceeding to Plan 1.

---

### Task 8: Teardown (leave the cluster exactly as before)

- [ ] **Step 1: Delete all PoC resources**

Run: `kubectl delete namespace poc --wait=true`
Expected: `namespace "poc" deleted`

- [ ] **Step 2: Confirm the PoC gateways are gone and the live gateway is untouched**

Run: `kubectl get gateway -A`
Expected: only `gateway/fatto-gateway` remains (no `poc-*`), `PROGRAMMED True`, address `172.16.1.11`

- [ ] **Step 3: Remove scratch manifests**

Run: `rm -rf /tmp/ingress-poc`
Expected: (no output)

---

## Self-Review

**Spec coverage:** This plan validates the spec's "Risk / validation" requirement ("PoC required before cutover: confirm wildcard SNI matching ... and HTTP→HTTPS redirect"). It does not implement any production change — that is Plan 1+. ✅

**Placeholder scan:** The only fill-ins are in `RESULT.md` (intended to be filled with observed runtime values) — not plan placeholders. All manifests and commands are complete. ✅

**Type/name consistency:** Gateway `poc-front` / `poc-backend`, Service `cilium-gateway-poc-front` / `cilium-gateway-poc-backend`, cert secret `poc-tls-cert`, hostnames `*.poc.test` / `app.poc.test`, `$FRONT_IP` — all consistent across tasks. TLSRoute uses `gateway.networking.k8s.io/v1alpha2` (matches the installed `tlsroutes.gateway.networking.k8s.io` CRD); Gateway/HTTPRoute use `v1`. ✅

## Notes / known caveats
- If `cilium-gateway-poc-front` ClusterIP forwarding to `cilium-gateway-poc-backend` is blocked by an L7/Envoy quirk, an alternative is to point the TLSRoute `backendRef` directly at a per-backend `ClusterIP` Service fronting the backend Envoy; document any such adjustment in RESULT.md.
- `hashicorp/http-echo:1.0` and `curlimages/curl:8.11.1` are pinned; if image pull is blocked by the cluster's registry policy, substitute an already-present image (e.g. the Zot/Nexus-mirrored equivalent) and note it.
