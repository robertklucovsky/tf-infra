# -----------------------------------------------------------------------------
# CERT-MANAGER — TLS Certificates
#
# Uses Let's Encrypt with DigitalOcean DNS-01 challenge for wildcard certs.
# Requires DO_AUTH_TOKEN for DNS record management.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# CERT-MANAGER HELM RELEASE
# Canonical K8s doesn't include cert-manager — install it via Helm
# -----------------------------------------------------------------------------

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_version
  namespace        = "cert-manager"
  create_namespace = true

  set {
    name  = "crds.enabled"
    value = "true"
  }
}

# -----------------------------------------------------------------------------
# DIGITALOCEAN API TOKEN SECRET
# -----------------------------------------------------------------------------

resource "kubernetes_secret" "digitalocean_dns" {
  metadata {
    name      = "digitalocean-dns"
    namespace = "cert-manager"
  }

  data = {
    access-token = var.digitalocean_token
  }

  depends_on = [helm_release.cert_manager]
}

# -----------------------------------------------------------------------------
# CLUSTER ISSUER — Let's Encrypt + DigitalOcean DNS-01
# -----------------------------------------------------------------------------

locals {
  acme_server = var.letsencrypt_staging ? "https://acme-staging-v02.api.letsencrypt.org/directory" : "https://acme-v02.api.letsencrypt.org/directory"
  issuer_name = var.letsencrypt_staging ? "letsencrypt-staging" : "letsencrypt-prod"
}

resource "kubectl_manifest" "letsencrypt_issuer" {
  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: ${local.issuer_name}
    spec:
      acme:
        server: ${local.acme_server}
        email: ${var.letsencrypt_email}
        privateKeySecretRef:
          name: ${local.issuer_name}-key
        solvers:
          - dns01:
              digitalocean:
                tokenSecretRef:
                  name: ${kubernetes_secret.digitalocean_dns.metadata[0].name}
                  key: access-token
  YAML

  depends_on = [kubernetes_secret.digitalocean_dns]
}

# -----------------------------------------------------------------------------
# WILDCARD CERTIFICATES
# Certificates live in the "gateway" namespace alongside the Gateway resource
# so that TLS secrets are directly accessible by the gateway listeners.
# -----------------------------------------------------------------------------

# *.klucovsky.com — Infrastructure tools (VPN only)
resource "kubectl_manifest" "cert_klucovsky_wildcard" {
  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: klucovsky-wildcard-tls
      namespace: gateway
    spec:
      secretName: klucovsky-wildcard-tls
      issuerRef:
        name: ${local.issuer_name}
        kind: ClusterIssuer
      dnsNames:
        - "*.klucovsky.com"
        - "klucovsky.com"
  YAML

  depends_on = [kubectl_manifest.letsencrypt_issuer, kubernetes_namespace.gateway]
}
