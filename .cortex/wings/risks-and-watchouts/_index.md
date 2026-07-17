---
scope: project
applies_in_modes: all
updated: 2026-07-17 05:44 CEST
---

# Risks & Watchouts — gotchas a incidents

> Vivid anchor: veci, ktoré ticho rozbijú apply/destroy, OIDC, DB alebo sieť, ak na ne zabudneš.

## Watchouts

- **Destroy order:** platformu ničíš AŽ PO všetkých tenantoch.
- **Backend stav:** `tf/main.tf` je na `backend "local"` (teardown-era). Over pred apply/destroy.
- **Postgres hostssl vynútené (od 2026-07-16):** server **odmieta plaintext**. KAŽDÝ konzument musí
  `sslmode=require` — vrátane **tenantov (fatto-erp)** a `pg` backendu / `PG_CONN_STR`. Zabudnutý
  tenant = zlyhá connect. Rollback = zmazať `hostnossl reject` z `pg_hba` v `tf/cnpg.tf`.
- **RustFS je krehký po nečistom vypnutí (od 2026-07-16):** single-disk `xl-single`, **žiadny heal
  command**. Po odstávke `/health/ready` 503 (`VolumeNotFound`). Pred plánovaným reštartom server
  gracefully zastav. Raw záloha: `/root/rustfs-backup-2026-07-16/data.tgz` na node.
- **Nexus plan-time timeout:** pomalý LAN/API refresh → "context deadline exceeded"; `timeout=60`
  v nexus provideri (`tf/main.tf`) + niekedy treba `-target` na obídenie flaky nexus refreshu.
- **Secrets:** `terraform.tfvars` je od 2026-07-16 **untracked + gitignored** (predtým bol omylom
  tracked — obsahoval len placeholdery, reálne secrets sú v `secrets.auto.tfvars`). **`*.auto.tfvars`
  OVERRIDE-uje `terraform.tfvars`** — reálne heslá/token/rustfs_oidc_client_secret žijú v `secrets.auto.tfvars`.
- **Omada ACL `aclDisable` je UI-hint, NIE globálny vypínač** — pravidlo so `status:true` je enforced.
- **rawfile CSI storage path:** disk.img žijú na host `/var/snap/k8s/common/rawfile-storage/pvc-*/`
  (nie `/data` — to je len mount vnútri CSI kontajnera; chybové cesty klamú).
- **macOS `timeout` neexistuje** → `timeout ... /dev/tcp` = false negatívy pri TCP testoch; použi `nc -z -G`.
- **MinIO → RustFS (historicky):** MinIO odstránené; S3 je RustFS (`s3.klucovsky.com`, NodePorty 30910/11).
  Staré MinIO OIDC / 30900 / minio_ssl referencie sú neplatné.

## Loci

_(Konsolidované z WM 2026-07-16.)_

Source pointery: `docs/security/2026-07-14-home-lab-risk-assessment.md`, `tf/cnpg.tf`, `tf/rustfs.tf`, `working-memory/robert-klucovsky/2026-07-16.md`.
