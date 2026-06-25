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
# CONFIGMAPS — Theme & Realm Import
# -----------------------------------------------------------------------------

resource "kubernetes_config_map" "keycloak_theme" {
  metadata {
    name      = "keycloak-theme"
    namespace = kubernetes_namespace.keycloak.metadata[0].name
    labels = {
      "app.kubernetes.io/name"    = "keycloak"
      "app.kubernetes.io/part-of" = "fatto"
    }
  }

  data = {
    "theme.properties" = file("${path.module}/keycloak-theme/login/theme.properties")
    "login.ftl"        = file("${path.module}/keycloak-theme/login/login.ftl")
    "login.css"        = file("${path.module}/keycloak-theme/login/resources/css/login.css")
  }
}

resource "kubernetes_config_map" "keycloak_realm" {
  metadata {
    name      = "keycloak-realm"
    namespace = kubernetes_namespace.keycloak.metadata[0].name
    labels = {
      "app.kubernetes.io/name"    = "keycloak"
      "app.kubernetes.io/part-of" = "fatto"
    }
  }

  data = {
    "fatto-realm.json" = file("${path.module}/keycloak-realm/fatto-realm.json")
  }
}

# -----------------------------------------------------------------------------
# STATEFULSET
# -----------------------------------------------------------------------------

resource "kubernetes_stateful_set" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace.keycloak.metadata[0].name
    labels = {
      "app.kubernetes.io/name"    = "keycloak"
      "app.kubernetes.io/part-of" = "fatto"
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
        annotations = {
          "checksum/theme" = sha256(join("", values(kubernetes_config_map.keycloak_theme.data)))
          "checksum/realm" = sha256(join("", values(kubernetes_config_map.keycloak_realm.data)))
        }
      }

      spec {
        # Init container: assemble theme directory structure from ConfigMap
        init_container {
          name  = "theme-init"
          image = "busybox:1.37"

          command = ["sh", "-c", <<-EOT
            mkdir -p /theme/fatto/login/resources/css
            cp /theme-src/theme.properties /theme/fatto/login/theme.properties
            cp /theme-src/login.ftl /theme/fatto/login/login.ftl
            cp /theme-src/login.css /theme/fatto/login/resources/css/login.css
            echo "Theme directory assembled:"
            find /theme -type f
          EOT
          ]

          volume_mount {
            name       = "theme-src"
            mount_path = "/theme-src"
            read_only  = true
          }

          volume_mount {
            name       = "theme-dir"
            mount_path = "/theme"
          }
        }

        container {
          name  = "keycloak"
          image = "quay.io/keycloak/keycloak:26.5.3"

          args = ["start-dev", "--health-enabled=true", "--import-realm"]

          env {
            name  = "KEYCLOAK_ADMIN"
            value = var.keycloak_admin_user
          }

          # Sourced directly from the generated password rather than the
          # fatto-credentials Secret, which lives in the fatto-erp-dev namespace
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
            value = "https://auth.${var.domain}"
          }

          env {
            name  = "KC_HTTP_ENABLED"
            value = "true"
          }

          env {
            name  = "KC_PROXY_HEADERS"
            value = "xforwarded"
          }

          # Custom theme directory
          env {
            name  = "KC_SPI_THEME_DIR"
            value = "/opt/keycloak/themes"
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

          # Theme files (assembled by init container)
          volume_mount {
            name       = "theme-dir"
            mount_path = "/opt/keycloak/themes"
            read_only  = true
          }

          # Realm import
          volume_mount {
            name       = "realm-import"
            mount_path = "/opt/keycloak/data/import"
            read_only  = true
          }
        }

        volume {
          name = "theme-src"
          config_map {
            name = kubernetes_config_map.keycloak_theme.metadata[0].name
          }
        }

        volume {
          name = "theme-dir"
          empty_dir {}
        }

        volume {
          name = "realm-import"
          config_map {
            name = kubernetes_config_map.keycloak_realm.metadata[0].name
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

# -----------------------------------------------------------------------------
# GATEWAY HTTPROUTE
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "route_keycloak" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: keycloak
      namespace: ${kubernetes_namespace.keycloak.metadata[0].name}
    spec:
      parentRefs:
        - name: fatto-gateway
          namespace: gateway
          sectionName: https-dev
      hostnames:
        - "auth.${var.domain}"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: ${kubernetes_service.keycloak.metadata[0].name}
              port: 80
  YAML

  depends_on = [kubectl_manifest.gateway]
}
