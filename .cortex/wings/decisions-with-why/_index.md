---
scope: project
applies_in_modes: all
updated: 2026-06-28 21:03 CEST
---

# Decisions with Why — infra rozhodnutia + dôvody

> Vivid anchor: prečo platforma vyzerá tak ako vyzerá. Tu žije "prečo", nie "ako".

## Rozhodnutia (init seed)

- **`pg` backend na zdieľanom CNPG (default):** state použiteľný z hociktorého stroja
  s network prístupom, natívny state locking. Connection string out-of-band (`PG_CONN_STR`).
- **Dočasný `local` backend pri teardowne:** aby `terraform destroy` nezávisel od Postgresu,
  ktorý sám ničí (inak by si pílil konár pod sebou). Obnoviť pg backend pri re-apply.
- **Project-agnostic platforma pre OIDC:** platforma beží MinIO + Keycloak a publikuje
  `minio-admin` Secret; tenant si vlastní celé wiring → onboard tenanta needituje platform repo.
- **Role-based MinIO OIDC per tenant:** MinIO dovoľuje len 1 claim-based provider → každý
  tenant je role-based (jeden `role_policy` pre celý realm). Vedomý trade-off za multi-tenant.
- **Platforma NEnastavuje `MINIO_IDENTITY_OPENID_*` env:** env-set kľúče locknú API override;
  provider registrácia musí ísť cez runtime admin API (`minio_iam_idp_openid`).
- **Nexus provider `timeout=60`:** tolerancia pomalých plan-time refresh GET-ov na LAN/API
  (inak "context deadline exceeded" zhodí celý plan).
- **SonarQube default OFF** (`sonarqube_enabled=false`): voliteľná, ťažká služba.

## Loci

_(Seed z init — ADR-style loci s plným kontextom sa pridajú podľa potreby.)_

Source pointery: `tf/main.tf`, `tf/nexus.tf`, `tf/minio.tf`, `tf/sonarqube.tf`, `README.md`, git log.
