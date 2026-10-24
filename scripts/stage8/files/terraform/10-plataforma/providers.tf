provider "kubernetes" {
  config_path    = var.kubeconfig
  config_context = var.kube_context
}

# helm 3.x: "kubernetes" es un atributo (= { ... }), ya no un bloque
provider "helm" {
  kubernetes = {
    config_path    = var.kubeconfig
    config_context = var.kube_context
  }
}
