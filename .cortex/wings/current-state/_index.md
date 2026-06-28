---
scope: project
applies_in_modes: all
updated: 2026-06-28 21:03 CEST
---

# Current State — kde sme teraz

> Vivid anchor: platforma stojí a beží na homelab K8s (172.16.1.11). Práve teraz je
> state **dočasne na lokálnom súbore** (nie pg backend) kvôli teardown cyklu, a posledná
> aktívna téma bola MinIO↔Keycloak OIDC ako **tenant-owned** model.

## Loci

_(Zatiaľ žiadne konsolidované loci — seed z init 2026-06-28. WM entries sa sem promotnú pri konsolidácii.)_

## Snapshot (init seed)

- **Fáza:** funkčná platforma, iteratívne dolaďovanie zdieľaných služieb.
- **Backend:** `backend "local"` v `dev/main.tf` (TEMPORARY pre teardown). Pôvodný `backend "pg"`
  (schema `terraform_platform`) je zakomentovaný — obnoviť ak sa repo znovu apply-uje.
- **Posledné commity (kontext):** nexus provider `timeout=60` (slow plan-time refresh),
  keycloak-admin Secret publishing, MinIO OIDC revert na tenant-owned (`minio_iam_idp_openid`).
- **Otvorené otázky:** GitLab tenant (plánovaný, ešte nepridaný ako `.tf` v `dev/`).

Source pointery: `dev/main.tf`, git log @ 2026-06-28.
