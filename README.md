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
export PG_CONN_STR="postgres://postgres:<postgres_password>@172.16.1.11:30432/postgres?sslmode=disable"
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
export PG_CONN_STR="postgres://postgres:<postgres_password>@172.16.1.11:30432/postgres?sslmode=disable"
```

### Using from another machine

```bash
git clone git@github.com:robertklucovsky/tf-infra.git
cd tf-infra/dev

# Secrets are gitignored — provide terraform.tfvars manually (or via TF_VAR_* env vars)
export PG_CONN_STR="postgres://postgres:<postgres_password>@172.16.1.11:30432/postgres?sslmode=disable"

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

The platform registers one role-based MinIO OIDC provider per project, driven by
`var.minio_oidc_projects`, and publishes a generated `client_secret` as the
`minio-oidc-<project>` Secret in the `minio` namespace. Each tenant repo owns its
realm and bucket access:

1. **Platform apply #1** — add the project to `minio_oidc_projects` with
   `provider_enabled = false`. This publishes `minio-oidc-<project>`.
2. **Tenant repo** — read `minio-oidc-<project>`; create the `keycloak_realm`,
   a confidential `keycloak_openid_client` (standard flow, valid redirect URI
   `https://s3.klucovsky.com/oauth_callback`, client_id/secret from the Secret),
   the `minio_iam_policy` resources named in the entry's `role_policy`, and the
   buckets.
3. **Platform apply #2** — set `provider_enabled = true` so MinIO loads the
   provider.

Full design: `docs/superpowers/specs/2026-06-28-minio-keycloak-oidc-design.md`.
