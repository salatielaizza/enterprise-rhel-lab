output "namespaces_de_equipo" {
  description = "Namespaces de aplicación creados, con su cuota"
  value       = { for k, v in var.equipos : k => "${v.cpu_limits} CPU / ${v.mem_limits} RAM / ${v.pods} pods" }
}

output "versiones_desplegadas" {
  value = {
    metallb               = helm_release.metallb.version
    kube_prometheus_stack = helm_release.kube_prometheus_stack.version
  }
}
