# Entorno "lab". Un segundo fichero (p. ej. pre.tfvars) con otras cuotas = otro entorno con el mismo código.
# La contraseña de Grafana NO va aquí: export TF_VAR_grafana_admin_password='...'
equipos = {
  demo = {
    cpu_requests = "1"
    mem_requests = "1Gi"
    cpu_limits   = "2"
    mem_limits   = "2Gi"
    pods         = 20
  }
  tienda = {
    cpu_requests = "500m"
    mem_requests = "512Mi"
    cpu_limits   = "1"
    mem_limits   = "1Gi"
    pods         = 10
  }
}
