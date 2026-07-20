# CNPG Czech/Slovak full-text search dictionaries

**Date:** 2026-07-20
**Repo:** `tf-platform` (shared platform infrastructure)
**Status:** Approved design, not yet implemented

## Goal

The FATTO-AAC RFP (`../fatto/fatto-aac/requst-for-proposal/07-ai-ml-specification.md`
§7.3.2) requires PostgreSQL `tsvector` full-text search with "multilingual
configuration with appropriate stemming" across English, Czech, and Slovak.
English ships with Postgres core; Czech and Slovak do not — there is no
built-in stemmer for either language. This design covers making Czech/Slovak
stemming data available on the shared CNPG PostgreSQL cluster that `tf-platform`
already runs in Kubernetes.

## Scope (locked)

`tf-platform`'s job stops at the CNPG image and cluster rollout: getting the
Czech/Slovak dictionary *files* onto disk in every Postgres instance in the
running cluster. The actual `CREATE TEXT SEARCH DICTIONARY` /
`CREATE TEXT SEARCH CONFIGURATION` objects, GIN indexes on
`document_file.parsed_markdown`, and reconciling the `simple`-vs-stemmed
mismatch already flagged in FATTO-AAC's `05-data-model.md:233` all belong to
the FATTO-AAC tenant repo — per this repo's own existing convention
(`tf/postgresql.tf`: *"vector and age are left to DB owners (CREATE EXTENSION
in their own DBs)"*). No per-database SQL objects are created by this repo.

## Approach (locked)

Debian apt packages `hunspell-cs` and `hunspell-sk`, installed in the final
stage of `images/cnpg/Dockerfile` alongside the existing
`postgresql-17-pgvector` package. Postgres's `ispell` dictionary template
accepts Hunspell-format affix files directly — no conversion needed, just a
copy/rename into `tsearch_data`. This was chosen over two alternatives:

- Fetching `cs_CZ`/`sk_SK` dictionaries from the LibreOffice dictionaries repo
  at build time (mirrors the existing Apache AGE `git clone` builder pattern) —
  rejected as first choice because it adds an external build-time dependency
  and a version to track, for no benefit unless Debian's packaged dictionaries
  turn out to be stale or low quality. Kept as fallback (see below).
- `unaccent` + `simple` config only, no real stemming — rejected because it
  doesn't satisfy the RFP's "appropriate stemming" requirement (§7.3.2); it's
  a diacritic-folding tokenizer, not a stemmer.

### To verify during implementation (not asserted)

- That `hunspell-cs` and `hunspell-sk` are available in the `bookworm` apt
  repos used by the base image, and that their `.aff`/`.dic` files are
  ISPELL/Hunspell-format-compatible with Postgres's `ispell` template
  out of the box (no encoding/format quirks). If either package is missing or
  the dictionary loads but produces poor stemming, fall back to the
  LibreOffice-dictionaries-repo approach instead.

## Architecture

```
tf-platform (this repo)                      FATTO-AAC tenant repo
────────────────────────                     ─────────────────────
images/cnpg/Dockerfile                       CREATE TEXT SEARCH DICTIONARY
  + hunspell-cs, hunspell-sk (apt)             czech_ispell (template=ispell,
  + copy .aff/.dic → tsearch_data/             dictfile=czech, afffile=czech)
    czech.{affix,dict}                        CREATE TEXT SEARCH CONFIGURATION
    slovak.{affix,dict}                        czech / slovak (mapping words
                                                 to czech_ispell/slovak_ispell,
CNPG cluster (shared-db)                        falling back to simple)
  imageName: new tag                          GIN index on
  → rolling update (replica, switchover)        document_file.parsed_markdown
```

## Implementation

### 1. Image changes (`images/cnpg/Dockerfile`)

In the final stage, extend the existing `apt-get install` line to also pull
`hunspell-cs` and `hunspell-sk`. Add a `RUN` step copying/renaming:

- `/usr/share/hunspell/cs_CZ.aff` → `/usr/share/postgresql/17/tsearch_data/czech.affix`
- `/usr/share/hunspell/cs_CZ.dic` → `/usr/share/postgresql/17/tsearch_data/czech.dict`
- `/usr/share/hunspell/sk_SK.aff` → `/usr/share/postgresql/17/tsearch_data/slovak.affix`
- `/usr/share/hunspell/sk_SK.dic` → `/usr/share/postgresql/17/tsearch_data/slovak.dict`

No new build stage — unlike Apache AGE there's no compilation, just an apt
package and a file copy. Add a comment near the existing "vector and age are
left to DB owners" note in `tf/postgresql.tf` clarifying that czech/slovak
dictionary *files* are now image-wide available, but creating the dictionary/
config objects is left to tenant repos, same as vector/age.

### 2. Local validation (before touching the cluster)

Build the image locally (`docker build images/cnpg`), run it standalone
(no k8s), and manually verify `CREATE TEXT SEARCH DICTIONARY` + `ts_lexize`
for both czech and slovak. This catches bad affix/dict format issues before
they reach CI or the running cluster.

### 3. Rollout mechanics

1. Bump the image tag (next in sequence: `17-bookworm-ext.2`) and trigger
   `.github/workflows/cnpg-image.yml` via `workflow_dispatch` to build and
   push it.
2. Update `variables.tf`'s `cnpg_image` default to the new tag.
3. `terraform apply` updates `kubectl_manifest.cnpg_cluster`'s `imageName`;
   the CNPG operator runs its standard rolling update — replica restarts on
   the new image, then a switchover promotes it and restarts the old primary
   (brief connection blip, no full outage — same risk profile as the prior
   pgvector/AGE image rollout on this cluster; acceptable to run anytime, no
   maintenance window required).

This is a plain image swap: no `shared_preload_libraries` change this time,
so the preload-ordering gate that `cnpg_preload_ready` exists for does not
apply here.

### 4. Verification gate

New `terraform_data.cnpg_dict_ready`, parallel to the existing
`terraform_data.cnpg_preload_ready`: triggered by `var.cnpg_image` changing,
depends on `kubectl_manifest.cnpg_cluster`. It `kubectl exec`s into the
primary pod and runs a throwaway smoke test — create a temporary `czech`/
`slovak` ispell dictionary, run `ts_lexize` against a known word for each,
then drop them — all in one script, leaving no persistent objects behind.
Non-zero exit (missing files, bad affix format, `ts_lexize` returning null or
erroring) fails the `apply`.

## Out of scope

- FATTO-AAC's own `TEXT SEARCH CONFIGURATION` objects, GIN indexes on
  `document_file.parsed_markdown`, and reconciling the `simple`-vs-stemmed
  mismatch in `05-data-model.md` — belong to the tenant repo.
- No changes to `shared_preload_libraries`, `pg_hba`, or the existing
  keycloak/opal/postgres databases.
- English — already available via Postgres core's `pg_catalog.english`
  config, no work needed.
