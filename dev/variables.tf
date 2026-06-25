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
  description = "PostgreSQL superuser password"
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
  default     = "100Gi"
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

# -----------------------------------------------------------------------------
# ACTIONS RUNNER CONTROLLER (ARC)
# -----------------------------------------------------------------------------

variable "github_org" {
  description = "GitHub organization that runners register with"
  type        = string
  default     = "Fatto-ERP"
}

variable "github_app_id" {
  description = "GitHub App ID for ARC (from GitHub App settings)"
  type        = string
}

variable "github_app_installation_id" {
  description = "GitHub App installation ID for ARC"
  type        = string
}

variable "github_app_private_key" {
  description = "GitHub App private key PEM contents (sensitive)"
  type        = string
  sensitive   = true
}

variable "arc_controller_chart_version" {
  description = "gha-runner-scale-set-controller OCI chart version"
  type        = string
  default     = "0.9.3"
}

variable "arc_runner_chart_version" {
  description = "gha-runner-scale-set OCI chart version (must match controller)"
  type        = string
  default     = "0.9.3"
}

variable "arc_runner_max_replicas" {
  description = "Max concurrent runner pods"
  type        = number
  default     = 3
}

variable "arc_runner_min_replicas" {
  description = "Min idle runner pods (0 = scale to zero when no jobs)"
  type        = number
  default     = 0
}

# -----------------------------------------------------------------------------
# ZOT (Container registry, MinIO-backed)
# -----------------------------------------------------------------------------

variable "zot_chart_version" {
  description = "Zot Helm chart version"
  type        = string
  default     = "0.1.66"
}

variable "zot_admin_user" {
  description = "Zot admin username"
  type        = string
  default     = "admin"
}

# -----------------------------------------------------------------------------
# SONATYPE NEXUS OSS
# -----------------------------------------------------------------------------

# NOTE: Plan defaulted to 73.0.0 but the Sonatype Helm repo only publishes up
# to 64.2.0 for the nexus-repository-manager chart (the chart was deprecated
# in favor of nxrm-ha, which is HA-focused / overkill here). 64.2.0 is the
# latest published version of the simple single-instance chart.
variable "nexus_chart_version" {
  description = "Sonatype Nexus Repository Manager Helm chart version"
  type        = string
  default     = "64.2.0"
}

variable "nexus_storage_size" {
  description = "Nexus PVC storage size"
  type        = string
  default     = "20Gi"
}

# Nexus application (image) version is decoupled from the Helm chart version.
# The chart 64.2.0 ships sonatype/nexus3:3.64.0 by default, which carries a
# critical security issue; override the image tag to >= 3.68.1.
variable "nexus_image_tag" {
  description = "sonatype/nexus3 image tag (Nexus application version)"
  type        = string
  default     = "3.68.1"
}
