output "url" {
  description = "Dónde responde la aplicación"
  value       = var.ip_lb == null ? "http://${var.nombre}.${var.namespace}.svc.cluster.local" : "http://${var.ip_lb}"
}
