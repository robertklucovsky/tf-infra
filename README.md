# Shared Platform Infrastructure

Terraform configuration for the shared Kubernetes platform that tenants (FATTO, GitLab, etc.) consume.

## What's here

- Cluster bootstrap: CNPG, cert-manager, Cilium Gateway API, ArgoCD
- Shared backing services: Redis, MinIO, Keycloak, Mailpit, pgAdmin
- Observability: Prometheus, Grafana, Tempo, Loki, Promtail
- Code quality: SonarQube (optional — gated behind `sonarqube_enabled`, disabled by default)
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
export PG_CONN_STR="postgres://postgres:<postgres_password>@172.16.1.11:30432/postgres?sslmode=require"
terraform init
terraform apply
```

## Remote state (PostgreSQL backend)

State lives in the shared CNPG PostgreSQL via the Terraform `pg` backend
(schema `terraform_platform`), not in a local file. This lets the config be
used from any machine with network access to the cluster's Postgres, with
native state locking.

The connection string is **not** committed (it contains the superuser
password). Supply it out-of-band via the `PG_CONN_STR` env var before any
`terraform` command:

```bash
export PG_CONN_STR="postgres://postgres:<postgres_password>@172.16.1.11:30432/postgres?sslmode=require"
```

### Using from another machine

```bash
git clone git@github.com:robertklucovsky/tf-infra.git
cd tf-infra/dev

# Secrets are gitignored — provide terraform.tfvars manually (or via TF_VAR_* env vars)
export PG_CONN_STR="postgres://postgres:<postgres_password>@172.16.1.11:30432/postgres?sslmode=require"

terraform init    # pulls existing state from Postgres
terraform plan
```

Requirements on any machine: network access to `172.16.1.11:30432` (Postgres)
and to the platform hostnames (e.g. `nexus.klucovsky.com`), a kubeconfig with
the `k8s` context, and the secrets in `terraform.tfvars`. `terraform.tfvars`,
`terraform.tfstate`, and `terraform.tfstate.backup` are gitignored; the same
Postgres password appears in both `terraform.tfvars` and `PG_CONN_STR`, so
rotate it in both places.

## Tenants

- FATTO ERP — `/Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/`
- GitLab (planned) — to be added as another `.tf` file in `dev/`

### MinIO OIDC (Keycloak) per project

The platform is **project-agnostic** for OIDC: it just runs MinIO + Keycloak and
publishes the `minio-admin` Secret in the `minio` namespace. **Each project's
`tf-infra` owns its entire MinIO ↔ Keycloak wiring** — realm, client, policies,
buckets, *and* the MinIO provider registration — via the `keycloak` and `minio`
Terraform providers. Nothing in this platform repo needs editing to onboard a
project.

MinIO supports multiple named OIDC providers but **only one may be JWT-claim-based;
all others must be role-based** (a fixed `role_policy` for every user of that
realm). So each project registers a **role-based** provider: all users in its
realm get the same bucket access.

In the project `tf-infra`, configure both providers and add:

```hcl
# Admin creds published by the platform (cross-namespace read)
data "kubernetes_secret" "minio_admin" {
  metadata {
    name      = "minio-admin"
    namespace = "minio"
  }
}

# Use the SAME minio provider config the project already uses to provision its
# buckets/access keys. The provider talks to the MinIO S3 API (port 9000), NOT
# the console (s3.klucovsky.com routes to the console on 9001). The S3 API is a
# NodePort on 30900; MinIO here runs without TLS, so minio_ssl = false.
provider "minio" {
  minio_server   = "172.16.1.11:30900"   # cluster node IP : api NodePort
  minio_user     = data.kubernetes_secret.minio_admin.data["username"]
  minio_password = data.kubernetes_secret.minio_admin.data["password"]
  minio_ssl      = false
}

# 1. Realm + confidential client for MinIO
resource "keycloak_realm" "this" {
  realm = "projecta"
}

resource "keycloak_openid_client" "minio" {
  realm_id              = keycloak_realm.this.id
  client_id             = "minio"
  access_type           = "CONFIDENTIAL"
  standard_flow_enabled = true
  valid_redirect_uris   = ["https://s3.klucovsky.com/oauth_callback"]
  web_origins           = ["https://s3.klucovsky.com"]
}

# 2. The MinIO policy granting this project's bucket access (role-based target)
resource "minio_iam_policy" "rw" {
  name   = "projecta-rw"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:*"]
      Resource = ["arn:aws:s3:::projecta-*", "arn:aws:s3:::projecta-*/*"]
    }]
  })
}

resource "minio_s3_bucket" "data" {
  bucket = "projecta-data"
}

# 3. Register the realm as a role-based OIDC provider on MinIO
resource "minio_iam_idp_openid" "keycloak" {
  name          = "projecta"   # provider config name (login-screen group)
  config_url    = "https://auth.klucovsky.com/realms/${keycloak_realm.this.realm}/.well-known/openid-configuration"
  client_id     = keycloak_openid_client.minio.client_id
  client_secret = keycloak_openid_client.minio.client_secret
  role_policy   = minio_iam_policy.rw.name   # role-based; do NOT set claim_name
  display_name  = "Project A"
  scopes        = "openid"
  redirect_uri  = "https://s3.klucovsky.com/oauth_callback"
}
```

Users then open `https://s3.klucovsky.com`, pick "Project A" on the login screen,
authenticate against the realm, and receive the `projecta-rw` policy.

> The MinIO provider registration is runtime config (MinIO admin API), so the
> platform MUST NOT also set `MINIO_IDENTITY_OPENID_*` env vars on the MinIO
> StatefulSet — env-set keys are locked against API override. The platform
> intentionally sets none.

Full design: `docs/superpowers/specs/2026-06-28-minio-keycloak-oidc-design.md`.
