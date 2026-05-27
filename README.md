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
