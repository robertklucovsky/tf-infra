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

# -----------------------------------------------------------------------------
# SHARED GATEWAY
# Single entry point for all HTTPS/HTTP traffic across all domains
# Listeners:
#   - *.dev.fatto.online  (dev apps, VPN only)
#   - *.test.fatto.online (test apps, public)
#   - *.klucovsky.com     (infra tools, VPN only)
#   - HTTP catch-all      (all HTTP → HTTPS)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "gateway" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: fatto-gateway
      namespace: gateway
    spec:
      gatewayClassName: ck-gateway
      listeners:
        # Dev environment — *.dev.fatto.online (VPN only, no public DNS)
        - name: https-dev
          port: 443
          protocol: HTTPS
          hostname: "*.dev.fatto.online"
          tls:
            mode: Terminate
            certificateRefs:
              - kind: Secret
                name: dev-wildcard-tls
          allowedRoutes:
            namespaces:
              from: All

        # Test environment — *.test.fatto.online (public)
        - name: https-test
          port: 443
          protocol: HTTPS
          hostname: "*.test.fatto.online"
          tls:
            mode: Terminate
            certificateRefs:
              - kind: Secret
                name: test-wildcard-tls
          allowedRoutes:
            namespaces:
              from: All

        # Infrastructure tools — *.klucovsky.com (VPN only)
        - name: https-klucovsky
          port: 443
          protocol: HTTPS
          hostname: "*.klucovsky.com"
          tls:
            mode: Terminate
            certificateRefs:
              - kind: Secret
                name: klucovsky-wildcard-tls
          allowedRoutes:
            namespaces:
              from: All

        # HTTP catch-all (redirect to HTTPS)
        - name: http
          port: 80
          protocol: HTTP
          allowedRoutes:
            namespaces:
              from: All
  YAML

  depends_on = [kubernetes_namespace.gateway]
}
