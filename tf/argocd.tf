# -----------------------------------------------------------------------------
# ARGOCD — GitOps Continuous Delivery
#
# Manages application deployments via Kustomize overlays.
# UI accessible at argocd.klucovsky.com (VPN only).
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# NAMESPACE
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"

    labels = {
      "app.kubernetes.io/name"       = "argocd"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# ARGOCD HELM RELEASE
# -----------------------------------------------------------------------------

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      # Server configuration
      server = {
        # Disable TLS on ArgoCD side (Gateway handles TLS termination)
        extraArgs = ["--insecure"]

        ingress = {
          enabled = false
        }
      }

      # Disable dex (use built-in auth for now)
      dex = {
        enabled = false
      }

      # Resource limits
      controller = {
        resources = {
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }
      }

      repoServer = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "256Mi"
          }
        }
      }
    })
  ]
}

