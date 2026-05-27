# -----------------------------------------------------------------------------
# CLOUDNATIVEPG — In-cluster PostgreSQL
#
# Replaces the external Docker Compose PostgreSQL (172.16.1.40).
# Provides a primary + replica cluster managed by the CNPG operator.
#
# Operator: Helm chart in cnpg-system namespace
# Cluster:  1 primary + 1 replica, 2Gi PVC, NodePort 30432
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# CNPG OPERATOR (Helm)
# -----------------------------------------------------------------------------

resource "helm_release" "cnpg_operator" {
  name             = "cnpg"
  repository       = "https://cloudnative-pg.github.io/charts"
  chart            = "cloudnative-pg"
  version          = var.cnpg_operator_version
  namespace        = "cnpg-system"
  create_namespace = true

  wait = true

  values = [
    yamlencode({
      monitoring = {
        podMonitorEnabled = true
      }
    })
  ]

  # PodMonitor CRD requires Prometheus CRDs to be installed first
  depends_on = [helm_release.prometheus_stack]
}

# -----------------------------------------------------------------------------
# CNPG SUPERUSER SECRET
# The CNPG cluster needs credentials for the postgres superuser
# -----------------------------------------------------------------------------

resource "kubernetes_secret" "cnpg_superuser" {
  metadata {
    name      = "cnpg-superuser"
    namespace = "cnpg-system"

    labels = {
      "cnpg.io/reload" = "true"
    }
  }

  data = {
    username = "postgres"
    password = var.postgres_superuser_password
  }

  depends_on = [helm_release.cnpg_operator]
}

# -----------------------------------------------------------------------------
# CNPG POSTGRESQL CLUSTER
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "cnpg_cluster" {
  yaml_body = <<-YAML
    apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    metadata:
      name: fatto-db
      namespace: cnpg-system
    spec:
      instances: ${var.cnpg_instances}
      imageName: ghcr.io/cloudnative-pg/postgresql:${var.cnpg_pg_version}

      bootstrap:
        initdb:
          database: postgres
          owner: postgres
          secret:
            name: ${kubernetes_secret.cnpg_superuser.metadata[0].name}

      superuserSecret:
        name: ${kubernetes_secret.cnpg_superuser.metadata[0].name}

      enableSuperuserAccess: true

      storage:
        size: ${var.cnpg_storage_size}
        storageClass: ${var.storage_class}

      postgresql:
        parameters:
          max_connections: "200"
          shared_buffers: "256MB"
          log_statement: "ddl"

      monitoring:
        enablePodMonitor: true

      resources:
        requests:
          memory: "512Mi"
          cpu: "250m"
        limits:
          memory: "1Gi"
          cpu: "1"
  YAML

  depends_on = [helm_release.cnpg_operator, kubernetes_secret.cnpg_superuser]
}

# -----------------------------------------------------------------------------
# NODEPORT SERVICE — Expose PostgreSQL for Terraform provider access
# The cyrilgdn/postgresql provider runs outside the cluster, so it needs
# a NodePort to reach the CNPG primary.
# -----------------------------------------------------------------------------

resource "kubernetes_service" "cnpg_nodeport" {
  metadata {
    name      = "fatto-db-nodeport"
    namespace = "cnpg-system"

    labels = {
      "app.kubernetes.io/name"       = "fatto-db-nodeport"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    type = "NodePort"

    selector = {
      "cnpg.io/cluster" = "fatto-db"
      "role"            = "primary"
    }

    port {
      name        = "postgresql"
      port        = 5432
      target_port = 5432
      node_port   = var.cnpg_nodeport
    }
  }

  depends_on = [kubectl_manifest.cnpg_cluster]
}

# -----------------------------------------------------------------------------
# READINESS CHECK — Wait for PostgreSQL to accept connections
# The CNPG cluster needs time to bootstrap. Terraform's postgresql provider
# will fail if it tries to connect before the primary pod is ready.
# -----------------------------------------------------------------------------

resource "terraform_data" "cnpg_ready" {
  depends_on = [kubernetes_service.cnpg_nodeport]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for CNPG PostgreSQL to accept connections on ${var.postgres_host}:${var.cnpg_nodeport}..."
      for i in $(seq 1 90); do
        if bash -c "echo > /dev/tcp/${var.postgres_host}/${var.cnpg_nodeport}" 2>/dev/null; then
          echo "PostgreSQL is ready!"
          exit 0
        fi
        echo "Attempt $i/90 — not ready, waiting 2s..."
        sleep 2
      done
      echo "ERROR: PostgreSQL did not become ready in 180s"
      exit 1
    EOT
  }
}
