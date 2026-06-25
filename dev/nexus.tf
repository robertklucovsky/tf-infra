# -----------------------------------------------------------------------------
# SONATYPE NEXUS OSS — multi-format package registry (npm, maven, generic)
#
# Initial admin password is auto-generated at /nexus-data/admin.password on
# first boot. We capture it via an in-cluster Job (using a Service Account
# with secret-write RBAC) after the Helm release is ready.
#
# NOTE on chart values (sonatype/nexus-repository-manager 64.2.0):
#   - The chart's `service` block does NOT support a `port` field; the listen
#     port is fixed by `nexus.nexusPort` (default 8081) and the rendered
#     Service always exposes 8081. We still pass `service.port = 8081` for
#     documentation purposes (silently ignored by the chart).
#   - The chart names its Service `<release-name>-nexus-repository-manager`,
#     so with release `nexus` the service is `nexus-nexus-repository-manager`.
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "nexus" {
  metadata {
    name = "nexus"
    labels = {
      "app.kubernetes.io/name"       = "nexus"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "nexus_data" {
  metadata {
    name      = "nexus-data"
    namespace = kubernetes_namespace.nexus.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class
    resources {
      requests = {
        storage = var.nexus_storage_size
      }
    }
  }

  # csi-rawfile-default storage class is WaitForFirstConsumer; PVC stays
  # Pending until a pod mounts it. Don't block Terraform on binding.
  wait_until_bound = false
}

resource "helm_release" "nexus" {
  name       = "nexus"
  repository = "https://sonatype.github.io/helm3-charts/"
  chart      = "nexus-repository-manager"
  version    = var.nexus_chart_version
  namespace  = kubernetes_namespace.nexus.metadata[0].name

  values = [
    yamlencode({
      # Override the chart's default image tag (3.64.0) to a version that
      # fixes the critical security issue. App version is decoupled from the
      # pinned chart version (64.2.0 is the latest published simple chart).
      image = {
        repository = "sonatype/nexus3"
        tag        = var.nexus_image_tag
      }
      nexus = {
        # Node is small (4 cpu) and already 88% requested by other workloads,
        # so keep cpu/memory requests modest. Limits are higher to allow
        # Nexus to use spare capacity during burst.
        resources = {
          requests = { cpu = "200m", memory = "1Gi" }
          limits   = { cpu = "2000m", memory = "3Gi" }
        }
      }
      persistence = {
        enabled       = true
        existingClaim = kubernetes_persistent_volume_claim_v1.nexus_data.metadata[0].name
      }
      service = {
        type = "ClusterIP"
        # Chart ignores service.port (port is fixed at nexus.nexusPort=8081);
        # kept here for self-documentation.
        port = 8081
      }
      ingress = {
        enabled = false
      }
    })
  ]

  depends_on = [kubernetes_persistent_volume_claim_v1.nexus_data]
  # Nexus first boot is slow (Java + plugin init); 20 min ceiling.
  timeout = 1200
}

# -----------------------------------------------------------------------------
# RBAC for the admin-password-capture Job to create secrets and exec into pod
# -----------------------------------------------------------------------------

resource "kubernetes_service_account_v1" "nexus_init" {
  metadata {
    name      = "nexus-init"
    namespace = kubernetes_namespace.nexus.metadata[0].name
  }
}

resource "kubernetes_role_v1" "nexus_init" {
  metadata {
    name      = "nexus-init"
    namespace = kubernetes_namespace.nexus.metadata[0].name
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["create", "patch", "get", "update"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "pods/exec"]
    verbs      = ["get", "list", "create"]
  }
}

resource "kubernetes_role_binding_v1" "nexus_init" {
  metadata {
    name      = "nexus-init"
    namespace = kubernetes_namespace.nexus.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.nexus_init.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.nexus_init.metadata[0].name
    namespace = kubernetes_namespace.nexus.metadata[0].name
  }
}

# -----------------------------------------------------------------------------
# Admin password capture Job
# -----------------------------------------------------------------------------

resource "kubernetes_job_v1" "nexus_admin_capture" {
  metadata {
    name      = "nexus-admin-capture"
    namespace = kubernetes_namespace.nexus.metadata[0].name
  }

  spec {
    backoff_limit = 3

    template {
      metadata {
        labels = { job = "nexus-admin-capture" }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.nexus_init.metadata[0].name
        restart_policy       = "OnFailure"

        container {
          name    = "capture"
          image   = "bitnami/kubectl:latest"
          command = ["sh", "-c"]
          args = [
            <<-EOT
              set -e
              POD=""
              for i in $(seq 1 90); do
                POD=$(kubectl get pods -n nexus -l app.kubernetes.io/name=nexus-repository-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
                if [ -n "$POD" ]; then
                  READY=$(kubectl get pod "$POD" -n nexus -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
                  if [ "$READY" = "true" ]; then
                    if kubectl exec -n nexus "$POD" -- test -f /nexus-data/admin.password 2>/dev/null; then
                      break
                    fi
                  fi
                fi
                echo "Waiting for Nexus pod and admin.password... ($i/90)"
                sleep 10
              done

              if [ -z "$POD" ]; then
                echo "ERROR: Nexus pod not found"
                exit 1
              fi

              PASSWORD=$(kubectl exec -n nexus "$POD" -- cat /nexus-data/admin.password)
              if [ -z "$PASSWORD" ]; then
                echo "ERROR: admin.password is empty"
                exit 1
              fi

              kubectl create secret generic nexus-credentials \
                -n nexus \
                --from-literal=username=admin \
                --from-literal=password="$PASSWORD" \
                --dry-run=client -o yaml | kubectl apply -f -

              echo "nexus-credentials secret created/updated"
            EOT
          ]
        }
      }
    }

    ttl_seconds_after_finished = 600
  }

  wait_for_completion = true
  timeouts {
    create = "30m"
  }

  depends_on = [
    helm_release.nexus,
    kubernetes_role_binding_v1.nexus_init,
  ]
}

# Read the secret back so Terraform can expose it via outputs
data "kubernetes_secret" "nexus_credentials" {
  metadata {
    name      = "nexus-credentials"
    namespace = kubernetes_namespace.nexus.metadata[0].name
  }
  depends_on = [kubernetes_job_v1.nexus_admin_capture]
}

