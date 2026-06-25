# -----------------------------------------------------------------------------
# ACTIONS RUNNER CONTROLLER (ARC)
#
# Two Helm releases:
#   1. arc-system/arc-controller — the controller + CRDs
#   2. arc-runners/fatto-runners — a runner scale set registering with GitHub org
#
# Uses the new GitHub-blessed ARC (gha-runner-scale-set), not the legacy
# actions.summerwind.dev CRDs.
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

resource "kubernetes_namespace" "arc_runners" {
  metadata {
    name = "arc-runners"
    labels = {
      "app.kubernetes.io/name"       = "arc-runners"
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

resource "kubernetes_secret" "github_app" {
  metadata {
    name      = "github-app-secret"
    namespace = kubernetes_namespace.arc_runners.metadata[0].name
  }

  data = {
    github_app_id              = var.github_app_id
    github_app_installation_id = var.github_app_installation_id
    github_app_private_key     = var.github_app_private_key
  }
}

resource "helm_release" "arc_runners" {
  name       = "fatto-runners"
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set"
  version    = var.arc_runner_chart_version
  namespace  = kubernetes_namespace.arc_runners.metadata[0].name

  values = [
    yamlencode({
      githubConfigUrl    = "https://github.com/${var.github_org}"
      githubConfigSecret = kubernetes_secret.github_app.metadata[0].name
      runnerScaleSetName = "fatto-erp"
      minRunners         = var.arc_runner_min_replicas
      maxRunners         = var.arc_runner_max_replicas

      # Docker-in-Docker: build workflows use docker/buildx, which needs a
      # Docker daemon. dind adds a privileged dind sidecar to each runner pod
      # and points DOCKER_HOST at it.
      containerMode = {
        type = "dind"
      }
    })
  ]

  depends_on = [
    helm_release.arc_controller,
    kubernetes_secret.github_app
  ]
}
