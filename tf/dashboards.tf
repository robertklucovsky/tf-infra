# -----------------------------------------------------------------------------
# GRAFANA DASHBOARDS
# Creates ConfigMaps with dashboards that kube-prometheus-stack will auto-discover
# via the grafana_dashboard = "1" label.
# -----------------------------------------------------------------------------

resource "kubernetes_config_map" "grafana_dashboard_tempo" {
  metadata {
    name      = "grafana-dashboard-tempo"
    namespace = kubernetes_namespace.observability.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "tempo-dashboard.json" = file("${path.module}/tempo-dashboard.json")
  }
}

resource "kubernetes_config_map" "grafana_dashboard_loki" {
  metadata {
    name      = "grafana-dashboard-loki"
    namespace = kubernetes_namespace.observability.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "loki-dashboard.json" = file("${path.module}/loki-dashboard.json")
  }
}
