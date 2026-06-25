# -----------------------------------------------------------------------------
# GENERATED PASSWORDS FOR PLATFORM SERVICES
#
# These belong to platform-owned services that live in their own namespaces:
#   - minio_password    → MinIO StatefulSet + zot + minio-admin handoff secret
#   - keycloak_password → Keycloak StatefulSet
#   - grafana_password  → kube-prometheus-stack (Grafana)
#
# The tenant namespace and its resources (redis, tenant credentials)
# are owned by the tenant repo. Tenants read the MinIO admin
# password via the minio-admin Secret (see minio.tf).
# -----------------------------------------------------------------------------

resource "random_password" "minio_password" {
  length  = 24
  special = false
}

resource "random_password" "keycloak_password" {
  length  = 24
  special = false
}

resource "random_password" "grafana_password" {
  length  = 24
  special = false
}
