# Local CI + multi-format registry stack — design

**Date**: 2026-05-28
**Status**: Draft, pending user review
**Replaces**: the earlier GitLab brainstorming (superseded — GitLab is too heavy for the actual need)

## Background

The paid GitHub plan's monthly **storage limit** for Actions + Packages keeps getting exhausted (CI minutes are not currently a constraint — usage is ~460/3000). User-confirmed: Actions storage (artifacts + cache) is the dominant pain point; Packages storage is likely also significant given the user publishes container images, npm, and maven artifacts. Source code stays on GitHub. Goal: keep the GitHub workflow but move the metered storage surfaces (container images, npm/maven artifacts, Actions artifacts, Actions cache) onto the existing `tf-platform` cluster — plus pre-empt CI-minute pressure with self-hosted runners.

## Goals

1. Eliminate paid-plan overage by self-hosting the metered surfaces.
2. Minimal disruption to existing GitHub workflows — only the `runs-on:` label changes; the YAML lives in the same repos.
3. Reuse the platform's existing MinIO for container image storage (no new block-storage PVCs for images).
4. Three components added to `tf-platform/dev/`, all consistent with the platform's existing patterns (Helm-installed, HTTPRoutes on the existing Cilium Gateway, TLS via the existing wildcard cert).

## Non-goals

- Replacing GitHub for source hosting. Repos stay on GitHub.
- High availability for any of the three components — single-replica, like the rest of the dev platform.
- Image scanning, package retention policies, proxy/caching of upstream registries — all add-later items.
- Backups — same fresh-apply philosophy as the rest of the platform.
- Migrating existing CI/CD pipelines beyond changing the `runs-on:` label.

## Stack

| Component | Role | Helm chart | Replicas |
|---|---|---|---|
| `actions-runner-controller` (ARC) | GitHub-maintained controller that registers ephemeral runner pods with GitHub | `actions-runner-controller/actions-runner-controller` | 1 controller + autoscaling runners (min 0, max 3) |
| `Zot` | OCI-native container registry, MinIO-backed | `project-zot/zot` | 1 |
| `Sonatype Nexus OSS` | Multi-format package registry (npm, maven, generic) | `sonatype/nexus-repository-manager` | 1 |
| `github-actions` MinIO bucket | Backing storage for workflow cache + artifacts (no new pod; just a bucket in existing MinIO) | — | — |

## Component placement in tf-platform

```
tf-platform/dev/
├── ... (existing files)
├── arc.tf       # NEW — actions-runner-controller Helm release + RunnerSet for GitHub org
├── zot.tf       # NEW — Zot Helm release with S3 storage driver pointing at platform MinIO
└── nexus.tf     # NEW — Sonatype Nexus OSS Helm release + PVC + admin password data source
```

Each file is independent of the others; depends only on existing platform pieces (MinIO for Zot, the fatto-gateway + cert-manager for ingress, default StorageClass for Nexus's PVC).

## Hostnames and ingress

| Service | Hostname | TLS cert | DNS record to create |
|---|---|---|---|
| Zot registry | `registry.klucovsky.com` | Existing `klucovsky-wildcard-tls` | A record `registry` → gateway LB IP |
| Nexus UI + repos | `nexus.klucovsky.com` | Existing `klucovsky-wildcard-tls` | A record `nexus` → gateway LB IP |
| ARC | none — controller is outbound-only (registers runners with GitHub API) | n/a | n/a |

Two new `HTTPRoute` resources targeting the existing `fatto-gateway` in the `gateway` namespace. Two new DigitalOcean A records pointing to the gateway's LB IP (same as the existing `grafana`/`prometheus`/`argocd` records).

## Authentication and secrets

### ARC — GitHub App
A GitHub App created in the GitHub org's settings with these permissions:
- Repository: Actions (R+W), Administration (R+W), Checks (Read), Metadata (Read), Workflows (Read)
- Subscribe to events: Workflow job, Workflow run

User creates the App once in GitHub's UI. Three values land in `tf-platform/dev/terraform.tfvars`:
- `github_app_id` (number)
- `github_app_installation_id` (number, from installing the App on the org/repos)
- `github_app_private_key` (PEM string, sensitive — multiline in tfvars via heredoc or path)

`arc.tf` constructs a Kubernetes secret from these for the controller to consume.

### Zot — htpasswd
- Single admin user `admin` with auto-generated 24-char password via `random_password.zot_admin`.
- Password stored in K8s secret `zot-credentials` in the `zot` namespace.
- htpasswd file mounted into the Zot pod via a Secret volume.
- CI workflows use the admin token for now; per-CI-job tokens are a follow-up.

### Nexus — auto-generated admin password, captured via data source
- Nexus generates its initial admin password at `/nexus-data/admin.password` inside the pod on first boot.
- Terraform reads it via a `kubernetes_exec`-style approach: a `terraform_data` resource with a `local-exec` provisioner that runs `kubectl exec -n nexus deploy/nexus -- cat /nexus-data/admin.password` and stores the result in TF state.
- After Terraform has captured it, it's written to a K8s secret `nexus-credentials` in the `nexus` namespace.
- User changes the password in the Nexus UI on first login if desired (Nexus prompts you to anyway).

Trade-off accepted: the initial password lives in TF state. For a single-user lab this is fine.

## Storage

| Component | Storage shape | Size at start |
|---|---|---|
| ARC controller | None | — |
| ARC runners | None for state; optional `emptyDir` mounts for build cache | — |
| Zot | S3-compatible storage driver against platform MinIO — new bucket `zot-storage` | Grows with image volume; no PVC |
| Nexus | PVC (default StorageClass `csi-rawfile-default`) at `/nexus-data` | 20 GB |

The Zot-on-MinIO setup means container image storage is just another bucket in the platform's MinIO — no new block-storage PVCs for images, and you can inspect raw layers via the MinIO console for debugging.

## CI workflow integration

Existing GitHub Actions workflow files require one change:

```yaml
jobs:
  build:
    runs-on: [self-hosted, fatto]    # was: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: docker build -t registry.klucovsky.com/fatto/catalog:${{ github.sha }} .
      - run: docker push registry.klucovsky.com/fatto/catalog:${{ github.sha }}
```

The `RunnerSet` declared in `arc.tf` registers runners with the label `fatto`. GitHub schedules jobs that request that label onto the in-cluster runners.

Where workflows previously pushed to `ghcr.io`, change the registry hostname to `registry.klucovsky.com`. Where they pulled from / published to GitHub Packages (npm, maven), point at `nexus.klucovsky.com/repository/npm-hosted/` (or equivalent maven URL).

## Per-component details

### `arc.tf`

- `helm_release.arc_controller`: chart `actions-runner-controller/actions-runner-controller`, namespace `arc-system`, deploys controller + webhook server.
- Pre-Helm: `kubernetes_secret.github_app_creds` in `arc-system` namespace with `github_app_id`, `github_app_installation_id`, `github_app_private_key`.
- Post-Helm: `kubectl_manifest.runner_set` defining a `RunnerSet` with:
  - `repository: <org>/<repo>` or `organization: <org>` (org-wide runners — set both, the org-wide is more flexible)
  - `labels: [fatto, self-hosted]`
  - `minReplicas: 0, maxReplicas: 3`
  - `template.spec.containers[0].image`: `ghcr.io/actions/actions-runner:latest` (use a pinned tag in practice)
  - Tolerations / nodeSelectors as needed for the cluster's nodes

### `zot.tf`

- `kubernetes_namespace.zot`
- `random_password.zot_admin`
- `kubernetes_secret.zot_credentials` (htpasswd format)
- **Bucket creation** via a one-shot Kubernetes Job (`kubernetes_job_v1.zot_bucket_init`) that runs `mc alias set local http://minio.fatto-erp-dev.svc.cluster.local:9000 $ROOT_USER $ROOT_PASSWORD && mc mb --ignore-existing local/zot-storage`. The Job mounts the MinIO root credentials from the platform's existing `fatto-credentials` (which already contains `minio-password`); `minio_root_user` is read from a config map or hardcoded `fatto-admin` (matches platform default).
- **MinIO credentials for Zot**: use the existing MinIO root credentials (read from `data.kubernetes_secret.fatto_credentials`). Creating a dedicated MinIO service account is out of scope — adds MinIO admin API integration with little benefit for a single-tenant setup.
- `helm_release.zot`: chart `project-zot/zot`, Helm values configuring:
  - Storage driver: `s3` with endpoint `http://minio.fatto-erp-dev.svc.cluster.local:9000`, bucket `zot-storage`, access key + secret from the secret above
  - Auth: htpasswd reading from the credentials secret
  - Ingress: disabled (we use Gateway API HTTPRoute separately)
- `kubectl_manifest.zot_route`: `HTTPRoute` for `registry.klucovsky.com` → `zot.zot.svc.cluster.local:5000`

### `nexus.tf`

- `kubernetes_namespace.nexus`
- `kubernetes_persistent_volume_claim.nexus_data` — 20 GB
- `helm_release.nexus`: chart `sonatype/nexus-repository-manager`, Helm values:
  - Persistence backed by the PVC above
  - Resource requests: 500m CPU / 1 GB RAM; limits 2000m / 3 GB
  - Ingress disabled (Gateway API used separately)
- **Admin password capture via in-cluster Job, not `terraform exec`**: a `kubernetes_job_v1.nexus_admin_capture` runs after Nexus is ready, mounting the same `nexus-data` PVC, reading `/nexus-data/admin.password`, and writing it to a K8s Secret `nexus-credentials` in the `nexus` namespace. Job uses a small image (e.g. `bitnami/kubectl` or busybox + a curl call to the K8s API via the in-cluster service account).
- `data "kubernetes_secret" "nexus_credentials"` then reads that secret back so the password appears in `output "nexus_admin_credentials"`. The password lives in TF state via this data-source read — acceptable for a single-user lab.
- `kubectl_manifest.nexus_route`: `HTTPRoute` for `nexus.klucovsky.com` → `nexus.nexus.svc.cluster.local:8081`

Note: Nexus repository setup (creating `npm-hosted`, `maven-releases`, `maven-snapshots`, etc.) is **not** Terraform-managed — you do that via the Nexus UI on first login. Terraform manages only the install.

## Variables added to `tf-platform/dev/variables.tf`

```hcl
variable "github_app_id" {
  description = "GitHub App ID for ARC runner registration"
  type        = string
}

variable "github_app_installation_id" {
  description = "GitHub App installation ID (from installing the App on the org)"
  type        = string
}

variable "github_app_private_key" {
  description = "GitHub App private key PEM (sensitive)"
  type        = string
  sensitive   = true
}

variable "github_org" {
  description = "GitHub organization for org-wide runners"
  type        = string
  default     = "Fatto-ERP"
}

variable "arc_chart_version" {
  description = "actions-runner-controller Helm chart version"
  type        = string
  default     = "0.23.7"
}

variable "zot_chart_version" {
  description = "Zot Helm chart version"
  type        = string
  default     = "0.1.66"
}

variable "nexus_chart_version" {
  description = "Sonatype Nexus Repository Manager Helm chart version"
  type        = string
  default     = "73.0.0"
}
```

Chart versions are pinned **placeholders** and must be verified against the chart repos at install time (the values above were not freshly checked against the registries when this spec was written). Implementation plan should re-check via `helm search repo` before pinning.

## Outputs added to `tf-platform/dev/outputs.tf`

```hcl
output "registry_url" { value = "https://registry.klucovsky.com" }
output "nexus_url"    { value = "https://nexus.klucovsky.com" }

output "zot_admin_credentials" {
  value = {
    username = "admin"
    password = random_password.zot_admin.result
  }
  sensitive = true
}

output "nexus_admin_credentials" {
  value = {
    username = "admin"
    password = terraform_data.nexus_admin_password.output
  }
  sensitive = true
}
```

## Actions storage redirect (artifacts + cache)

Beyond container images and packages, GitHub Actions itself consumes storage in two ways: **workflow artifacts** (`actions/upload-artifact`) and **workflow caches** (`actions/cache`). Neither has a built-in "use my own storage" toggle in GitHub, but both can be redirected via workflow-level changes.

### Cache — drop-in S3-backed action

Replace `actions/cache@v4` in workflows with `tespkg/actions-cache@v1` (or equivalent: `runs-on/cache`, `whywaita/actions-cache-s3`). Same step interface (`key`, `path`, `restore-keys`), but the backend is S3-compatible storage of your choice.

Workflow snippet:

```yaml
- uses: tespkg/actions-cache@v1
  with:
    endpoint: minio.dev.fatto.online   # platform MinIO public ingress
    insecure: false
    accessKey: ${{ secrets.MINIO_ACCESS_KEY }}
    secretKey: ${{ secrets.MINIO_SECRET_KEY }}
    bucket: github-actions
    use-fallback: false
    path: ~/.gradle/caches
    key: gradle-${{ runner.os }}-${{ hashFiles('**/*.gradle*') }}
    restore-keys: gradle-${{ runner.os }}-
```

### Artifacts — direct push to MinIO, skip `upload-artifact`

For artifacts that need to be passed between jobs (or downloaded later):

```yaml
- name: Upload build artifact
  run: |
    mc alias set local https://minio.dev.fatto.online \
      "${{ secrets.MINIO_ACCESS_KEY }}" "${{ secrets.MINIO_SECRET_KEY }}"
    mc cp ./build/output.tar.gz \
      local/github-actions/artifacts/${{ github.repository }}/${{ github.run_id }}/output.tar.gz
```

For artifacts that only need to live during the workflow run (passed between jobs), GitHub's `actions/upload-artifact` is still convenient for short-lived data — but only if its retention is set very low (e.g. `retention-days: 1`) to avoid storage accrual. The migration target should be: nothing long-lived on GitHub.

### Infrastructure side — one new MinIO bucket

A `github-actions` bucket in the platform's existing MinIO. Created via the same one-shot Kubernetes Job pattern as `zot-storage`:

- `kubernetes_job_v1.github_actions_bucket_init` runs `mc mb --ignore-existing local/github-actions` using the platform's existing MinIO root creds. Lifecycle: idempotent, runs at apply time.

A dedicated MinIO service account for GitHub Actions (with bucket-scoped permissions) is a follow-up; initial setup uses the existing root credentials, surfaced as MinIO `accessKey`/`secretKey` GitHub repo or org secrets that the user copies manually after `terraform apply`.

### Access shape

GitHub-hosted runners reach MinIO via the **public ingress** (`minio.dev.fatto.online`) — already exists in the platform. Self-hosted runners (ARC, once installed) reach MinIO via the **in-cluster service** (`minio.fatto-erp-dev.svc.cluster.local:9000`). Workflows should use the public endpoint so they work in both modes; ARC runners just resolve the public DNS internally with negligible cost.

### Recommendation

Migrate one workflow as a pilot. Once the `tespkg/actions-cache` round-trip is verified to work and artifacts are landing in MinIO, do a sweep across the org's workflows in a single PR.

## Apply / destroy ordering

All three modules depend only on existing platform components (MinIO, gateway, cert-manager). They can be applied alongside the existing platform with a single `terraform apply` from `tf-platform/dev/`. No ordering between the three internally.

Destroy: standard `terraform destroy`. Zot's image bucket in MinIO won't be auto-deleted (the storage driver doesn't clean up); manual `mc rb minio/zot-storage --force` after destroy if you want full cleanup. Nexus's PVC is also retained by default (depending on storage class reclaim policy).

## Risks and mitigations

- **GitHub App scope creep**: The App initially needs Actions + Admin + Workflows. If you later want Container Registry / Packages permissions in the same App, expand it incrementally. Don't over-grant up front.
- **Zot-MinIO bucket conflict**: If `zot-storage` bucket exists from a prior run, Zot will use it. If MinIO is reset, image data is lost. This is the same as any storage backend — but it's worth being explicit because the bucket lives "in a different system" (MinIO) than the registry pod itself.
- **Nexus admin password rotation**: After first capture, if you rotate the password in the Nexus UI, the K8s secret holds a stale value. Either don't rotate, or update the secret manually.
- **ARC runner pods running untrusted code**: Self-hosted runners by default run arbitrary code from the repo's workflows. For a private org-internal repo set this is acceptable. For public repos, ARC requires additional configuration (label-based gating) — out of scope here.

## Out of scope (follow-up specs)

- Per-CI-job ephemeral tokens for Zot pushes (instead of admin token).
- Image scanning integration (Trivy via Zot's scan endpoint).
- Nexus proxy/caching repositories for upstream npm/maven mirrors.
- Backups for Nexus PVC and the Zot MinIO bucket.
- Monitoring/alerting on registry storage growth, Nexus disk usage, ARC queue depth.
