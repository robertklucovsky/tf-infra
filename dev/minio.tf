# -----------------------------------------------------------------------------
# MINIO
# Official MinIO Docker Image - Standalone deployment for development
# https://hub.docker.com/r/minio/minio
# -----------------------------------------------------------------------------

resource "kubernetes_stateful_set" "minio" {
  metadata {
    name      = "minio"
    namespace = kubernetes_namespace.fatto_dev.metadata[0].name
    labels = {
      "app.kubernetes.io/name"    = "minio"
      "app.kubernetes.io/part-of" = "fatto"
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

  depends_on = [kubernetes_namespace.fatto_dev]
}

resource "kubernetes_service" "minio" {
  metadata {
    name      = "minio"
    namespace = kubernetes_namespace.fatto_dev.metadata[0].name
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

# -----------------------------------------------------------------------------
# GATEWAY HTTPROUTE
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "route_minio" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: minio
      namespace: ${kubernetes_namespace.fatto_dev.metadata[0].name}
    spec:
      parentRefs:
        - name: fatto-gateway
          namespace: gateway
          sectionName: https-dev
      hostnames:
        - "minio.${var.domain}"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: ${kubernetes_service.minio.metadata[0].name}
              port: 9001
  YAML

  depends_on = [kubectl_manifest.gateway]
}


# -----------------------------------------------------------------------------
# CATALOG MINIO CREDENTIALS
# Phase 4 (G-002): consumed by fatto-catalog Deployment + bucket-provision Job
# -----------------------------------------------------------------------------

resource "kubernetes_secret" "catalog_minio_credentials" {
  metadata {
    name      = "catalog-minio-credentials"
    namespace = kubernetes_namespace.fatto_dev.metadata[0].name

    labels = {
      "app.kubernetes.io/name"       = "fatto-catalog"
      "app.kubernetes.io/component"  = "config"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    "endpoint"   = "minio:9000"
    "access-key" = var.minio_root_user
    "secret-key" = random_password.minio_password.result
  }

  depends_on = [kubernetes_stateful_set.minio]
}

# Job to create default buckets
resource "kubernetes_job" "minio_bucket_init" {
  metadata {
    name      = "minio-bucket-init"
    namespace = kubernetes_namespace.fatto_dev.metadata[0].name
  }

  spec {
    template {
      metadata {
        name = "minio-bucket-init"
      }
      spec {
        container {
          name  = "mc"
          image = "minio/mc:latest"
          command = [
            "sh", "-c",
            <<-EOT
              mc alias set local http://minio:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD
              mc mb --ignore-existing local/fatto-attachments
              mc mb --ignore-existing local/fatto-cad-files
              mc mb --ignore-existing local/fatto-exports
              echo "Buckets created successfully"
            EOT
          ]
          env {
            name  = "MINIO_ROOT_USER"
            value = var.minio_root_user
          }
          env {
            name  = "MINIO_ROOT_PASSWORD"
            value = random_password.minio_password.result
          }
        }
        restart_policy = "Never"
      }
    }
    backoff_limit = 5
  }

  wait_for_completion = true
  timeouts {
    create = "5m"
  }

  depends_on = [kubernetes_stateful_set.minio, kubernetes_service.minio]
}
