# Local CI + Registry Stack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three components to `tf-platform/dev/` so GitHub stops being the metered bottleneck for CI minutes, container images, npm/maven packages, and Actions storage (artifacts + cache).

**Architecture:** Each component is a single new `.tf` file in `tf-platform/dev/`, installed via Helm and exposed via the platform's existing Cilium Gateway with the existing `klucovsky-wildcard-tls` cert. Zot is backed by the platform's existing MinIO via S3 driver; Nexus uses its own PVC; ARC's controller runs in `arc-system` and a runner scale set in `arc-runners` registers with the GitHub org. Workflow YAML changes (separate, in app repos) redirect Actions cache/artifacts to a `github-actions` MinIO bucket.

**Tech Stack:** Terraform 1.0+, providers in `tf-platform/dev/main.tf` (`kubernetes ~> 2.36`, `helm ~> 2.17`, `kubectl ~> 2.1`, `random ~> 3.6`, `postgresql ~> 1.25`). Helm charts: `oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller` + `gha-runner-scale-set`, `project-zot/zot`, `sonatype/nexus-repository-manager`. Cluster: Canonical K8s at `172.16.1.10` (node `172.16.1.11`), kubeconfig context `k8s`.

**Reference:** Spec at `docs/superpowers/specs/2026-05-28-local-ci-registry-stack-design.md` (same repo).

**Working directory:** `/Users/robert.klucovsky/Developer/tf-platform/`

---

## Prerequisite Tasks (one-time, user-driven)

### Task 0a: Create the GitHub App for ARC

**Type:** Manual user step. Not Terraform.

The user needs to create a GitHub App in their org's settings. ARC uses this App's credentials to register runners with GitHub.

- [ ] **Step 1: Navigate to org settings**

In a browser: `https://github.com/organizations/<org-name>/settings/apps/new`
(Replace `<org-name>` with the actual GitHub org — likely `Fatto-ERP` based on existing context.)

- [ ] **Step 2: Fill out the form with these exact values**

- **GitHub App name**: `<org>-arc` (e.g. `Fatto-ERP-arc`)
- **Homepage URL**: `https://gitlab.klucovsky.com` or any placeholder URL (required field, not actually used)
- **Webhook**: **Uncheck** "Active" — ARC polls; no webhook needed.
- **Repository permissions**:
  - `Actions`: **Read and write**
  - `Administration`: **Read and write** (needed to register runners)
  - `Checks`: **Read**
  - `Metadata`: **Read** (auto-selected)
- **Organization permissions**:
  - `Self-hosted runners`: **Read and write**
- **Where can this GitHub App be installed?**: Only on this account.

Click **Create GitHub App**.

- [ ] **Step 3: Note the App ID**

On the resulting page, copy the **App ID** (a number, e.g. `1234567`). Set aside for Task 2.

- [ ] **Step 4: Generate a private key**

Scroll to "Private keys" section. Click **Generate a private key**. A `.pem` file downloads. Save it as `~/Developer/fatto-arc-github-app.pem` (gitignored location).

- [ ] **Step 5: Install the App on the org**

Click **Install App** in the left sidebar. Install on the org (your account), either "All repositories" or "Only select repositories" — for FATTO, select all FATTO repos.

- [ ] **Step 6: Note the Installation ID**

After installation, the URL becomes `https://github.com/organizations/<org>/settings/installations/<installation_id>`. Copy the installation ID (a number).

You now have: App ID, Installation ID, and a PEM file. Total ~5 minutes.

---

### Task 0b: Create DNS A records in DigitalOcean

**Type:** Manual user step. Not Terraform.

Both `registry.klucovsky.com` and `nexus.klucovsky.com` need to resolve to the platform's gateway LB IP.

- [ ] **Step 1: Identify the gateway LB IP**

Run:
```bash
kubectl get gateway -n gateway -o jsonpath='{.items[*].status.addresses[*].value}'
echo
```

Expected: one or more IPs (e.g. `172.16.1.20`). This is what `grafana.klucovsky.com` and `prometheus.klucovsky.com` already point to.

- [ ] **Step 2: Add records in DigitalOcean**

Log in to DigitalOcean → Networking → Domains → `klucovsky.com`. Add two A records:

| Hostname | Type | Value (the LB IP from Step 1) | TTL |
|---|---|---|---|
| `registry` | A | `172.16.1.20` (replace with actual) | 300 |
| `nexus` | A | `172.16.1.20` (replace with actual) | 300 |

- [ ] **Step 3: Verify resolution**

After ~1 minute:
```bash
dig +short registry.klucovsky.com
dig +short nexus.klucovsky.com
```

Both should return the LB IP. Wait longer if not — TTL propagation.

---

## Phase A — Add ARC (Actions Runner Controller)

### Task 1: Add ARC variables to `variables.tf`

**Files:**
- Modify: `/Users/robert.klucovsky/Developer/tf-platform/dev/variables.tf`

- [ ] **Step 1: Append these variable blocks at the end of `variables.tf`**

```hcl
# -----------------------------------------------------------------------------
# ACTIONS RUNNER CONTROLLER (ARC)
# -----------------------------------------------------------------------------

variable "github_org" {
  description = "GitHub organization that runners register with"
  type        = string
  default     = "Fatto-ERP"
}

variable "github_app_id" {
  description = "GitHub App ID for ARC (from Task 0a)"
  type        = string
}

variable "github_app_installation_id" {
  description = "GitHub App installation ID for ARC (from Task 0a)"
  type        = string
}

variable "github_app_private_key" {
  description = "GitHub App private key PEM contents (sensitive)"
  type        = string
  sensitive   = true
}

variable "arc_controller_chart_version" {
  description = "gha-runner-scale-set-controller OCI chart version (verify with: helm show chart oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller)"
  type        = string
  default     = "0.9.3"
}

variable "arc_runner_chart_version" {
  description = "gha-runner-scale-set OCI chart version (must match controller version)"
  type        = string
  default     = "0.9.3"
}

variable "arc_runner_max_replicas" {
  description = "Max concurrent runner pods"
  type        = number
  default     = 3
}

variable "arc_runner_min_replicas" {
  description = "Min idle runner pods (0 = scale to zero when no jobs)"
  type        = number
  default     = 0
}
```

- [ ] **Step 2: Verify fmt**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform fmt -check variables.tf
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform
git add dev/variables.tf
git commit -m "vars: add ARC GitHub App + chart version variables"
```

---

### Task 2: Add ARC values to `terraform.tfvars`

**Files:**
- Modify: `/Users/robert.klucovsky/Developer/tf-platform/dev/terraform.tfvars` (gitignored)

- [ ] **Step 1: Append to `terraform.tfvars` using the values captured in Task 0a**

```hcl

# -----------------------------------------------------------------------------
# ARC (GitHub App credentials from Task 0a)
# -----------------------------------------------------------------------------

github_app_id              = "1234567"     # replace with App ID from Task 0a Step 3
github_app_installation_id = "12345678"    # replace with Installation ID from Task 0a Step 6
github_app_private_key     = <<-EOT
-----BEGIN RSA PRIVATE KEY-----
... paste contents of ~/Developer/fatto-arc-github-app.pem here ...
-----END RSA PRIVATE KEY-----
EOT
```

- [ ] **Step 2: Verify the file parses**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform plan -refresh=false 2>&1 | head -5
```

Expected: plan starts running (or shows the existing 71 resources). No syntax errors about `Invalid HCL`.

**Do not commit.** The file is in `.gitignore`.

---

### Task 3: Create `arc.tf`

**Files:**
- Create: `/Users/robert.klucovsky/Developer/tf-platform/dev/arc.tf`

- [ ] **Step 1: Write the file**

Write `/Users/robert.klucovsky/Developer/tf-platform/dev/arc.tf` with EXACTLY this content:

```hcl
# -----------------------------------------------------------------------------
# ACTIONS RUNNER CONTROLLER (ARC)
#
# Two Helm releases:
#   1. arc-system/gha-runner-scale-set-controller — the controller + CRDs
#   2. arc-runners/fatto-runners — a runner scale set registering with GitHub org
#
# Uses the new GitHub-blessed ARC (not the legacy actions.summerwind.dev CRDs).
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "arc_system" {
  metadata {
    name = "arc-system"
    labels = {
      "app.kubernetes.io/name"       = "arc-system"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_namespace" "arc_runners" {
  metadata {
    name = "arc-runners"
    labels = {
      "app.kubernetes.io/name"       = "arc-runners"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# Controller — installs CRDs and the controller manager
resource "helm_release" "arc_controller" {
  name       = "arc-controller"
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set-controller"
  version    = var.arc_controller_chart_version
  namespace  = kubernetes_namespace.arc_system.metadata[0].name

  # No values — controller defaults are fine.
}

# GitHub App credentials secret consumed by the runner scale set
resource "kubernetes_secret" "github_app" {
  metadata {
    name      = "github-app-secret"
    namespace = kubernetes_namespace.arc_runners.metadata[0].name
  }

  data = {
    github_app_id              = var.github_app_id
    github_app_installation_id = var.github_app_installation_id
    github_app_private_key     = var.github_app_private_key
  }
}

# Runner scale set — registers runners with the GitHub org
resource "helm_release" "arc_runners" {
  name       = "fatto-runners"
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set"
  version    = var.arc_runner_chart_version
  namespace  = kubernetes_namespace.arc_runners.metadata[0].name

  values = [
    yamlencode({
      githubConfigUrl    = "https://github.com/${var.github_org}"
      githubConfigSecret = kubernetes_secret.github_app.metadata[0].name
      runnerScaleSetName = "fatto"
      minRunners         = var.arc_runner_min_replicas
      maxRunners         = var.arc_runner_max_replicas
      template = {
        spec = {
          containers = [
            {
              name  = "runner"
              image = "ghcr.io/actions/actions-runner:latest"
              command = ["/home/runner/run.sh"]
            }
          ]
        }
      }
    })
  ]

  depends_on = [
    helm_release.arc_controller,
    kubernetes_secret.github_app
  ]
}
```

- [ ] **Step 2: Verify fmt + validate**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform fmt -check arc.tf
terraform validate
```

Expected: fmt no output, validate `Success! The configuration is valid.`

- [ ] **Step 3: Plan**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform plan -out=tfplan-arc 2>&1 | tail -10
```

Expected: plan shows `5 to add` (2 namespaces, 2 helm releases, 1 secret), `0 to change, 0 to destroy`.

- [ ] **Step 4: Apply**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform apply tfplan-arc
```

Expected: ~3-5 min. The controller install is fast; the runner scale set may take ~1 min to initialize.

- [ ] **Step 5: Verify the controller is running**

```bash
kubectl get pods -n arc-system
```

Expected: one pod `arc-controller-gha-rs-controller-...` in `Running` state.

- [ ] **Step 6: Verify the runner scale set is connected to GitHub**

```bash
kubectl get pods -n arc-runners
kubectl get autoscalingrunnerset -n arc-runners
```

Expected: an `AutoscalingRunnerSet` named `fatto-runners` exists. With `minRunners: 0`, no runner pods exist until a job is queued. Listener pod (`fatto-runners-...`) should be running.

- [ ] **Step 7: Verify the runner appears in GitHub org settings**

In a browser: `https://github.com/organizations/<org>/settings/actions/runner-groups` (or `/actions/runners`).

You should see a runner group / scale set named `fatto`. Status may be "Online" (waiting for jobs) once a runner pod spins up. With `minRunners: 0` it'll show "Idle" or empty until a workflow with `runs-on: fatto` triggers.

- [ ] **Step 8: Commit `arc.tf`**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform
git add dev/arc.tf
git commit -m "feat: add ARC controller + runner scale set for GitHub Actions"
```

---

## Phase B — Add Zot Container Registry

### Task 4: Add Zot variables to `variables.tf`

**Files:**
- Modify: `/Users/robert.klucovsky/Developer/tf-platform/dev/variables.tf`

- [ ] **Step 1: Append at the end of `variables.tf`**

```hcl
# -----------------------------------------------------------------------------
# ZOT (Container registry, MinIO-backed)
# -----------------------------------------------------------------------------

variable "zot_chart_version" {
  description = "Zot Helm chart version (verify with: helm search repo project-zot/zot)"
  type        = string
  default     = "0.1.66"
}

variable "zot_admin_user" {
  description = "Zot admin username"
  type        = string
  default     = "admin"
}
```

- [ ] **Step 2: Verify fmt**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform fmt -check variables.tf
```

- [ ] **Step 3: Commit**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform
git add dev/variables.tf
git commit -m "vars: add Zot chart version + admin user"
```

---

### Task 5: Create `zot.tf`

**Files:**
- Create: `/Users/robert.klucovsky/Developer/tf-platform/dev/zot.tf`

- [ ] **Step 1: Write the file**

Write `/Users/robert.klucovsky/Developer/tf-platform/dev/zot.tf` with EXACTLY this content:

```hcl
# -----------------------------------------------------------------------------
# ZOT — OCI container registry, MinIO-backed
#
# Storage backend: platform's existing MinIO via S3 driver.
# Authentication: htpasswd with a single admin user.
# Bucket `zot-storage` is created up-front by a one-shot Job using mc.
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "zot" {
  metadata {
    name = "zot"
    labels = {
      "app.kubernetes.io/name"       = "zot"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# Admin credentials (htpasswd format)
# -----------------------------------------------------------------------------

resource "random_password" "zot_admin" {
  length  = 24
  special = false
}

resource "kubernetes_secret" "zot_admin_plain" {
  metadata {
    name      = "zot-admin-plain"
    namespace = kubernetes_namespace.zot.metadata[0].name
  }
  data = {
    username = var.zot_admin_user
    password = random_password.zot_admin.result
  }
}

# htpasswd secret — bcrypt() produces $2a$... format which Apache/Zot's htpasswd
# parser accepts. No external Job needed since the hash is computable inline.
resource "kubernetes_secret" "zot_htpasswd" {
  metadata {
    name      = "zot-htpasswd"
    namespace = kubernetes_namespace.zot.metadata[0].name
  }
  data = {
    # bcrypt() produces $2a$... which apache/httpd accepts in htpasswd.
    htpasswd = "${var.zot_admin_user}:${bcrypt(random_password.zot_admin.result, 10)}"
  }
}

# -----------------------------------------------------------------------------
# MinIO bucket creation — one-shot Job using mc
# -----------------------------------------------------------------------------

resource "kubernetes_job_v1" "zot_bucket_init" {
  metadata {
    name      = "zot-bucket-init"
    namespace = kubernetes_namespace.zot.metadata[0].name
  }

  spec {
    backoff_limit = 3

    template {
      metadata {
        labels = { job = "zot-bucket-init" }
      }
      spec {
        restart_policy = "OnFailure"

        container {
          name    = "mc"
          image   = "minio/mc:latest"
          command = ["sh", "-c"]
          args = [
            <<-EOT
              set -e
              mc alias set local http://minio.${var.namespace}.svc.cluster.local:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
              mc mb --ignore-existing local/zot-storage
              echo "zot-storage bucket ready"
            EOT
          ]

          env {
            name  = "MINIO_ROOT_USER"
            value = var.minio_root_user
          }
          env {
            name = "MINIO_ROOT_PASSWORD"
            value_from {
              secret_key_ref {
                name = "fatto-credentials"
                key  = "minio-password"
              }
            }
          }
        }
      }
    }

    ttl_seconds_after_finished = 300
  }

  wait_for_completion = true
  timeouts {
    create = "5m"
  }

  depends_on = [
    kubernetes_secret.fatto_credentials  # ensure platform credentials exist
  ]
}

# -----------------------------------------------------------------------------
# Zot Helm release
# -----------------------------------------------------------------------------

resource "helm_release" "zot" {
  name       = "zot"
  repository = "https://zotregistry.dev/helm-charts"
  chart      = "zot"
  version    = var.zot_chart_version
  namespace  = kubernetes_namespace.zot.metadata[0].name

  values = [
    yamlencode({
      service = {
        type = "ClusterIP"
        port = 5000
      }
      ingress = {
        enabled = false  # we use Gateway API HTTPRoute (see below)
      }
      mountConfig = true
      configFiles = {
        "config.json" = jsonencode({
          distSpecVersion = "1.1.1"
          storage = {
            rootDirectory = "/var/lib/registry"
            dedupe        = true
            storageDriver = {
              name           = "s3"
              rootdirectory  = "/zot"
              region         = "us-east-1"
              regionendpoint = "http://minio.${var.namespace}.svc.cluster.local:9000"
              bucket         = "zot-storage"
              forcepathstyle = true
              secure         = false
              skipverify     = true
              accesskey      = var.minio_root_user
              secretkey      = random_password.minio_password.result
            }
          }
          http = {
            address = "0.0.0.0"
            port    = "5000"
            auth = {
              htpasswd = {
                path = "/etc/zot-htpasswd/htpasswd"
              }
            }
          }
          log = {
            level = "info"
          }
        })
      }
      mountSecret = true
      secretMounts = [
        {
          name      = "zot-htpasswd"
          secret    = "zot-htpasswd"
          mountPath = "/etc/zot-htpasswd"
        }
      ]
    })
  ]

  depends_on = [
    kubernetes_secret.zot_htpasswd,
    kubernetes_job_v1.zot_bucket_init,
  ]
}

# -----------------------------------------------------------------------------
# Gateway API HTTPRoute — registry.klucovsky.com → Zot
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "zot_route" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: zot
      namespace: ${kubernetes_namespace.zot.metadata[0].name}
    spec:
      parentRefs:
        - name: fatto-gateway
          namespace: gateway
          sectionName: https-klucovsky
      hostnames:
        - "registry.klucovsky.com"
      rules:
        - backendRefs:
            - name: zot
              port: 5000
  YAML

  depends_on = [helm_release.zot]
}
```

**IMPORTANT note about Helm chart values**: the Zot Helm chart's value names (`configFiles`, `mountSecret`, `secretMounts`, etc.) come from its `values.yaml`. The exact key names may differ slightly per chart version. Before applying, verify:

```bash
helm repo add zot https://zotregistry.dev/helm-charts 2>/dev/null || true
helm show values zot/zot --version ${ZOT_CHART_VERSION:-0.1.66} | grep -E "^(service|ingress|configFiles|mountConfig|secretMounts|mountSecret):" -A 3
```

If the value names differ, update the `values = [...]` block above to match the chart's schema. The `helm install` will error clearly if a key doesn't exist.

- [ ] **Step 2: Verify fmt + validate**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform fmt -check zot.tf
terraform validate
```

Expected: fmt clean, validate success.

If validate fails, the most likely cause is a typo in resource references. Common ones to verify: `kubernetes_secret.fatto_credentials` exists in `namespace.tf` (it does), `random_password.minio_password` exists in `namespace.tf` (it does), `var.minio_root_user` exists in `variables.tf` (it does).

- [ ] **Step 3: Plan**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform plan -out=tfplan-zot 2>&1 | tail -10
```

Expected: plan shows ~7 resources to add (1 namespace, 1 random_password, 2 secrets, 1 job, 1 helm release, 1 manifest).

- [ ] **Step 4: Apply**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform apply tfplan-zot
```

Expected: 1-2 minutes. The slowest steps are the `mc mb` Job (~10s) and the Helm release (~30s for pod ready).

- [ ] **Step 5: Verify Zot is up**

```bash
kubectl get pods -n zot
```

Expected: a `zot-...` pod in `Running` state, all containers ready.

- [ ] **Step 6: Verify the MinIO bucket exists**

```bash
kubectl run -n fatto-erp-dev mc-debug --image=minio/mc:latest --rm -it --restart=Never -- \
  sh -c 'mc alias set local http://minio.fatto-erp-dev.svc.cluster.local:9000 fatto-admin "$(kubectl get secret fatto-credentials -n fatto-erp-dev -o jsonpath="{.data.minio-password}" | base64 -d)" 2>&1 && mc ls local/zot-storage'
```

Actually that's unwieldy. Simpler: from any pod with mc, run `mc ls local/zot-storage`. Or check via the MinIO console: `https://minio.dev.fatto.online` → log in with `fatto-admin` / `<minio-password from fatto-credentials>` → see the `zot-storage` bucket listed.

Expected: bucket exists. Empty is fine — Zot has nothing in it yet.

- [ ] **Step 7: Test push from inside the cluster**

```bash
kubectl run -n zot crane-debug --image=gcr.io/go-containerregistry/crane:debug --rm -it --restart=Never -- sh
# Inside the pod:
# crane auth login zot.zot.svc.cluster.local:5000 -u admin -p '<paste-zot-admin-password>'
# crane copy alpine:3.20 zot.zot.svc.cluster.local:5000/test/alpine:3.20
# crane catalog zot.zot.svc.cluster.local:5000
# Expected: catalog shows "test/alpine"
# exit
```

Get the zot admin password via: `terraform output -json zot_admin_credentials` (after Task 7 adds the output).

- [ ] **Step 8: Commit `zot.tf`**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform
git add dev/zot.tf
git commit -m "feat: add Zot container registry backed by MinIO"
```

---

### Task 6: Verify Zot reachable externally

Prerequisite: Task 0b DNS records for `registry.klucovsky.com` are in place.

- [ ] **Step 1: Wait for cert-manager to issue the wildcard cert (if not already)**

```bash
kubectl get certificate -n gateway klucovsky-wildcard-tls
```

Expected: `READY=True`. The existing platform already has this cert; just confirming.

- [ ] **Step 2: HTTPS connectivity test**

```bash
curl -sI https://registry.klucovsky.com/v2/ 2>&1 | head -5
```

Expected: `HTTP/2 401` (Zot requires auth — 401 is the correct response for unauthenticated request). Anything other than 401/200 means the route or cert is wrong.

- [ ] **Step 3: Login + push from your dev machine**

```bash
ZOT_PASSWORD=$(cd /Users/robert.klucovsky/Developer/tf-platform/dev && terraform output -raw zot_admin_password 2>/dev/null || echo "OUTPUT NOT YET ADDED")
echo "$ZOT_PASSWORD" | docker login registry.klucovsky.com -u admin --password-stdin
docker pull alpine:3.20
docker tag alpine:3.20 registry.klucovsky.com/test/alpine:3.20
docker push registry.klucovsky.com/test/alpine:3.20
```

Expected: successful push. If `terraform output -raw zot_admin_password` errors, skip to Task 7 to add the output.

---

### Task 7: Add Zot outputs

**Files:**
- Modify: `/Users/robert.klucovsky/Developer/tf-platform/dev/outputs.tf`

- [ ] **Step 1: Append at the end of `outputs.tf`**

```hcl
# -----------------------------------------------------------------------------
# ZOT
# -----------------------------------------------------------------------------

output "registry_url" {
  description = "Zot container registry URL"
  value       = "https://registry.klucovsky.com"
}

output "zot_admin_user" {
  description = "Zot admin username"
  value       = var.zot_admin_user
}

output "zot_admin_password" {
  description = "Zot admin password (also stored in zot-admin-plain secret)"
  value       = random_password.zot_admin.result
  sensitive   = true
}
```

- [ ] **Step 2: Verify fmt + apply**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform fmt -check outputs.tf
terraform apply -auto-approve
```

Expected: 0 resources to add/change (outputs don't trigger resource changes), but `terraform output` now includes the new entries.

- [ ] **Step 3: Verify the output works**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform output -raw zot_admin_password | wc -c
```

Expected: 25 (24 chars + newline).

- [ ] **Step 4: Commit**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform
git add dev/outputs.tf
git commit -m "out: expose Zot registry URL + admin credentials"
```

---

## Phase C — Add Sonatype Nexus

### Task 8: Add Nexus variables to `variables.tf`

**Files:**
- Modify: `/Users/robert.klucovsky/Developer/tf-platform/dev/variables.tf`

- [ ] **Step 1: Append at the end**

```hcl
# -----------------------------------------------------------------------------
# SONATYPE NEXUS OSS
# -----------------------------------------------------------------------------

variable "nexus_chart_version" {
  description = "Sonatype Nexus Repository Manager Helm chart version (verify with: helm search repo sonatype/nexus-repository-manager)"
  type        = string
  default     = "73.0.0"
}

variable "nexus_storage_size" {
  description = "Nexus PVC storage size"
  type        = string
  default     = "20Gi"
}
```

- [ ] **Step 2: Verify + commit**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform fmt -check variables.tf

cd /Users/robert.klucovsky/Developer/tf-platform
git add dev/variables.tf
git commit -m "vars: add Nexus chart version + storage size"
```

---

### Task 9: Create `nexus.tf`

**Files:**
- Create: `/Users/robert.klucovsky/Developer/tf-platform/dev/nexus.tf`

- [ ] **Step 1: Write the file**

```hcl
# -----------------------------------------------------------------------------
# SONATYPE NEXUS OSS — multi-format package registry (npm, maven, generic)
#
# Nexus generates an initial admin password at /nexus-data/admin.password
# on first boot. We capture it via an in-cluster Job after the Helm release
# is ready, and store it into a Kubernetes secret for Terraform to read back.
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "nexus" {
  metadata {
    name = "nexus"
    labels = {
      "app.kubernetes.io/name"       = "nexus"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "nexus_data" {
  metadata {
    name      = "nexus-data"
    namespace = kubernetes_namespace.nexus.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class
    resources {
      requests = {
        storage = var.nexus_storage_size
      }
    }
  }

  # Don't delete the PVC on terraform destroy by default — admin can rm manually.
  wait_until_bound = true
}

resource "helm_release" "nexus" {
  name       = "nexus"
  repository = "https://sonatype.github.io/helm3-charts/"
  chart      = "nexus-repository-manager"
  version    = var.nexus_chart_version
  namespace  = kubernetes_namespace.nexus.metadata[0].name

  values = [
    yamlencode({
      nexus = {
        resources = {
          requests = { cpu = "500m", memory = "1Gi" }
          limits   = { cpu = "2000m", memory = "3Gi" }
        }
      }
      persistence = {
        enabled       = true
        existingClaim = kubernetes_persistent_volume_claim_v1.nexus_data.metadata[0].name
      }
      service = {
        type = "ClusterIP"
        port = 8081
      }
      ingress = {
        enabled = false  # we use Gateway API HTTPRoute
      }
    })
  ]

  depends_on = [kubernetes_persistent_volume_claim_v1.nexus_data]

  timeout = 600  # Nexus first boot can take a few minutes
}

# -----------------------------------------------------------------------------
# RBAC for the admin-password-capture Job to create secrets
# -----------------------------------------------------------------------------

resource "kubernetes_service_account_v1" "nexus_init" {
  metadata {
    name      = "nexus-init"
    namespace = kubernetes_namespace.nexus.metadata[0].name
  }
}

resource "kubernetes_role_v1" "nexus_init" {
  metadata {
    name      = "nexus-init"
    namespace = kubernetes_namespace.nexus.metadata[0].name
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["create", "patch", "get"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "pods/exec"]
    verbs      = ["get", "list", "create"]
  }
}

resource "kubernetes_role_binding_v1" "nexus_init" {
  metadata {
    name      = "nexus-init"
    namespace = kubernetes_namespace.nexus.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.nexus_init.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.nexus_init.metadata[0].name
    namespace = kubernetes_namespace.nexus.metadata[0].name
  }
}

# -----------------------------------------------------------------------------
# Admin password capture Job
#
# Uses kubectl from within the cluster (via the service account) to exec
# into the Nexus pod, read /nexus-data/admin.password, and create a secret.
# -----------------------------------------------------------------------------

resource "kubernetes_job_v1" "nexus_admin_capture" {
  metadata {
    name      = "nexus-admin-capture"
    namespace = kubernetes_namespace.nexus.metadata[0].name
  }

  spec {
    backoff_limit = 3

    template {
      metadata {
        labels = { job = "nexus-admin-capture" }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.nexus_init.metadata[0].name
        restart_policy       = "OnFailure"

        container {
          name    = "capture"
          image   = "bitnami/kubectl:latest"
          command = ["sh", "-c"]
          args = [
            <<-EOT
              set -e
              # Wait for the Nexus pod to be ready and the admin.password file to exist.
              POD=""
              for i in $(seq 1 60); do
                POD=$(kubectl get pods -n nexus -l app.kubernetes.io/name=nexus-repository-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
                if [ -n "$POD" ]; then
                  READY=$(kubectl get pod "$POD" -n nexus -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
                  if [ "$READY" = "true" ]; then
                    if kubectl exec -n nexus "$POD" -- test -f /nexus-data/admin.password 2>/dev/null; then
                      break
                    fi
                  fi
                fi
                echo "Waiting for Nexus pod and admin.password... ($i/60)"
                sleep 10
              done

              if [ -z "$POD" ]; then
                echo "ERROR: Nexus pod not found"
                exit 1
              fi

              PASSWORD=$(kubectl exec -n nexus "$POD" -- cat /nexus-data/admin.password)
              if [ -z "$PASSWORD" ]; then
                echo "ERROR: admin.password is empty"
                exit 1
              fi

              # Create or update the secret with the captured password.
              kubectl create secret generic nexus-credentials \
                -n nexus \
                --from-literal=username=admin \
                --from-literal=password="$PASSWORD" \
                --dry-run=client -o yaml | kubectl apply -f -

              echo "nexus-credentials secret created/updated"
            EOT
          ]
        }
      }
    }

    ttl_seconds_after_finished = 600
  }

  wait_for_completion = true
  timeouts {
    create = "15m"  # First Nexus boot can take 5+ minutes
  }

  depends_on = [
    helm_release.nexus,
    kubernetes_role_binding_v1.nexus_init,
  ]
}

# -----------------------------------------------------------------------------
# Read the secret back so Terraform can expose it via outputs
# -----------------------------------------------------------------------------

data "kubernetes_secret" "nexus_credentials" {
  metadata {
    name      = "nexus-credentials"
    namespace = kubernetes_namespace.nexus.metadata[0].name
  }
  depends_on = [kubernetes_job_v1.nexus_admin_capture]
}

# -----------------------------------------------------------------------------
# Gateway API HTTPRoute — nexus.klucovsky.com → Nexus
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "nexus_route" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: nexus
      namespace: ${kubernetes_namespace.nexus.metadata[0].name}
    spec:
      parentRefs:
        - name: fatto-gateway
          namespace: gateway
          sectionName: https-klucovsky
      hostnames:
        - "nexus.klucovsky.com"
      rules:
        - backendRefs:
            - name: nexus-nexus-repository-manager
              port: 8081
  YAML

  depends_on = [helm_release.nexus]
}
```

**Note on the Service name** (`nexus-nexus-repository-manager`): the Sonatype Helm chart names its Service `<release-name>-nexus-repository-manager`. Since the release name is `nexus`, the service is `nexus-nexus-repository-manager`. Verify after install with `kubectl get svc -n nexus`.

- [ ] **Step 2: Verify fmt + validate**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform fmt -check nexus.tf
terraform validate
```

Expected: fmt clean, validate success.

- [ ] **Step 3: Plan**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform plan -out=tfplan-nexus 2>&1 | tail -10
```

Expected: ~9 resources to add (namespace, PVC, helm release, SA, role, role binding, job, secret data source, manifest).

- [ ] **Step 4: Apply**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform apply tfplan-nexus
```

Expected: 5-10 minutes. The slowest part is Nexus first-boot which takes 3-5 min, followed by the admin-capture Job waiting for the password file (another ~2 min).

If apply times out on `kubernetes_job_v1.nexus_admin_capture`, the Job is likely still waiting for Nexus. Check:
```bash
kubectl get pods -n nexus
kubectl logs -n nexus -l job=nexus-admin-capture --tail=20
```
If the Job is still running, increase the timeout in the resource and re-apply.

- [ ] **Step 5: Verify Nexus is up**

```bash
kubectl get pods -n nexus
kubectl get secret nexus-credentials -n nexus -o jsonpath='{.data.password}' | base64 -d | wc -c
```

Expected: Nexus pod `Running`. Password length ~30+ chars.

- [ ] **Step 6: Commit `nexus.tf`**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform
git add dev/nexus.tf
git commit -m "feat: add Sonatype Nexus OSS for npm + maven packages"
```

---

### Task 10: Add Nexus outputs + verify external access

**Files:**
- Modify: `/Users/robert.klucovsky/Developer/tf-platform/dev/outputs.tf`

- [ ] **Step 1: Append at the end of `outputs.tf`**

```hcl
# -----------------------------------------------------------------------------
# NEXUS
# -----------------------------------------------------------------------------

output "nexus_url" {
  description = "Nexus Repository Manager URL"
  value       = "https://nexus.klucovsky.com"
}

output "nexus_admin_credentials" {
  description = "Nexus admin login (rotate this in the Nexus UI on first login)"
  value = {
    username = data.kubernetes_secret.nexus_credentials.data["username"]
    password = data.kubernetes_secret.nexus_credentials.data["password"]
  }
  sensitive = true
}
```

- [ ] **Step 2: Apply**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform apply -auto-approve
```

- [ ] **Step 3: Verify external access**

Prerequisite: Task 0b's `nexus` A record exists.

```bash
curl -sI https://nexus.klucovsky.com/service/rest/v1/status 2>&1 | head -3
```

Expected: `HTTP/2 200`. If you get TLS errors, the wildcard cert hasn't been picked up yet — wait 1-2 min.

- [ ] **Step 4: Log in via UI**

In a browser: `https://nexus.klucovsky.com`. Username `admin`, password from:
```bash
terraform output -json nexus_admin_credentials | jq -r '.password'
```

On first login, Nexus runs a setup wizard:
1. Change the admin password (or keep it; the secret in K8s now has the OLD one — be aware)
2. Configure anonymous access (recommend: **disable** for a single-user dev — you'll authenticate)

- [ ] **Step 5: Commit**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform
git add dev/outputs.tf
git commit -m "out: expose Nexus URL + admin credentials"
```

---

### Task 11: Configure Nexus repositories (manual, via UI)

**Type:** Manual user step. Not Terraform.

Nexus's first-boot includes default repositories (`maven-central`, `maven-public`, etc.). You need to ensure hosted repositories exist for your publishing needs.

- [ ] **Step 1: In Nexus UI → Administration → Repositories**

Verify these exist (create if not):

| Repository name | Format | Type | Notes |
|---|---|---|---|
| `npm-hosted` | npm | hosted | For your own npm packages. Allow republish: false. |
| `maven-releases` | maven2 | hosted | For your maven release artifacts. Version policy: Release. |
| `maven-snapshots` | maven2 | hosted | For your maven snapshot artifacts. Version policy: Snapshot. |

Default Nexus setup includes `maven-releases` and `maven-snapshots`. You'll need to create `npm-hosted` if it's not there.

- [ ] **Step 2: Verify upload + download with a test artifact**

```bash
# npm publish test
npm config set registry https://nexus.klucovsky.com/repository/npm-hosted/
npm config set //nexus.klucovsky.com/repository/npm-hosted/:_authToken "$(echo -n 'admin:<password>' | base64)"

# In a test directory:
mkdir /tmp/test-pkg && cd /tmp/test-pkg
npm init -y
npm publish

# Expected: "+ test-pkg@1.0.0" success message
# Verify in Nexus UI → Browse → npm-hosted
```

- [ ] **Step 3: Document the configuration in repo README**

(Optional — note in the tf-platform README that Nexus repo setup is manual.)

---

## Phase D — Add GitHub Actions storage bucket

### Task 12: Add `github-actions` bucket init Job

**Files:**
- Modify: `/Users/robert.klucovsky/Developer/tf-platform/dev/minio.tf` (add a Job at the end)

Actually, this should be its own file to keep concerns separate. Create a new file.

**Files:**
- Create: `/Users/robert.klucovsky/Developer/tf-platform/dev/github-actions-storage.tf`

- [ ] **Step 1: Write the file**

```hcl
# -----------------------------------------------------------------------------
# GITHUB ACTIONS STORAGE — MinIO bucket for workflow cache + artifacts
#
# Bucket is consumed by GitHub Actions workflows via tespkg/actions-cache
# (cache) and direct `mc cp` (artifacts). The actual workflow YAML changes
# live in the consumer repos, not here.
# -----------------------------------------------------------------------------

resource "kubernetes_job_v1" "github_actions_bucket_init" {
  metadata {
    name      = "github-actions-bucket-init"
    namespace = var.namespace  # uses platform's existing namespace
  }

  spec {
    backoff_limit = 3

    template {
      metadata {
        labels = { job = "github-actions-bucket-init" }
      }
      spec {
        restart_policy = "OnFailure"

        container {
          name    = "mc"
          image   = "minio/mc:latest"
          command = ["sh", "-c"]
          args = [
            <<-EOT
              set -e
              mc alias set local http://minio.${var.namespace}.svc.cluster.local:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
              mc mb --ignore-existing local/github-actions
              echo "github-actions bucket ready"
            EOT
          ]

          env {
            name  = "MINIO_ROOT_USER"
            value = var.minio_root_user
          }
          env {
            name = "MINIO_ROOT_PASSWORD"
            value_from {
              secret_key_ref {
                name = "fatto-credentials"
                key  = "minio-password"
              }
            }
          }
        }
      }
    }

    ttl_seconds_after_finished = 300
  }

  wait_for_completion = true
  timeouts {
    create = "5m"
  }

  depends_on = [kubernetes_secret.fatto_credentials]
}
```

- [ ] **Step 2: Verify fmt + apply**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform fmt -check github-actions-storage.tf
terraform validate
terraform apply -auto-approve
```

Expected: 1 new resource (the Job), runs and completes in ~10s.

- [ ] **Step 3: Verify bucket exists**

In a browser: `https://minio.dev.fatto.online` → log in as `fatto-admin` → see both `github-actions` and `zot-storage` buckets in the list.

- [ ] **Step 4: Commit**

```bash
cd /Users/robert.klucovsky/Developer/tf-platform
git add dev/github-actions-storage.tf
git commit -m "feat: add github-actions MinIO bucket for workflow cache + artifacts"
```

---

### Task 13: Pilot — migrate one GitHub Actions workflow

**Type:** User-driven, not Terraform.

Pick **one** real workflow in the FATTO repos (a small one if possible, e.g. a simple build job) and migrate it to use the new infrastructure.

- [ ] **Step 1: Add MinIO credentials as GitHub repo/org secrets**

In `https://github.com/organizations/<org>/settings/secrets/actions` (or per-repo):

| Secret name | Value |
|---|---|
| `MINIO_ACCESS_KEY` | `fatto-admin` |
| `MINIO_SECRET_KEY` | (output of `terraform output -json minio_credentials \| jq -r .secret_key`) |

- [ ] **Step 2: Edit the workflow YAML**

In the chosen repo's `.github/workflows/<file>.yml`:

```yaml
jobs:
  build:
    runs-on: [self-hosted, fatto]    # was: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Restore Gradle cache (via MinIO)
        uses: tespkg/actions-cache@v1
        with:
          endpoint: minio.dev.fatto.online
          insecure: false
          accessKey: ${{ secrets.MINIO_ACCESS_KEY }}
          secretKey: ${{ secrets.MINIO_SECRET_KEY }}
          bucket: github-actions
          use-fallback: false
          path: ~/.gradle/caches
          key: gradle-${{ runner.os }}-${{ hashFiles('**/*.gradle*') }}
          restore-keys: gradle-${{ runner.os }}-

      - name: Build
        run: ./gradlew build

      - name: Push image to local registry
        run: |
          echo "${{ secrets.ZOT_PASSWORD }}" | docker login registry.klucovsky.com -u admin --password-stdin
          docker build -t registry.klucovsky.com/fatto/catalog:${{ github.sha }} .
          docker push registry.klucovsky.com/fatto/catalog:${{ github.sha }}
```

You'll also need a `ZOT_PASSWORD` repo/org secret with the value from `terraform output -raw zot_admin_password`.

- [ ] **Step 3: Trigger the workflow and observe**

Push the change to a feature branch and watch the workflow run in GitHub's UI.

Expected:
- The job is queued, sits "Waiting for a self-hosted runner..." briefly
- An ARC runner pod appears in `arc-runners` namespace (`kubectl get pods -n arc-runners --watch`)
- Job picks up and runs
- Cache step completes (first run: cache miss, uploads to MinIO; subsequent runs: cache hit, downloads from MinIO)
- Image push succeeds, visible at `https://registry.klucovsky.com/v2/_catalog`

- [ ] **Step 4: Verify storage paths**

```bash
# Check MinIO github-actions bucket has data
# Browse https://minio.dev.fatto.online → github-actions bucket

# Check Zot has the image
curl -u "admin:$ZOT_PASSWORD" https://registry.klucovsky.com/v2/_catalog
# Expected: {"repositories":["fatto/catalog","test/alpine"]}
```

- [ ] **Step 5: Roll out to other workflows incrementally**

Apply the same pattern to remaining workflows in a separate PR per repo. Not tracked as Terraform changes; just YAML edits in app repos.

---

## Self-Review Notes

**Spec coverage check:**

| Spec section | Plan task(s) |
|---|---|
| ARC controller + RunnerSet | Tasks 1, 2, 3 |
| Zot container registry | Tasks 4, 5, 6, 7 |
| Sonatype Nexus | Tasks 8, 9, 10, 11 |
| Actions storage redirect (cache + artifacts) | Tasks 12, 13 |
| Hostnames (registry + nexus) | Task 0b (DNS) + HTTPRoutes inside Tasks 5 and 9 |
| GitHub App auth | Task 0a (creation) + Task 2 (tfvars) + Task 3 (secret + helm) |
| Bucket creation pattern (Jobs) | Task 5 (zot-storage) + Task 12 (github-actions) |
| Nexus admin password capture | Task 9 (Job + RBAC + data source) |
| Workflow YAML changes | Task 13 |

**No placeholders:** Every code block contains real content; every command has an expected outcome. Two placeholder-flavored items deliberately preserved:
- Chart versions (`0.9.3` for ARC, `0.1.66` for Zot, `73.0.0` for Nexus) — flagged as placeholders to verify with `helm search repo` before applying.
- Helm chart values key names — flagged in Task 5 because chart schemas vary across versions; verify with `helm show values` if validate fails.

**Type consistency:**
- `var.namespace` (= `"fatto-erp-dev"`) referenced consistently for MinIO endpoint.
- `kubernetes_secret.fatto_credentials` referenced consistently (defined in platform's existing `namespace.tf`).
- `random_password.minio_password` referenced consistently (defined in platform's existing `namespace.tf`).
- `var.minio_root_user` (= `"fatto-admin"`) referenced consistently.
- The Zot HTTPRoute references the `klucovsky` Gateway section name (`https-klucovsky`) — verify it exists in the platform's `gateway.tf` before applying. If it doesn't, use the correct section name (likely `https-dev` for the dev domain or a generic `https`).
