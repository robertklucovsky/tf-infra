# MinIO ↔ Keycloak OIDC integration (multi-realm, role-based)

**Date:** 2026-06-28
**Repo:** `tf-platform` (shared platform infrastructure)
**Status:** Revised — tenant-owned registration via `minio_iam_idp_openid`

## Revision note (2026-06-28)

The original design (commits `44441d5`..`ef78d29`, merged then reverted) put a
per-project `minio_oidc_projects` map in **this platform repo**, rendering
`MINIO_IDENTITY_OPENID_*` env vars onto the MinIO StatefulSet and publishing a
generated `client_secret` handoff Secret. It worked, but it forced a platform-side
edit for every project onboarded.

We then found that the MinIO Terraform provider already in use (`aminueza/minio`,
v3.23.0+) offers a **`minio_iam_idp_openid`** resource that registers an OIDC
provider on MinIO via the admin API. That lets each project's `tf-infra` own its
**entire** wiring — including the MinIO provider registration — with zero
platform-side per-project config. The platform-side plumbing was reverted in
favor of this model.

## Goal

Let MinIO users authenticate and authorize against Keycloak instead of using only
the MinIO root credentials. Support **multiple projects**, where each project maps
to its own **Keycloak realm**, and each realm authorizes its users to a set of
**MinIO buckets**.

## Decisions (locked)

1. **Ownership: fully tenant-owned.** Each project's `tf-infra` creates its realm,
   OIDC client, MinIO policies, buckets, **and** the MinIO provider registration.
   The platform repo holds **no** per-project OIDC config.
2. **Platform responsibility: project-agnostic.** This repo runs the MinIO +
   Keycloak servers and publishes the `minio-admin` Secret in the `minio`
   namespace (pre-existing). It sets **no** `MINIO_IDENTITY_OPENID_*` env vars.
3. **Authorization granularity: uniform per realm (role-based).** Every user who
   logs in through a given realm receives the same set of MinIO policies.
4. **Registration mechanism: `minio_iam_idp_openid`** (MinIO admin API / runtime
   config), not StatefulSet env vars.

## Verified technical facts

- **Only one OIDC provider may be JWT-claim-based; all others must be role-based.**
  (MinIO `mc idp openid add` docs, via Context7 `/minio/docs`.) The multi-realm
  model therefore uses role-based providers — see Decision 3.
- **Role-based authorization:** `role_policy` names one or more MinIO policies; all
  users authenticating through that provider receive exactly those policies. If a
  named policy does not exist, the user can perform no actions. `role_policy`
  cannot coexist with `claim_name`/`claim_prefix`.
- **`minio_iam_idp_openid`** (aminueza/minio provider) accepts: `name` (config
  name for multi-provider), `config_url` (required), `client_id` (required),
  `client_secret`, `role_policy`, `display_name`, `scopes`, `redirect_uri`,
  `claim_name`/`claim_prefix`, `enable`, `comment`. Source:
  https://github.com/aminueza/terraform-provider-minio/blob/main/docs/resources/iam_idp_openid.md
- **Env-var vs API config:** keys set via `MINIO_IDENTITY_OPENID_*` env vars are
  locked against admin-API override. Because providers are registered via the API
  (`minio_iam_idp_openid`), the platform MUST set no OIDC env vars.

### To verify during a project rollout (not asserted)

- MinIO behavior when a role-based provider's `role_policy` references a
  not-yet-existing policy, or `config_url` is unreachable at registration time.
  Mitigation: create the realm + policies before the `minio_iam_idp_openid`
  resource (Terraform `depends_on` / resource references handle ordering within
  one project state).

## Architecture

```
PLATFORM repo (this one)                  PROJECT tf-infra (per project)
─────────────────────────                 ──────────────────────────────
MinIO server (StatefulSet)                keycloak_realm        "projecta"
Keycloak server                           keycloak_openid_client "minio"
minio-admin Secret  ───────────────────►  data.kubernetes_secret.minio_admin
   (admin creds; pre-existing)            minio_iam_policy      "projecta-rw"
                                          minio_s3_bucket       "projecta-*"
                                          minio_iam_idp_openid  "projecta" (role_policy)
```

Each **project = one Keycloak realm = one role-based `minio_iam_idp_openid`
provider**, all declared in that project's own Terraform state.

## Platform implementation (this repo)

**None.** The platform reverted to project-agnostic. It already:
- runs the MinIO StatefulSet (root creds for admin/break-glass + tenant
  provisioning) and Keycloak,
- publishes the `minio-admin` Secret consumed cross-namespace by project repos,
- routes `s3.klucovsky.com` → MinIO console and `auth.klucovsky.com` → Keycloak.

No `minio_oidc_projects` variable, no OIDC env vars, no handoff Secret.

## Project `tf-infra` contract (per project)

Configure the `keycloak` and `minio` Terraform providers (MinIO admin creds read
from the `minio-admin` Secret) and create, in the project's own state:

1. `keycloak_realm` — the project's realm.
2. `keycloak_openid_client` — confidential, standard flow enabled, valid redirect
   URI `https://s3.klucovsky.com/oauth_callback`, web origin
   `https://s3.klucovsky.com`. (Role-based needs **no** policy-claim mapper.)
3. `minio_iam_policy` resources granting the desired `s3:*` actions on the
   project's bucket ARNs.
4. `minio_s3_bucket` resources for the project's buckets.
5. `minio_iam_idp_openid` — `config_url` = the realm's discovery URL,
   `client_id`/`client_secret` from (2), `role_policy` = the policy name(s) from
   (3), `display_name`, `scopes = "openid"`. Do **not** set `claim_name` (that
   would make it claim-based; only one such provider is allowed cluster-wide).

A worked HCL block is in `README.md` → "MinIO OIDC (Keycloak) per project".

## Login & authorization flow

1. User opens `https://s3.klucovsky.com` → the console shows one SSO button per
   registered provider (`display_name`).
2. User picks their project → redirected to that Keycloak realm → authenticates →
   returned to the console.
3. MinIO attaches the provider's `role_policy` → the user sees exactly that
   project's buckets.
4. Programmatic S3 access via `AssumeRoleWithWebIdentity` against the S3 API works
   with the same realm token and role.

## Verification

- Platform: `terraform validate`/`plan` clean; MinIO StatefulSet carries **no**
  `MINIO_IDENTITY_OPENID_*` env vars.
- Per project (in its own `tf-infra`): after apply, the SSO button appears on the
  console; login via the realm succeeds; the user sees only that project's buckets
  and is denied on others.

## Out of scope

- Per-user authorization within a realm (would require the single claim-based
  provider slot).
- Migrating existing root-credential workflows; root stays for admin/break-glass
  and tenant bucket provisioning.
- The project-side resources themselves (owned by each project's `tf-infra`).
