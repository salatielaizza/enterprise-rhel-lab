# kubernetes_manifest = cualquier objeto de Kubernetes, también de CRDs. Necesita el CRD YA en el
# clúster durante el plan: por eso vive en esta capa y no en 10-plataforma (escenario T6).
resource "kubernetes_manifest" "metallb_pool" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"
    metadata = {
      name      = "lab-pool"
      namespace = "metallb-system"
    }
    spec = {
      addresses = [var.pool_metallb]
    }
  }
}

resource "kubernetes_manifest" "metallb_l2" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "L2Advertisement"
    metadata = {
      name      = "lab-l2"
      namespace = "metallb-system"
    }
    spec = {
      ipAddressPools = ["lab-pool"]
    }
  }
  depends_on = [kubernetes_manifest.metallb_pool]
}
