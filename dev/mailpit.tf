# -----------------------------------------------------------------------------
# MAILPIT
# Local email testing server (catches all outbound SMTP)
# https://github.com/axllent/mailpit
# -----------------------------------------------------------------------------

resource "kubernetes_deployment" "mailpit" {
  metadata {
    name      = "mailpit"
    namespace = kubernetes_namespace.fatto_dev.metadata[0].name

    labels = {
      "app.kubernetes.io/name"      = "mailpit"
      "app.kubernetes.io/component" = "email"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "mailpit"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "mailpit"
        }
      }

      spec {
        container {
          name  = "mailpit"
          image = "axllent/mailpit:v1.24"

          port {
            name           = "smtp"
            container_port = 1025
          }

          port {
            name           = "http"
            container_port = 8025
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }

          env {
            name  = "MP_SMTP_AUTH_ACCEPT_ANY"
            value = "true"
          }

          env {
            name  = "MP_SMTP_AUTH_ALLOW_INSECURE"
            value = "true"
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.fatto_dev]
}

resource "kubernetes_service" "mailpit" {
  metadata {
    name      = "mailpit"
    namespace = kubernetes_namespace.fatto_dev.metadata[0].name
  }

  spec {
    selector = {
      "app.kubernetes.io/name" = "mailpit"
    }

    port {
      name        = "smtp"
      port        = 1025
      target_port = 1025
    }

    port {
      name        = "http"
      port        = 8025
      target_port = 8025
    }
  }

  depends_on = [kubernetes_deployment.mailpit]
}

# -----------------------------------------------------------------------------
# GATEWAY HTTPROUTE
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "route_mailpit" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: mailpit
      namespace: ${kubernetes_namespace.fatto_dev.metadata[0].name}
    spec:
      parentRefs:
        - name: fatto-gateway
          namespace: gateway
          sectionName: https-dev
      hostnames:
        - "mail.${var.domain}"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: ${kubernetes_service.mailpit.metadata[0].name}
              port: 8025
  YAML

  depends_on = [kubectl_manifest.gateway, kubernetes_service.mailpit]
}

