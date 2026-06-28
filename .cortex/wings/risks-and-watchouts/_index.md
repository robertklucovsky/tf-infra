---
scope: project
applies_in_modes: all
updated: 2026-06-28 21:03 CEST
---

# Risks & Watchouts — gotchas a incidents

> Vivid anchor: veci, ktoré ticho rozbijú apply/destroy alebo OIDC, ak na ne zabudneš.

## Watchouts (init seed)

- **Destroy order:** platformu ničíš AŽ PO všetkých tenantoch. Inak ostanú dangling závislosti.
- **Backend stav:** pred apply/destroy over, či je `dev/main.tf` na `pg` alebo `local`
  backende — momentálne `local` (teardown). Zlý backend = práca proti nesprávnemu state.
- **`PG_CONN_STR` musí byť exportnutý** pred každým `terraform` príkazom keď je pg backend aktívny.
- **MinIO env vs API lock:** ak by platforma niekedy nastavila `MINIO_IDENTITY_OPENID_*` env,
  tenant OIDC registrácia cez API prestane fungovať (env-set kľúče sú locknuté). NEnastavovať.
- **Nexus plan-time timeout:** pomalý LAN/API refresh → "context deadline exceeded";
  riešené `timeout=60` v nexus provideri (`dev/main.tf`).
- **Secrets sú gitignored:** `terraform.tfvars`, `secrets.auto.tfvars`, `terraform.tfstate*`.
  Na novom stroji ich treba dodať manuálne (alebo cez `TF_VAR_*`).
- **MinIO provider endpoint:** mieri na S3 API NodePort `30900` (`minio_ssl=false`),
  NIE na console `s3.klucovsky.com` (:9001). Zámena je častý omyl.

## Loci

_(Seed z init.)_

Source pointery: `README.md`, `dev/main.tf`, git log (fix/revert commity).
