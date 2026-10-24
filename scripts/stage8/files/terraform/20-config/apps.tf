# Un módulo, N aplicaciones: añadir una app monitorizada = añadir una entrada en apps (tfvars)
module "app" {
  source   = "../modules/app-monitorizada"
  for_each = var.apps

  nombre         = each.key
  namespace      = each.value.namespace
  imagen         = each.value.imagen
  replicas       = each.value.replicas
  ip_lb          = each.value.ip_lb
  umbral_errores = each.value.umbral_errores

  depends_on = [kubernetes_manifest.metallb_l2]
}

output "apps" {
  value = { for k, m in module.app : k => m.url }
}
