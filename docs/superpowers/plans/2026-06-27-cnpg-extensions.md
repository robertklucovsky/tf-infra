# CNPG pgvector + Apache AGE Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the shared CloudNativePG operand image with pgvector + Apache AGE, add `age, pg_stat_statements` to `shared_preload_libraries`, and create `pg_stat_statements` in the platform `postgres` DB.

**Architecture:** A multi-stage Dockerfile (`images/cnpg/`) builds a custom operand image `FROM ghcr.io/cloudnative-pg/postgresql:17-bookworm` — pgvector via the PGDG apt package, Apache AGE compiled from source. A GitHub Actions workflow builds it (linux/amd64) and pushes to `ghcr.io/robertklucovsky/cnpg-postgresql`. Terraform points the `shared-db` cluster at the new image, sets the preload libraries, waits for the rolling restart to activate them, then creates `pg_stat_statements`.

**Tech Stack:** Docker (multi-stage, buildx), GitHub Actions, Terraform (`cyrilgdn/postgresql ~> 1.25`, `alekc/kubectl ~> 2.1`, CloudNativePG operator), PostgreSQL 17.

## Global Constraints

- PostgreSQL major version is **17**. Apache AGE branch: **`release/PG17/1.7.0`**. pgvector: PGDG package **`postgresql-17-pgvector`**.
- Build target architecture: **`linux/amd64` only** (single node `cwwk`, Ubuntu 24.04, amd64).
- Image registry: **`ghcr.io/robertklucovsky/cnpg-postgresql`**. Image must be **public** so the node pulls anonymously on cold bootstrap (same as the base image today).
- Image tag **must** keep the `17` prefix and **must never be `latest`** — the CNPG operator parses the PG major version from the tag. Tag convention: `17-bookworm-ext.<N>`.
- `shared-db` is cold-bootstrap infra: the custom image must exist in ghcr.io **before** Terraform references it.
- Extension scope: platform creates **`pg_stat_statements` only** (in `postgres`). `vector` and `age` are left to DB owners.
- The `postgresql` provider connects to `database = "postgres"` (`dev/main.tf:65-72`).
- All `kubectl` invocations from Terraform `local-exec` must pass `--kubeconfig ${var.kubeconfig_path} --context ${var.kubeconfig_context}` to match the provider config.

---

## File Structure

- `images/cnpg/Dockerfile` — multi-stage build: AGE compiled in builder stage, pgvector via apt in final stage, artifacts copied in. **New.**
- `images/cnpg/smoke-test.sh` — local verification that both extensions' `.so`/control/sql files are present in the built image. **New.**
- `.github/workflows/cnpg-image.yml` — build & push to ghcr.io on `cnpg-image-*` tag or manual dispatch. **New.**
- `dev/variables.tf` — add `cnpg_image`, remove `cnpg_pg_version`. **Modify.**
- `dev/cnpg.tf` — `imageName` → `var.cnpg_image`; add `shared_preload_libraries`. **Modify.**
- `dev/postgresql.tf` — add `cnpg_preload_ready` gate + `pg_stat_statements` extension. **Modify.**

---

## Task 1: Custom operand image (Dockerfile + smoke test)

**Files:**
- Create: `images/cnpg/Dockerfile`
- Create: `images/cnpg/smoke-test.sh`

**Interfaces:**
- Produces: a buildable image containing `vector.so` + `vector.control` + `vector--*.sql` and `age.so` + `age.control` + `age--*.sql` at the PGDG paths (`/usr/lib/postgresql/17/lib`, `/usr/share/postgresql/17/extension`). Consumed by Task 2 (CI build) and Task 3 (`var.cnpg_image`).

- [ ] **Step 1: Write the Dockerfile**

Create `images/cnpg/Dockerfile`:

```dockerfile
# Custom CloudNativePG operand image: stock PG17 + pgvector + Apache AGE.
# Keep the "17" tag prefix when publishing — the CNPG operator parses the
# PG major version from the image tag.
ARG BASE=ghcr.io/cloudnative-pg/postgresql:17-bookworm

# ---- builder: compile Apache AGE from source (no apt package exists) --------
FROM ${BASE} AS builder
USER root
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      build-essential git flex bison postgresql-server-dev-17; \
    rm -rf /var/lib/apt/lists/*
ARG AGE_REF=release/PG17/1.7.0
RUN set -eux; \
    git clone --depth 1 --branch "${AGE_REF}" https://github.com/apache/age.git /tmp/age; \
    cd /tmp/age; \
    make PG_CONFIG=/usr/lib/postgresql/17/bin/pg_config; \
    make PG_CONFIG=/usr/lib/postgresql/17/bin/pg_config install

# ---- final: stock base + pgvector (apt) + AGE artifacts (copied) ------------
FROM ${BASE}
USER root
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends postgresql-17-pgvector; \
    rm -rf /var/lib/apt/lists/*
COPY --from=builder /usr/lib/postgresql/17/lib/age.so \
                    /usr/lib/postgresql/17/lib/age.so
COPY --from=builder /usr/share/postgresql/17/extension/age.control \
                    /usr/share/postgresql/17/extension/age.control
COPY --from=builder /usr/share/postgresql/17/extension/age--*.sql \
                    /usr/share/postgresql/17/extension/
# Restore the non-root operand user used by the base image.
USER 26
```

- [ ] **Step 2: Write the smoke-test script**

Create `images/cnpg/smoke-test.sh`:

```bash
#!/usr/bin/env bash
# Verify both extensions are installed in a built image.
# Usage: ./smoke-test.sh <image-ref>
set -euo pipefail
IMG="${1:?usage: smoke-test.sh <image-ref>}"

docker run --rm --entrypoint bash "$IMG" -lc '
  set -eu
  LIBDIR=$(pg_config --pkglibdir)
  EXTDIR=$(pg_config --sharedir)/extension
  for f in "$LIBDIR/vector.so" "$LIBDIR/age.so" \
           "$EXTDIR/vector.control" "$EXTDIR/age.control"; do
    test -f "$f" || { echo "MISSING: $f"; exit 1; }
  done
  echo "pgvector sql: $(ls "$EXTDIR"/vector--*.sql | head -1)"
  echo "age sql:      $(ls "$EXTDIR"/age--*.sql | head -1)"
  echo "SMOKE OK"
'
```

- [ ] **Step 3: Make the script executable**

Run: `chmod +x images/cnpg/smoke-test.sh`
Expected: no output, exit 0.

- [ ] **Step 4: Build the image locally**

Run: `docker build --platform linux/amd64 -t cnpg-postgresql:test images/cnpg`
Expected: build succeeds. If `postgresql-17-pgvector` is not found in apt, fall back to compiling pgvector from source in the builder stage (`git clone --branch v0.8.0 https://github.com/pgvector/pgvector.git`, `make && make install`, then `COPY` `vector.so`/`vector.control`/`vector--*.sql` like AGE). If the AGE `make` fails on a missing path, run `docker run --rm --entrypoint bash <base> -lc 'pg_config --pkglibdir; pg_config --sharedir'` to confirm the real paths and adjust the `COPY` lines.

- [ ] **Step 5: Run the smoke test to verify it passes**

Run: `images/cnpg/smoke-test.sh cnpg-postgresql:test`
Expected: prints the resolved `vector--*.sql` and `age--*.sql` filenames and `SMOKE OK`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add images/cnpg/Dockerfile images/cnpg/smoke-test.sh
git commit -m "feat(cnpg): custom operand image with pgvector + Apache AGE

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: GitHub Actions build & publish workflow

**Files:**
- Create: `.github/workflows/cnpg-image.yml`

**Interfaces:**
- Consumes: `images/cnpg/Dockerfile` from Task 1.
- Produces: published image `ghcr.io/robertklucovsky/cnpg-postgresql:<tag>` (public), referenced by Task 3.

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/cnpg-image.yml`:

```yaml
name: Build CNPG operand image

on:
  push:
    tags:
      - 'cnpg-image-*'
  workflow_dispatch:
    inputs:
      tag:
        description: 'Image tag (must start with 17, never latest)'
        required: true
        default: '17-bookworm-ext.1'

env:
  IMAGE: ghcr.io/robertklucovsky/cnpg-postgresql

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - name: Resolve image tag
        id: tag
        run: |
          if [ "${{ github.event_name }}" = "workflow_dispatch" ]; then
            TAG="${{ inputs.tag }}"
          else
            TAG="${GITHUB_REF_NAME#cnpg-image-}"
          fi
          case "$TAG" in
            17*) : ;;
            *) echo "Tag must start with 17: $TAG"; exit 1 ;;
          esac
          [ "$TAG" = "latest" ] && { echo "tag must not be latest"; exit 1; }
          echo "tag=$TAG" >> "$GITHUB_OUTPUT"

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/build-push-action@v6
        with:
          context: images/cnpg
          platforms: linux/amd64
          push: true
          tags: ${{ env.IMAGE }}:${{ steps.tag.outputs.tag }}
```

- [ ] **Step 2: Commit and push the workflow**

```bash
git add .github/workflows/cnpg-image.yml
git commit -m "ci(cnpg): build & publish custom operand image to ghcr.io

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push -u origin feat/cnpg-extensions
```

- [ ] **Step 3: Trigger the build**

Tag and push to trigger the workflow:

```bash
git tag cnpg-image-17-bookworm-ext.1
git push origin cnpg-image-17-bookworm-ext.1
```

Run: `gh run watch $(gh run list --workflow=cnpg-image.yml -L1 --json databaseId -q '.[0].databaseId')`
Expected: workflow completes successfully.

- [ ] **Step 4: Make the package public**

The package is created private by default. Make it public so the cluster node pulls anonymously:

Run: `gh api -X PATCH /user/packages/container/cnpg-postgresql/visibility -f visibility=public` (or set it in the GitHub UI: Packages → cnpg-postgresql → Package settings → Change visibility → Public).

Verify the manifest is pullable without auth:
Run: `docker pull ghcr.io/robertklucovsky/cnpg-postgresql:17-bookworm-ext.1`
Expected: pull succeeds.

- [ ] **Step 5: Smoke-test the published image**

Run: `images/cnpg/smoke-test.sh ghcr.io/robertklucovsky/cnpg-postgresql:17-bookworm-ext.1`
Expected: `SMOKE OK`.

---

## Task 3: Terraform wiring (image, preload libs, extension)

**Files:**
- Modify: `dev/variables.tf` (add `cnpg_image`; remove `cnpg_pg_version`)
- Modify: `dev/cnpg.tf:73` (imageName) and `dev/cnpg.tf:95-99` (parameters)
- Modify: `dev/postgresql.tf` (add `cnpg_preload_ready` + `pg_stat_statements`)

**Interfaces:**
- Consumes: published image from Task 2 via `var.cnpg_image`.
- Produces: `terraform_data.cnpg_preload_ready` (gate) and `postgresql_extension.pg_stat_statements` (in `postgres`).

- [ ] **Step 1: Add the `cnpg_image` variable**

In `dev/variables.tf`, replace the `cnpg_pg_version` block (lines 94-98):

```hcl
variable "cnpg_pg_version" {
  description = "PostgreSQL version for CNPG cluster"
  type        = string
  default     = "17-bookworm"
}
```

with:

```hcl
variable "cnpg_image" {
  description = "CNPG operand image — custom build with pgvector + Apache AGE (tag must keep the 17 prefix; never latest)"
  type        = string
  default     = "ghcr.io/robertklucovsky/cnpg-postgresql:17-bookworm-ext.1"
}
```

- [ ] **Step 2: Remove `cnpg_pg_version` from tfvars if present**

`terraform.tfvars` is gitignored — check it manually:
Run: `grep -n cnpg_pg_version dev/terraform.tfvars || echo "not set — ok"`
If present, delete that line (an undeclared variable would otherwise emit a warning on every apply).

- [ ] **Step 3: Point the cluster at the custom image**

In `dev/cnpg.tf`, change line 73 from:

```
      imageName: ghcr.io/cloudnative-pg/postgresql:${var.cnpg_pg_version}
```

to:

```
      imageName: ${var.cnpg_image}
```

- [ ] **Step 4: Add the preload libraries**

In `dev/cnpg.tf`, in the `postgresql.parameters` block (lines 96-99), add the `shared_preload_libraries` line:

```
      postgresql:
        parameters:
          max_connections: "200"
          shared_buffers: "256MB"
          log_statement: "ddl"
          shared_preload_libraries: "age, pg_stat_statements"
```

- [ ] **Step 5: Add the preload-readiness gate and extension**

In `dev/postgresql.tf`, append:

```hcl
# -----------------------------------------------------------------------------
# PRELOAD READINESS GATE
# shared_preload_libraries changes require a restart; the CNPG operator does a
# rolling restart that terraform_data.cnpg_ready (a TCP check) may pass before
# the new library is active. Wait until the primary actually reports
# pg_stat_statements in shared_preload_libraries before creating the extension.
# -----------------------------------------------------------------------------

resource "terraform_data" "cnpg_preload_ready" {
  depends_on = [terraform_data.cnpg_ready, kubectl_manifest.cnpg_cluster]

  # Re-run when the operand image changes (a rollout that may toggle preload libs).
  triggers_replace = [var.cnpg_image]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      KC="--kubeconfig ${var.kubeconfig_path} --context ${var.kubeconfig_context}"
      echo "Waiting for pg_stat_statements in shared_preload_libraries..."
      for i in $(seq 1 60); do
        POD=$(kubectl $KC get pods -n cnpg-system \
          -l cnpg.io/cluster=shared-db,role=primary \
          -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
        if [ -n "$POD" ]; then
          VAL=$(kubectl $KC exec -n cnpg-system "$POD" -c postgres -- \
            psql -U postgres -tAc "show shared_preload_libraries" 2>/dev/null || true)
          case "$VAL" in
            *pg_stat_statements*) echo "preload ready: $VAL"; exit 0 ;;
          esac
        fi
        echo "Attempt $i/60 — not ready (got: $VAL), waiting 5s..."
        sleep 5
      done
      echo "ERROR: pg_stat_statements not active after 300s"
      exit 1
    EOT
  }
}

# -----------------------------------------------------------------------------
# pg_stat_statements — cluster-wide query stats (platform-owned).
# vector and age are left to DB owners (CREATE EXTENSION in their own DBs).
# -----------------------------------------------------------------------------

resource "postgresql_extension" "pg_stat_statements" {
  name     = "pg_stat_statements"
  database = "postgres"

  depends_on = [terraform_data.cnpg_preload_ready]
}
```

- [ ] **Step 6: Format and validate**

Run: `cd dev && terraform fmt && terraform validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 7: Commit**

```bash
git add dev/variables.tf dev/cnpg.tf dev/postgresql.tf
git commit -m "feat(cnpg): use custom image, set preload libs, add pg_stat_statements

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Apply and verify against the live cluster

**Files:** none (apply + verification only)

**Interfaces:**
- Consumes: everything from Tasks 1-3.

- [ ] **Step 1: Review the plan**

Run: `cd dev && terraform plan` (with `PG_CONN_STR` and `terraform.tfvars` in place per README)
Expected: shows the `shared-db` Cluster manifest updating `imageName` + `shared_preload_libraries`, replacement of `terraform_data.cnpg_preload_ready`, and creation of `postgresql_extension.pg_stat_statements`. No unexpected destroys.

- [ ] **Step 2: Apply**

Run: `cd dev && terraform apply`
Expected: apply completes; `cnpg_preload_ready` provisioner prints `preload ready: ...pg_stat_statements...`.

- [ ] **Step 3: Verify the rollout reached the new image**

Run:
```bash
kubectl --context k8s get pods -n cnpg-system -l cnpg.io/cluster=shared-db \
  -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.spec.containers[0].image}{"\n"}{end}'
```
Expected: all pods Running on `ghcr.io/robertklucovsky/cnpg-postgresql:17-bookworm-ext.1`. (If the operator rejected the tag, the cluster events will show a version-parse error — fall back to a `17.<minor>-ext<N>` tag: rebuild via Task 2 with the new tag and update `var.cnpg_image`.)

- [ ] **Step 4: Verify preload libraries and pg_stat_statements**

Run:
```bash
POD=$(kubectl --context k8s get pods -n cnpg-system -l cnpg.io/cluster=shared-db,role=primary -o jsonpath='{.items[0].metadata.name}')
kubectl --context k8s exec -n cnpg-system "$POD" -c postgres -- psql -U postgres -c "show shared_preload_libraries;"
kubectl --context k8s exec -n cnpg-system "$POD" -c postgres -- psql -U postgres -c "select extname from pg_extension where extname='pg_stat_statements';"
```
Expected: `shared_preload_libraries` contains `age, pg_stat_statements`; the second query returns one row `pg_stat_statements`.

- [ ] **Step 5: Verify vector + age are installable by DB owners**

Run:
```bash
kubectl --context k8s exec -n cnpg-system "$POD" -c postgres -- psql -U postgres -c "create database ext_smoke;"
kubectl --context k8s exec -n cnpg-system "$POD" -c postgres -- psql -U postgres -d ext_smoke -c "create extension vector; create extension age; load 'age';"
kubectl --context k8s exec -n cnpg-system "$POD" -c postgres -- psql -U postgres -c "drop database ext_smoke;"
```
Expected: `CREATE EXTENSION` (x2) and `LOAD` succeed; database dropped cleanly.

- [ ] **Step 6: Final commit (if any cleanup/tweaks were needed)**

```bash
git add -A
git commit -m "chore(cnpg): finalize extension rollout

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" || echo "nothing to commit"
```

---

## Notes & open items (resolve during execution)

- **Operator tag parsing:** verified in Task 4 Step 3. Documented fallback: `17.<minor>-ext<N>`.
- **pgvector package availability:** Task 1 Step 4 has the source-build fallback if `postgresql-17-pgvector` is missing from PGDG at build time.
- **Package visibility:** Task 2 Step 4 makes it public (required for cold-bootstrap anonymous pull). If it must stay private, add an `imagePullSecret` to the cluster spec instead — out of scope unless required.
- **PGDG paths:** the `COPY` lines assume `/usr/lib/postgresql/17/{lib}` and `/usr/share/postgresql/17/extension`. Task 1 Step 4 confirms via `pg_config` if the build fails.
