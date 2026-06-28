---
scope: project
applies_in_modes: all
updated: 2026-06-28 21:03 CEST
---

# Architectural Essence — hlavné osi platformy

> Vivid anchor: jeden Terraform root modul (`dev/`) bootstrapuje celý zdieľaný K8s
> platform layer. Aplikuje sa **prvý**, ničí sa **posledný**. Tenant-i si na ňom stavajú.

## Kľúčové osi (init seed)

- **Single root module:** všetok platform IaC žije v `dev/` — žiadne `.tf` na roote repa.
  Jeden `terraform apply` z `dev/`.
- **Apply/destroy order:** platforma sa apply-uje PRED akýmkoľvek tenant repom a destroy-uje
  AŽ PO všetkých tenantoch (poskytuje cluster-wide závislosti).
- **State backend:** normálne `pg` backend na zdieľanom CNPG Postgrese (schema
  `terraform_platform`, `172.16.1.11:30432`) → použiteľné z hociktorého stroja s network
  prístupom. `PG_CONN_STR` out-of-band. **Teraz dočasne `local`** (teardown nezávislý od Postgresu).
- **Providers:** `kubernetes ~2.36`, `helm ~2.17`, `random ~3.6`, `alekc/kubectl ~2.1`,
  `cyrilgdn/postgresql ~1.25`, `datadrivers/nexus ~2.0`. K8s/helm/kubectl cez kubeconfig
  context `k8s`; postgresql cez superuser na node IP; nexus cez `https://nexus.klucovsky.com`.
- **Networking:** Cilium Gateway API + cert-manager (Let's Encrypt, DigitalOcean DNS-01).
  Služby exponované cez hostnames `*.klucovsky.com` + NodePort-y na `172.16.1.11`.
- **Project-agnostic platforma:** platforma neimplementuje per-tenant logiku — publikuje
  Secrets a beží zdieľané služby; tenant-i si vlastnia svoje wiring (viď `tenant-integration`).

## Loci

_(Seed z init — detailné loci sa pridajú pri konsolidácii.)_

Source pointery: `dev/main.tf`, `dev/variables.tf`, `dev/gateway-platform.tf`, `dev/certificates.tf`, `README.md`.
