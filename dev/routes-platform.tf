# -----------------------------------------------------------------------------
# PLATFORM TOOL ROUTES (B2) — parallel routes on platform-terminating
#
# Dual-serve: each *.klucovsky.com tool also gets a route on the new terminating
# Gateway (reached via the passthrough front on 172.16.1.12). The original routes
# on fatto-gateway stay live. Cross-namespace parentRef (gateway ns) is allowed by
# platform-terminating's allowedRoutes.namespaces.from=All.
#
# Removing the old fatto-gateway routes + the .11 flip happen at the final cutover
# (after the project Gateway / Plan 6 takes over the fatto domain).
# -----------------------------------------------------------------------------

locals {
  platform_tool_routes = {
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
    sonarqube = {
      namespace = "sonarqube"
      hostname  = "sonar.klucovsky.com"
      backend   = "sonarqube-sonarqube"
      port      = 9000
    }
    zot = {
      namespace = "zot"
      hostname  = "registry.klucovsky.com"
      backend   = "zot"
      port      = 5000
    }
  }
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
