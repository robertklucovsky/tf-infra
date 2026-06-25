# -----------------------------------------------------------------------------
# ACTIONS RUNNER CONTROLLER (ARC) — controller only
#
# The shared ARC controller + CRDs (gha-runner-scale-set-controller). Runner
# scale sets are tenant-owned: each tenant repo deploys its own scale set
# (registering with the tenant's GitHub org) against this shared controller.
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "arc_system" {
  metadata {
    name = "arc-system"
    labels = {
      "app.kubernetes.io/name"       = "arc-system"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "arc_controller" {
  name       = "arc-controller"
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set-controller"
  version    = var.arc_controller_chart_version
  namespace  = kubernetes_namespace.arc_system.metadata[0].name
}
