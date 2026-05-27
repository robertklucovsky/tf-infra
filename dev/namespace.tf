# -----------------------------------------------------------------------------
# TENANT NAMESPACE — fatto-erp-dev
#
# Owned by the platform so the FATTO app repo can rely on it existing
# with credentials pre-populated.
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "fatto_dev" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/name"       = "fatto"
      "app.kubernetes.io/component"  = "infrastructure"
      "app.kubernetes.io/managed-by" = "terraform"
      "environment"                  = "dev"
    }
  }
}

# -----------------------------------------------------------------------------
# GENERATED PASSWORDS FOR PLATFORM SERVICES
# -----------------------------------------------------------------------------

resource "random_password" "redis_password" {
  length  = 24
  special = false
}

resource "random_password" "minio_password" {
  length  = 24
  special = false
}

resource "random_password" "keycloak_password" {
  length  = 24
  special = false
}

resource "random_password" "grafana_password" {
  length  = 24
  special = false
}

# -----------------------------------------------------------------------------
# fatto-credentials — bundle of platform-service passwords
# -----------------------------------------------------------------------------

resource "kubernetes_secret" "fatto_credentials" {
  metadata {
    name      = "fatto-credentials"
    namespace = kubernetes_namespace.fatto_dev.metadata[0].name
  }

  data = {
    "postgres-password" = var.postgres_superuser_password
    "redis-password"    = random_password.redis_password.result
    "minio-password"    = random_password.minio_password.result
    "keycloak-password" = random_password.keycloak_password.result
  }
}
