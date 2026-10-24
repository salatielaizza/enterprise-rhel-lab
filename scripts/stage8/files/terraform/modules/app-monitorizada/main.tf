# =============================================================================
# Módulo app-monitorizada: una aplicación que expone /metrics (como podinfo) con TODO
# lo que necesita para estar "en producción" en el lab:
#   Deployment (seguro por defecto) + Service + ServiceMonitor + PrometheusRule de errores.
# Los dos últimos llevan release: kube-prometheus-stack (si no, Prometheus no los ve: E08).
# =============================================================================
locals {
  selector = { "app.kubernetes.io/name" = var.nombre }
  labels = merge(local.selector, {
    "app.kubernetes.io/managed-by" = "terraform"
  })
}

resource "kubernetes_deployment_v1" "app" {
  metadata {
    name      = var.nombre
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    replicas = var.replicas
    selector {
      match_labels = local.selector
    }
    template {
      metadata {
        labels = local.labels
      }
      spec {
        security_context {
          run_as_non_root = true
          run_as_user     = 100
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          name    = "app"
          image   = var.imagen
          command = ["./podinfo", "--port=9898", "--level=info"]
          port {
            name           = "http"
            container_port = 9898
          }
          readiness_probe {
            http_get {
              path = "/readyz"
              port = "http"
            }
            period_seconds = 5
          }
          liveness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
            period_seconds = 10
          }
          resources {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { cpu = var.cpu_limit, memory = var.mem_limit }
          }
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "app" {
  metadata {
    name        = var.nombre
    namespace   = var.namespace
    labels      = local.labels
    annotations = var.ip_lb == null ? {} : { "metallb.io/loadBalancerIPs" = var.ip_lb }
  }
  spec {
    type     = var.ip_lb == null ? "ClusterIP" : "LoadBalancer"
    selector = local.selector
    port {
      name        = "http"
      port        = 80
      target_port = "http"
    }
  }
}

resource "kubernetes_manifest" "servicemonitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = var.nombre
      namespace = var.namespace
      labels    = merge(local.labels, { release = "kube-prometheus-stack" })
    }
    spec = {
      selector  = { matchLabels = local.selector }
      endpoints = [{ port = "http", path = "/metrics", interval = "15s" }]
    }
  }
}

resource "kubernetes_manifest" "alerta_errores" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "${var.nombre}-errores"
      namespace = var.namespace
      labels    = merge(local.labels, { release = "kube-prometheus-stack" })
    }
    spec = {
      groups = [{
        name = "${var.nombre}.errores"
        rules = [{
          alert = "ErroresAltos"
          expr  = "sum(rate(http_requests_total{namespace=\"${var.namespace}\",service=\"${var.nombre}\",status=~\"5..\"}[5m])) / sum(rate(http_requests_total{namespace=\"${var.namespace}\",service=\"${var.nombre}\"}[5m])) > ${var.umbral_errores}"
          for   = "2m"
          labels = {
            severity = "critical"
            app      = var.nombre
          }
          annotations = {
            summary = "${var.nombre}: más del ${var.umbral_errores * 100} % de respuestas 5xx"
          }
        }]
      }]
    }
  }
}
