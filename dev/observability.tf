# -----------------------------------------------------------------------------
# OBSERVABILITY STACK
# Tempo for distributed tracing, Loki for log aggregation,
# Promtail for log collection, Prometheus + Grafana for metrics
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# OBSERVABILITY NAMESPACE
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "observability" {
  metadata {
    name = "observability"

    labels = {
      "app.kubernetes.io/name"       = "observability"
      "app.kubernetes.io/component"  = "monitoring"
      "app.kubernetes.io/managed-by" = "terraform"
      "environment"                  = "dev"
    }
  }
}

# -----------------------------------------------------------------------------
# GRAFANA TEMPO (Distributed Tracing)
# Monolithic mode with local filesystem storage for dev.
# Accepts OTLP traces on 4317 (gRPC) and 4318 (HTTP).
# Query API on port 3200.
# -----------------------------------------------------------------------------

resource "helm_release" "tempo" {
  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = var.tempo_chart_version
  namespace  = kubernetes_namespace.observability.metadata[0].name

  wait    = true
  timeout = 600

  depends_on = [kubernetes_namespace.observability]

  values = [
    yamlencode({
      tempo = {
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }

        # Trace retention
        retention = "72h"

        # Storage — local filesystem for dev
        storage = {
          trace = {
            backend = "local"
            local = {
              path = "/var/tempo/traces"
            }
          }
        }

        # OTLP receivers
        receivers = {
          otlp = {
            protocols = {
              grpc = {
                endpoint = "0.0.0.0:4317"
              }
              http = {
                endpoint = "0.0.0.0:4318"
              }
            }
          }
        }

        # Metrics generator — derive RED metrics from traces
        metricsGenerator = {
          enabled = true
          remoteWriteUrl = "http://prometheus-kube-prometheus-prometheus.observability.svc.cluster.local:9090/api/v1/write"
        }
      }

      # Persistence (disabled for dev — ephemeral storage)
      persistence = {
        enabled = false
      }
    })
  ]
}

# -----------------------------------------------------------------------------
# GRAFANA LOKI (Log Aggregation)
# Single-binary mode with local filesystem storage for dev.
# Receives logs from Promtail via push API on port 3100.
# -----------------------------------------------------------------------------

resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.loki_chart_version
  namespace  = kubernetes_namespace.observability.metadata[0].name

  wait    = true
  timeout = 600

  depends_on = [kubernetes_namespace.observability]

  values = [
    yamlencode({
      # Single-binary deployment mode (all-in-one for dev)
      deploymentMode = "SingleBinary"

      singleBinary = {
        replicas = 1
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }

      # Disable components not needed in SingleBinary mode
      backend = {
        replicas = 0
      }
      read = {
        replicas = 0
      }
      write = {
        replicas = 0
      }

      # Local storage for dev
      loki = {
        auth_enabled = false
        commonConfig = {
          replication_factor = 1
        }
        schemaConfig = {
          configs = [
            {
              from         = "2024-01-01"
              store        = "tsdb"
              object_store = "filesystem"
              schema       = "v13"
              index = {
                prefix = "index_"
                period = "24h"
              }
            }
          ]
        }
        storage = {
          type = "filesystem"
          filesystem = {
            chunks_directory = "/var/loki/chunks"
            rules_directory  = "/var/loki/rules"
          }
        }
        limits_config = {
          retention_period = "72h"
        }
      }

      # Disable gateway (nginx) for simplicity in dev
      gateway = {
        enabled = false
      }

      # Disable minio sub-chart
      minio = {
        enabled = false
      }

      # Disable chunksCache, resultsCache for dev
      chunksCache = {
        enabled = false
      }
      resultsCache = {
        enabled = false
      }
    })
  ]
}

# -----------------------------------------------------------------------------
# PROMTAIL (Log Collection Agent)
# DaemonSet that collects container logs from all nodes and ships to Loki.
# Automatically discovers pods and adds Kubernetes labels.
# -----------------------------------------------------------------------------

resource "helm_release" "promtail" {
  name       = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = var.promtail_chart_version
  namespace  = kubernetes_namespace.observability.metadata[0].name

  wait    = true
  timeout = 600

  depends_on = [kubernetes_namespace.observability, helm_release.loki]

  values = [
    yamlencode({
      config = {
        clients = [
          {
            url = "http://loki.observability.svc.cluster.local:3100/loki/api/v1/push"
          }
        ]
      }

      resources = {
        limits = {
          cpu    = "200m"
          memory = "128Mi"
        }
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
      }
    })
  ]
}

# -----------------------------------------------------------------------------
# NODEPORT SERVICE FOR OTLP ACCESS (for local development)
# Exposes Tempo's OTLP ports for services running outside the cluster.
# -----------------------------------------------------------------------------

resource "kubernetes_service" "tempo_otlp_nodeport" {
  metadata {
    name      = "tempo-otlp-nodeport"
    namespace = kubernetes_namespace.observability.metadata[0].name
  }

  spec {
    type = "NodePort"

    selector = {
      "app.kubernetes.io/name"     = "tempo"
      "app.kubernetes.io/instance" = "tempo"
    }

    # OTLP gRPC port
    port {
      name        = "otlp-grpc"
      port        = 4317
      target_port = 4317
      node_port   = 30417
    }

    # OTLP HTTP port
    port {
      name        = "otlp-http"
      port        = 4318
      target_port = 4318
      node_port   = 30418
    }
  }

  depends_on = [helm_release.tempo]
}

# -----------------------------------------------------------------------------
# PROMETHEUS + GRAFANA (kube-prometheus-stack)
# Full metrics, alerting, and dashboards
# -----------------------------------------------------------------------------

resource "helm_release" "prometheus_stack" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.prometheus_stack_version
  namespace  = kubernetes_namespace.observability.metadata[0].name

  depends_on = [kubernetes_namespace.observability]

  # Increase timeout for CRD installation
  timeout = 600

  values = [
    yamlencode({
      # Prometheus configuration
      prometheus = {
        prometheusSpec = {
          # Retain metrics for 7 days (dev environment)
          retention = "7d"
          # Resource limits
          resources = {
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
          }
          # Storage (no persistent storage for dev)
          storageSpec = {}
          # Scrape all namespaces
          podMonitorSelectorNilUsesHelmValues     = false
          serviceMonitorSelectorNilUsesHelmValues = false
        }
      }

      # Alertmanager configuration
      alertmanager = {
        enabled = true
        alertmanagerSpec = {
          resources = {
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
          }
        }
      }

      # Grafana configuration
      grafana = {
        enabled       = true
        adminUser     = var.grafana_admin_user
        adminPassword = random_password.grafana_password.result

        # Additional data sources
        additionalDataSources = [
          {
            name      = "Tempo"
            type      = "tempo"
            access    = "proxy"
            url       = "http://tempo.observability.svc.cluster.local:3200"
            uid       = "tempo"
            isDefault = false
            jsonData = {
              tracesToLogs = {
                datasourceUid       = "loki"
                filterByTraceID     = true
                filterBySpanID      = false
                mapTagNamesEnabled  = true
                mappedTags = [
                  { key = "service.name", value = "service_name" }
                ]
              }
              tracesToMetrics = {
                datasourceUid = "prometheus"
              }
              serviceMap = {
                datasourceUid = "prometheus"
              }
              nodeGraph = {
                enabled = true
              }
            }
          },
          {
            name      = "Loki"
            type      = "loki"
            access    = "proxy"
            url       = "http://loki.observability.svc.cluster.local:3100"
            uid       = "loki"
            isDefault = false
            jsonData = {
              derivedFields = [
                {
                  name          = "TraceID"
                  matcherRegex  = "traceId=(\\w+)"
                  url           = "$${__value.raw}"
                  datasourceUid = "tempo"
                  matcherType   = "label"
                }
              ]
            }
          }
        ]

        # Resource limits
        resources = {
          limits = {
            cpu    = "300m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }

        # Persistence (disabled for dev)
        persistence = {
          enabled = false
        }

        # Default dashboards
        defaultDashboardsEnabled  = true
        defaultDashboardsTimezone = "browser"
        defaultDashboardsEditable = true
      }

      # Node exporter for host metrics
      nodeExporter = {
        enabled = true
      }

      # Kube-state-metrics for K8s object metrics
      kubeStateMetrics = {
        enabled = true
      }

      # Disable components not needed for MicroK8s
      kubeControllerManager = {
        enabled = false
      }
      kubeScheduler = {
        enabled = false
      }
      kubeProxy = {
        enabled = false
      }
      kubeEtcd = {
        enabled = false
      }
    })
  ]
}


