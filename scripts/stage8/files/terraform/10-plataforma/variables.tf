variable "kubeconfig" {
  description = "Ruta del kubeconfig del clúster del lab"
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Contexto del kubeconfig (kubeadm lo llama kubernetes-admin@<clusterName>)"
  type        = string
  default     = "kubernetes-admin@lab-k8s"
}

variable "grafana_admin_password" {
  description = "Contraseña de admin de Grafana. Nunca en un .tfvars del repo: export TF_VAR_grafana_admin_password=..."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.grafana_admin_password) >= 12 && var.grafana_admin_password != "admin"
    error_message = "La contraseña de Grafana debe tener 12 caracteres o más y no puede ser 'admin'."
  }
}

variable "equipos" {
  description = "Namespaces de aplicación con su cuota (un 'equipo' por namespace)"
  type = map(object({
    cpu_requests = string
    mem_requests = string
    cpu_limits   = string
    mem_limits   = string
    pods         = number
  }))
}

variable "versiones" {
  description = "Versiones FIJADAS de los charts: un cambio de versión es un cambio revisado en el plan"
  type = object({
    metallb               = string
    kube_prometheus_stack = string
  })
  default = {
    metallb               = "0.16.1"
    kube_prometheus_stack = "88.6.2"
  }
}
