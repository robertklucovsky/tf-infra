# -----------------------------------------------------------------------------
# GENERATED PASSWORDS FOR PLATFORM SERVICES
#
# These belong to platform-owned services that live in their own namespaces:
#   - keycloak_password → Keycloak StatefulSet
#   - grafana_password  → kube-prometheus-stack (Grafana)
#   - rustfs_password   → RustFS StatefulSet + rustfs-admin handoff secret
#
# The tenant namespace and its resources (redis, tenant credentials)
# are owned by the tenant repo. Tenants read the RustFS admin
# password via the rustfs-admin Secret (see rustfs.tf).
# -----------------------------------------------------------------------------

resource "random_password" "keycloak_password" {
  length  = 24
  special = false
}

resource "random_password" "grafana_password" {
  length  = 24
  special = false
}

resource "random_password" "rustfs_password" {
  length  = 24
  special = false
}
