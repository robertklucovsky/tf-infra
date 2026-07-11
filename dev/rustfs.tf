# -----------------------------------------------------------------------------
# RUSTFS — S3-compatible object storage (MinIO replacement)
#
# MinIO community edition is archived (Feb 2026) with unpatched CVEs and a
# stripped console (no OIDC login since RELEASE.2025-05-24). RustFS is its
# Apache-2.0 successor with MinIO-parity claim-based OIDC (claim_name=policy),
# STS AssumeRoleWithWebIdentity, and an embedded console WITH SSO — served on
# the same port as the S3 API under /rustfs/console/.
#
# OIDC is configured via env vars here (RustFS model), pointing at the
# fatto-aac Keycloak realm's `minio` client — the same client the tenant repo
# owns and whose group→policy mapper drives authorization. This replaces the
# tenant-registered `minio_iam_idp_openid` model used with MinIO.
#
# Migration status: MinIO (minio.tf) keeps running until data + IAM are
# migrated and RustFS is verified; then s3.klucovsky.com is repointed and
# MinIO decommissioned. Tenant repos must re-point their `minio` provider to
# the RustFS endpoint; TF-managed IAM resources are frozen until a RustFS
# Terraform provider exists (IAM is migrated via export/import + runtime API).
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "rustfs" {
  metadata {
    name = "rustfs"
    labels = {
      "app.kubernetes.io/name"       = "rustfs"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# Admin credentials handoff for tenant repos (same pattern as minio-admin).
resource "kubernetes_secret" "rustfs_admin" {
  metadata {
    name      = "rustfs-admin"
    namespace = kubernetes_namespace.rustfs.metadata[0].name

    labels = {
      "app.kubernetes.io/name"       = "rustfs"
      "app.kubernetes.io/component"  = "admin-credentials"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    username = "rustfs-admin"
    password = random_password.rustfs_password.result
    url      = "http://rustfs.rustfs.svc.cluster.local:9000"
  }
}

resource "kubernetes_secret" "rustfs_env" {
  metadata {
    name      = "rustfs-env"
    namespace = kubernetes_namespace.rustfs.metadata[0].name

    labels = {
      "app.kubernetes.io/name"       = "rustfs"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    RUSTFS_ACCESS_KEY = "rustfs-admin"
    RUSTFS_SECRET_KEY = random_password.rustfs_password.result

    # OIDC — fatto-aac realm, client `minio` (tenant-owned; its group→policy
    # mapper emits the multi-valued `policy` claim RustFS unions).
    RUSTFS_IDENTITY_OPENID_ENABLE        = "on"
    RUSTFS_IDENTITY_OPENID_CONFIG_URL    = "https://auth.klucovsky.com/realms/fatto-aac/.well-known/openid-configuration"
    RUSTFS_IDENTITY_OPENID_CLIENT_ID     = "minio"
    RUSTFS_IDENTITY_OPENID_CLIENT_SECRET = var.rustfs_oidc_client_secret
    RUSTFS_IDENTITY_OPENID_CLAIM_NAME    = "policy"
    RUSTFS_IDENTITY_OPENID_SCOPES        = "openid"
    # Keycloak access tokens carry aud=["minio","account"]; unlike MinIO,
    # RustFS rejects untrusted extra audiences unless whitelisted here.
    RUSTFS_IDENTITY_OPENID_OTHER_AUDIENCES = "account"
    RUSTFS_IDENTITY_OPENID_DISPLAY_NAME    = "FATTO-AAC"
    RUSTFS_IDENTITY_OPENID_REDIRECT_URI    = "https://s3.klucovsky.com/rustfs/admin/v3/oidc/callback/default"
  }
}

resource "kubernetes_stateful_set" "rustfs" {
  metadata {
    name      = "rustfs"
    namespace = kubernetes_namespace.rustfs.metadata[0].name
    labels = {
      "app.kubernetes.io/name"    = "rustfs"
      "app.kubernetes.io/part-of" = "platform"
    }
  }

  spec {
    service_name = "rustfs"
    replicas     = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "rustfs"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "rustfs"
        }
      }

      spec {
        # Image runs as uid 10001 (rustfs); fsGroup makes the PVC writable.
        security_context {
          run_as_user  = 10001
          run_as_group = 10001
          fs_group     = 10001
        }

        container {
          name = "rustfs"
          # 1.0.0-beta.8 (2026-06-10), pinned by digest (linux/amd64+arm64)
          image = "rustfs/rustfs:1.0.0-beta.8@sha256:fa19210ac4697c79d7ccca1ec9b0eb91aebacc6691991ffb14014bb3c67e6cc3"

          env {
            name  = "RUSTFS_ADDRESS"
            value = ":9000"
          }
          env {
            name  = "RUSTFS_VOLUMES"
            value = "/data"
          }
          env {
            name  = "RUSTFS_CONSOLE_ENABLE"
            value = "true"
          }
          # The console listener runs the FULL server (S3 + admin + console
          # static UI) on its own port; the :9000 listener has console off.
          # The gateway therefore routes s3.klucovsky.com to :9001.
          env {
            name  = "RUSTFS_CONSOLE_ADDRESS"
            value = ":9001"
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.rustfs_env.metadata[0].name
            }
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
              cpu    = "1"
              memory = "1Gi"
            }
          }

          volume_mount {
            name       = "rustfs-data"
            mount_path = "/data"
          }

          readiness_probe {
            http_get {
              path = "/health/ready"
              port = 9000
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/health/live"
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
        name = "rustfs-data"
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = var.storage_class
        resources {
          requests = {
            storage = var.rustfs_storage_size
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.rustfs]
}

resource "kubernetes_service" "rustfs" {
  metadata {
    name      = "rustfs"
    namespace = kubernetes_namespace.rustfs.metadata[0].name
    labels = {
      "app.kubernetes.io/name" = "rustfs"
    }
  }

  spec {
    type = "NodePort"

    selector = {
      "app.kubernetes.io/name" = "rustfs"
    }

    # S3 + admin API (no console UI)
    port {
      port        = 9000
      target_port = 9000
      node_port   = 30910
      name        = "api"
    }

    # Full server incl. console UI (/rustfs/console/) — gateway target
    port {
      port        = 9001
      target_port = 9001
      node_port   = 30911
      name        = "console"
    }
  }
}
