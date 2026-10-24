locals {
  etiquetas_comunes = {
    "app.kubernetes.io/managed-by" = "terraform"
    "lab/etapa"                    = "8"
  }
}

# Namespaces de plataforma. MetalLB necesita privilegios (speaker en la red del nodo).
resource "kubernetes_namespace_v1" "plataforma" {
  for_each = {
    monitoring     = "privileged" # node-exporter usa hostNetwork y hostPID
    metallb-system = "privileged"
  }
  metadata {
    name = each.key
    labels = merge(local.etiquetas_comunes, {
      "pod-security.kubernetes.io/enforce" = each.value
    })
  }
}

# Un namespace por equipo, siempre con cuota y límites por defecto (nadie despliega "sin techo")
resource "kubernetes_namespace_v1" "equipo" {
  for_each = var.equipos
  metadata {
    name = each.key
    labels = merge(local.etiquetas_comunes, {
      "pod-security.kubernetes.io/enforce" = "restricted"
    })
  }
}

resource "kubernetes_resource_quota_v1" "equipo" {
  for_each = var.equipos
  metadata {
    name      = "cuota"
    namespace = kubernetes_namespace_v1.equipo[each.key].metadata[0].name
  }
  spec {
    hard = {
      "requests.cpu"    = each.value.cpu_requests
      "requests.memory" = each.value.mem_requests
      "limits.cpu"      = each.value.cpu_limits
      "limits.memory"   = each.value.mem_limits
      pods              = each.value.pods
    }
  }
}

resource "kubernetes_limit_range_v1" "equipo" {
  for_each = var.equipos
  metadata {
    name      = "limites-por-defecto"
    namespace = kubernetes_namespace_v1.equipo[each.key].metadata[0].name
  }
  spec {
    limit {
      type            = "Container"
      default         = { cpu = "200m", memory = "128Mi" }
      default_request = { cpu = "50m", memory = "64Mi" }
    }
  }
}
