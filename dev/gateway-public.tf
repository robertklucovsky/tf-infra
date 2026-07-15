# -----------------------------------------------------------------------------
# PUBLIC INGRESS — internet-facing gateway on 172.16.1.12
#
# Serves ONLY s3/auth/fatto-aac (the intentionally-public hosts). The router's
# 80/443 forward is repointed here (see remediation plan Task 7), leaving the
# all-hosts path on 172.16.1.11 intranet-only. Direct-terminating on its own LB
# IP (verified working against the existing terminating gateway's .13).
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "platform_public_gw" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: platform-public
      namespace: gateway
      annotations:
        metallb.io/allow-shared-ip: "platform-public"
        metallb.io/loadBalancerIPs: "172.16.1.12"
    spec:
      gatewayClassName: ck-gateway
      listeners:
        - name: https-public
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

resource "kubectl_manifest" "platform_public_http_gw" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: platform-public-http
      namespace: gateway
      annotations:
        metallb.io/allow-shared-ip: "platform-public"
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

# HTTP -> HTTPS 301 redirect on the public IP.
resource "kubectl_manifest" "platform_public_http_redirect" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: platform-public-http-redirect
      namespace: gateway
    spec:
      parentRefs:
        - name: platform-public-http
          sectionName: http
      rules:
        - filters:
            - type: RequestRedirect
              requestRedirect:
                scheme: https
                statusCode: 301
  YAML

  depends_on = [kubectl_manifest.platform_public_http_gw]
}

# Pin MetalLB IP on the generated cilium-gateway-* Services (annotations on the
# Gateway are not propagated by Cilium — same reason as gateway-platform.tf).
resource "kubernetes_annotations" "public_https_lb_ip" {
  api_version = "v1"
  kind        = "Service"
  metadata {
    name      = "cilium-gateway-platform-public"
    namespace = "gateway"
  }
  annotations = {
    "metallb.io/allow-shared-ip" = "platform-public"
    "metallb.io/loadBalancerIPs" = "172.16.1.12"
  }
  force      = true
  depends_on = [kubectl_manifest.platform_public_gw]
}

resource "kubernetes_annotations" "public_http_lb_ip" {
  api_version = "v1"
  kind        = "Service"
  metadata {
    name      = "cilium-gateway-platform-public-http"
    namespace = "gateway"
  }
  annotations = {
    "metallb.io/allow-shared-ip" = "platform-public"
    "metallb.io/loadBalancerIPs" = "172.16.1.12"
  }
  force      = true
  depends_on = [kubectl_manifest.platform_public_http_gw]
}

# Public HTTPRoutes — one per public host, in the backend's namespace
# (cross-namespace parentRef is allowed by allowedRoutes.namespaces.from=All).
resource "kubectl_manifest" "s3_public_route" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: s3-public
      namespace: rustfs
    spec:
      parentRefs:
        - name: platform-public
          namespace: gateway
          sectionName: https-public
      hostnames:
        - "s3.klucovsky.com"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: rustfs
              port: 9001
  YAML

  depends_on = [kubectl_manifest.platform_public_gw]
}

resource "kubectl_manifest" "auth_public_route" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: auth-public
      namespace: keycloak
    spec:
      parentRefs:
        - name: platform-public
          namespace: gateway
          sectionName: https-public
      hostnames:
        - "auth.klucovsky.com"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: keycloak
              port: 80
  YAML

  depends_on = [kubectl_manifest.platform_public_gw]
}

resource "kubectl_manifest" "fatto_aac_public_redirect" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: fatto-aac-public
      namespace: rustfs
    spec:
      parentRefs:
        - name: platform-public
          namespace: gateway
          sectionName: https-public
      hostnames:
        - "fatto-aac.klucovsky.com"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          filters:
            - type: RequestRedirect
              requestRedirect:
                scheme: https
                hostname: s3.klucovsky.com
                path:
                  type: ReplaceFullPath
                  replaceFullPath: /rustfs/admin/v3/oidc/authorize/default
                statusCode: 302
  YAML

  depends_on = [kubectl_manifest.platform_public_gw]
}
