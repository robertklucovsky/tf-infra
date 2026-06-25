# -----------------------------------------------------------------------------
# ZOT — OCI container registry, MinIO-backed
#
# Storage backend: platform's existing MinIO via S3 driver.
# Authentication: htpasswd with a single admin user (bcrypt hash via Terraform's
# bcrypt() function — no external Job needed).
# Bucket `zot-storage` is created up-front by a one-shot Job using mc.
#
# NOTE on chart value names (zot/zot 0.1.66): the chart does NOT have a
# top-level `secretMounts` key. To mount an externally-managed Secret (our
# htpasswd) we use `externalSecrets: [{ secretName, mountPath }]`. The Secret's
# data keys become files at `mountPath/<key>`.
#
# NOTE on bcrypt: terraform's bcrypt() is non-deterministic (fresh salt each
# run), which would cause perpetual drift on the htpasswd secret. We add
# `lifecycle { ignore_changes = [data] }` so the secret is only created once.
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "zot" {
  metadata {
    name = "zot"
    labels = {
      "app.kubernetes.io/name"       = "zot"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# Admin credentials
# -----------------------------------------------------------------------------

resource "random_password" "zot_admin" {
  length  = 24
  special = false
}

# Plain credentials (stored for reference / dotenv use)
resource "kubernetes_secret" "zot_admin_plain" {
  metadata {
    name      = "zot-admin-plain"
    namespace = kubernetes_namespace.zot.metadata[0].name
  }
  data = {
    username = var.zot_admin_user
    password = random_password.zot_admin.result
  }
}

# htpasswd secret — bcrypt() produces $2a$... format which Zot accepts.
# bcrypt() is non-deterministic; ignore_changes pins the data after first create.
resource "kubernetes_secret" "zot_htpasswd" {
  metadata {
    name      = "zot-htpasswd"
    namespace = kubernetes_namespace.zot.metadata[0].name
  }
  data = {
    htpasswd = "${var.zot_admin_user}:${bcrypt(random_password.zot_admin.result, 10)}"
  }

  lifecycle {
    ignore_changes = [data]
  }
}

# -----------------------------------------------------------------------------
# MinIO bucket creation — one-shot Job using mc
# -----------------------------------------------------------------------------

resource "kubernetes_job_v1" "zot_bucket_init" {
  metadata {
    name      = "zot-bucket-init"
    namespace = kubernetes_namespace.zot.metadata[0].name
  }

  spec {
    backoff_limit = 3

    template {
      metadata {
        labels = { job = "zot-bucket-init" }
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
              mc alias set local http://minio.${kubernetes_namespace.minio.metadata[0].name}.svc.cluster.local:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
              mc mb --ignore-existing local/zot-storage
              echo "zot-storage bucket ready"
            EOT
          ]

          # NOTE: the tenant credentials Secret lives in the tenant namespace
          # and Kubernetes Secrets are namespace-scoped, so we source the MinIO
          # password directly from the `random_password.minio_password` resource
          # (the same way the Zot Helm release does below).
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

  depends_on = [
    random_password.minio_password,
  ]
}

# -----------------------------------------------------------------------------
# Zot Helm release
# -----------------------------------------------------------------------------

resource "helm_release" "zot" {
  name       = "zot"
  repository = "https://zotregistry.dev/helm-charts"
  chart      = "zot"
  version    = var.zot_chart_version
  namespace  = kubernetes_namespace.zot.metadata[0].name

  values = [
    yamlencode({
      service = {
        type = "ClusterIP"
        port = 5000
      }
      ingress = {
        enabled = false
      }
      # Kubernetes probes hit /v2/ which requires auth (we have htpasswd
      # enabled). The chart turns `authHeader` into a Basic Authorization
      # header for the liveness/readiness/startup probes.
      authHeader  = base64encode("${var.zot_admin_user}:${random_password.zot_admin.result}")
      mountConfig = true
      configFiles = {
        "config.json" = jsonencode({
          distSpecVersion = "1.1.1"
          storage = {
            rootDirectory = "/var/lib/registry"
            # dedupe requires a cacheDriver/remote DB when using a remote
            # storageDriver (S3). Disabled to keep this stack self-contained.
            dedupe = false
            storageDriver = {
              name           = "s3"
              rootdirectory  = "/zot"
              region         = "us-east-1"
              regionendpoint = "http://minio.${kubernetes_namespace.minio.metadata[0].name}.svc.cluster.local:9000"
              bucket         = "zot-storage"
              forcepathstyle = true
              secure         = false
              skipverify     = true
              accesskey      = var.minio_root_user
              secretkey      = random_password.minio_password.result
            }
          }
          http = {
            address = "0.0.0.0"
            port    = "5000"
            auth = {
              htpasswd = {
                path = "/etc/zot-htpasswd/htpasswd"
              }
            }
          }
          log = {
            level = "info"
          }
          # Web UI (zui). The `ui` extension needs `search` enabled to power
          # its image listing. The full zot image (zot-linux-amd64, not the
          # -minimal variant) ships both extensions.
          extensions = {
            search = { enable = true }
            ui     = { enable = true }
          }
        })
      }
      externalSecrets = [
        {
          secretName = "zot-htpasswd"
          mountPath  = "/etc/zot-htpasswd"
        }
      ]
    })
  ]

  depends_on = [
    kubernetes_secret.zot_htpasswd,
    kubernetes_job_v1.zot_bucket_init,
  ]
}

