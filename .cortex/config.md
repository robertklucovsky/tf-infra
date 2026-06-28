# tf-platform — cortex config

```yaml
cortex_location:
  type: local                 # iba tento stroj/repo; cortex je verzovaný v gite spolu s kódom
  path: /Users/robert.klucovsky/Developer/tf-platform/.cortex
  initialized_by: robert.klucovsky@isdd.sk
  initialized_at: 2026-06-28

category: codebase            # IaC / platform-engineering repo
final_environment: dev        # "dev" cluster (single homelab K8s @ 172.16.1.11); nie production
default_mode: archive         # read-heavy, safe start (§2.6)
user_cortex_path: /Users/robert.klucovsky/.cortex-personal

mode_overrides:
  # per-mode project override tu, ak treba (inak cascade na user → baseline)
```

## Storage bases

Pre resolving source pointerov v loci frontmatter.

```yaml
storage_bases:
  repo:
    base: "/Users/robert.klucovsky/Developer/tf-platform"
    note: "Terraform root modul v dev/, docs v docs/superpowers/"
  github:
    base: "https://github.com/robertklucovsky/tf-infra"
```

## Cluster / endpoint facts (source-first — over voči live stavu pred akciou, §2.10)

```yaml
cluster:
  context: k8s                 # kubeconfig context
  node_ip: 172.16.1.11
  postgres_nodeport: 30432     # CNPG superuser Postgres (terraform_platform schema = pg backend)
  minio_api_nodeport: 30900    # S3 API (NOT console)
hostnames:
  nexus: nexus.klucovsky.com
  keycloak: auth.klucovsky.com
  minio_console: s3.klucovsky.com   # routes to console :9001
```

## Secrets policy

`terraform.tfvars`, `terraform.tfstate*`, `secrets.auto.tfvars` sú **gitignored**.
`PG_CONN_STR` sa dodáva out-of-band cez env var (obsahuje superuser heslo). Cortex
**nikdy** neukladá credentials — patria mimo scope (§2.7.a).
