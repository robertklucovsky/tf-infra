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
  length  = 24
  special = false
}

resource "random_password" "sonarqube_monitoring" {
  length  = 24
  special = false
}

resource "postgresql_role" "sonarqube" {
  name     = "sonarqube"
  login    = true
  password = random_password.pg_sonarqube.result

  depends_on = [terraform_data.cnpg_ready]
}

resource "postgresql_database" "sonarqube" {
  name  = "sonarqube"
  owner = postgresql_role.sonarqube.name

  depends_on = [postgresql_role.sonarqube]
}

# -----------------------------------------------------------------------------
# SONARQUBE HELM RELEASE
# -----------------------------------------------------------------------------

resource "helm_release" "sonarqube" {
  name       = "sonarqube"
  repository = "https://SonarSource.github.io/helm-chart-sonarqube"
  chart      = "sonarqube"
  version    = var.sonarqube_version
  namespace  = kubernetes_namespace.sonarqube.metadata[0].name

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      # Enable Community Edition
      community = {
        enabled = true
      }

      # Monitoring passcode (required by new chart versions)
      monitoringPasscode = random_password.sonarqube_monitoring.result

      # Use external CNPG PostgreSQL
      postgresql = {
        enabled = false
      }

      jdbcOverwrite = {
        enable   = true
        jdbcUrl  = "jdbc:postgresql://shared-db-rw.cnpg-system.svc.cluster.local:5432/sonarqube"
        jdbcUsername = postgresql_role.sonarqube.name
        jdbcPassword = random_password.pg_sonarqube.result
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

# -----------------------------------------------------------------------------
# HTTPROUTE — sonar.klucovsky.com (VPN only)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "sonarqube_route" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: sonarqube
      namespace: ${kubernetes_namespace.sonarqube.metadata[0].name}
    spec:
      parentRefs:
        - name: fatto-gateway
          namespace: gateway
          sectionName: https-klucovsky
      hostnames:
        - "sonar.klucovsky.com"
      rules:
        - backendRefs:
            - name: sonarqube-sonarqube
              port: 9000
  YAML

  depends_on = [helm_release.sonarqube]
}
