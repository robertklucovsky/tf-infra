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
