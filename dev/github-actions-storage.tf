# -----------------------------------------------------------------------------
# GITHUB ACTIONS STORAGE — MinIO bucket for workflow cache + artifacts
#
# Consumed by GitHub Actions workflows via tespkg/actions-cache (cache) and
# direct `mc cp` (artifacts). Workflow YAML changes live in consumer repos.
#
# The bucket-init Job uses random_password.minio_password directly rather than
# a secretRef, because cross-namespace secret refs aren't supported and the
# fatto-credentials secret lives in fatto-erp-dev (same gotcha as zot.tf).
# -----------------------------------------------------------------------------

resource "kubernetes_job_v1" "github_actions_bucket_init" {
  metadata {
    name      = "github-actions-bucket-init"
    namespace = var.namespace
  }

  spec {
    backoff_limit = 3

    template {
      metadata {
        labels = { job = "github-actions-bucket-init" }
      }
      spec {
        restart_policy = "OnFailure"

        container {
          name    = "mc"
          image   = "minio/mc:latest"
          command = ["sh", "-c"]
          args = [
            <<-EOT
              set -e
              mc alias set local http://minio.${var.namespace}.svc.cluster.local:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
              mc mb --ignore-existing local/github-actions
              echo "github-actions bucket ready"
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
      }
    }

    ttl_seconds_after_finished = 300
  }

  wait_for_completion = true
  timeouts {
    create = "5m"
  }

  depends_on = [kubernetes_secret.fatto_credentials]
}
