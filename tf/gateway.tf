# -----------------------------------------------------------------------------
# GATEWAY API
# Cilium Gateway Controller (built-in with Canonical K8s)
#
# The ck-gateway feature provides:
#   - Gateway API CRDs
#   - GatewayClass "ck-gateway" (Cilium controller)
#
# We only need to define the Gateway resource and HTTPRoutes.
# No NGINX Gateway Fabric or manual CRD install needed.
# -----------------------------------------------------------------------------

# Namespace for gateway resources (TLS secrets, certificates, etc.)
resource "kubernetes_namespace" "gateway" {
  metadata {
    name = "gateway"

    labels = {
      "app.kubernetes.io/name"       = "gateway"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# NOTE: the shared gateway was replaced by the B2 platform ingress
# (platform-front-tls / platform-front-http / platform-terminating) in
# gateway-platform.tf. This file now only owns the gateway namespace.
