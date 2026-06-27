# -----------------------------------------------------------------------------
# PLATFORM POSTGRESQL — DBs and roles for platform-owned services
#
# SonarQube's DB/role are defined inline in sonarqube.tf (existing pattern).
# Keycloak and OPAL are defined here. Tenant per-service DBs live in the
# tenant repo.
# -----------------------------------------------------------------------------

# Internal CNPG service DNS names (used by Keycloak StatefulSet)
locals {
  pg_rw_host = "shared-db-rw.cnpg-system.svc.cluster.local"
  pg_ro_host = "shared-db-ro.cnpg-system.svc.cluster.local"
  pg_port    = 5432
}

# -----------------------------------------------------------------------------
# KEYCLOAK DATABASE
# -----------------------------------------------------------------------------

resource "random_password" "pg_keycloak" {
  length  = 24
  special = false
}

resource "postgresql_role" "keycloak" {
  name     = "keycloak"
  login    = true
  password = random_password.pg_keycloak.result

  depends_on = [terraform_data.cnpg_ready]
}

resource "postgresql_database" "keycloak" {
  name  = "keycloak"
  owner = postgresql_role.keycloak.name

  depends_on = [postgresql_role.keycloak]
}

# -----------------------------------------------------------------------------
# OPAL DATABASE (legacy — OPAL workload not currently deployed,
# but DB kept to preserve historical state)
# -----------------------------------------------------------------------------

resource "random_password" "pg_opal" {
  length  = 24
  special = false
}

resource "postgresql_role" "opal" {
  name     = "opal"
  login    = true
  password = random_password.pg_opal.result

  depends_on = [terraform_data.cnpg_ready]
}

resource "postgresql_database" "opal" {
  name  = "opal"
  owner = postgresql_role.opal.name

  depends_on = [postgresql_role.opal]
}

# -----------------------------------------------------------------------------
# KEYCLOAK DB CREDENTIALS SECRET (consumed by Keycloak StatefulSet)
# -----------------------------------------------------------------------------

resource "kubernetes_secret" "keycloak_db_credentials" {
  metadata {
    name      = "keycloak-db-credentials"
    namespace = kubernetes_namespace.keycloak.metadata[0].name

    labels = {
      "app.kubernetes.io/name"       = "keycloak-db-credentials"
      "app.kubernetes.io/component"  = "database"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    "keycloak-url"      = "jdbc:postgresql://${local.pg_rw_host}:${local.pg_port}/keycloak"
    "keycloak-username" = postgresql_role.keycloak.name
    "keycloak-password" = random_password.pg_keycloak.result
  }
}

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
      echo "Waiting for age + pg_stat_statements in shared_preload_libraries..."
      for i in $(seq 1 60); do
        POD=$(kubectl $KC get pods -n cnpg-system \
          -l cnpg.io/cluster=shared-db,role=primary \
          -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
        VAL=""
        if [ -n "$POD" ]; then
          VAL=$(kubectl $KC exec -n cnpg-system "$POD" -c postgres -- \
            psql -U postgres -tAc "show shared_preload_libraries" 2>/dev/null || true)
          if printf '%s' "$VAL" | grep -q pg_stat_statements && printf '%s' "$VAL" | grep -q age; then
            echo "preload ready: $VAL"; exit 0
          fi
        fi
        echo "Attempt $i/60 — not ready (got: $VAL), waiting 5s..."
        sleep 5
      done
      echo "ERROR: age + pg_stat_statements not active after 300s"
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
