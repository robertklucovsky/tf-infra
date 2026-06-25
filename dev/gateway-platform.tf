# -----------------------------------------------------------------------------
# PLATFORM INGRESS (B2) — parallel build on 172.16.1.12
#
# Front (passthrough :443) + Front (redirect :80) + Terminating (*.klucovsky.com).
# Wired with the PoC-validated relay-Endpoints pattern (a TLSRoute backendRef
# cannot target a cilium-gateway-* Service directly). Built alongside the live
# fatto-gateway (.11); no existing route is touched here.
# -----------------------------------------------------------------------------

# Terminating Gateway: terminates TLS for platform tools on *.klucovsky.com.
resource "kubectl_manifest" "platform_terminating_gw" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: platform-terminating
      namespace: gateway
    spec:
      gatewayClassName: ck-gateway
      listeners:
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
  YAML

  depends_on = [kubernetes_namespace.gateway, kubectl_manifest.cert_klucovsky_wildcard]
}

# Front Gateway A: generic TLS passthrough on :443 (no hostname, no cert).
resource "kubectl_manifest" "platform_front_tls_gw" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: platform-front-tls
      namespace: gateway
      annotations:
        metallb.io/allow-shared-ip: "platform-front"
        metallb.io/loadBalancerIPs: "172.16.1.12"
    spec:
      gatewayClassName: ck-gateway
      listeners:
        - name: tls-passthrough
          port: 443
          protocol: TLS
          tls:
            mode: Passthrough
          allowedRoutes:
            kinds:
              - kind: TLSRoute
            namespaces:
              from: All
  YAML

  depends_on = [kubernetes_namespace.gateway]
}

# Front Gateway B: generic HTTP -> HTTPS redirect on :80 (separate Gateway —
# Cilium refuses to attach an HTTPRoute to a Gateway that has a passthrough
# listener). Shares 172.16.1.12 with the passthrough Gateway via MetalLB.
resource "kubectl_manifest" "platform_front_http_gw" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: platform-front-http
      namespace: gateway
      annotations:
        metallb.io/allow-shared-ip: "platform-front"
        metallb.io/loadBalancerIPs: "172.16.1.12"
    spec:
      gatewayClassName: ck-gateway
      listeners:
        - name: http
          port: 80
          protocol: HTTP
          allowedRoutes:
            namespaces:
              from: All
  YAML

  depends_on = [kubernetes_namespace.gateway]
}

# Generic HTTP -> HTTPS 301 redirect (no hostname).
resource "kubectl_manifest" "platform_http_redirect_route" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: platform-http-redirect
      namespace: gateway
    spec:
      parentRefs:
        - name: platform-front-http
          sectionName: http
      rules:
        - filters:
            - type: RequestRedirect
              requestRedirect:
                scheme: https
                statusCode: 301
  YAML

  depends_on = [kubectl_manifest.platform_front_http_gw]
}

# The terminating Gateway's auto-created Envoy Service. We read its ClusterIP
# to build a relay the front TLSRoute can target.
data "kubernetes_service" "platform_terminating_envoy" {
  metadata {
    name      = "cilium-gateway-platform-terminating"
    namespace = "gateway"
  }

  depends_on = [kubectl_manifest.platform_terminating_gw]
}

# Relay Service (no selector) + manual Endpoints → terminating Gateway ClusterIP:443.
# A TLSRoute backendRef cannot target the cilium-gateway-* Service directly
# (Cilium Envoy->Envoy via the EDS sentinel fails), so we bridge via a plain svc.
resource "kubernetes_service" "platform_terminating_relay" {
  metadata {
    name      = "platform-terminating-relay"
    namespace = "gateway"
  }
  spec {
    port {
      name        = "https"
      port        = 443
      target_port = 443
    }
  }
}

resource "kubernetes_endpoints" "platform_terminating_relay" {
  metadata {
    name      = "platform-terminating-relay"
    namespace = "gateway"
  }
  subset {
    address {
      ip = data.kubernetes_service.platform_terminating_envoy.spec[0].cluster_ip
    }
    port {
      name = "https"
      port = 443
    }
  }
}

# SNI route: *.klucovsky.com on the passthrough front -> relay -> terminating GW.
resource "kubectl_manifest" "platform_tls_route" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1alpha2
    kind: TLSRoute
    metadata:
      name: platform-klucovsky
      namespace: gateway
    spec:
      parentRefs:
        - name: platform-front-tls
          sectionName: tls-passthrough
      hostnames:
        - "*.klucovsky.com"
      rules:
        - backendRefs:
            - name: platform-terminating-relay
              port: 443
  YAML

  depends_on = [
    kubectl_manifest.platform_front_tls_gw,
    kubernetes_endpoints.platform_terminating_relay,
  ]
}
