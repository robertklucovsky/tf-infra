# -----------------------------------------------------------------------------
# PLATFORM OUTPUTS
# Cross-repo handoff happens via Kubernetes secrets, not Terraform outputs.
# These outputs exist for human inspection.
# -----------------------------------------------------------------------------

output "tenant_namespace" {
  description = "Tenant namespace created by platform"
  value       = kubernetes_namespace.fatto_dev.metadata[0].name
}

output "redis_password" {
  description = "Redis password (also stored in fatto-credentials secret)"
  value       = random_password.redis_password.result
  sensitive   = true
}

output "minio_credentials" {
  description = "MinIO access credentials"
  value = {
    access_key = var.minio_root_user
    secret_key = random_password.minio_password.result
  }
  sensitive = true
}

output "keycloak_admin_credentials" {
  description = "Keycloak admin login"
  value = {
    username = var.keycloak_admin_user
    password = random_password.keycloak_password.result
  }
  sensitive = true
}

output "grafana_credentials" {
  description = "Grafana admin login"
  value = {
    username = var.grafana_admin_user
    password = random_password.grafana_password.result
  }
  sensitive = true
}

output "pgadmin_credentials" {
  description = "pgAdmin admin login"
  value = {
    email    = var.pgadmin_email
    password = random_password.pgadmin_password.result
  }
  sensitive = true
}

# -----------------------------------------------------------------------------
# Web UI URLs (informational)
# -----------------------------------------------------------------------------

output "keycloak_url" { value = "https://auth.${var.domain}" }
output "mailpit_url" { value = "https://mail.${var.domain}" }
output "minio_console_url" { value = "https://minio.${var.domain}" }
output "grafana_url" { value = "https://grafana.klucovsky.com" }
output "prometheus_url" { value = "https://prometheus.klucovsky.com" }
output "alertmanager_url" { value = "https://alertmanager.klucovsky.com" }
output "sonarqube_url" { value = "https://sonar.klucovsky.com" }
output "pgadmin_url" { value = "https://db.klucovsky.com" }
output "argocd_url" { value = "https://argocd.klucovsky.com" }
