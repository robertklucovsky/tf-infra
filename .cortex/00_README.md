# tf-platform — cortex

> Persistentná pamäť pre AI v projekte **tf-platform** (Shared Kubernetes Platform Infrastructure).
> Inicializované: 2026-06-28
> Posledná konsolidácia: 2026-06-28
> Spec: cortex 1.0 · Skill: cortex 1.0.1-alpha

## TL;DR projektu

Terraform konfigurácia pre **zdieľanú Kubernetes platformu** (Canonical K8s), ktorú
konzumujú tenant-i (FATTO ERP, GitLab plánovaný). Jeden root modul v `dev/`. Platforma
poskytuje cluster bootstrap (CNPG PostgreSQL, cert-manager, Cilium Gateway API, ArgoCD)
a zdieľané backing services (MinIO, Keycloak, Nexus, Zot, Redis, Mailpit, pgAdmin) +
observability stack (Prometheus, Grafana, Tempo, Loki, Promtail) + ARC (GitHub Actions
runner controller) + voliteľne SonarQube. Aplikuje sa **prvá** pred tenant repami,
ničí sa **posledná**. Repo: `github.com/robertklucovsky/tf-infra`.

## Stav projektu (teraz)

Platforma je funkčná. **Backend dočasne migrovaný z `pg` (CNPG) na lokálny súbor**
kvôli teardownu (aby `terraform destroy` nezávisel na Postgrese, ktorý sám ničí).
Posledná práca: MinIO ↔ Keycloak OIDC (tenant-owned model), Nexus provider timeout fix,
keycloak-admin Secret publishing. Detail → `wings/current-state/_index.md`.

## Ako navigovať

1. Pre orientáciu po krídlach: [`map.md`](map.md)
2. Pre storage/path resolving: [`config.md`](config.md)
3. Pre špecifické úlohy → otvor relevantné wing → `_index.md` → konkrétny locus

## Aktívne krídla

- [`wings/current-state/`](wings/current-state/_index.md) — kde sme teraz, aktívna práca, otvorené otázky
- [`wings/architectural-essence/`](wings/architectural-essence/_index.md) — apply order, backend, provider topology, cluster layout
- [`wings/platform-services/`](wings/platform-services/_index.md) — katalóg zdieľaných služieb + source pointery do `dev/*.tf`
- [`wings/tenant-integration/`](wings/tenant-integration/_index.md) — ako tenant-i konzumujú platformu (OIDC kontrakt, platform-vs-tenant ownership)
- [`wings/decisions-with-why/`](wings/decisions-with-why/_index.md) — infra rozhodnutia + prečo
- [`wings/risks-and-watchouts/`](wings/risks-and-watchouts/_index.md) — gotchas, incidents, watchouts
- [`wings/tribal-knowledge/`](wings/tribal-knowledge/_index.md) — operačné know-how (PG_CONN_STR, kubeconfig, secrets)
- [`wings/people-dynamics/`](wings/people-dynamics/_index.md) — collab profil
- [`wings/glossary-essence/`](wings/glossary-essence/_index.md) — doménová terminológia

## Vzťah k project storage

Tento cortex žije **v repe** vedľa Terraform kódu (`dev/*.tf`). Drží esenciu + pointery,
NIE kópie. Source pointery v loci vedú späť do `dev/<file>.tf` alebo `docs/superpowers/`.

## Trojstupňový pamäťový model

- **Tier 1 — `working-memory/`**: AI píše voľne (aggressive default). Auto-archive po 30 dňoch.
- **Tier 2 — `wings/`**: konsolidovaná pamäť. AI nikdy nepíše priamo, iba cez consolidation s user súhlasom (výnimka: rule-establishing utterances §2.3.1).
- **Tier 3 — `canonical/`**: iba človek píše. AI read-only. ADR, business pravidlá.

## AI session protokol

Multi-scope blend (user cortex + tento project cortex) — detail SKILL.md skillu `cortex` §2.1.
