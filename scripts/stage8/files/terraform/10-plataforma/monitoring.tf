# Secret de Grafana ANTES del chart (el chart lo referencia con grafana.admin.existingSecret)
resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace_v1.plataforma["monitoring"].metadata[0].name
    labels    = local.etiquetas_comunes
  }
  data = {
    "admin-user"     = "admin"
    "admin-password" = var.grafana_admin_password
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.versiones.kube_prometheus_stack
  namespace  = kubernetes_namespace_v1.plataforma["monitoring"].metadata[0].name
  timeout    = 900

  # EL MISMO fichero de valores que la instalación a mano de la 8.8: una sola fuente de verdad
  values = [file("${path.module}/../../monitoring/kube-prometheus-stack-values.yaml")]

  depends_on = [kubernetes_secret_v1.grafana_admin, helm_release.metallb]

  # Borrar la monitorización por error deja a ciegas a todo el clúster (escenario T7)
  lifecycle {
    prevent_destroy = true
  }
}
