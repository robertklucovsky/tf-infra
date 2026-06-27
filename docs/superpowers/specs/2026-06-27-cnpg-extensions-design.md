# Custom CNPG image with pgvector + Apache AGE

**Date:** 2026-06-27
**Status:** Approved (design)

## Problem

The shared `shared-db` CloudNativePG cluster (`dev/cnpg.tf`) runs the stock operand
image `ghcr.io/cloudnative-pg/postgresql:17-bookworm`, which ships none of the
extensions we need. Consumers that run `CREATE EXTENSION vector` / `CREATE
EXTENSION age` fail because the binaries are absent, and there is no
`pg_stat_statements` for query observability. We need to extend the operand image
with **pgvector** and **Apache AGE**, and add `age, pg_stat_statements` to
`shared_preload_libraries`.

## Constraints & context

- Cluster is pinned to **PostgreSQL 17** (`cnpg_pg_version = "17-bookworm"`).
  Both pgvector and Apache AGE support PG 17 (AGE via its `release/PG17/1.7.0`
  branch).
- `shared-db` is **cold-bootstrap infrastructure** — applied first, before the
  in-cluster Zot registry / MinIO exist. The custom image must therefore live in
  an externally reachable registry (ghcr.io), not in-cluster Zot.
- This repo is **pure Terraform, applied from a workstation**. ARC runner scale
  sets are tenant-owned, so there are **no platform-owned CI runners**.
- Repo principle: tenants own their per-service databases and the extensions
  within them. Platform owns cluster-level concerns.
- Cluster is a **single amd64 node** (`cwwk`, Ubuntu 24.04). Build target is
  `linux/amd64` only.
- CloudNativePG (and its docs) require the operand image tag to keep the PG major
  version prefix and never be `latest` — the operator parses the major version
  from the tag.
- Image Volume extensions (the modern CNPG approach) are **not** viable here: they
  require CNPG 1.29+/PG18 + the K8s ImageVolume feature gate, and AGE is not in
  the official extension catalog. A custom operand image is the correct approach.

## Decisions (locked during brainstorming)

1. **Build & host:** custom image built by **GitHub Actions** (GitHub-hosted
   runners) and pushed to **`ghcr.io/robertklucovsky/cnpg-postgresql`**.
2. **Source location:** Dockerfile and workflow live **in this repo**
   (`images/cnpg/` + `.github/workflows/`), co-located with the cluster
   definition so version bumps land in one PR.
3. **Extension scope:** platform runs `CREATE EXTENSION pg_stat_statements` only
   (in the `postgres` DB — it is a cluster-wide monitoring concern tied to the
   preload lib). `vector` and `age` stay **owner-created** by whoever owns each
   database (e.g. tenant repos).

## Architecture

```
images/cnpg/Dockerfile  --build-->  ghcr.io/robertklucovsky/cnpg-postgresql:17-bookworm-ext.N
        ^                                          |
        | GitHub Actions (.github/workflows/cnpg-image.yml)
        |                                          v
dev/cnpg.tf  --imageName via var.cnpg_image-->  shared-db Cluster (rolling restart)
        |
        +-- postgresql.parameters.shared_preload_libraries = "age, pg_stat_statements"
        +-- postgresql_extension.pg_stat_statements  (postgres DB)
```

## Components

### 1. `images/cnpg/Dockerfile` (multi-stage)

- **Builder stage** `FROM ghcr.io/cloudnative-pg/postgresql:17-bookworm` as
  `USER root`:
  - Install build deps: `postgresql-server-dev-17`, `build-essential`, `git`,
    `flex`, `bison` (and any AGE-required headers).
  - `git clone --branch ${AGE_REF} https://github.com/apache/age.git`, then
    `make PG_CONFIG=$(which pg_config) && make install` to produce `age.so`,
    `age.control`, `age--*.sql`.
- **Final stage** `FROM ghcr.io/cloudnative-pg/postgresql:17-bookworm`:
  - As root: `apt-get update && apt-get install -y --no-install-recommends
    postgresql-17-pgvector` (packaged in the PGDG repo already present in the
    image), then `rm -rf /var/lib/apt/lists/*`.
  - `COPY --from=builder` the AGE artifacts into the lib dir
    (`$(pg_config --pkglibdir)`) and extension dir
    (`$(pg_config --sharedir)/extension`).
  - Restore the original non-root user (`USER 26`).
- **Build args (pinned):** `AGE_REF=release/PG17/1.7.0`; pgvector version is
  pinned by the PGDG package available for PG17 at build time (record the
  resolved version in the build log / image labels).

### 2. `.github/workflows/cnpg-image.yml`

- **Triggers:** push of git tags matching `cnpg-image-*`, plus `workflow_dispatch`.
- **Permissions:** `packages: write`, `contents: read`.
- **Steps:** checkout → `docker/login-action` to ghcr.io with `GITHUB_TOKEN` →
  `docker/build-push-action` with `platforms: linux/amd64`, build context
  `images/cnpg/`, push tag `17-bookworm-ext.<N>` (and the matching git tag's
  derived version). Never tag `latest`.

### 3. Terraform changes

**`dev/variables.tf`**
- Add `cnpg_image` (string, default
  `ghcr.io/robertklucovsky/cnpg-postgresql:17-bookworm-ext.1`).
- Keep `cnpg_pg_version` only if still referenced elsewhere; otherwise the
  hardcoded `imageName` interpolation is replaced wholesale by `var.cnpg_image`.

**`dev/cnpg.tf`**
- Replace `imageName: ghcr.io/cloudnative-pg/postgresql:${var.cnpg_pg_version}`
  with `imageName: ${var.cnpg_image}`.
- Add to `spec.postgresql.parameters`:
  `shared_preload_libraries: "age, pg_stat_statements"`.
- Confirm whether the node needs an image pull secret for the custom package
  (the base image already pulls anonymously from ghcr.io; make the published
  package **public** so no pull secret is required — record this in the workflow
  / package settings).

**`dev/postgresql.tf`** (platform DB/extension definitions)
- Add `resource "postgresql_extension" "pg_stat_statements"` targeting the
  `postgres` database, `depends_on = [terraform_data.cnpg_ready]`.

## Data flow / rollout

1. Bump image: edit `images/cnpg/Dockerfile` (or just rebuild), push a
   `cnpg-image-*` git tag → CI publishes `…:17-bookworm-ext.<N+1>`.
2. Bump `var.cnpg_image` (or its default) to the new tag → `terraform apply`.
3. CNPG performs a rolling pod replacement onto the new image. The
   `shared_preload_libraries` change forces the restart that activates `age`
   and `pg_stat_statements`.
4. `postgresql_extension.pg_stat_statements` creates the extension in `postgres`.
5. Downstream DB owners run `CREATE EXTENSION vector;` / `CREATE EXTENSION age;`
   as needed.

## Error handling / risks

- **Operator rejects the tag:** CNPG parses the PG major version from the image
  tag. Verify the operator accepts `17-bookworm-ext.<N>`. Fallback: use a
  `17.<minor>-ext<N>` style tag that the operator's version regex accepts.
- **AGE shared-lib mismatch:** the AGE `.so` must match PG major + distro + arch.
  Building the builder stage `FROM` the same `17-bookworm` base guarantees this;
  target arch is `linux/amd64` only.
- **`shared_preload_libraries` ordering:** set as a single comma-separated value;
  a CNPG-managed restart is required (expected, not a failure). The cluster has a
  replica (`cnpg_instances = 2`) so the rollout is rolling.
- **pgvector package availability for PG17:** if `postgresql-17-pgvector` is
  unavailable in the PGDG repo at build time, fall back to compiling pgvector
  from source in the builder stage (same pattern as AGE).
- **Pull access:** if the ghcr package is private, the node pull fails on cold
  bootstrap. Mitigation: publish the package as public (preferred), or add an
  imagePullSecret to the cluster spec.

## Out of scope

- `CREATE EXTENSION vector` / `age` in any specific database — owner-driven.
- Multi-arch builds (single amd64 node).
- Migrating to CNPG Image Volume extensions (future, when on PG18/CNPG 1.29+).

## Verification

After CI publishes and `terraform apply` completes:

1. `kubectl get pods -n cnpg-system -l cnpg.io/cluster=shared-db -o
   jsonpath='{.items[*].spec.containers[*].image}'` shows the new image; pods
   Running.
2. `SHOW shared_preload_libraries;` lists `age, pg_stat_statements`.
3. `SELECT extname FROM pg_extension;` in `postgres` includes
   `pg_stat_statements`.
4. In a scratch DB: `CREATE EXTENSION vector;` and `CREATE EXTENSION age;` both
   succeed; `LOAD 'age';` works.
