# -----------------------------------------------------------------------------
# PGADMIN — PostgreSQL Admin UI
#
# Deployed in cnpg-system alongside the PostgreSQL cluster.
# Accessible at db.klucovsky.com (VPN only).
# -----------------------------------------------------------------------------

resource "kubernetes_deployment" "pgadmin" {
  metadata {
    name      = "pgadmin"
    namespace = "cnpg-system"

    labels = {
      "app.kubernetes.io/name"       = "pgadmin"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "pgadmin"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "pgadmin"
        }
      }

      spec {
        security_context {
          run_as_user  = 5050
          run_as_group = 5050
          fs_group     = 5050
        }

        init_container {
          name  = "fix-permissions"
          image = "busybox:1.38"

          command = ["sh", "-c", "chown -R 5050:5050 /var/lib/pgadmin"]

          security_context {
            run_as_user = 0
          }

          volume_mount {
            name       = "pgadmin-data"
            mount_path = "/var/lib/pgadmin"
          }
        }

        container {
          name  = "pgadmin"
          image = "dpage/pgadmin4:${var.pgadmin_version}"

          port {
            container_port = 5050
          }

          env {
            name  = "PGADMIN_DEFAULT_EMAIL"
            value = var.pgadmin_email
          }

          env {
            name = "PGADMIN_DEFAULT_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.pgadmin_credentials.metadata[0].name
                key  = "password"
              }
            }
          }

          env {
            name  = "PGADMIN_CONFIG_SERVER_MODE"
            value = "True"
          }

          env {
            name  = "PGADMIN_LISTEN_PORT"
            value = "5050"
          }

          env {
            name  = "PGADMIN_SERVER_JSON_FILE"
            value = "/pgadmin4/servers.json"
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
            name       = "pgadmin-data"
            mount_path = "/var/lib/pgadmin"
          }

          volume_mount {
            name       = "servers-config"
            mount_path = "/pgadmin4/servers.json"
            sub_path   = "servers.json"
            read_only  = true
          }
        }

        volume {
          name = "pgadmin-data"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.pgadmin_data.metadata[0].name
          }
        }

        volume {
          name = "servers-config"

          config_map {
            name = kubernetes_config_map.pgadmin_servers.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubectl_manifest.cnpg_cluster, kubernetes_config_map.pgadmin_servers]
}

# Pre-configured server connections for pgAdmin
resource "kubernetes_config_map" "pgadmin_servers" {
  metadata {
    name      = "pgadmin-servers"
    namespace = "cnpg-system"

    labels = {
      "app.kubernetes.io/name"       = "pgadmin"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    "servers.json" = jsonencode({
      Servers = {
        "1" = {
          Name          = "Shared DB (CNPG)"
          Group         = "CNPG Cluster"
          Host          = "shared-db-rw.cnpg-system.svc.cluster.local"
          Port          = 5432
          MaintenanceDB = "postgres"
          Username      = "postgres"
          SSLMode       = "prefer"
          PassFile      = ""
        }
        "2" = {
          Name          = "Shared DB Read-Only"
          Group         = "CNPG Cluster"
          Host          = "shared-db-ro.cnpg-system.svc.cluster.local"
          Port          = 5432
          MaintenanceDB = "postgres"
          Username      = "postgres"
          SSLMode       = "prefer"
          PassFile      = ""
        }
      }
    })
  }

  depends_on = [helm_release.cnpg_operator]
}

# PVC for pgAdmin data
resource "kubernetes_persistent_volume_claim" "pgadmin_data" {
  metadata {
    name      = "pgadmin-data"
    namespace = "cnpg-system"
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class

    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }

  wait_until_bound = false

  depends_on = [helm_release.cnpg_operator]
}

# Credentials
resource "random_password" "pgadmin_password" {
  length  = 24
  special = false
}

resource "kubernetes_secret" "pgadmin_credentials" {
  metadata {
    name      = "pgadmin-credentials"
    namespace = "cnpg-system"

    labels = {
      "app.kubernetes.io/name"       = "pgadmin"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    password = random_password.pgadmin_password.result
  }

  depends_on = [helm_release.cnpg_operator]
}

# Service
resource "kubernetes_service" "pgadmin" {
  metadata {
    name      = "pgadmin"
    namespace = "cnpg-system"

    labels = {
      "app.kubernetes.io/name"       = "pgadmin"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    selector = {
      "app.kubernetes.io/name" = "pgadmin"
    }

    port {
      port        = 80
      target_port = 5050
    }
  }

  depends_on = [helm_release.cnpg_operator]
}
