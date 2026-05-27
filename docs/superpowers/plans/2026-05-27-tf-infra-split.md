# tf-infra split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `/Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev/` into a new shared platform repo at `/Users/robert.klucovsky/Developer/tf-platform/dev/` plus a slimmed-down FATTO-specific repo, with cross-references replaced by Kubernetes data sources.

**Architecture:** Two Terraform repos with independent local state. The platform creates a `fatto-erp-dev` namespace pre-populated with a `fatto-credentials` secret bundling platform-service passwords. The app's `postgresql` provider authenticates via `data.kubernetes_secret.cnpg-superuser`, and the app's outputs/secrets read platform passwords via `data.kubernetes_secret.fatto-credentials`. Apply order: platform first, app second.

**Tech Stack:** Terraform 1.0+, providers `hashicorp/kubernetes ~> 2.36`, `hashicorp/helm ~> 2.17`, `alekc/kubectl ~> 2.1`, `cyrilgdn/postgresql ~> 1.25`, `hashicorp/random ~> 3.6`. Canonical K8s cluster at `172.16.1.10` (node IP `172.16.1.11`), kubeconfig context `k8s`.

**Reference:** Spec at `docs/superpowers/specs/2026-05-27-tf-infra-split-design.md`. Source repo: `/Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev/`. Target platform repo: `/Users/robert.klucovsky/Developer/tf-platform/`.

---

## Phase A — Build the new tf-platform repo (no cluster changes)

### Task 1: Pre-flight — snapshot current outputs

**Files:**
- Create: `/Users/robert.klucovsky/fatto-tf-pre-split-outputs-2026-05-27.json` (reference snapshot, outside any repo)

- [ ] **Step 1: Capture current outputs to a JSON file**

Run:
```bash
cd /Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev
terraform output -json > /Users/robert.klucovsky/fatto-tf-pre-split-outputs-2026-05-27.json
```

Expected: file created with all current outputs. If terraform errors out (state empty / not initialized), record that — there may be nothing to snapshot, and the rest of Phase B's destroy steps need adjustment.

- [ ] **Step 2: Verify snapshot is non-empty**

Run:
```bash
wc -c /Users/robert.klucovsky/fatto-tf-pre-split-outputs-2026-05-27.json
head -c 200 /Users/robert.klucovsky/fatto-tf-pre-split-outputs-2026-05-27.json
```

Expected: file size > 100 bytes, JSON content visible (`{ "namespace": { ... }, ... }`). If empty or `{}`, note this — likely terraform state was already empty.

---

### Task 2: Create tf-platform repo skeleton

**Files:**
- Create: `/Users/robert.klucovsky/Developer/tf-platform/README.md`
- Create: `/Users/robert.klucovsky/Developer/tf-platform/.gitignore`
- Create: `/Users/robert.klucovsky/Developer/tf-platform/dev/` (directory)

- [ ] **Step 1: Make directory and initialize git**

Run:
```bash
mkdir -p /Users/robert.klucovsky/Developer/tf-platform/dev
cd /Users/robert.klucovsky/Developer/tf-platform
git init
```

Expected: empty git repo initialized.

- [ ] **Step 2: Create .gitignore**

Write `/Users/robert.klucovsky/Developer/tf-platform/.gitignore`:
```
# Terraform
.terraform/
.terraform.lock.hcl
terraform.tfstate
terraform.tfstate.backup
terraform.tfvars
*.tfplan

# IDE
.idea/
.vscode/

# OS
.DS_Store
```

- [ ] **Step 3: Create README.md**

Write `/Users/robert.klucovsky/Developer/tf-platform/README.md`:
```markdown
# Shared Platform Infrastructure

Terraform configuration for the shared Kubernetes platform that tenants (FATTO, GitLab, etc.) consume.

## What's here

- Cluster bootstrap: CNPG, cert-manager, Cilium Gateway API, ArgoCD
- Shared backing services: Redis, MinIO, Keycloak, Mailpit, pgAdmin
- Observability: Prometheus, Grafana, Tempo, Loki, Promtail
- Code quality: SonarQube
- Tenant namespace setup: `fatto-erp-dev` with `fatto-credentials` secret

## What's not here

- Per-service databases / users — tenant repos own these
- ArgoCD Applications for tenant workloads — tenant repos own these
- Tenant-specific image pull secrets — tenant repos own these

## Apply / destroy order

This repo is applied **first** before any tenant repo. Destroyed **last** after all tenant repos.

```bash
cd dev
source ~/Developer/fatto/tf-variables.sh
terraform init
terraform apply
```

## Tenants

- FATTO ERP — `/Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/`
- GitLab (planned) — to be added as another `.tf` file in `dev/`
```

- [ ] **Step 4: Commit skeleton**

Run:
```bash
cd /Users/robert.klucovsky/Developer/tf-platform
git add .gitignore README.md
git commit -m "Initial: tf-platform skeleton"
```

Expected: one commit on `main` (or `master`).

---

### Task 3: Copy platform .tf files from app repo to platform repo (unchanged copies)

**Files:**
- Copy from `/Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev/` to `/Users/robert.klucovsky/Developer/tf-platform/dev/`:
  - `cnpg.tf`, `gateway.tf`, `certificates.tf`, `redis.tf`, `minio.tf`, `keycloak.tf`, `mailpit.tf`, `pgadmin.tf`, `observability.tf`, `dashboards.tf`, `loki-dashboard.json`, `tempo-dashboard.json`, `argocd.tf`, `sonarqube.tf`

- [ ] **Step 1: Copy each file**

Run:
```bash
SRC=/Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev
DST=/Users/robert.klucovsky/Developer/tf-platform/dev
cp "$SRC/cnpg.tf" "$DST/"
cp "$SRC/gateway.tf" "$DST/"
cp "$SRC/certificates.tf" "$DST/"
cp "$SRC/redis.tf" "$DST/"
cp "$SRC/minio.tf" "$DST/"
cp "$SRC/keycloak.tf" "$DST/"
cp "$SRC/mailpit.tf" "$DST/"
cp "$SRC/pgadmin.tf" "$DST/"
cp "$SRC/observability.tf" "$DST/"
cp "$SRC/dashboards.tf" "$DST/"
cp "$SRC/loki-dashboard.json" "$DST/"
cp "$SRC/tempo-dashboard.json" "$DST/"
cp "$SRC/argocd.tf" "$DST/"
cp "$SRC/sonarqube.tf" "$DST/"
ls "$DST"
```

Expected: 14 files now in `/Users/robert.klucovsky/Developer/tf-platform/dev/`.

- [ ] **Step 2: Verify each file copied with non-zero size**

Run:
```bash
wc -l /Users/robert.klucovsky/Developer/tf-platform/dev/*.tf
```

Expected: every file has > 0 lines.

---

### Task 4: Write platform main.tf

**Files:**
- Create: `/Users/robert.klucovsky/Developer/tf-platform/dev/main.tf`

- [ ] **Step 1: Write the file**

Write `/Users/robert.klucovsky/Developer/tf-platform/dev/main.tf`:
```hcl
# FATTO Shared Platform Infrastructure
# Terraform configuration for shared K8s platform (Canonical K8s)

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

# -----------------------------------------------------------------------------
# PROVIDERS
# -----------------------------------------------------------------------------

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kubeconfig_context
  }
}

provider "kubectl" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}
```

Notes for the engineer:
- No `postgresql` provider here. The platform installs CNPG but does **not** create per-service databases or users.
- No `provider "postgresql"` block whatsoever — if you find one creeping in, stop and re-read the spec.

- [ ] **Step 2: Verify file parses (syntax-only)**

Run:
```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform fmt -check main.tf
```

Expected: no output (fmt-clean). If errors, run `terraform fmt main.tf` to normalize, then re-check.

---

### Task 5: Write platform variables.tf

**Files:**
- Create: `/Users/robert.klucovsky/Developer/tf-platform/dev/variables.tf`

- [ ] **Step 1: Write the file**

Write `/Users/robert.klucovsky/Developer/tf-platform/dev/variables.tf`:
```hcl
# -----------------------------------------------------------------------------
# GENERAL VARIABLES
# -----------------------------------------------------------------------------

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "Kubernetes context to use"
  type        = string
  default     = "k8s"
}

variable "namespace" {
  description = "Kubernetes namespace for FATTO dev environment (tenant)"
  type        = string
  default     = "fatto-erp-dev"
}

variable "domain" {
  description = "Base domain for dev environment gateway routing"
  type        = string
  default     = "dev.fatto.online"
}

# -----------------------------------------------------------------------------
# KUBERNETES STORAGE
# -----------------------------------------------------------------------------

variable "storage_class" {
  description = "Kubernetes StorageClass name"
  type        = string
  default     = "csi-rawfile-default"
}

variable "server_host" {
  description = "Infrastructure server IP address (K8s node)"
  type        = string
  default     = "172.16.1.11"
}

# -----------------------------------------------------------------------------
# CERT-MANAGER
# -----------------------------------------------------------------------------

variable "cert_manager_version" {
  description = "cert-manager Helm chart version"
  type        = string
  default     = "v1.19.3"
}

variable "digitalocean_token" {
  description = "DigitalOcean API token for DNS-01 challenge"
  type        = string
  sensitive   = true
}

variable "letsencrypt_email" {
  description = "Email for Let's Encrypt certificate registration"
  type        = string
}

variable "letsencrypt_staging" {
  description = "Use Let's Encrypt staging server (true) or production (false)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# POSTGRESQL / CNPG VARIABLES
# -----------------------------------------------------------------------------

variable "postgres_host" {
  description = "PostgreSQL host for connectivity checks during CNPG bootstrap (NodePort on K8s node)"
  type        = string
  default     = "172.16.1.11"
}

variable "postgres_port" {
  description = "PostgreSQL NodePort"
  type        = number
  default     = 30432
}

variable "postgres_superuser" {
  description = "PostgreSQL superuser username"
  type        = string
  default     = "postgres"
}

variable "postgres_superuser_password" {
  description = "PostgreSQL superuser password (stored into fatto-credentials secret)"
  type        = string
  sensitive   = true
}

variable "cnpg_operator_version" {
  description = "CloudNativePG operator Helm chart version"
  type        = string
  default     = "0.27.0"
}

variable "cnpg_pg_version" {
  description = "PostgreSQL version for CNPG cluster"
  type        = string
  default     = "17-bookworm"
}

variable "cnpg_instances" {
  description = "Number of PostgreSQL instances (1 primary + N-1 replicas)"
  type        = number
  default     = 2
}

variable "cnpg_storage_size" {
  description = "PVC storage size per CNPG instance"
  type        = string
  default     = "5Gi"
}

variable "cnpg_nodeport" {
  description = "NodePort for CNPG primary"
  type        = number
  default     = 30432
}

# -----------------------------------------------------------------------------
# SONARQUBE
# -----------------------------------------------------------------------------

variable "sonarqube_version" {
  description = "SonarQube Helm chart version"
  type        = string
  default     = "2026.1.0"
}

variable "sonarqube_plugins" {
  description = "List of SonarQube plugins to install"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# PGADMIN
# -----------------------------------------------------------------------------

variable "pgadmin_version" {
  description = "pgAdmin Docker image tag"
  type        = string
  default     = "9.12"
}

variable "pgadmin_email" {
  description = "pgAdmin default admin email"
  type        = string
  default     = "admin@klucovsky.com"
}

# -----------------------------------------------------------------------------
# REDIS
# -----------------------------------------------------------------------------

variable "redis_version" {
  description = "Redis version"
  type        = string
  default     = "8.4"
}

variable "redis_storage_size" {
  description = "Redis PVC storage size"
  type        = string
  default     = "1Gi"
}

# -----------------------------------------------------------------------------
# MINIO
# -----------------------------------------------------------------------------

variable "minio_storage_size" {
  description = "MinIO PVC storage size"
  type        = string
  default     = "10Gi"
}

variable "minio_root_user" {
  description = "MinIO root user"
  type        = string
  default     = "fatto-admin"
}

# -----------------------------------------------------------------------------
# KEYCLOAK
# -----------------------------------------------------------------------------

variable "keycloak_admin_user" {
  description = "Keycloak admin username"
  type        = string
  default     = "admin"
}

# -----------------------------------------------------------------------------
# OBSERVABILITY
# -----------------------------------------------------------------------------

variable "tempo_chart_version" {
  description = "Grafana Tempo Helm chart version"
  type        = string
  default     = "1.24.1"
}

variable "loki_chart_version" {
  description = "Grafana Loki Helm chart version"
  type        = string
  default     = "6.53.0"
}

variable "promtail_chart_version" {
  description = "Grafana Promtail Helm chart version"
  type        = string
  default     = "6.17.1"
}

variable "prometheus_stack_version" {
  description = "kube-prometheus-stack Helm chart version"
  type        = string
  default     = "81.6.9"
}

variable "grafana_admin_user" {
  description = "Grafana admin username"
  type        = string
  default     = "admin"
}

# -----------------------------------------------------------------------------
# ARGOCD
# -----------------------------------------------------------------------------

variable "argocd_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "9.4.2"
}
```

Notes:
- No `ghcr_username`, `ghcr_token`, `postgres_host`, `postgres_port`, `postgres_superuser` here. Those stay app-side. The platform doesn't talk to Postgres or GHCR.
- `postgres_superuser_password` stays — platform stores it into `fatto-credentials` so the app can read it back via the `cnpg-superuser` data source (actually CNPG creates that secret natively, but `fatto-credentials` also bundles it for dotenv use).

- [ ] **Step 2: Verify fmt**

Run:
```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform fmt -check variables.tf
```

Expected: no output.

---

### Task 6: Write platform namespace.tf (owns fatto-erp-dev + fatto-credentials)

**Files:**
- Create: `/Users/robert.klucovsky/Developer/tf-platform/dev/namespace.tf`

- [ ] **Step 1: Write the file**

Write `/Users/robert.klucovsky/Developer/tf-platform/dev/namespace.tf`:
```hcl
# -----------------------------------------------------------------------------
# TENANT NAMESPACE — fatto-erp-dev
#
# Owned by the platform so the FATTO app repo can rely on it existing
# with credentials pre-populated.
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "fatto_dev" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/name"       = "fatto"
      "app.kubernetes.io/component"  = "infrastructure"
      "app.kubernetes.io/managed-by" = "terraform"
      "environment"                  = "dev"
    }
  }
}

# -----------------------------------------------------------------------------
# GENERATED PASSWORDS FOR PLATFORM SERVICES
# -----------------------------------------------------------------------------

resource "random_password" "redis_password" {
  length  = 24
  special = false
}

resource "random_password" "minio_password" {
  length  = 24
  special = false
}

resource "random_password" "keycloak_password" {
  length  = 24
  special = false
}

resource "random_password" "grafana_password" {
  length  = 24
  special = false
}

# -----------------------------------------------------------------------------
# fatto-credentials — bundle of platform-service passwords
#
# Read by the FATTO app repo via:
#   data "kubernetes_secret" "fatto_credentials" {
#     metadata { name = "fatto-credentials"; namespace = "fatto-erp-dev" }
#   }
# -----------------------------------------------------------------------------

resource "kubernetes_secret" "fatto_credentials" {
  metadata {
    name      = "fatto-credentials"
    namespace = kubernetes_namespace.fatto_dev.metadata[0].name
  }

  data = {
    "postgres-password" = var.postgres_superuser_password
    "redis-password"    = random_password.redis_password.result
    "minio-password"    = random_password.minio_password.result
    "keycloak-password" = random_password.keycloak_password.result
  }
}
```

- [ ] **Step 2: Verify fmt**

Run:
```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform fmt -check namespace.tf
```

Expected: no output.

---

### Task 7: Add platform-side outputs.tf

**Files:**
- Create: `/Users/robert.klucovsky/Developer/tf-platform/dev/outputs.tf`

- [ ] **Step 1: Write the file**

Write `/Users/robert.klucovsky/Developer/tf-platform/dev/outputs.tf`:
```hcl
# -----------------------------------------------------------------------------
# PLATFORM OUTPUTS
#
# Most cross-repo handoff goes through Kubernetes secrets, not Terraform outputs.
# These outputs exist for human inspection (debugging, sharing credentials).
# -----------------------------------------------------------------------------

output "tenant_namespace" {
  description = "Tenant namespace created by platform"
  value       = kubernetes_namespace.fatto_dev.metadata[0].name
}

output "redis_password" {
  description = "Redis password (also stored in fatto-credentials secret)"
  value       = random_password.redis_password.result
  sensitive   = true
}

output "minio_credentials" {
  description = "MinIO access credentials"
  value = {
    access_key = var.minio_root_user
    secret_key = random_password.minio_password.result
  }
  sensitive = true
}

output "keycloak_admin_credentials" {
  description = "Keycloak admin login"
  value = {
    username = var.keycloak_admin_user
    password = random_password.keycloak_password.result
  }
  sensitive = true
}

output "grafana_credentials" {
  description = "Grafana admin login"
  value = {
    username = var.grafana_admin_user
    password = random_password.grafana_password.result
  }
  sensitive = true
}

output "pgadmin_credentials" {
  description = "pgAdmin admin login"
  value = {
    email    = var.pgadmin_email
    password = random_password.pgadmin_password.result
  }
  sensitive = true
}

# -----------------------------------------------------------------------------
# Web UI URLs (informational)
# -----------------------------------------------------------------------------

output "keycloak_url"       { value = "https://auth.${var.domain}" }
output "mailpit_url"        { value = "https://mail.${var.domain}" }
output "minio_console_url"  { value = "https://minio.${var.domain}" }
output "grafana_url"        { value = "https://grafana.klucovsky.com" }
output "prometheus_url"     { value = "https://prometheus.klucovsky.com" }
output "alertmanager_url"   { value = "https://alertmanager.klucovsky.com" }
output "sonarqube_url"      { value = "https://sonar.klucovsky.com" }
output "pgadmin_url"        { value = "https://db.klucovsky.com" }
output "argocd_url"         { value = "https://argocd.klucovsky.com" }
```

Note: `random_password.pgadmin_password` is referenced — it lives in `pgadmin.tf` (already copied in Task 3, unchanged).

- [ ] **Step 2: Verify fmt**

Run:
```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform fmt -check outputs.tf
```

Expected: no output.

---

### Task 8: Verify tf-platform terraform configuration is valid

**Files:** No new files.

- [ ] **Step 1: Verify all required vars are documented**

Run:
```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
grep -E '^variable' variables.tf | wc -l
```

Expected: 25 variables defined. If count differs, re-check Task 5.

- [ ] **Step 2: Check that no stray app-side references exist**

Run:
```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
grep -n "var\.ghcr_" *.tf
```

Expected: **no output**. The platform does not use GHCR. If matches appear, they're stray copy-pastes — find them and remove.

- [ ] **Step 3: Confirm `cnpg.tf` references `var.postgres_host` for connectivity check (this is expected, not a leak)**

Run:
```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
grep -n "var.postgres_host" cnpg.tf
```

Expected: 2 matches around the "Waiting for CNPG PostgreSQL to accept connections" probe.

- [ ] **Step 4: terraform init + validate**

Prerequisite: `~/Developer/fatto/tf-variables.sh` must export `TF_VAR_postgres_superuser_password`, `TF_VAR_digitalocean_token`, `TF_VAR_letsencrypt_email`. If unsure, run `cat ~/Developer/fatto/tf-variables.sh` first.

Run:
```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
source ~/Developer/fatto/tf-variables.sh
terraform init -backend=false
terraform validate
```

Expected: `Success! The configuration is valid.` Any errors mean a reference to a platform resource is missing or an unknown variable was used — fix inline before continuing.

---

### Task 9: Commit tf-platform initial scaffold

**Files:** None new.

- [ ] **Step 1: Stage and commit**

Run:
```bash
cd /Users/robert.klucovsky/Developer/tf-platform
git add dev/*.tf dev/*.json
git status
```

Expected: all `dev/*.tf` and `*.json` files staged; no `terraform.tfstate*` or `.terraform/` directories staged (the .gitignore handles those).

- [ ] **Step 2: Commit**

Run:
```bash
cd /Users/robert.klucovsky/Developer/tf-platform
git commit -m "Initial platform terraform configuration"
```

Expected: one commit added.

---

## Phase B — Destroy the current dev environment

### Task 10: User confirmation before destructive step

**Files:** None.

- [ ] **Step 1: Pause for user confirmation**

Output to user (verbatim):

> The next step runs `terraform destroy` on `/Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev/`, removing the entire current dev cluster state (databases, secrets, all Helm releases). The pre-flight snapshot is at `/Users/robert.klucovsky/fatto-tf-pre-split-outputs-2026-05-27.json`. Confirm before I proceed.

Wait for explicit confirmation ("yes", "go", "do it"). Do NOT proceed without confirmation.

---

### Task 11: Destroy the current dev environment

**Files:** None.

- [ ] **Step 1: Run terraform destroy**

Run:
```bash
cd /Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev
source ~/Developer/fatto/tf-variables.sh
terraform destroy -auto-approve
```

Expected: Terraform plans destruction of all resources, then destroys them. May take 5–10 minutes. If any resource hangs (typical: PVCs, finalizers on CRDs), let the engineer investigate manually before forcing.

- [ ] **Step 2: Verify state is empty**

Run:
```bash
cd /Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev
terraform state list
```

Expected: empty output. If any resources remain, do not proceed — investigate and either remove them via `terraform state rm` (only if confident) or have the engineer reconcile.

- [ ] **Step 3: Sanity check the cluster**

Run:
```bash
kubectl get namespaces | grep -E "fatto|argocd|cnpg|cert-manager|observability"
```

Expected: no namespaces matching these patterns (or only ones with `Terminating` status). If `Terminating` lingers > 2 min on any namespace, that's a finalizer issue — investigate before continuing.

---

## Phase C — Slim down the fatto-erp/tf-infra app repo

### Task 12: Delete moved files from app repo

**Files:**
- Delete from `/Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev/`:
  - `cnpg.tf`, `gateway.tf`, `certificates.tf`, `redis.tf`, `minio.tf`, `keycloak.tf`, `mailpit.tf`, `pgadmin.tf`, `observability.tf`, `dashboards.tf`, `loki-dashboard.json`, `tempo-dashboard.json`, `argocd.tf`, `sonarqube.tf`, `namespace.tf`

- [ ] **Step 1: Delete the files**

Run:
```bash
cd /Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev
rm cnpg.tf gateway.tf certificates.tf redis.tf minio.tf keycloak.tf mailpit.tf pgadmin.tf observability.tf dashboards.tf loki-dashboard.json tempo-dashboard.json argocd.tf sonarqube.tf namespace.tf
ls
```

Expected remaining files: `main.tf`, `variables.tf`, `terraform.tfvars`, `postgresql.tf`, `argocd-apps.tf`, `ghcr-pull-secret.tf`, `outputs.tf`, `keycloak-realm/`, `keycloak-theme/`, plus any `terraform.tfstate*` (now empty).

- [ ] **Step 2: Also remove now-empty `.terraform.lock.hcl`**

Run:
```bash
cd /Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev
rm -rf .terraform .terraform.lock.hcl
```

Expected: clean directory. The next `terraform init` will recreate the lockfile with the (now-smaller) provider set.

---

### Task 13: Refactor app main.tf to use K8s data sources

**Files:**
- Modify: `/Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev/main.tf`

- [ ] **Step 1: Overwrite main.tf**

Write `/Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev/main.tf`:
```hcl
# FATTO Dev Environment — FATTO-specific Terraform configuration
# Depends on tf-platform/dev being applied first.

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.25"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

# -----------------------------------------------------------------------------
# PROVIDERS
# -----------------------------------------------------------------------------

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}

provider "kubectl" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}

# -----------------------------------------------------------------------------
# PLATFORM HANDOFF — data sources reading what tf-platform created
# -----------------------------------------------------------------------------

data "kubernetes_secret" "cnpg_superuser" {
  metadata {
    name      = "cnpg-superuser"
    namespace = "cnpg-system"
  }
}

data "kubernetes_secret" "fatto_credentials" {
  metadata {
    name      = "fatto-credentials"
    namespace = var.namespace
  }
}

# -----------------------------------------------------------------------------
# POSTGRESQL PROVIDER — authenticates against CNPG via NodePort,
# password sourced from the platform-created cnpg-superuser secret.
# -----------------------------------------------------------------------------

provider "postgresql" {
  host     = var.postgres_host
  port     = var.postgres_port
  username = var.postgres_superuser
  password = data.kubernetes_secret.cnpg_superuser.data["password"]
  sslmode  = "disable"
  database = "postgres"
}
```

Notes:
- No `helm` provider on the app side (app installs no Helm releases).
- No `var.postgres_superuser_password` — password comes from the data source.
- The `data` source lookup fails fast with a clear error if the platform hasn't applied yet (`Error: secret "cnpg-superuser" not found`).

- [ ] **Step 2: Verify fmt**

Run:
```bash
cd /Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev
terraform fmt -check main.tf
```

Expected: no output.

---

### Task 14: Refactor app variables.tf

**Files:**
- Modify: `/Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev/variables.tf`

- [ ] **Step 1: Overwrite variables.tf**

Write `/Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev/variables.tf`:
```hcl
# -----------------------------------------------------------------------------
# GENERAL VARIABLES
# -----------------------------------------------------------------------------

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "Kubernetes context to use"
  type        = string
  default     = "k8s"
}

variable "namespace" {
  description = "Tenant namespace (created by tf-platform)"
  type        = string
  default     = "fatto-erp-dev"
}

variable "domain" {
  description = "Base domain for dev environment gateway routing"
  type        = string
  default     = "dev.fatto.online"
}

variable "server_host" {
  description = "Infrastructure server IP address (K8s node, for NodePort access)"
  type        = string
  default     = "172.16.1.11"
}

# -----------------------------------------------------------------------------
# POSTGRESQL (CNPG NodePort access)
# -----------------------------------------------------------------------------

variable "postgres_host" {
  description = "PostgreSQL host (CNPG NodePort on K8s node)"
  type        = string
  default     = "172.16.1.11"
}

variable "postgres_port" {
  description = "PostgreSQL NodePort"
  type        = number
  default     = 30432
}

variable "postgres_superuser" {
  description = "PostgreSQL superuser username (typical default: postgres)"
  type        = string
  default     = "postgres"
}

# -----------------------------------------------------------------------------
# GHCR (FATTO container image registry)
# -----------------------------------------------------------------------------

variable "ghcr_username" {
  description = "GitHub username for ghcr.io"
  type        = string
}

variable "ghcr_token" {
  description = "GitHub PAT for ghcr.io image pulls"
  type        = string
  sensitive   = true
}
```

Notes:
- `postgres_superuser_password` removed — comes from CNPG via data source.
- `digitalocean_token`, `letsencrypt_*`, all chart-version vars, all platform-service vars removed — they're now on the platform side.

- [ ] **Step 2: Verify fmt**

Run:
```bash
cd /Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev
terraform fmt -check variables.tf
```

Expected: no output.

---

### Task 15: Refactor ghcr-pull-secret.tf to use var.namespace

**Files:**
- Modify: `/Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev/ghcr-pull-secret.tf`

- [ ] **Step 1: Overwrite the file**

Write `/Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev/ghcr-pull-secret.tf`:
```hcl
# -----------------------------------------------------------------------------
# GHCR.IO PULL SECRET
#
# Allows the K8s cluster to pull container images from GitHub Container Registry
# for FATTO services. The platform-created namespace is referenced by name
# (var.namespace) — no kubernetes_namespace resource exists here anymore.
# -----------------------------------------------------------------------------

resource "kubernetes_secret" "ghcr_pull_secret_dev" {
  metadata {
    name      = "ghcr-pull-secret"
    namespace = var.namespace

    labels = {
      "app.kubernetes.io/name"       = "ghcr-pull-secret"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          auth = base64encode("${var.ghcr_username}:${var.ghcr_token}")
        }
      }
    })
  }
}
```

The only change vs the original: `namespace = kubernetes_namespace.fatto_dev.metadata[0].name` → `namespace = var.namespace`.

- [ ] **Step 2: Verify fmt**

Run:
```bash
cd /Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev
terraform fmt -check ghcr-pull-secret.tf
```

Expected: no output.

---

### Task 16: Refactor argocd-apps.tf cross-references

**Files:**
- Modify: `/Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev/argocd-apps.tf`

Cross-references to refactor (six places use `random_password.redis_password.result`; multiple `depends_on` blocks reference `helm_release.argocd`; one references `kubectl_manifest.gateway`; two reference `kubernetes_namespace.fatto_dev.metadata[0].name`; one references `kubernetes_namespace.argocd.metadata[0].name`).

- [ ] **Step 1: Rewrite `argocd-apps.tf` — replace platform-resource references with data sources and `var.namespace`**

Use a single Edit pass per pattern. Do these replacements:

1. **Namespace reference (kubernetes_namespace.fatto_dev.metadata[0].name → var.namespace)**:
   - In `kubernetes_secret.fatto_product_config`, `kubernetes_secret.fatto_bff_config`, `kubernetes_secret.fatto_party_config`, `kubernetes_secret.fatto_inventory_config`, `kubernetes_secret.fatto_sales_config`, `kubernetes_secret.fatto_purchasing_config`.
   - Replace `namespace = kubernetes_namespace.fatto_dev.metadata[0].name` with `namespace = var.namespace`.

2. **Argocd namespace reference (kubernetes_namespace.argocd.metadata[0].name → "argocd")**:
   - In `kubernetes_secret.argocd_repo_creds`.
   - Replace `namespace = kubernetes_namespace.argocd.metadata[0].name` with `namespace = "argocd"`.

3. **Redis password reference (random_password.redis_password.result → data source)**:
   - In all six `kubernetes_secret.fatto_*_config` resources where `redis-url` is set.
   - Replace `${random_password.redis_password.result}` with `${data.kubernetes_secret.fatto_credentials.data["redis-password"]}`.

4. **Remove `helm_release.argocd` from `depends_on` everywhere**:
   - In each `kubectl_manifest.argocd_app_*` resource and in `kubernetes_secret.argocd_repo_creds`.
   - Remove the line `helm_release.argocd,` from `depends_on` blocks. If the block becomes empty (`depends_on = []`), remove the block entirely.

5. **Remove `kubectl_manifest.gateway` from `depends_on` in `bff_route`**:
   - In `kubectl_manifest.bff_route`.
   - Remove the entire `depends_on = [kubectl_manifest.gateway]` line.

The final file is mechanically identical to the original except for these substitutions. **Do not** restructure the YAML manifests or change ArgoCD application names.

- [ ] **Step 2: Verify no stray platform-resource references remain**

Run:
```bash
cd /Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev
grep -n "helm_release.argocd\|random_password.redis_password\|random_password.minio_password\|random_password.keycloak_password\|kubectl_manifest.gateway\|kubernetes_namespace.fatto_dev\|kubernetes_namespace.argocd" argocd-apps.tf
```

Expected: **no output**. Any matches mean a reference to a platform-owned resource is still present — fix before continuing.

- [ ] **Step 3: Verify fmt**

Run:
```bash
cd /Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev
terraform fmt -check argocd-apps.tf
```

Expected: no output.

---

### Task 17: Verify postgresql.tf locals don't reference platform resources

**Files:**
- Inspect: `/Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev/postgresql.tf`

- [ ] **Step 1: Check for platform-resource references**

Run:
```bash
cd /Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev
grep -n "helm_release\|random_password.redis\|random_password.minio\|random_password.keycloak\|random_password.grafana\|kubernetes_namespace.fatto_dev\|kubernetes_namespace.argocd\|kubernetes_namespace.cnpg" postgresql.tf
```

Expected: **no output**. Per-service `random_password.pg_*` resources are app-side and OK.

If `kubernetes_namespace.fatto_dev` is referenced, replace with `var.namespace` (same as Task 16 step 1).

- [ ] **Step 2: Check that the postgresql provider password reference (if any) was already removed**

Run:
```bash
cd /Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev
grep -n "var.postgres_superuser_password" *.tf
```

Expected: **no output**. The password is now sourced via `data.kubernetes_secret.cnpg_superuser` in `main.tf` only.

---

### Task 18: Slim down outputs.tf to FATTO-specific outputs

**Files:**
- Modify: `/Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev/outputs.tf`

- [ ] **Step 1: Overwrite outputs.tf**

Write `/Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev/outputs.tf`:
```hcl
# -----------------------------------------------------------------------------
# FATTO-specific outputs
# Platform-side credentials are read from data.kubernetes_secret.fatto_credentials
# -----------------------------------------------------------------------------

locals {
  redis_password    = data.kubernetes_secret.fatto_credentials.data["redis-password"]
  minio_password    = data.kubernetes_secret.fatto_credentials.data["minio-password"]
  keycloak_password = data.kubernetes_secret.fatto_credentials.data["keycloak-password"]
}

# -----------------------------------------------------------------------------
# Per-service Postgres connection strings
# -----------------------------------------------------------------------------

output "postgres_fatto_product" {
  description = "PostgreSQL connection for fatto-catalog (read/write)"
  value       = "postgresql://fatto_product:${random_password.pg_fatto_product.result}@${var.postgres_host}:${var.postgres_port}/fatto-catalog"
  sensitive   = true
}

output "postgres_fatto_order" {
  description = "PostgreSQL connection for fatto-order (read/write)"
  value       = "postgresql://fatto_order:${random_password.pg_fatto_order.result}@${var.postgres_host}:${var.postgres_port}/fatto_order"
  sensitive   = true
}

output "postgres_fatto_inventory" {
  description = "PostgreSQL connection for fatto-inventory (read/write)"
  value       = "postgresql://fatto_inventory:${random_password.pg_fatto_inventory.result}@${var.postgres_host}:${var.postgres_port}/fatto_inventory"
  sensitive   = true
}

output "postgres_fatto_identity" {
  description = "PostgreSQL connection for fatto-identity (read/write)"
  value       = "postgresql://fatto_identity:${random_password.pg_fatto_identity.result}@${var.postgres_host}:${var.postgres_port}/fatto_identity"
  sensitive   = true
}

output "postgres_fatto_party" {
  description = "PostgreSQL connection for fatto-party (read/write)"
  value       = "postgresql://fatto_party:${random_password.pg_fatto_party.result}@${var.postgres_host}:${var.postgres_port}/fatto_party"
  sensitive   = true
}

output "postgres_fatto_sales" {
  description = "PostgreSQL connection for fatto-sales (read/write)"
  value       = "postgresql://fatto_sales:${random_password.pg_fatto_sales.result}@${var.postgres_host}:${var.postgres_port}/fatto_sales"
  sensitive   = true
}

output "postgres_fatto_purchasing" {
  description = "PostgreSQL connection for fatto-purchasing (read/write)"
  value       = "postgresql://fatto_purchasing:${random_password.pg_fatto_purchasing.result}@${var.postgres_host}:${var.postgres_port}/fatto_purchasing"
  sensitive   = true
}

# -----------------------------------------------------------------------------
# .env file content for local development
# -----------------------------------------------------------------------------

output "dotenv_content" {
  description = "Content for .env file (local development)"
  value       = <<-EOT
    # FATTO Dev Environment
    # Generated by Terraform
    
    # Database (per-service — use the one matching your service)
    DATABASE_URL_CATALOG=postgresql://fatto_product:${random_password.pg_fatto_product.result}@${var.postgres_host}:${var.postgres_port}/fatto-catalog
    DATABASE_URL_ORDER=postgresql://fatto_order:${random_password.pg_fatto_order.result}@${var.postgres_host}:${var.postgres_port}/fatto_order
    DATABASE_URL_INVENTORY=postgresql://fatto_inventory:${random_password.pg_fatto_inventory.result}@${var.postgres_host}:${var.postgres_port}/fatto_inventory
    DATABASE_URL_IDENTITY=postgresql://fatto_identity:${random_password.pg_fatto_identity.result}@${var.postgres_host}:${var.postgres_port}/fatto_identity
    DATABASE_URL_PARTY=postgresql://fatto_party:${random_password.pg_fatto_party.result}@${var.postgres_host}:${var.postgres_port}/fatto_party
    DATABASE_URL_SALES=postgresql://fatto_sales:${random_password.pg_fatto_sales.result}@${var.postgres_host}:${var.postgres_port}/fatto_sales
    DATABASE_URL_PURCHASING=postgresql://fatto_purchasing:${random_password.pg_fatto_purchasing.result}@${var.postgres_host}:${var.postgres_port}/fatto_purchasing
    
    # Redis
    REDIS_URL=redis://:${local.redis_password}@${var.server_host}:30379
    
    # MinIO (S3)
    S3_ENDPOINT=http://${var.server_host}:30900
    S3_ACCESS_KEY=fatto-admin
    S3_SECRET_KEY=${local.minio_password}
    S3_BUCKET=fatto-attachments
    
    # Keycloak
    KEYCLOAK_URL=https://auth.${var.domain}
    KEYCLOAK_REALM=fatto
    KEYCLOAK_CLIENT_ID=fatto-app
    
    # Mail (SMTP)
    SMTP_HOST=${var.server_host}
    SMTP_PORT=30025
    
    # OpenTelemetry
    OTEL_EXPORTER_OTLP_ENDPOINT=http://${var.server_host}:30417
    OTEL_SERVICE_NAME=fatto-catalog
    OTEL_TRACES_EXPORTER=otlp
  EOT
  sensitive   = true
}
```

Notes:
- `S3_ACCESS_KEY=fatto-admin` is hardcoded (matches `var.minio_root_user` default on the platform side). If the platform's `minio_root_user` is non-default, replace this with the platform's value (no clean way to read MinIO root user without adding it to `fatto-credentials`, which we deliberately didn't do for naming consistency).
- All keycloak-realm / web UI / observability outputs from the original are removed — they were either platform concerns (now on platform side) or informational.

- [ ] **Step 2: Verify fmt**

Run:
```bash
cd /Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev
terraform fmt -check outputs.tf
```

Expected: no output.

---

### Task 19: Verify app terraform configuration is valid

**Files:** None new.

- [ ] **Step 1: terraform init and validate**

Run:
```bash
cd /Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev
source ~/Developer/fatto/tf-variables.sh
terraform init -backend=false
terraform validate
```

Expected: `Success! The configuration is valid.` Errors here indicate either a stray cross-reference or a missing variable — fix inline.

Note: `terraform validate` does NOT contact the cluster, so it will accept the data source declarations even though the secrets don't exist yet.

---

### Task 20: Commit slimmed app repo

**Files:** None new.

- [ ] **Step 1: Check git status**

Run:
```bash
cd /Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra
git status
```

Expected: deletions of the 15 platform .tf/.json files, modifications to `main.tf`, `variables.tf`, `outputs.tf`, `argocd-apps.tf`, `ghcr-pull-secret.tf`.

- [ ] **Step 2: Stage and commit**

Run:
```bash
cd /Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra
git add -A dev/
git status
git commit -m "Split: move shared platform out to tf-platform repo"
```

Expected: single commit with deletions + modifications.

---

## Phase D — Apply and verify

### Task 21: Apply tf-platform

**Files:** None new.

- [ ] **Step 1: terraform init**

Run:
```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
source ~/Developer/fatto/tf-variables.sh
terraform init
```

Expected: providers downloaded, lockfile written.

- [ ] **Step 2: terraform plan**

Run:
```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform plan -out=tfplan
```

Expected: plan shows ~50+ resources to add. Review the count — if drastically different (e.g., <20 or >100), something is wrong. If the plan shows any DESTROY actions, stop and investigate (state should be empty).

- [ ] **Step 3: terraform apply**

Run:
```bash
cd /Users/robert.klucovsky/Developer/tf-platform/dev
terraform apply tfplan
```

Expected: takes 10–15 minutes. The CNPG cluster bootstrap is the slowest step (~5 min). Don't interrupt mid-apply.

If apply fails partway through, READ THE ERROR before re-running. CNPG cluster timing issues sometimes resolve on a second `terraform apply` without any code changes.

- [ ] **Step 4: Verify platform secrets exist**

Run:
```bash
kubectl get secret cnpg-superuser -n cnpg-system
kubectl get secret fatto-credentials -n fatto-erp-dev
```

Expected: both secrets exist. If `cnpg-superuser` is missing, CNPG cluster didn't reach ready state — wait 1 min and re-check before continuing.

- [ ] **Step 5: Verify ArgoCD is up**

Run:
```bash
kubectl get pods -n argocd | grep -E "argocd-server|argocd-application-controller"
```

Expected: pods are `Running` and `Ready`.

---

### Task 22: Wait for CNPG cluster ready

**Files:** None.

- [ ] **Step 1: Verify CNPG cluster status**

Run:
```bash
kubectl get cluster.postgresql.cnpg.io -A
```

Expected: status `Cluster in healthy state`. If still bootstrapping (`Setting up primary`), wait 30s and re-check. Do NOT proceed to app apply until the cluster is healthy — the `postgresql` provider will fail authentication otherwise.

- [ ] **Step 2: Test postgres connectivity from outside the cluster**

Run:
```bash
PG_PASSWORD=$(kubectl get secret cnpg-superuser -n cnpg-system -o jsonpath='{.data.password}' | base64 -d)
PGPASSWORD="$PG_PASSWORD" psql -h 172.16.1.11 -p 30432 -U postgres -d postgres -c "SELECT 1;"
```

Expected: returns `1`. If `psql` is not installed, skip — the next `terraform apply` will exercise the same connection and fail fast on error.

---

### Task 23: Apply fatto-erp/tf-infra

**Files:** None new.

- [ ] **Step 1: terraform init**

Run:
```bash
cd /Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev
source ~/Developer/fatto/tf-variables.sh
terraform init
```

Expected: providers downloaded (smaller set than before — no `helm`).

- [ ] **Step 2: terraform plan**

Run:
```bash
cd /Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev
terraform plan -out=tfplan
```

Expected: plan adds per-service DBs/users, FATTO ArgoCD Applications, `bff_route`, `ghcr-pull-secret`, `argocd-repo-fatto`, and the per-service config secrets. ~30–40 resources. The data sources for `cnpg-superuser` and `fatto-credentials` should resolve cleanly.

If you see `Error: secret "cnpg-superuser" not found`, the platform isn't ready — re-run Task 22.

- [ ] **Step 3: terraform apply**

Run:
```bash
cd /Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev
terraform apply tfplan
```

Expected: ~2 minutes. Apply should succeed cleanly.

---

### Task 24: Regenerate .env.development

**Files:**
- Create/overwrite: `/Users/robert.klucovsky/Developer/fatto/fatto-erp/.env.development`

- [ ] **Step 1: Generate the dotenv**

Run:
```bash
cd /Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev
terraform output -raw dotenv_content > ../../.env.development
```

Expected: file written.

- [ ] **Step 2: Sanity-check the dotenv**

Run:
```bash
head -20 /Users/robert.klucovsky/Developer/fatto/fatto-erp/.env.development
```

Expected: visible `DATABASE_URL_*`, `REDIS_URL`, `S3_*`, `KEYCLOAK_*`, `SMTP_*`, `OTEL_*` entries. No `${...}` placeholders (those mean a value didn't interpolate).

---

### Task 25: Smoke test — verify ArgoCD applications synced

**Files:** None.

- [ ] **Step 1: Check ArgoCD Applications**

Run:
```bash
kubectl get applications.argoproj.io -n argocd
```

Expected: 6 FATTO applications (`fatto-catalog`, `fatto-bff`, `fatto-party`, `fatto-inventory`, `fatto-sales`, `fatto-purchasing`). Sync status may take a minute to show `Synced/Healthy` — that's normal.

- [ ] **Step 2: Check per-service config secrets**

Run:
```bash
kubectl get secrets -n fatto-erp-dev | grep -E "fatto-.*-config|postgres-credentials|ghcr-pull-secret|fatto-credentials"
```

Expected: 6 `fatto-*-config` secrets, `postgres-credentials`, `ghcr-pull-secret`, `fatto-credentials` (the last one created by the platform).

- [ ] **Step 3: Verify the redis-url inside a service config secret**

Run:
```bash
kubectl get secret fatto-catalog-config -n fatto-erp-dev -o jsonpath='{.data.redis-url}' | base64 -d
```

Expected: a string like `redis://:<24-char-password>@redis.fatto-erp-dev.svc.cluster.local:6379`. The password should match what's in `fatto-credentials`:

```bash
kubectl get secret fatto-credentials -n fatto-erp-dev -o jsonpath='{.data.redis-password}' | base64 -d
```

These two values must be identical.

---

### Task 26: Move spec into tf-platform repo and commit

**Files:**
- Move: `/Users/robert.klucovsky/Developer/gitlab/docs/superpowers/specs/2026-05-27-tf-infra-split-design.md` → `/Users/robert.klucovsky/Developer/tf-platform/docs/superpowers/specs/2026-05-27-tf-infra-split-design.md`
- Move: `/Users/robert.klucovsky/Developer/gitlab/docs/superpowers/plans/2026-05-27-tf-infra-split.md` → `/Users/robert.klucovsky/Developer/tf-platform/docs/superpowers/plans/2026-05-27-tf-infra-split.md`

- [ ] **Step 1: Create docs subdirectories in tf-platform**

Run:
```bash
mkdir -p /Users/robert.klucovsky/Developer/tf-platform/docs/superpowers/specs
mkdir -p /Users/robert.klucovsky/Developer/tf-platform/docs/superpowers/plans
```

- [ ] **Step 2: Move the files**

Run:
```bash
mv /Users/robert.klucovsky/Developer/gitlab/docs/superpowers/specs/2026-05-27-tf-infra-split-design.md \
   /Users/robert.klucovsky/Developer/tf-platform/docs/superpowers/specs/

mv /Users/robert.klucovsky/Developer/gitlab/docs/superpowers/plans/2026-05-27-tf-infra-split.md \
   /Users/robert.klucovsky/Developer/tf-platform/docs/superpowers/plans/
```

- [ ] **Step 3: Stage and commit in tf-platform**

Run:
```bash
cd /Users/robert.klucovsky/Developer/tf-platform
git add docs/
git commit -m "docs: tf-infra split design + plan"
```

Expected: one commit.

---

## Self-review notes

Plan covers all spec sections:

- ✅ Pre-flight snapshot (Task 1)
- ✅ tf-platform skeleton & files (Tasks 2–9)
- ✅ Destroy old environment (Tasks 10–11)
- ✅ Slim app repo, refactor cross-references (Tasks 12–20)
- ✅ Apply platform then app (Tasks 21–23)
- ✅ Regenerate dotenv (Task 24)
- ✅ Smoke test (Task 25)
- ✅ Spec relocation + commit (Task 26)

Spec cross-reference table — every entry has a corresponding task:

- `helm_release.argocd` removal → Task 16 step 1.4
- `random_password.{redis,minio,keycloak}_password` → Task 16 step 1.3 + Task 18 (via `data.kubernetes_secret.fatto_credentials`)
- `kubectl_manifest.gateway` removal → Task 16 step 1.5
- `var.postgres_superuser_password` → Task 13 (data source in provider)
- `local.pg_rw_host`/`local.pg_port` → Task 17 (verified stay app-side)
- Namespace references → Task 16 step 1.1, Task 15 (ghcr-pull-secret)
