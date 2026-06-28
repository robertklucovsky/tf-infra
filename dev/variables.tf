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
  default     = "v1.20.3"
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
  default     = "0.28.3"
}

variable "cnpg_image" {
  description = "CNPG operand image — custom build with pgvector + Apache AGE (tag must keep the 17 prefix; never latest)"
  type        = string
  default     = "ghcr.io/robertklucovsky/cnpg-postgresql:17-bookworm-ext.1"
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

variable "sonarqube_enabled" {
  description = "Whether to deploy SonarQube (namespace, DB, Helm release, route)"
  type        = bool
  default     = false
}

variable "sonarqube_version" {
  description = "SonarQube Helm chart version"
  type        = string
  default     = "2026.3.1"
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
  default     = "9.16"
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
  default     = "minio-admin"
}

variable "minio_oidc_projects" {
  description = <<-EOT
    MinIO OIDC providers, keyed by project. One Keycloak realm per entry,
    configured as a role-based provider (all users in a realm get the same
    role_policy). The client_secret is generated and published via the
    minio-oidc-<key> Secret in the minio namespace; the tenant repo reads it
    to create a matching Keycloak client. Set provider_enabled=true only after
    the realm + the role_policy's MinIO policies exist (see the design spec).
    Map keys must be lowercase alphanumerics and "-".
  EOT
  type = map(object({
    display_name     = string                    # SSO button label on the console login page
    realm            = string                    # Keycloak realm name -> builds config_url
    client_id        = optional(string, "minio") # must match the tenant's keycloak_openid_client
    role_policy      = string                    # comma-separated MinIO policy names for this realm's users
    scopes           = optional(string, "openid")
    provider_enabled = optional(bool, false)     # phase gate: render provider env only after realm+policies exist
  }))
  default = {}
  validation {
    condition     = alltrue([for k in keys(var.minio_oidc_projects) : can(regex("^[a-z0-9-]+$", k))])
    error_message = "Keys in minio_oidc_projects must contain only lowercase letters, digits, and hyphens (they are transformed into MinIO env-var suffixes)."
  }
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
  default     = "1.24.4"
}

variable "loki_chart_version" {
  description = "Grafana Loki Helm chart version"
  type        = string
  default     = "7.0.0"
}

variable "promtail_chart_version" {
  description = "Grafana Promtail Helm chart version"
  type        = string
  default     = "6.17.1"
}

variable "prometheus_stack_version" {
  description = "kube-prometheus-stack Helm chart version"
  type        = string
  default     = "87.2.1"
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
  default     = "10.0.0"
}

# -----------------------------------------------------------------------------
# ACTIONS RUNNER CONTROLLER (ARC)
# -----------------------------------------------------------------------------

variable "arc_controller_chart_version" {
  description = "gha-runner-scale-set-controller OCI chart version"
  type        = string
  default     = "0.14.2"
}

# -----------------------------------------------------------------------------
# ZOT (Container registry, MinIO-backed)
# -----------------------------------------------------------------------------

variable "zot_chart_version" {
  description = "Zot Helm chart version"
  type        = string
  default     = "0.1.118"
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
# The chart 64.2.0 ships sonatype/nexus3:3.64.0 by default; override the image
# tag to the latest 3.x. NOTE: the nexus-repository-manager chart is deprecated
# and pinned at 64.2.0, so verify the newer image still boots cleanly under this
# old chart on the next apply (fresh deploy initializes a new data dir).
variable "nexus_image_tag" {
  description = "sonatype/nexus3 image tag (Nexus application version)"
  type        = string
  default     = "3.93.2"
}
