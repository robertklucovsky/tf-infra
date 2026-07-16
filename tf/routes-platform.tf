# -----------------------------------------------------------------------------
# PLATFORM TOOL ROUTES (B2) — HTTPRoutes on platform-terminating
#
# Each *.klucovsky.com tool routes to its backend Service via platform-terminating
# (which sits behind the passthrough front on 172.16.1.11). Cross-namespace
# parentRef (gateway ns) is allowed by platform-terminating's
# allowedRoutes.namespaces.from=All.
# -----------------------------------------------------------------------------

locals {
  platform_tool_routes = merge({
    argocd = {
      namespace = "argocd"
      hostname  = "argocd.klucovsky.com"
      backend   = "argocd-server"
      port      = 80
    }
    pgadmin = {
      namespace = "cnpg-system"
      hostname  = "db.klucovsky.com"
      backend   = "pgadmin"
      port      = 80
    }
    nexus = {
      namespace = "nexus"
      hostname  = "nexus.klucovsky.com"
      backend   = "nexus-nexus-repository-manager"
      port      = 8081
    }
    alertmanager = {
      namespace = "observability"
      hostname  = "alertmanager.klucovsky.com"
      backend   = "prometheus-kube-prometheus-alertmanager"
      port      = 9093
    }
    grafana = {
      namespace = "observability"
      hostname  = "grafana.klucovsky.com"
      backend   = "prometheus-grafana"
      port      = 80
    }
    prometheus = {
      namespace = "observability"
      hostname  = "prometheus.klucovsky.com"
      backend   = "prometheus-kube-prometheus-prometheus"
      port      = 9090
    }
    zot = {
      namespace = "zot"
      hostname  = "registry.klucovsky.com"
      backend   = "zot"
      port      = 5000
    }
    keycloak = {
      namespace = "keycloak"
      hostname  = "auth.klucovsky.com"
      backend   = "keycloak"
      port      = 80
    }
    mailpit = {
      namespace = "mailpit"
      hostname  = "mail.klucovsky.com"
      backend   = "mailpit"
      port      = 8025
    }
    # RustFS console listener = full server (S3 + admin + console UI), so a
    # single backend covers S3 API, STS, OIDC callback and /rustfs/console/.
    rustfs = {
      namespace = "rustfs"
      hostname  = "s3.klucovsky.com"
      backend   = "rustfs"
      port      = 9001
    }
    }, var.sonarqube_enabled ? {
    sonarqube = {
      namespace = "sonarqube"
      hostname  = "sonar.klucovsky.com"
      backend   = "sonarqube-sonarqube"
      port      = 9000
    }
  } : {})
}

resource "kubectl_manifest" "platform_tool_route" {
  for_each = local.platform_tool_routes

  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: ${each.key}-platform
      namespace: ${each.value.namespace}
    spec:
      parentRefs:
        - name: platform-terminating
          namespace: gateway
          sectionName: https-klucovsky
      hostnames:
        - "${each.value.hostname}"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: ${each.value.backend}
              port: ${each.value.port}
  YAML

  depends_on = [kubectl_manifest.platform_terminating_gw]
}

# SSO shortcut: fatto-aac.klucovsky.com 302-redirects straight into the RustFS
# OIDC authorize flow — Keycloak login (or silent SSO) → storage console,
# skipping the console login page. DNS record lives in dns.tf.
resource "kubectl_manifest" "fatto_aac_sso_redirect" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: fatto-aac-sso-redirect
      namespace: rustfs
    spec:
      parentRefs:
        - name: platform-terminating
          namespace: gateway
          sectionName: https-klucovsky
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

  depends_on = [kubectl_manifest.platform_terminating_gw]
}
