# -----------------------------------------------------------------------------
# KEYCLOAK
# Official Keycloak Docker Image - Development deployment
# https://hub.docker.com/r/keycloak/keycloak (Quarkus-based)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# NAMESPACE
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "keycloak" {
  metadata {
    name = "keycloak"
    labels = {
      "app.kubernetes.io/name"       = "keycloak"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# ADMIN CREDENTIALS HANDOFF
# Tenant repos that own their Keycloak↔MinIO OIDC wiring need Keycloak admin
# creds to provision their realm/clients/mappers via the Keycloak Terraform
# provider. Published as a Secret here (same pattern as rustfs-admin) so tenants
# can read it via data.kubernetes_secret without coupling to this repo's state.
# -----------------------------------------------------------------------------

resource "kubernetes_secret" "keycloak_admin" {
  metadata {
    name      = "keycloak-admin"
    namespace = kubernetes_namespace.keycloak.metadata[0].name

    labels = {
      "app.kubernetes.io/name"       = "keycloak"
      "app.kubernetes.io/component"  = "admin-credentials"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    username = var.keycloak_admin_user
    password = random_password.keycloak_password.result
    url      = "https://auth.klucovsky.com"
  }
}

# -----------------------------------------------------------------------------
# STATEFULSET
#
# Vanilla Keycloak: no realm import, no custom theme. Realms + login themes are
# tenant-owned and will be provisioned by each tenant via the Keycloak provider
# + a shared themes volume once the tenant is deployed.
# -----------------------------------------------------------------------------

resource "kubernetes_stateful_set" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace.keycloak.metadata[0].name
    labels = {
      "app.kubernetes.io/name"    = "keycloak"
      "app.kubernetes.io/part-of" = "platform"
    }
  }

  spec {
    service_name = "keycloak"
    replicas     = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "keycloak"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "keycloak"
        }
      }

      spec {
        container {
          name  = "keycloak"
          image = "quay.io/keycloak/keycloak:26.6.4"

          args = ["start-dev", "--health-enabled=true"]

          env {
            name  = "KEYCLOAK_ADMIN"
            value = var.keycloak_admin_user
          }

          # Sourced directly from the generated password rather than the
          # tenant credentials Secret, which lives in the tenant namespace
          # (Kubernetes Secrets are namespace-scoped). Mirrors MinIO's approach.
          env {
            name  = "KEYCLOAK_ADMIN_PASSWORD"
            value = random_password.keycloak_password.result
          }

          env {
            name  = "KC_DB"
            value = "postgres"
          }

          env {
            name = "KC_DB_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.keycloak_db_credentials.metadata[0].name
                key  = "keycloak-url"
              }
            }
          }

          env {
            name = "KC_DB_USERNAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.keycloak_db_credentials.metadata[0].name
                key  = "keycloak-username"
              }
            }
          }

          env {
            name = "KC_DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.keycloak_db_credentials.metadata[0].name
                key  = "keycloak-password"
              }
            }
          }

          env {
            name  = "KC_HOSTNAME"
            value = "https://auth.klucovsky.com"
          }

          env {
            name  = "KC_HTTP_ENABLED"
            value = "true"
          }

          env {
            name  = "KC_PROXY_HEADERS"
            value = "xforwarded"
          }

          port {
            container_port = 8080
            name           = "http"
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }

          readiness_probe {
            http_get {
              path = "/health/ready"
              port = 9000
            }
            initial_delay_seconds = 60
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/health/live"
              port = 9000
            }
            initial_delay_seconds = 180
            period_seconds        = 30
            failure_threshold     = 6
          }

        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.keycloak,
    kubernetes_secret.keycloak_db_credentials,
    postgresql_database.keycloak
  ]
}

resource "kubernetes_service" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace.keycloak.metadata[0].name
    labels = {
      "app.kubernetes.io/name" = "keycloak"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/name" = "keycloak"
    }

    port {
      port        = 80
      target_port = 8080
      name        = "http"
    }
  }
}
