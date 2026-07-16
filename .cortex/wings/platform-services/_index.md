---
scope: project
applies_in_modes: all
updated: 2026-06-28 21:03 CEST
---

# Platform Services — katalóg zdieľaných služieb

> Vivid anchor: každá služba = jeden `.tf` súbor v `tf/`. Toto je mapa "ktorá služba, ktorý súbor".

## Služby a ich source (init seed)

| Služba | `tf/` súbor | Účel |
|---|---|---|
| CNPG PostgreSQL | `cnpg.tf`, `postgresql.tf` | Zdieľaná DB + operator; hostí aj TF state (pg backend) |
| cert-manager | `certificates.tf` | TLS certy (Let's Encrypt, DO DNS-01) |
| Cilium Gateway API | `gateway-platform.tf`, `gateway.tf`, `routes-platform.tf` | Ingress / routing |
| ArgoCD | `argocd.tf` | GitOps CD (platform-level) |
| MinIO | `minio.tf` | S3-compatible object storage; OIDC cez Keycloak (tenant-owned) |
| Keycloak | `keycloak.tf` | IdP; publikuje `keycloak-admin` Secret |
| Nexus | `nexus.tf`, `nexus-npm.tf` | Artifact/npm repo; `datadrivers/nexus` provider |
| Zot | `zot.tf` | OCI image registry |
| Mailpit | `mailpit.tf` | Dev SMTP / mail catcher |
| pgAdmin | `pgadmin.tf` | Postgres admin UI |
| Observability | `observability.tf`, `dashboards.tf`, `*-dashboard.json` | Prometheus, Grafana, Tempo, Loki, Promtail |
| ARC | `arc.tf` | GitHub Actions Runner Controller |
| SonarQube | `sonarqube.tf` | Code quality — gated `sonarqube_enabled` (default OFF) |
| GitHub Actions storage | `github-actions-storage.tf` | Backing storage pre ARC runnery |
| Passwords / secrets | `passwords.tf`, `secrets.auto.tfvars`, `terraform.tfvars` | Random hesla + secret vars (gitignored) |
| Outputs | `outputs.tf` | Exporty (endpoints, creds refs) |

## Loci

_(Seed z init — per-service essence loci sa pridajú podľa potreby.)_

Source pointery: `tf/*.tf`.
