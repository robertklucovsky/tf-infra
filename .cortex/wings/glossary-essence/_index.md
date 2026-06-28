---
scope: project
applies_in_modes: all
updated: 2026-06-28 21:03 CEST
---

# Glossary Essence — doménová terminológia

> Vivid anchor: skratky špecifické pre túto platformu (§2.13 — first-use expand pre nestandardné).

## Termíny (init seed)

- **CNPG** — CloudNativePG: PostgreSQL operator pre K8s. Hostí aj Terraform state (pg backend).
- **ARC** — Actions Runner Controller: self-hosted GitHub Actions runneri na K8s.
- **Zot** — OCI-native image registry (`zot.tf`).
- **Cilium Gateway API** — implementácia K8s Gateway API postavená na Cilium (ingress/routing).
- **Tenant** — projekt konzumujúci túto zdieľanú platformu (FATTO ERP, GitLab) cez vlastný `tf-infra` repo.
- **Platform repo** — tento repo (`tf-infra` / lokálne `tf-platform`): zdieľaný layer, apply prvý, destroy posledný.
- **pg backend** — Terraform state v PostgreSQL (schema `terraform_platform`); vs dočasný `local` backend.
- **OIDC role-based provider** — MinIO OIDC provider s fixným `role_policy` pre celý realm (vs claim-based).

## Loci

_(Seed z init — rozšír ak prekročí ~prah §2.13 Tier 2.)_
