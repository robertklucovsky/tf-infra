# MinIO ↔ Keycloak OIDC Implementation Plan

> **⚠️ SUPERSEDED (2026-06-28).** This plan implemented a platform-side
> `minio_oidc_projects` map (StatefulSet env vars + generated handoff Secret). It
> was implemented, merged, then **reverted** in favor of fully tenant-owned
> registration via the `minio_iam_idp_openid` resource. See the design spec's
> "Revision note" and `README.md` → "MinIO OIDC (Keycloak) per project" for the
> current model. Kept for historical context only.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let MinIO users authenticate/authorize against Keycloak, with one role-based OIDC provider per project realm, driven by a Terraform map and a generated per-project credential handoff.

**Architecture:** This platform repo renders MinIO's named-OIDC-provider env vars from a `minio_oidc_projects` map and publishes a generated `client_secret` per project as a Kubernetes Secret in the `minio` namespace. Realms, clients, MinIO policies, and buckets stay tenant-owned (documented contract only). A `provider_enabled` gate per entry separates "publish the secret" (phase 1) from "load the provider" (phase 2) so the generated-secret ordering is safe.

**Tech Stack:** Terraform (hashicorp/kubernetes, random providers — both already configured), MinIO multi-provider OIDC env vars, Keycloak 26.x (server already running).

## Global Constraints

- No new Terraform providers. Only `hashicorp/kubernetes` and `hashicorp/random` are used; both are already in `dev/main.tf`. The Keycloak Terraform provider is **not** added to this repo.
- All changes are confined to `dev/variables.tf`, `dev/minio.tf`, and `dev/README.md` (or root `README.md`). Do not touch `keycloak.tf`.
- Keycloak external URL is `https://auth.klucovsky.com` (hardcoded the same way `keycloak.tf` already does). MinIO console is reachable at `https://s3.klucovsky.com`.
- Env-var suffix per project = `upper(replace(<map-key>, "-", "_"))`. Map keys must be lowercase alphanumerics and `-` only.
- `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` env blocks remain unchanged (admin break-glass + tenant bucket provisioning).
- Handoff Secret is published for **every** map entry (regardless of `provider_enabled`); provider env vars are rendered **only** for entries with `provider_enabled = true`.
- `client_secret` is generated (`random_password`), never placed in the variable.
- Verification: `terraform -chdir=dev validate` is the offline gate (run `terraform -chdir=dev init -backend=false` once first if `.terraform` providers are stale). `terraform -chdir=dev plan` is the integration check and requires `PG_CONN_STR` + cluster/network access per `README.md`; run it where that access exists.

---

### Task 1: Add the `minio_oidc_projects` variable

**Files:**
- Modify: `dev/variables.tf` (append after the MINIO section, around line 175)

**Interfaces:**
- Produces: `var.minio_oidc_projects` — `map(object({ display_name=string, realm=string, client_id=optional(string,"minio"), role_policy=string, scopes=optional(string,"openid"), provider_enabled=optional(bool,false) }))`, default `{}`. Tasks 2 and 3 consume this.

- [ ] **Step 1: Add the variable block**

Append to `dev/variables.tf` immediately after the `minio_root_user` variable (the existing MINIO section):

```hcl
variable "minio_oidc_projects" {
  description = <<-EOT
    MinIO OIDC providers, keyed by project. One Keycloak realm per entry,
    configured as a role-based provider (all users in a realm get the same
    role_policy). The client_secret is generated and published via the
    minio-oidc-<key> Secret in the minio namespace; the tenant repo reads it
    to create a matching Keycloak client. Set provider_enabled=true only after
    the realm + the role_policy's MinIO policies exist (see the design spec).
    Map keys must be lowercase alphanumerics and "-".
  EOT
  type = map(object({
    display_name     = string                    # SSO button label on the console login page
    realm            = string                    # Keycloak realm name -> builds config_url
    client_id        = optional(string, "minio") # must match the tenant's keycloak_openid_client
    role_policy      = string                    # comma-separated MinIO policy names for this realm's users
    scopes           = optional(string, "openid")
    provider_enabled = optional(bool, false)     # phase gate: render provider env only after realm+policies exist
  }))
  default = {}
}
```

- [ ] **Step 2: Validate**

Run: `terraform -chdir=dev validate`
Expected: `Success! The configuration is valid.`
(If it errors about uninitialized providers, run `terraform -chdir=dev init -backend=false` once, then re-run validate.)

- [ ] **Step 3: Spot-check the suffix expression (offline, optional but recommended)**

Run: `echo 'upper(replace("proj-a", "-", "_"))' | terraform -chdir=dev console`
Expected output: `"PROJ_A"`

- [ ] **Step 4: Commit**

```bash
git add dev/variables.tf
git commit -m "feat(minio): add minio_oidc_projects variable for Keycloak OIDC providers"
```

---

### Task 2: Generate per-project secret and publish the handoff Secret

**Files:**
- Modify: `dev/minio.tf` (add resources after `kubernetes_secret.minio_admin`, around line 41)

**Interfaces:**
- Consumes: `var.minio_oidc_projects` (Task 1); `kubernetes_namespace.minio` (existing).
- Produces: `random_password.minio_oidc[<key>].result`; Secret `minio-oidc-<key>` in namespace `minio` with data keys `client_id`, `client_secret`, `config_url`, `realm`. Task 3 consumes `random_password.minio_oidc`. The tenant repo consumes the Secret cross-namespace.

- [ ] **Step 1: Add the generated password and handoff Secret**

In `dev/minio.tf`, add after the `kubernetes_secret "minio_admin"` resource (before `kubernetes_stateful_set "minio"`):

```hcl
# -----------------------------------------------------------------------------
# OIDC PROVIDER CREDENTIAL HANDOFF (per project / realm)
# The client_secret is generated here and published as minio-oidc-<key> in the
# minio namespace. Each tenant repo reads it to create a Keycloak client whose
# client_id/client_secret match this provider. Published for every entry so the
# tenant can build its realm before the provider is enabled (see provider_enabled).
# -----------------------------------------------------------------------------

resource "random_password" "minio_oidc" {
  for_each = var.minio_oidc_projects
  length   = 32
  special  = false
}

resource "kubernetes_secret" "minio_oidc" {
  for_each = var.minio_oidc_projects

  metadata {
    name      = "minio-oidc-${each.key}"
    namespace = kubernetes_namespace.minio.metadata[0].name

    labels = {
      "app.kubernetes.io/name"       = "minio"
      "app.kubernetes.io/component"  = "oidc-credentials"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    client_id     = each.value.client_id
    client_secret = random_password.minio_oidc[each.key].result
    config_url    = "https://auth.klucovsky.com/realms/${each.value.realm}/.well-known/openid-configuration"
    realm         = each.value.realm
  }
}
```

- [ ] **Step 2: Validate**

Run: `terraform -chdir=dev validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Integration check (where cluster access exists)**

With a temporary entry, e.g. a file `dev/oidc-test.auto.tfvars`:
```hcl
minio_oidc_projects = {
  testproj = { display_name = "Test", realm = "testproj", role_policy = "testproj-rw" }
}
```
Run: `terraform -chdir=dev plan`
Expected: plan shows `random_password.minio_oidc["testproj"]` and `kubernetes_secret.minio_oidc["testproj"]` to be **created**, and **no change** to the `minio` StatefulSet (provider_enabled defaults to false).
Then delete `dev/oidc-test.auto.tfvars`.

- [ ] **Step 4: Commit**

```bash
git add dev/minio.tf
git commit -m "feat(minio): publish generated per-project OIDC client_secret handoff Secret"
```

---

### Task 3: Render the role-based provider env vars on the StatefulSet

**Files:**
- Modify: `dev/minio.tf` (add `locals` block near the top after the file header; add a `dynamic "env"` block inside the MinIO container, after the `MINIO_ROOT_PASSWORD` env block ~line 85)

**Interfaces:**
- Consumes: `var.minio_oidc_projects` (Task 1); `random_password.minio_oidc` (Task 2).
- Produces: suffixed `MINIO_IDENTITY_OPENID_*_<SUFFIX>` env vars on the `minio` container for every entry with `provider_enabled = true`.

- [ ] **Step 1: Add the locals that flatten enabled projects into an env map**

In `dev/minio.tf`, add after the file's top comment header (before `resource "kubernetes_namespace" "minio"`):

```hcl
locals {
  # Only projects whose realm + role_policy already exist should load as providers.
  minio_oidc_enabled = { for k, v in var.minio_oidc_projects : k => v if v.provider_enabled }

  # Flatten each enabled project into MinIO's suffixed named-provider env vars.
  # Suffix = upper(key) with "-" -> "_" (valid MinIO config name + env token).
  minio_oidc_env = merge([
    for k, v in local.minio_oidc_enabled : {
      "MINIO_IDENTITY_OPENID_CONFIG_URL_${upper(replace(k, "-", "_"))}"           = "https://auth.klucovsky.com/realms/${v.realm}/.well-known/openid-configuration"
      "MINIO_IDENTITY_OPENID_CLIENT_ID_${upper(replace(k, "-", "_"))}"            = v.client_id
      "MINIO_IDENTITY_OPENID_CLIENT_SECRET_${upper(replace(k, "-", "_"))}"        = random_password.minio_oidc[k].result
      "MINIO_IDENTITY_OPENID_DISPLAY_NAME_${upper(replace(k, "-", "_"))}"         = v.display_name
      "MINIO_IDENTITY_OPENID_ROLE_POLICY_${upper(replace(k, "-", "_"))}"          = v.role_policy
      "MINIO_IDENTITY_OPENID_SCOPES_${upper(replace(k, "-", "_"))}"               = v.scopes
      "MINIO_IDENTITY_OPENID_REDIRECT_URI_DYNAMIC_${upper(replace(k, "-", "_"))}" = "on"
    }
  ]...)
}
```

- [ ] **Step 2: Add the dynamic env block to the container**

In `dev/minio.tf`, inside the `container { name = "minio" ... }` block, immediately after the existing `MINIO_ROOT_PASSWORD` env block (and before the `port { container_port = 9000 ... }` block), add:

```hcl
          # Named OIDC providers (one per enabled project/realm), role-based.
          dynamic "env" {
            for_each = local.minio_oidc_env
            content {
              name  = env.key
              value = env.value
            }
          }
```

- [ ] **Step 3: Validate**

Run: `terraform -chdir=dev validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 4: Integration check (where cluster access exists)**

Re-create `dev/oidc-test.auto.tfvars`, this time enabled:
```hcl
minio_oidc_projects = {
  testproj = { display_name = "Test", realm = "testproj", role_policy = "testproj-rw", provider_enabled = true }
}
```
Run: `terraform -chdir=dev plan`
Expected: plan shows the `minio` StatefulSet updated to add env vars
`MINIO_IDENTITY_OPENID_CONFIG_URL_TESTPROJ`, `..._CLIENT_ID_TESTPROJ`,
`..._CLIENT_SECRET_TESTPROJ`, `..._DISPLAY_NAME_TESTPROJ`, `..._ROLE_POLICY_TESTPROJ`,
`..._SCOPES_TESTPROJ`, `..._REDIRECT_URI_DYNAMIC_TESTPROJ`.
Then delete `dev/oidc-test.auto.tfvars`.

- [ ] **Step 5: Commit**

```bash
git add dev/minio.tf
git commit -m "feat(minio): render role-based Keycloak OIDC providers from minio_oidc_projects"
```

---

### Task 4: Document the tenant contract and apply ordering

**Files:**
- Modify: `README.md` (add a short subsection under "Tenants" / "What's not here")

**Interfaces:**
- Consumes: nothing. Produces: human-readable contract pointing to the design spec.

- [ ] **Step 1: Add the contract note to `README.md`**

Add this subsection to `README.md` (e.g. under the "Tenants" section):

```markdown
### MinIO OIDC (Keycloak) per project

The platform registers one role-based MinIO OIDC provider per project, driven by
`var.minio_oidc_projects`, and publishes a generated `client_secret` as the
`minio-oidc-<project>` Secret in the `minio` namespace. Each tenant repo owns its
realm and bucket access:

1. **Platform apply #1** — add the project to `minio_oidc_projects` with
   `provider_enabled = false`. This publishes `minio-oidc-<project>`.
2. **Tenant repo** — read `minio-oidc-<project>`; create the `keycloak_realm`,
   a confidential `keycloak_openid_client` (standard flow, valid redirect URI
   `https://s3.klucovsky.com/oauth_callback`, client_id/secret from the Secret),
   the `minio_iam_policy` resources named in the entry's `role_policy`, and the
   buckets.
3. **Platform apply #2** — set `provider_enabled = true` so MinIO loads the
   provider.

Full design: `docs/superpowers/specs/2026-06-28-minio-keycloak-oidc-design.md`.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: document MinIO OIDC per-project tenant contract and apply ordering"
```

---

## Post-implementation verification (manual, requires cluster)

After enabling one real project end-to-end:

- [ ] Confirm the suffixed env vars are present on the running pod:
  `kubectl -n minio exec sts/minio -- env | grep MINIO_IDENTITY_OPENID`
- [ ] Open `https://s3.klucovsky.com` → an SSO button with the project's
  `display_name` appears; login via the realm succeeds; the user sees only that
  project's buckets and is denied on others.
- [ ] **Confirm and document** MinIO's startup behavior when a role-based
  provider references a missing `role_policy` or unreachable `config_url`
  (the spec's open "to verify" item) — check pod logs after a deliberate
  premature enable, and record whether MinIO hard-fails or disables just that
  provider. Update the spec with the finding.
