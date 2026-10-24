resource "helm_release" "metallb" {
  name       = "metallb"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  version    = var.versiones.metallb
  namespace  = kubernetes_namespace_v1.plataforma["metallb-system"].metadata[0].name
  wait       = true
  timeout    = 600
}
