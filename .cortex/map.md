# cortex Map — tf-platform

```yaml
cortex:
  name: tf-platform
  project_type: codebase        # IaC / platform-engineering
  version: 0.1
  spec: 1.0
  initialized: 2026-06-28
  last_consolidation: 2026-06-28
  project_storage:
    type: local
    base: "/Users/robert.klucovsky/Developer/tf-platform"
    repo: "github.com/robertklucovsky/tf-infra"

wings:
  - id: current-state
    path: wings/current-state/
    purpose: "Stav teraz — fáza, aktívna práca, backend stav, otvorené otázky."
    loci_count: 0
  - id: architectural-essence
    path: wings/architectural-essence/
    purpose: "Apply/destroy order, backend (pg vs local), provider topology, cluster layout, hostnames/IP."
    loci_count: 0
  - id: platform-services
    path: wings/platform-services/
    purpose: "Katalóg zdieľaných služieb (CNPG, MinIO, Keycloak, Nexus, Zot, observability, ArgoCD, ARC…) + pointery do dev/*.tf."
    loci_count: 0
  - id: tenant-integration
    path: wings/tenant-integration/
    purpose: "Ako tenant-i konzumujú platformu — OIDC kontrakt, platform-vs-tenant ownership, FATTO ERP, GitLab."
    loci_count: 0
  - id: decisions-with-why
    path: wings/decisions-with-why/
    purpose: "Infra rozhodnutia + dôvody (pg backend, role-based OIDC, project-agnostic platforma…)."
    loci_count: 0
  - id: risks-and-watchouts
    path: wings/risks-and-watchouts/
    purpose: "Gotchas, incidents, watchouts (env-set OIDC keys lock, nexus timeout, teardown order)."
    loci_count: 0
  - id: tribal-knowledge
    path: wings/tribal-knowledge/
    purpose: "Operačné know-how — PG_CONN_STR, kubeconfig context, secrets handling, apply z iného stroja."
    loci_count: 0
  - id: people-dynamics
    path: wings/people-dynamics/
    purpose: "Collab profil per user."
    loci_count: 1
  - id: glossary-essence
    path: wings/glossary-essence/
    purpose: "Doménová terminológia (CNPG, ARC, Zot, Cilium Gateway API, iPaaS, tenant…)."
    loci_count: 0

working_memory:
  path: working-memory/
  status: empty
  note: "Sem AI píše počas session (working-memory/robert-klucovsky/<date>.md)"

journeys:
  status: not_yet_defined
```

## Quick navigation

| Pýtam sa o... | Krídlo |
|---|---|
| Kde sme teraz / čo sa rieši | `current-state` |
| Poradie apply/destroy, backend, providery, cluster IP/hostnames | `architectural-essence` |
| Konkrétna služba (Nexus, MinIO, Keycloak, CNPG…) a jej `.tf` | `platform-services` |
| Ako sa pripojí nový tenant / OIDC wiring | `tenant-integration` |
| Prečo sme niečo spravili takto | `decisions-with-why` |
| Čo môže pokaziť deploy / known gotchas | `risks-and-watchouts` |
| Ako spustiť terraform / odkiaľ heslá | `tribal-knowledge` |
| Význam skratky / termínu | `glossary-essence` |
