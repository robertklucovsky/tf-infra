# tf-infra split — Platform / App separation

**Date**: 2026-05-27
**Status**: Draft, pending user review
**Migration mode**: Fresh apply (dev cluster will be destroyed and recreated)

## Background

`/Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/dev/` currently provisions every piece of infrastructure used by FATTO development — both the shared platform (k8s addons, CNPG, Redis, MinIO, Keycloak, observability, ArgoCD, gateway, cert-manager) and the FATTO-specific resources (per-service databases, ArgoCD Application manifests). The platform layer changes slowly; the app layer changes with FATTO development. Mixing them means app-level changes go through platform-level state, and the platform isn't reusable by other tenants (e.g., a planned GitLab install on the same cluster).

## Goals

1. Separate platform infrastructure from FATTO-specific resources into two Terraform repos with independent lifecycles.
2. Keep cross-repo coupling loose — no shared state backend, no `terraform_remote_state`. Contract surface is the Kubernetes cluster itself.
3. Preserve existing secret naming and structure (`fatto-credentials`, `postgres-credentials`, `cnpg-superuser`).
4. Enable future platform tenants (GitLab next, possibly more) to be added without touching the FATTO app repo.

## Non-goals

- Remote state backend (local state stays local).
- Shared module library (move first, modularize later if patterns emerge).
- Preserving any currently-running cluster state — dev environment is recreated fresh.
- Staging/prod environment scaffolding (textual intent stays in READMEs; no empty directories).
- Automated apply ordering via CI — manual order is fine for one operator.

## Target structure

```
/Users/robert.klucovsky/Developer/
├── tf-platform/                          # NEW — shared infrastructure
│   ├── README.md
│   ├── CLAUDE.md
│   ├── .gitignore
│   └── dev/
│       ├── main.tf                       # kubernetes, helm, kubectl, postgresql (CNPG admin), random
│       ├── variables.tf
│       ├── terraform.tfvars              # gitignored
│       ├── namespace.tf                  # fatto-erp-dev namespace + fatto-credentials + ghcr-pull-secret
│       ├── cnpg.tf                       # CNPG operator + cluster
│       ├── gateway.tf                    # Cilium Gateway API
│       ├── certificates.tf               # cert-manager + wildcard certs
│       ├── redis.tf                      # Bitnami Helm
│       ├── minio.tf                      # Bitnami Helm
│       ├── keycloak.tf                   # StatefulSet + realm-less install
│       ├── mailpit.tf
│       ├── pgadmin.tf
│       ├── observability.tf              # Tempo/Loki/Promtail/Prom/Grafana
│       ├── dashboards.tf
│       ├── loki-dashboard.json
│       ├── tempo-dashboard.json
│       ├── argocd.tf                     # ArgoCD install only
│       ├── sonarqube.tf
│       └── outputs.tf                    # platform-side identifiers (for debugging)
│
└── fatto/fatto-erp/tf-infra/             # EXISTING — slimmed
    └── dev/
        ├── main.tf                       # kubernetes + kubectl + postgresql + random providers; data sources for platform handoff
        ├── variables.tf
        ├── terraform.tfvars
        ├── postgresql.tf                 # FATTO per-service DBs/roles/extensions + postgres-credentials secret (FATTO entries only)
        ├── argocd-apps.tf                # FATTO ArgoCD Application manifests + bff_route HTTPRoute + argocd-repo-fatto secret
        ├── ghcr-pull-secret.tf           # GHCR docker-config pull secret in fatto-erp-dev namespace
        └── outputs.tf                    # dotenv_content generator
```

Note: `keycloak-realm/` and `keycloak-theme/` move to `tf-platform/dev/` alongside `keycloak.tf` because the platform's `keycloak.tf` references them via `${path.module}/keycloak-{realm,theme}/...`. They cannot stay in the app repo.

## Providers

**Platform** (`tf-platform/dev/main.tf`): `kubernetes`, `helm`, `kubectl`, `random`, `postgresql`. Platform creates Keycloak's and SonarQube's databases (and the legacy OPAL database) via the postgresql provider — these are platform-service databases, owned alongside the services themselves.

**App** (`fatto-erp/tf-infra/dev/main.tf`): `kubernetes`, `kubectl` (for `kubectl_manifest` ArgoCD Applications and HTTPRoutes), `postgresql` (per-service DBs/users via CNPG NodePort), `random` (per-service DB passwords). No `helm` provider — no Helm releases installed from the app side.

Both sides authenticate the `postgresql` provider against CNPG via NodePort (`172.16.1.11:30432`). The platform sources the superuser password from `var.postgres_superuser_password` directly; the app sources it from `data.kubernetes_secret.cnpg_superuser.data["password"]`.

## File ownership

**Moves to `tf-platform/dev/`**: `main.tf` (with full provider set including `postgresql`), `variables.tf` (platform vars), `namespace.tf` (with `fatto-credentials` secret), `cnpg.tf`, `gateway.tf`, `certificates.tf`, `redis.tf`, `minio.tf`, `keycloak.tf`, `keycloak-realm/`, `keycloak-theme/` (Keycloak is platform-owned, so its realm/theme assets move with it), `mailpit.tf`, `pgadmin.tf`, `observability.tf`, `dashboards.tf`, `loki-dashboard.json`, `tempo-dashboard.json`, `argocd.tf`, `sonarqube.tf`, the platform-service `random_password` resources (redis, minio, keycloak admin, grafana, pgadmin, plus pg_keycloak and pg_opal), plus a new `postgresql.tf` defining keycloak/opal DB resources and the `keycloak-db-credentials` secret.

**Stays in `fatto-erp/tf-infra/dev/`**: `main.tf` (slimmed), `variables.tf` (slimmed to app vars + ghcr), `postgresql.tf` (FATTO per-service DBs/roles/extensions only — keycloak/opal entries removed; `postgres-credentials` secret no longer contains keycloak/opal keys), `argocd-apps.tf`, `ghcr-pull-secret.tf`, `outputs.tf` (slimmed to dotenv generation).

## Secret contract

The platform exposes its outputs to the app via Kubernetes secrets — no Terraform state coupling.

| Secret | Namespace | Creator | Contents |
|---|---|---|---|
| `cnpg-superuser` | `cnpg-system` | CNPG operator (native) | Postgres superuser credentials |
| `fatto-credentials` | `fatto-erp-dev` | Platform | `postgres-password`, `redis-password`, `minio-password`, `keycloak-password` (Keycloak admin UI password, NOT the DB password) |
| `keycloak-db-credentials` | `fatto-erp-dev` | Platform | `keycloak-url`, `keycloak-username`, `keycloak-password` (Keycloak's database credentials — consumed by the Keycloak StatefulSet env vars) |
| `ghcr-pull-secret` | `fatto-erp-dev` | App | Docker pull credentials for FATTO container images |
| `argocd-repo-fatto` | `argocd` | App | GHCR credentials for ArgoCD to clone FATTO repos |
| `postgres-credentials` | `fatto-erp-dev` | App | Per-service DB users/passwords for FATTO services (fatto-catalog, fatto-order, etc.) |

The app's `main.tf` reads `cnpg-superuser` via `data "kubernetes_secret"` to authenticate its `postgresql` provider. The app's `outputs.tf` reads `fatto-credentials` to compose `dotenv_content`. App-created `postgres-credentials` is consumed by FATTO services at runtime (not by Terraform).

## Cross-references that must be refactored on the app side

`argocd-apps.tf` and `postgresql.tf` today reference platform-owned Terraform resources by symbolic name. After the split these names don't exist on the app side and must be replaced with `data` source lookups:

| Current reference (app file) | Replacement after split |
|---|---|
| `helm_release.argocd` (in `depends_on`) | Remove — replaced by implicit ordering from `data "kubernetes_namespace" "argocd"` lookup, or simply omitted (the manifest apply fails fast if ArgoCD CRDs aren't installed) |
| `random_password.redis_password.result` (in dotenv URLs) | `data.kubernetes_secret.fatto_credentials.data["redis-password"]` |
| `random_password.minio_password.result` | `data.kubernetes_secret.fatto_credentials.data["minio-password"]` |
| `random_password.keycloak_password.result` | `data.kubernetes_secret.fatto_credentials.data["keycloak-password"]` |
| `kubectl_manifest.gateway` (in `depends_on` for `bff_route`) | Remove — replaced by either no dependency (manifest apply fails fast if Gateway CRD/instance missing) or a `data` source on the Gateway resource |
| `var.postgres_superuser_password` (for postgresql provider) | `data.kubernetes_secret.cnpg_superuser.data["password"]` |
| `local.pg_rw_host` / `local.pg_port` (currently locals in postgresql.tf) | Stay as app-side locals, but their values point at NodePort `172.16.1.10:30432` — verify these don't reference platform resources |

Each of these is a one-line change but they're load-bearing — getting them wrong is how `terraform apply` fails on the app side.

## Apply / destroy ordering

**Apply**:
1. `terraform apply` in `tf-platform/dev/` — creates namespace, CNPG, all platform Helm releases, ArgoCD.
2. `terraform apply` in `fatto-erp/tf-infra/dev/` — creates per-service DBs/users, FATTO ArgoCD Applications, writes `.env.development`.

If step 2 runs first, the K8s data source lookup for `cnpg-superuser` fails fast — explicit ordering violation, no silent failure.

**Destroy**:
1. `terraform destroy` in `fatto-erp/tf-infra/dev/` first (Applications + per-service DBs).
2. `terraform destroy` in `tf-platform/dev/` second.

Reverse order leaves orphaned ArgoCD Application CRDs and (briefly) per-service DBs inside a doomed CNPG cluster. README in each repo documents the rule.

## Execution sequence

Pre-flight snapshot for reference:

```bash
cd ~/Developer/fatto/fatto-erp/tf-infra/dev
terraform output -json > ~/Developer/fatto-tf-pre-split-outputs.json
```

1. **Destroy old**: `terraform destroy` in `fatto-erp/tf-infra/dev/`.
2. **Create new platform repo**: `mkdir -p ~/Developer/tf-platform/dev && git init`.
3. **Move files**: copy/edit per "File ownership" above.
4. **Slim app repo**: delete moved files, rewire `main.tf` and `outputs.tf` for the K8s-data-source handoff, refresh provider configs.
5. **Apply platform**: `terraform init && terraform apply` in `tf-platform/dev/`.
6. **Apply app**: `terraform init && terraform apply` in `fatto-erp/tf-infra/dev/`.
7. **Regenerate dotenv**: `terraform output -raw dotenv_content > ../../.env.development`.
8. **Commit both repos**.

Estimated wall time: destroy ~5 min, platform apply ~10–15 min, app apply ~2 min — roughly 20–25 minutes end to end.

## Risks & mitigations

- **All current dev data lost**: accepted — fresh apply was chosen explicitly. No databases in dev hold anything that isn't regenerable.
- **New random passwords**: app's `.env.development` is rewritten on step 7, so downstream consumers pick up new values automatically.
- **Apply-order violation**: K8s data source lookup fails fast on the app side with a clear "secret not found" error — explicit, not silent.
- **CNPG cluster bootstrap takes time**: platform apply may report ~5–10 min on the CNPG cluster reaching ready state. Don't kill it mid-apply.
- **Provider auth races on first apply**: the `postgresql` provider on the app side authenticates against CNPG via NodePort. If CNPG isn't fully ready when the app applies, this fails. Mitigation: wait 30s between step 5 finishing and step 6 starting.

## Open questions / deferred decisions

- Whether `terraform.tfvars` should reference a shared `~/Developer/fatto/tf-variables.sh` (current pattern) or each repo gets its own variable seeding mechanism. Defaulting to: keep the shared script, both repos `source` it.
- Whether to introduce a top-level Makefile in each repo for `make apply` / `make destroy` to encode order. Out of scope for this split; can add later.

## Follow-up work (separate specs)

- GitLab install as another Helm release in `tf-platform/dev/gitlab.tf` (was the original brainstorming topic that triggered this split).
