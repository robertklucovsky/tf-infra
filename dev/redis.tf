# -----------------------------------------------------------------------------
# REDIS
# Official Redis Docker Image - Standalone deployment for development
# https://hub.docker.com/_/redis
# -----------------------------------------------------------------------------

resource "kubernetes_config_map" "redis_config" {
  metadata {
    name      = "redis-config"
    namespace = kubernetes_namespace.fatto_dev.metadata[0].name
  }

  data = {
    "redis.conf" = <<-EOT
      # Enable AOF for durability (important for Streams)
      appendonly yes
      appendfsync everysec
      
      # Streams configuration
      stream-node-max-bytes 4096
      stream-node-max-entries 100
      
      # Memory management
      maxmemory 200mb
      maxmemory-policy allkeys-lru
      
      # Password authentication
      requirepass ${random_password.redis_password.result}
    EOT
  }
}

resource "kubernetes_stateful_set" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace.fatto_dev.metadata[0].name
    labels = {
      "app.kubernetes.io/name"    = "redis"
      "app.kubernetes.io/part-of" = "fatto"
    }
  }

  spec {
    service_name = "redis"
    replicas     = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "redis"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "redis"
        }
      }

      spec {
        container {
          name  = "redis"
          image = "redis:8-alpine"

          command = ["redis-server", "/etc/redis/redis.conf"]

          port {
            container_port = 6379
            name           = "redis"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }

          volume_mount {
            name       = "redis-config"
            mount_path = "/etc/redis"
          }

          volume_mount {
            name       = "redis-data"
            mount_path = "/data"
          }

          readiness_probe {
            exec {
              command = ["redis-cli", "-a", random_password.redis_password.result, "ping"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          liveness_probe {
            exec {
              command = ["redis-cli", "-a", random_password.redis_password.result, "ping"]
            }
            initial_delay_seconds = 15
            period_seconds        = 20
          }
        }

        volume {
          name = "redis-config"
          config_map {
            name = kubernetes_config_map.redis_config.metadata[0].name
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "redis-data"
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = var.storage_class
        resources {
          requests = {
            storage = var.redis_storage_size
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.fatto_dev]
}

resource "kubernetes_service" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace.fatto_dev.metadata[0].name
    labels = {
      "app.kubernetes.io/name" = "redis"
    }
  }

  spec {
    type = "NodePort"

    selector = {
      "app.kubernetes.io/name" = "redis"
    }

    port {
      port        = 6379
      target_port = 6379
      node_port   = 30379
      name        = "redis"
    }
  }
}
