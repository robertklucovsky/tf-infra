# MinIO ↔ Keycloak OIDC integration (multi-realm, role-based)

**Date:** 2026-06-28
**Repo:** `tf-platform` (shared platform infrastructure)
**Status:** Design approved, pending spec review

## Goal

Let MinIO users authenticate and authorize against Keycloak instead of using
only the MinIO root credentials. The platform must support **multiple
projects**, where:

- each project maps to its own **Keycloak realm**, and
- each realm authorizes its users to a set of **MinIO buckets**.

## Decisions (locked)

1. **Ownership: split.** This platform repo provides the plumbing (MinIO server
   config + a per-project credential handoff). Each tenant/project repo owns its
   own realm, OIDC client, MinIO policies, and buckets. Matches the existing
   platform/tenant split in this repo (see comments in `minio.tf` and
   `keycloak.tf`).
2. **Authorization granularity: uniform per realm (role-based).** Every user who
   logs in through a given realm receives the same set of MinIO policies. No
   per-user differentiation within a realm.
3. **Credential handoff: generated secret.** The platform generates each
   project's OIDC `client_secret` and publishes it (with `client_id`,
   `config_url`, `realm`) as a Kubernetes Secret in the `minio` namespace. The
   tenant repo reads that Secret to create its Keycloak client with matching
   credentials. No manual secret copying.
4. **No worked tenant example.** The tenant side is documented as a contract
   only; this repo implements only the platform side.
5. **No Keycloak Terraform provider in this repo.** Realms are tenant-owned, so
   the platform only renders MinIO env vars and publishes handoff Secrets.

## Verified technical facts (MinIO docs, via Context7 `/minio/docs`)

- **Multiple named OIDC providers** are configured by appending a unique suffix
  to each env var: `MINIO_IDENTITY_OPENID_<SETTING>_<SUFFIX>`. Omitting the
  suffix configures the single default provider.
- **Only one provider may be JWT-claim-based; all others must be role-based.**
  (`mc idp openid add` docs.) This is why the multi-realm model uses role-based
  providers — see Decision 2.
- **Role-based authorization:** `MINIO_IDENTITY_OPENID_ROLE_POLICY_<SUFFIX>` =
  a comma-separated list of MinIO policy names. All users authenticating through
  that provider receive exactly those policies. If a named policy does not
  exist, the user can perform no actions.
- **`MINIO_IDENTITY_OPENID_REDIRECT_URI_DYNAMIC_<SUFFIX>="on"`** makes MinIO
  derive the OAuth callback from the request `Host` header, so it works behind
  the gateway at `s3.klucovsky.com` without hardcoding redirect URIs.
- OIDC settings apply on the **next MinIO server startup** (env-var driven);
  changing the env restarts the StatefulSet pod.

### To verify during implementation (not asserted)

- MinIO's exact behavior when a role-based provider references a **not-yet-existing
  `role_policy`** or an **unreachable `config_url`** at startup: does it hard-fail
  the whole server, or disable just that provider and continue? The
  `provider_enabled` gate (below) avoids the bad-provider window regardless, but
  the failure mode must be confirmed and documented.

## Architecture

```
PLATFORM repo (this one)                     TENANT repo (per project)
─────────────────────────                    ──────────────────────────
MinIO server (StatefulSet)                    keycloak_realm  "projA"
  └─ named OIDC provider per project   ◄────  keycloak_openid_client "minio"
     (role-based, role_policy=...)              (confidential, standard flow)
  └─ minio-oidc-<project> Secret ──────────►  reads client_id + client_secret
Keycloak server                              minio_iam_policy "projA-rw" (s3:* on projA buckets)
                                             minio_s3_bucket  a, b, c
```

Each **project = one Keycloak realm = one role-based MinIO named provider**.

## Platform implementation (this repo)

Changes are contained to `dev/variables.tf` and `dev/minio.tf`.

### Variable: project registry

```hcl
variable "minio_oidc_projects" {
  description = "MinIO OIDC providers, keyed by project. One Keycloak realm per entry (role-based)."
  type = map(object({
    display_name     = string                    # SSO button label on the console login page
    realm            = string                    # Keycloak realm name -> builds config_url
    client_id        = optional(string, "minio") # must match the tenant's keycloak_openid_client
    role_policy      = string                    # comma-separated MinIO policy names for this realm's users
    scopes           = optional(string, "openid")
    provider_enabled = optional(bool, false)     # phase gate: render the provider env only after realm+policies exist
  }))
  default = {}
}
```

`client_secret` is **not** in the map — it is generated (Decision 3).

### Resources in `minio.tf`

1. **Per-project generated secret**

   ```hcl
   resource "random_password" "minio_oidc" {
     for_each = var.minio_oidc_projects
     length   = 32
     special  = false
   }
   ```

2. **Per-project handoff Secret** in the `minio` namespace (mirrors the existing
   `minio-admin` handoff pattern), consumed cross-namespace by the tenant repo:

   ```hcl
   resource "kubernetes_secret" "minio_oidc" {
     for_each = var.minio_oidc_projects
     metadata {
       name      = "minio-oidc-${each.key}"
       namespace = kubernetes_namespace.minio.metadata[0].name
       labels = { "app.kubernetes.io/managed-by" = "terraform" }
     }
     data = {
       client_id     = each.value.client_id
       client_secret = random_password.minio_oidc[each.key].result
       config_url    = "https://auth.klucovsky.com/realms/${each.value.realm}/.well-known/openid-configuration"
       realm         = each.value.realm
     }
   }
   ```

3. **Provider env vars on the StatefulSet**, rendered only for entries with
   `provider_enabled = true`, via a `dynamic "env"` block flattened over the
   suffixed settings. For each enabled project `<KEY>` (uppercased suffix):

   ```
   MINIO_IDENTITY_OPENID_CONFIG_URL_<KEY>           = https://auth.klucovsky.com/realms/<realm>/.well-known/openid-configuration
   MINIO_IDENTITY_OPENID_CLIENT_ID_<KEY>            = <client_id>
   MINIO_IDENTITY_OPENID_CLIENT_SECRET_<KEY>        = <generated client_secret>
   MINIO_IDENTITY_OPENID_DISPLAY_NAME_<KEY>         = <display_name>
   MINIO_IDENTITY_OPENID_ROLE_POLICY_<KEY>          = <role_policy>
   MINIO_IDENTITY_OPENID_SCOPES_<KEY>               = <scopes>
   MINIO_IDENTITY_OPENID_REDIRECT_URI_DYNAMIC_<KEY> = on
   ```

   `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` are unchanged (admin break-glass;
   tenants still provision buckets via the `minio-admin` handoff).

### Suffix rule

The env-var suffix must be a valid MinIO config name and a valid env-var token.
Derive it from the map key by upper-casing and replacing `-` with `_`
(e.g. key `proj-a` → suffix `PROJ_A`). Document the allowed key charset.

## Tenant contract (documented; built in each project repo, not here)

Per project, the tenant repo adds the `keycloak` and `minio` Terraform providers
and creates:

- `data.kubernetes_secret.minio_oidc` reading `minio-oidc-<project>` from the
  `minio` namespace → `client_id`, `client_secret`.
- `keycloak_realm` — the project's realm (name must equal the `realm` value the
  platform used to build `config_url`).
- `keycloak_openid_client` — confidential, standard flow enabled,
  `client_id` + `client_secret` from the handoff Secret, valid redirect URI
  `https://s3.klucovsky.com/oauth_callback`, web origin `https://s3.klucovsky.com`.
  (Role-based needs **no** policy-claim protocol mapper.)
- `minio_iam_policy` resources granting the desired `s3:*` actions on the
  project's bucket ARNs, **named exactly** as listed in the platform's
  `role_policy`.
- `minio_s3_bucket` resources for the project's buckets.

## Apply ordering (per new project)

The `provider_enabled` gate separates the two opposing ordering requirements
(secret must exist before the tenant client; realm + policies must exist before
the provider loads):

1. **Platform apply #1** — add the map entry with `provider_enabled = false`.
   Generates the secret and publishes `minio-oidc-<project>`. No provider env is
   rendered yet; MinIO is untouched.
2. **Tenant apply** — read the handoff Secret; create realm + client + MinIO
   policies + buckets against the already-running platform servers.
3. **Platform apply #2** — flip `provider_enabled = true`. The provider env is
   rendered; MinIO restarts and registers a fully valid role-based provider.

Removing a project: set `provider_enabled = false` (or delete the entry) and
apply; tear down tenant-side resources in the tenant repo.

## Login & authorization flow

1. User opens `https://s3.klucovsky.com` → the MinIO console shows one SSO button
   per enabled provider (`display_name`).
2. User picks their project → redirected to that Keycloak realm → authenticates
   → returned to the console (callback derived from the `Host` header).
3. MinIO attaches the provider's `role_policy` → the user sees exactly that
   project's buckets.
4. Programmatic S3 access via `AssumeRoleWithWebIdentity` against the S3 API
   (NodePort `:30900`) works with the same realm token and role.

## Verification

- `terraform validate` and `terraform plan` are clean.
- After apply #2 for one project: confirm the suffixed env vars are present on
  the MinIO pod.
- Manual end-to-end login test for one realm: SSO button appears, login
  succeeds, and the user sees only that project's buckets (and is denied on
  others).
- Confirm and document MinIO's startup behavior for a missing `role_policy` /
  unreachable `config_url` (the "to verify" item above).

## Out of scope

- Per-user authorization within a realm (would require the single claim-based
  provider slot).
- Migrating existing root-credential workflows; root stays for admin/break-glass
  and tenant bucket provisioning.
- Building any tenant-repo resources.
