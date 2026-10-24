variable "kubeconfig" {
  type    = string
  default = "~/.kube/config"
}

variable "kube_context" {
  type    = string
  default = "kubernetes-admin@lab-k8s"
}

variable "pool_metallb" {
  description = "Rango de IPs del lab para los Service type: LoadBalancer (reservado en el README)"
  type        = string
  default     = "10.10.10.110-10.10.10.119"
}

variable "apps" {
  description = "Aplicaciones monitorizadas: cada entrada crea Deployment + Service + ServiceMonitor + alerta"
  type = map(object({
    namespace      = string
    imagen         = string
    replicas       = number
    ip_lb          = optional(string)
    umbral_errores = optional(number, 0.05)
  }))
}
