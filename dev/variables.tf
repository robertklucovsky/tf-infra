# -----------------------------------------------------------------------------
# GENERAL VARIABLES
# -----------------------------------------------------------------------------

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "Kubernetes context to use"
  type        = string
  default     = "k8s"
}

variable "namespace" {
  description = "Kubernetes namespace for FATTO dev environment (tenant)"
  type        = string
  default     = "fatto-erp-dev"
}

variable "domain" {
  description = "Base domain for dev environment gateway routing"
  type        = string
  default     = "dev.fatto.online"
}

# -----------------------------------------------------------------------------
# KUBERNETES STORAGE
# -----------------------------------------------------------------------------

variable "storage_class" {
  description = "Kubernetes StorageClass name"
  type        = string
  default     = "csi-rawfile-default"
}

variable "server_host" {
  description = "Infrastructure server IP address (K8s node)"
  type        = string
  default     = "172.16.1.11"
}

# -----------------------------------------------------------------------------
# CERT-MANAGER
# -----------------------------------------------------------------------------

variable "cert_manager_version" {
  description = "cert-manager Helm chart version"
  type        = string
  default     = "v1.19.3"
}

variable "digitalocean_token" {
  description = "DigitalOcean API token for DNS-01 challenge"
  type        = string
  sensitive   = true
}

variable "letsencrypt_email" {
  description = "Email for Let's Encrypt certificate registration"
  type        = string
}

variable "letsencrypt_staging" {
  description = "Use Let's Encrypt staging server (true) or production (false)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# POSTGRESQL / CNPG VARIABLES
# -----------------------------------------------------------------------------

variable "postgres_host" {
  description = "PostgreSQL host for connectivity checks during CNPG bootstrap (NodePort on K8s node)"
  type        = string
  default     = "172.16.1.11"
}

variable "postgres_port" {
  description = "PostgreSQL NodePort"
  type        = number
  default     = 30432
}

variable "postgres_superuser" {
  description = "PostgreSQL superuser username"
  type        = string
  default     = "postgres"
}

variable "postgres_superuser_password" {
  description = "PostgreSQL superuser password (stored into fatto-credentials secret)"
  type        = string
  sensitive   = true
}

variable "cnpg_operator_version" {
  description = "CloudNativePG operator Helm chart version"
  type        = string
  default     = "0.27.0"
}

variable "cnpg_pg_version" {
  description = "PostgreSQL version for CNPG cluster"
  type        = string
  default     = "17-bookworm"
}

variable "cnpg_instances" {
  description = "Number of PostgreSQL instances (1 primary + N-1 replicas)"
  type        = number
  default     = 2
}

variable "cnpg_storage_size" {
  description = "PVC storage size per CNPG instance"
  type        = string
  default     = "5Gi"
}

variable "cnpg_nodeport" {
  description = "NodePort for CNPG primary"
  type        = number
  default     = 30432
}

# -----------------------------------------------------------------------------
# SONARQUBE
# -----------------------------------------------------------------------------

variable "sonarqube_version" {
  description = "SonarQube Helm chart version"
  type        = string
  default     = "2026.1.0"
}

variable "sonarqube_plugins" {
  description = "List of SonarQube plugins to install"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# PGADMIN
# -----------------------------------------------------------------------------

variable "pgadmin_version" {
  description = "pgAdmin Docker image tag"
  type        = string
  default     = "9.12"
}

variable "pgadmin_email" {
  description = "pgAdmin default admin email"
  type        = string
  default     = "admin@klucovsky.com"
}

# -----------------------------------------------------------------------------
# REDIS
# -----------------------------------------------------------------------------

variable "redis_version" {
  description = "Redis version"
  type        = string
  default     = "8.4"
}

variable "redis_storage_size" {
  description = "Redis PVC storage size"
  type        = string
  default     = "1Gi"
}

# -----------------------------------------------------------------------------
# MINIO
# -----------------------------------------------------------------------------

variable "minio_storage_size" {
  description = "MinIO PVC storage size"
  type        = string
  default     = "10Gi"
}

variable "minio_root_user" {
  description = "MinIO root user"
  type        = string
  default     = "fatto-admin"
}

# -----------------------------------------------------------------------------
# KEYCLOAK
# -----------------------------------------------------------------------------

variable "keycloak_admin_user" {
  description = "Keycloak admin username"
  type        = string
  default     = "admin"
}

# -----------------------------------------------------------------------------
# OBSERVABILITY
# -----------------------------------------------------------------------------

variable "tempo_chart_version" {
  description = "Grafana Tempo Helm chart version"
  type        = string
  default     = "1.24.1"
}

variable "loki_chart_version" {
  description = "Grafana Loki Helm chart version"
  type        = string
  default     = "6.53.0"
}

variable "promtail_chart_version" {
  description = "Grafana Promtail Helm chart version"
  type        = string
  default     = "6.17.1"
}

variable "prometheus_stack_version" {
  description = "kube-prometheus-stack Helm chart version"
  type        = string
  default     = "81.6.9"
}

variable "grafana_admin_user" {
  description = "Grafana admin username"
  type        = string
  default     = "admin"
}

# -----------------------------------------------------------------------------
# ARGOCD
# -----------------------------------------------------------------------------

variable "argocd_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "9.4.2"
}
