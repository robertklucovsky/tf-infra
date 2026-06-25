# Shared Platform Infrastructure
# Terraform configuration for shared K8s platform (Canonical K8s)

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.25"
    }
    nexus = {
      source  = "datadrivers/nexus"
      version = "~> 2.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

# -----------------------------------------------------------------------------
# PROVIDERS
# -----------------------------------------------------------------------------

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kubeconfig_context
  }
}

provider "kubectl" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}

provider "postgresql" {
  host     = var.postgres_host
  port     = var.postgres_port
  username = var.postgres_superuser
  password = var.postgres_superuser_password
  sslmode  = "disable"
  database = "postgres"
}

# Nexus provider — manages npm repositories. Connects to Nexus via its public
# hostname (resolves to the gateway on the LAN where Terraform runs). Admin
# creds are read from the nexus-credentials Secret captured in nexus.tf.
provider "nexus" {
  url      = "https://nexus.klucovsky.com"
  username = data.kubernetes_secret.nexus_credentials.data["username"]
  password = data.kubernetes_secret.nexus_credentials.data["password"]
  insecure = false
}
