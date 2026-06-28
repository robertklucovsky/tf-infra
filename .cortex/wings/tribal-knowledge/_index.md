---
scope: project
applies_in_modes: all
updated: 2026-06-28 21:03 CEST
---

# Tribal Knowledge — operačné know-how

> Vivid anchor: "ako to reálne spustiť" — príkazy a triky, čo nie sú v kóde.

## Know-how (init seed)

- **Apply:**
  ```bash
  cd dev
  source ~/Developer/fatto/tf-variables.sh
  export PG_CONN_STR="postgres://postgres:<password>@172.16.1.11:30432/postgres?sslmode=disable"
  terraform init && terraform apply
  ```
- **Z iného stroja:** clone repo, dodaj `terraform.tfvars` (gitignored), exportni `PG_CONN_STR`,
  potrebuješ kubeconfig context `k8s` + network prístup na `172.16.1.11:30432` a `*.klucovsky.com`.
- **Heslo rotácia:** rovnaké Postgres heslo je v `terraform.tfvars` aj `PG_CONN_STR` — rotuj na oboch miestach.
- **Kubeconfig:** context `k8s` (var `kubeconfig_context`).

## Loci

_(Seed z init.)_

Source pointery: `README.md`, `dev/variables.tf`.
