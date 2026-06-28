---
scope: project
applies_in_modes: all
updated: 2026-06-28 21:03 CEST
---

# Tenant Integration — ako tenant-i konzumujú platformu

> Vivid anchor: platforma je "hostiteľ". Beží zdieľané služby a publikuje Secrets;
> **tenant `tf-infra` repo si vlastní celé svoje wiring**. Platforma sa needituje pri onboardingu tenanta.

## Tenant-i (init seed)

- **FATTO ERP** — `/Users/robert.klucovsky/Developer/fatto/fatto-erp/tf-infra/`
- **GitLab** — plánovaný, ešte nepridaný

## Platform-vs-tenant ownership

- **Platforma vlastní:** cluster bootstrap, zdieľané služby, publikované Secrets
  (`minio-admin`, `keycloak-admin` v príslušných namespace-och), tenant namespace setup
  (napr. `fatto-erp-dev` + `fatto-credentials`).
- **Tenant vlastní:** per-service DB/users, ArgoCD Applications pre svoje workloady,
  image pull secrets, a **celé MinIO↔Keycloak OIDC wiring** (realm, client, policies, buckets,
  provider registráciu cez `minio_iam_idp_openid`).

## MinIO OIDC kontrakt (kritický)

- MinIO podporuje viac OIDC providerov, ale **iba jeden smie byť JWT-claim-based**;
  všetky ostatné **musia byť role-based** (fixný `role_policy` pre všetkých userov realmu).
- Každý tenant registruje **role-based** provider → všetci useri jeho realmu dostanú rovnaký bucket access.
- Tenant používa MinIO **S3 API** (NodePort `30900`, `minio_ssl=false`), NIE console
  (`s3.klucovsky.com` → console :9001).
- ⚠️ Platforma **NESMIE** nastaviť `MINIO_IDENTITY_OPENID_*` env vars na MinIO StatefulSet —
  env-set kľúče sú locknuté proti API override (provider registrácia je runtime config).

## Loci

_(Seed z init.)_

Source pointery: `README.md` (MinIO OIDC sekcia + HCL príklad),
`docs/superpowers/specs/2026-06-28-minio-keycloak-oidc-design.md`,
`docs/superpowers/plans/2026-06-28-minio-keycloak-oidc.md`, `dev/keycloak.tf`, `dev/minio.tf`.
