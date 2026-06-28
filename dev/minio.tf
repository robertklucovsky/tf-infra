# -----------------------------------------------------------------------------
# MINIO
# Official MinIO Docker Image - Standalone deployment for development
# https://hub.docker.com/r/minio/minio
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "minio" {
  metadata {
    name = "minio"
    labels = {
      "app.kubernetes.io/name"       = "minio"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# ADMIN CREDENTIALS HANDOFF
# Tenant repos need MinIO admin creds to provision
# their own bucket + scoped access key via the MinIO Terraform provider.
# Published as a Secret here (same pattern as cnpg-superuser) so tenants can
# read it via data.kubernetes_secret without coupling to this repo's state.
# -----------------------------------------------------------------------------

resource "kubernetes_secret" "minio_admin" {
  metadata {
    name      = "minio-admin"
    namespace = kubernetes_namespace.minio.metadata[0].name

    labels = {
      "app.kubernetes.io/name"       = "minio"
      "app.kubernetes.io/component"  = "admin-credentials"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    username = var.minio_root_user
    password = random_password.minio_password.result
  }
}

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

resource "kubernetes_stateful_set" "minio" {
  metadata {
    name      = "minio"
    namespace = kubernetes_namespace.minio.metadata[0].name
    labels = {
      "app.kubernetes.io/name"    = "minio"
      "app.kubernetes.io/part-of" = "platform"
    }
  }

  spec {
    service_name = "minio"
    replicas     = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "minio"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "minio"
        }
      }

      spec {
        container {
          name  = "minio"
          image = "minio/minio:latest"

          args = ["server", "/data", "--console-address", ":9001"]

          env {
            name  = "MINIO_ROOT_USER"
            value = var.minio_root_user
          }

          env {
            name  = "MINIO_ROOT_PASSWORD"
            value = random_password.minio_password.result
          }

          port {
            container_port = 9000
            name           = "api"
          }

          port {
            container_port = 9001
            name           = "console"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          volume_mount {
            name       = "minio-data"
            mount_path = "/data"
          }

          readiness_probe {
            http_get {
              path = "/minio/health/ready"
              port = 9000
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/minio/health/live"
              port = 9000
            }
            initial_delay_seconds = 30
            period_seconds        = 20
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "minio-data"
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = var.storage_class
        resources {
          requests = {
            storage = var.minio_storage_size
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.minio]
}

resource "kubernetes_service" "minio" {
  metadata {
    name      = "minio"
    namespace = kubernetes_namespace.minio.metadata[0].name
    labels = {
      "app.kubernetes.io/name" = "minio"
    }
  }

  spec {
    type = "NodePort"

    selector = {
      "app.kubernetes.io/name" = "minio"
    }

    port {
      port        = 9000
      target_port = 9000
      node_port   = 30900
      name        = "api"
    }

    port {
      port        = 9001
      target_port = 9001
      node_port   = 30901
      name        = "console"
    }
  }
}

# NOTE: tenant buckets are owned by each tenant repo, which provisions its own
# bucket + scoped access key via the MinIO provider. The platform only runs the
# MinIO instance + root admin and publishes the minio-admin handoff Secret above.
