# -----------------------------------------------------------------------------
# SONARQUBE — Code Quality for AI Agent Review
#
# Deployed in its own namespace. Used locally by AI agents via the MCP Server
# plugin for code review before committing to Git.
# Not used in CI/CD pipelines.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# NAMESPACE
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "sonarqube" {
  count = var.sonarqube_enabled ? 1 : 0

  metadata {
    name = "sonarqube"

    labels = {
      "app.kubernetes.io/name"       = "sonarqube"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# SONARQUBE DATABASE
# -----------------------------------------------------------------------------

resource "random_password" "pg_sonarqube" {
  count   = var.sonarqube_enabled ? 1 : 0
  length  = 24
  special = false
}

resource "random_password" "sonarqube_monitoring" {
  count   = var.sonarqube_enabled ? 1 : 0
  length  = 24
  special = false
}

resource "postgresql_role" "sonarqube" {
  count    = var.sonarqube_enabled ? 1 : 0
  name     = "sonarqube"
  login    = true
  password = random_password.pg_sonarqube[0].result

  depends_on = [terraform_data.cnpg_ready]
}

resource "postgresql_database" "sonarqube" {
  count = var.sonarqube_enabled ? 1 : 0
  name  = "sonarqube"
  owner = postgresql_role.sonarqube[0].name

  depends_on = [postgresql_role.sonarqube]
}

# -----------------------------------------------------------------------------
# SONARQUBE HELM RELEASE
# -----------------------------------------------------------------------------

resource "helm_release" "sonarqube" {
  count      = var.sonarqube_enabled ? 1 : 0
  name       = "sonarqube"
  repository = "https://SonarSource.github.io/helm-chart-sonarqube"
  chart      = "sonarqube"
  version    = var.sonarqube_version
  namespace  = kubernetes_namespace.sonarqube[0].metadata[0].name

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      # Enable Community Edition
      community = {
        enabled = true
      }

      # Monitoring passcode (required by new chart versions)
      monitoringPasscode = random_password.sonarqube_monitoring[0].result

      # Use external CNPG PostgreSQL
      postgresql = {
        enabled = false
      }

      jdbcOverwrite = {
        enable       = true
        jdbcUrl      = "jdbc:postgresql://shared-db-rw.cnpg-system.svc.cluster.local:5432/sonarqube"
        jdbcUsername = postgresql_role.sonarqube[0].name
        jdbcPassword = random_password.pg_sonarqube[0].result
      }

      # Install MCP Server plugin
      plugins = {
        install = var.sonarqube_plugins
      }

      # Resource limits
      resources = {
        requests = {
          cpu    = "500m"
          memory = "1Gi"
        }
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
      }

      # Required for Elasticsearch
      initSysctl = {
        enabled = true
      }

      # Disable built-in ingress (we use Gateway API)
      ingress = {
        enabled = false
      }
    })
  ]

  depends_on = [postgresql_database.sonarqube]
}

