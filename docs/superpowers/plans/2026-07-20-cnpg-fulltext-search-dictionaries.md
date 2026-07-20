# CNPG Czech/Slovak Full-Text Search Dictionaries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bake Czech/Slovak Hunspell dictionary files into the shared CNPG PostgreSQL image and roll them out to the running cluster, so tenant repos (e.g. FATTO-AAC) can build `ispell`-based `czech`/`slovak` text search configurations.

**Architecture:** Add `hunspell-cs`/`hunspell-sk` (apt) to the final stage of `images/cnpg/Dockerfile`, copy their `.aff`/`.dic` files into Postgres's `tsearch_data` directory as `.affix`/`.dict` (Postgres's `ispell` template reads Hunspell format natively). Roll the new image tag into the already-running CNPG cluster via the existing Terraform-managed `imageName` field, gated by a new automated smoke-test resource (`terraform_data.cnpg_dict_ready`) that proves the dictionaries actually load before the apply is considered successful.

**Tech Stack:** Docker (CNPG operand image), Debian `bookworm` apt packages, PostgreSQL `ispell` text search template, Terraform (`cyrilgdn/postgresql`, `kubectl_manifest`, `terraform_data`/`local-exec`), GitHub Actions (`workflow_dispatch`), `gh` CLI, `kubectl`.

## Global Constraints

- Image tag must keep the `17` prefix and must never be `latest` (enforced by `.github/workflows/cnpg-image.yml`'s tag check and documented in `variables.tf`'s `cnpg_image` description).
- No changes to `shared_preload_libraries`, `pg_hba`, or the existing `keycloak`/`opal`/`postgres` databases.
- No per-database `TEXT SEARCH DICTIONARY`/`CONFIGURATION` objects are created by this repo — that is left to tenant repos (e.g. FATTO-AAC), mirroring the existing "vector and age are left to DB owners" convention in `tf/postgresql.tf`.
- The verification gate must leave no persistent SQL objects behind (create-test-drop only).
- English needs no work — `pg_catalog.english` ships in Postgres core.

Every task's requirements implicitly include the constraints above.

---

### Task 1: Add Czech/Slovak dictionary files to the CNPG image

**Files:**
- Modify: `images/cnpg/Dockerfile:24-27` (apt-get install line), append new `RUN` step after line 33

**Interfaces:**
- Produces: `/usr/share/postgresql/17/tsearch_data/czech.affix`, `czech.dict`, `slovak.affix`, `slovak.dict` inside the built image — consumed by Task 2's verification gate (must match these exact filenames, since they're referenced via `dictfile`/`afffile` in `CREATE TEXT SEARCH DICTIONARY`) and, later, by tenant repos.

- [ ] **Step 1: Modify the apt-get install line to add hunspell-cs and hunspell-sk**

In `images/cnpg/Dockerfile`, replace:

```dockerfile
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends postgresql-17-pgvector; \
    rm -rf /var/lib/apt/lists/*
```

with:

```dockerfile
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      postgresql-17-pgvector hunspell-cs hunspell-sk; \
    rm -rf /var/lib/apt/lists/*
```

- [ ] **Step 2: Add a RUN step copying the dictionary files into tsearch_data**

Immediately after the three `COPY --from=builder` lines (age artifacts) and before the trailing `USER 26` comment/line, insert:

```dockerfile
# Czech/Slovak full-text search: Postgres's ispell dictionary template reads
# Hunspell-format affix files directly, so no conversion — just place them
# under tsearch_data with the .affix/.dict extensions it expects. Creating
# the actual TEXT SEARCH DICTIONARY/CONFIGURATION objects is left to DB
# owners, same as vector and age (see tf/postgresql.tf).
RUN set -eux; \
    cp /usr/share/hunspell/cs_CZ.aff /usr/share/postgresql/17/tsearch_data/czech.affix; \
    cp /usr/share/hunspell/cs_CZ.dic /usr/share/postgresql/17/tsearch_data/czech.dict; \
    cp /usr/share/hunspell/sk_SK.aff /usr/share/postgresql/17/tsearch_data/slovak.affix; \
    cp /usr/share/hunspell/sk_SK.dic /usr/share/postgresql/17/tsearch_data/slovak.dict
```

The full final stage should now read (for reference, do not diverge):

```dockerfile
# ---- final: stock base + pgvector (apt) + AGE artifacts (copied) ------------
FROM ${BASE}
USER root
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      postgresql-17-pgvector hunspell-cs hunspell-sk; \
    rm -rf /var/lib/apt/lists/*
COPY --from=builder /usr/lib/postgresql/17/lib/age.so \
                    /usr/lib/postgresql/17/lib/age.so
COPY --from=builder /usr/share/postgresql/17/extension/age.control \
                    /usr/share/postgresql/17/extension/age.control
COPY --from=builder /usr/share/postgresql/17/extension/age--*.sql \
                    /usr/share/postgresql/17/extension/
# Czech/Slovak full-text search: Postgres's ispell dictionary template reads
# Hunspell-format affix files directly, so no conversion — just place them
# under tsearch_data with the .affix/.dict extensions it expects. Creating
# the actual TEXT SEARCH DICTIONARY/CONFIGURATION objects is left to DB
# owners, same as vector and age (see tf/postgresql.tf).
RUN set -eux; \
    cp /usr/share/hunspell/cs_CZ.aff /usr/share/postgresql/17/tsearch_data/czech.affix; \
    cp /usr/share/hunspell/cs_CZ.dic /usr/share/postgresql/17/tsearch_data/czech.dict; \
    cp /usr/share/hunspell/sk_SK.aff /usr/share/postgresql/17/tsearch_data/slovak.affix; \
    cp /usr/share/hunspell/sk_SK.dic /usr/share/postgresql/17/tsearch_data/slovak.dict
# Restore the non-root operand user used by the base image.
USER 26
```

- [ ] **Step 3: Build the image locally**

Run: `docker build -t cnpg-dict-test images/cnpg`
Expected: build succeeds; if `hunspell-cs`/`hunspell-sk` aren't found in the `bookworm` apt repos, this step fails here with an apt "Unable to locate package" error — if so, stop and fall back to the LibreOffice-dictionaries-repo approach noted in the spec's "to verify" section instead of proceeding.

- [ ] **Step 4: Run the image standalone and verify the dictionaries load and stem correctly**

```bash
docker run --rm -d --name cnpg-dict-test -e POSTGRES_PASSWORD=test cnpg-dict-test
until docker exec cnpg-dict-test pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done

docker exec cnpg-dict-test psql -U postgres -v ON_ERROR_STOP=1 -c "
DROP TEXT SEARCH DICTIONARY IF EXISTS tmp_check_czech;
DROP TEXT SEARCH DICTIONARY IF EXISTS tmp_check_slovak;
CREATE TEXT SEARCH DICTIONARY tmp_check_czech (template = ispell, dictfile = czech, afffile = czech);
CREATE TEXT SEARCH DICTIONARY tmp_check_slovak (template = ispell, dictfile = slovak, afffile = slovak);
SELECT ts_lexize('tmp_check_czech', 'domy') AS czech_result, ts_lexize('tmp_check_slovak', 'domy') AS slovak_result;
DROP TEXT SEARCH DICTIONARY tmp_check_czech;
DROP TEXT SEARCH DICTIONARY tmp_check_slovak;
"

docker rm -f cnpg-dict-test
```

Expected: the `SELECT` prints two non-null array values (e.g. `{dům}`-shaped results), proving both dictionaries load and actually stem the test word. If either column is `NULL` or any statement errors (missing file, bad affix format), the dictionary files are broken — fix before continuing to Task 2.

- [ ] **Step 5: Commit**

```bash
git add images/cnpg/Dockerfile
git commit -m "feat(cnpg): add czech/slovak hunspell dictionaries to operand image"
```

---

### Task 2: Add the Terraform verification gate and ownership documentation

**Files:**
- Modify: `tf/postgresql.tf` (append after line 146, the closing brace of `resource "postgresql_extension" "pg_stat_statements"`)

**Interfaces:**
- Consumes: `var.cnpg_image`, `var.kubeconfig_path`, `var.kubeconfig_context` (existing variables, see `tf/variables.tf`); `terraform_data.cnpg_ready`, `kubectl_manifest.cnpg_cluster` (existing resources, see `tf/cnpg.tf`); the `czech`/`slovak` `.affix`/`.dict` filenames produced by Task 1.
- Produces: `terraform_data.cnpg_dict_ready` — a resource other future tenant-facing Terraform work could `depends_on`, though nothing in this repo needs to yet.

- [ ] **Step 1: Append the new resource block to `tf/postgresql.tf`**

```hcl

# -----------------------------------------------------------------------------
# CZECH/SLOVAK FULL-TEXT SEARCH DICTIONARIES
# Dictionary *files* (hunspell-cs/hunspell-sk, baked into the CNPG image at
# /usr/share/postgresql/17/tsearch_data/{czech,slovak}.{affix,dict}) are
# available image-wide. Creating the TEXT SEARCH DICTIONARY/CONFIGURATION
# objects and GIN indexes is left to DB owners in their own databases —
# same pattern as vector and age above.
#
# This gate proves the files loaded correctly after an image rollout by
# creating and immediately dropping throwaway dictionary objects; it leaves
# no persistent SQL objects behind.
# -----------------------------------------------------------------------------

resource "terraform_data" "cnpg_dict_ready" {
  depends_on = [terraform_data.cnpg_ready, kubectl_manifest.cnpg_cluster]

  # Re-run when the operand image changes (a rollout that may add/replace
  # the czech/slovak dictionary files).
  triggers_replace = [var.cnpg_image]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      KCFG="${var.kubeconfig_path}"
      case "$KCFG" in
        "~/"*) KCFG="$HOME/$${KCFG#\~/}" ;;
        "~")   KCFG="$HOME" ;;
      esac
      KC="--kubeconfig $KCFG --context ${var.kubeconfig_context}"
      echo "Waiting for czech/slovak tsearch_data dictionaries to be usable..."
      for i in $(seq 1 60); do
        POD=$(kubectl $KC get pods -n cnpg-system \
          -l cnpg.io/cluster=shared-db,role=primary \
          -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
        if [ -n "$POD" ]; then
          if kubectl $KC exec -n cnpg-system "$POD" -c postgres -i -- \
            psql -U postgres -v ON_ERROR_STOP=1 <<'SQL' >/tmp/cnpg_dict_check.out 2>&1
DROP TEXT SEARCH DICTIONARY IF EXISTS tmp_check_czech;
DROP TEXT SEARCH DICTIONARY IF EXISTS tmp_check_slovak;
CREATE TEXT SEARCH DICTIONARY tmp_check_czech (template = ispell, dictfile = czech, afffile = czech);
CREATE TEXT SEARCH DICTIONARY tmp_check_slovak (template = ispell, dictfile = slovak, afffile = slovak);
DO $$
BEGIN
  IF ts_lexize('tmp_check_czech', 'domy') IS NULL THEN
    RAISE EXCEPTION 'czech dictionary failed to lexize test word';
  END IF;
  IF ts_lexize('tmp_check_slovak', 'domy') IS NULL THEN
    RAISE EXCEPTION 'slovak dictionary failed to lexize test word';
  END IF;
END
$$;
DROP TEXT SEARCH DICTIONARY tmp_check_czech;
DROP TEXT SEARCH DICTIONARY tmp_check_slovak;
SQL
          then
            echo "czech/slovak dictionaries OK"
            exit 0
          fi
        fi
        echo "Attempt $i/60 — not ready (see /tmp/cnpg_dict_check.out), waiting 5s..."
        sleep 5
      done
      echo "ERROR: czech/slovak dictionaries not usable after 300s"
      cat /tmp/cnpg_dict_check.out 2>/dev/null || true
      exit 1
    EOT
  }
}
```

- [ ] **Step 2: Format and statically validate**

Run: `cd tf && terraform fmt -check -diff`
Expected: no diff (if there is one, run `terraform fmt` to apply it, then re-check).

Run: `cd tf && terraform validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Confirm the plan targets the new resource without touching anything else**

Run: `cd tf && terraform plan -target=terraform_data.cnpg_dict_ready`
Expected: plan shows `terraform_data.cnpg_dict_ready` will be created (its `triggers_replace` value equals the *current* `var.cnpg_image`, since the image hasn't changed yet — Task 3 changes the tag and forces this to run for real). No other resources should appear in this targeted plan.

- [ ] **Step 4: Commit**

```bash
git add tf/postgresql.tf
git commit -m "feat(cnpg): add czech/slovak dictionary readiness gate"
```

---

### Task 3: Roll the new image out to the running cluster

**Files:**
- Modify: `tf/variables.tf:97` (`cnpg_image` default)

**Interfaces:**
- Consumes: the image built in Task 1 (Dockerfile) and the gate defined in Task 2 (`terraform_data.cnpg_dict_ready`).
- Produces: the running `shared-db` CNPG cluster now serves Postgres instances with the czech/slovak dictionary files present.

> **Production impact:** this task pushes a new image to a public registry (`ghcr.io/robertklucovsky/cnpg-postgresql`) and applies a change that makes the CNPG operator perform a rolling update of the live cluster (replica restarts on the new image, then a switchover promotes it and restarts the old primary — a brief connection blip for Keycloak and anything else on this cluster). Confirm with whoever owns this environment before running steps 2 and 4 if that hasn't already happened.

- [ ] **Step 1: Determine the next image tag**

Current tag (per `tf/variables.tf:97`): `17-bookworm-ext.1`. Next tag: `17-bookworm-ext.2`.

- [ ] **Step 2: Build and push the image via the existing GitHub Actions workflow**

Run: `gh workflow run cnpg-image.yml -f tag=17-bookworm-ext.2`

Then watch it: `gh run watch $(gh run list --workflow=cnpg-image.yml --limit=1 --json databaseId --jq '.[0].databaseId')`

Expected: workflow succeeds; `ghcr.io/robertklucovsky/cnpg-postgresql:17-bookworm-ext.2` now exists.

- [ ] **Step 3: Bump the image tag in Terraform**

In `tf/variables.tf`, change:

```hcl
variable "cnpg_image" {
  description = "CNPG operand image — custom build with pgvector + Apache AGE (tag must keep the 17 prefix; never latest)"
  type        = string
  default     = "ghcr.io/robertklucovsky/cnpg-postgresql:17-bookworm-ext.1"
}
```

to:

```hcl
variable "cnpg_image" {
  description = "CNPG operand image — custom build with pgvector + Apache AGE + czech/slovak fulltext dictionaries (tag must keep the 17 prefix; never latest)"
  type        = string
  default     = "ghcr.io/robertklucovsky/cnpg-postgresql:17-bookworm-ext.2"
}
```

- [ ] **Step 4: Apply**

Run: `cd tf && terraform plan` — review that only `kubectl_manifest.cnpg_cluster` (imageName change), `terraform_data.cnpg_dict_ready` (replacement, due to `triggers_replace`), and any resources that legitimately depend on the image tag are affected. Nothing under Keycloak/OPAL/pg_stat_statements config should change.

Run: `cd tf && terraform apply`
Expected: `kubectl_manifest.cnpg_cluster` updates, CNPG performs its rolling update, then `terraform_data.cnpg_dict_ready`'s `local-exec` runs and prints `czech/slovak dictionaries OK` before `apply` reports success. If it instead prints `ERROR: czech/slovak dictionaries not usable after 300s`, the apply fails — check `/tmp/cnpg_dict_check.out` on the machine running Terraform for the underlying psql error.

- [ ] **Step 5: Manual double-check against the live primary**

```bash
KC="--kubeconfig <your kubeconfig> --context <your context>"
POD=$(kubectl $KC get pods -n cnpg-system -l cnpg.io/cluster=shared-db,role=primary -o jsonpath='{.items[0].metadata.name}')
kubectl $KC exec -n cnpg-system "$POD" -c postgres -- ls /usr/share/postgresql/17/tsearch_data/ | grep -E 'czech|slovak'
```

Expected: `czech.affix`, `czech.dict`, `slovak.affix`, `slovak.dict` all listed.

- [ ] **Step 6: Commit**

```bash
git add tf/variables.tf
git commit -m "chore(cnpg): bump operand image to 17-bookworm-ext.2 (czech/slovak dictionaries)"
```
