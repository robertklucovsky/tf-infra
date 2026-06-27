# Development environment configuration — tf-platform

kubeconfig_path    = "~/.kube/config"
kubeconfig_context = "k8s"

# Infrastructure host
server_host = "172.16.1.11"

# PostgreSQL (CNPG — in-cluster via NodePort)
postgres_host               = "172.16.1.11"
postgres_port               = 30432
postgres_superuser          = "postgres"
postgres_superuser_password = "REPLACE_ME"

# TLS / cert-manager
letsencrypt_email  = "REPLACE_ME"
digitalocean_token = "REPLACE_ME"

# SonarQube — disabled (was deployed for AI agent code review)
sonarqube_enabled = false
