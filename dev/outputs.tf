# -----------------------------------------------------------------------------
# PLATFORM OUTPUTS
# Cross-repo handoff happens via Kubernetes secrets, not Terraform outputs.
# These outputs exist for human inspection.
# -----------------------------------------------------------------------------

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

output "keycloak_url" { value = "https://auth.klucovsky.com" }
output "mailpit_url" { value = "https://mail.klucovsky.com" }
output "minio_console_url" { value = "https://s3.klucovsky.com" }
output "grafana_url" { value = "https://grafana.klucovsky.com" }
output "prometheus_url" { value = "https://prometheus.klucovsky.com" }
output "alertmanager_url" { value = "https://alertmanager.klucovsky.com" }
output "sonarqube_url" { value = "https://sonar.klucovsky.com" }
output "pgadmin_url" { value = "https://db.klucovsky.com" }
output "argocd_url" { value = "https://argocd.klucovsky.com" }

# -----------------------------------------------------------------------------
# ZOT
# -----------------------------------------------------------------------------

output "registry_url" {
  description = "Zot container registry URL"
  value       = "https://registry.klucovsky.com"
}

output "zot_admin_user" {
  description = "Zot admin username"
  value       = var.zot_admin_user
}

output "zot_admin_password" {
  description = "Zot admin password"
  value       = random_password.zot_admin.result
  sensitive   = true
}

# -----------------------------------------------------------------------------
# NEXUS
# -----------------------------------------------------------------------------

output "nexus_url" {
  description = "Nexus Repository Manager URL"
  value       = "https://nexus.klucovsky.com"
}

output "nexus_admin_credentials" {
  description = "Nexus admin login (rotate in UI on first login)"
  value = {
    username = data.kubernetes_secret.nexus_credentials.data["username"]
    password = data.kubernetes_secret.nexus_credentials.data["password"]
  }
  sensitive = true
}
