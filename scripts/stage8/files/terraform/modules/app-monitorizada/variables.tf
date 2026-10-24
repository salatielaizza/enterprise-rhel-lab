variable "nombre" {
  description = "Nombre de la aplicación (Deployment, Service, ServiceMonitor y regla)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.nombre))
    error_message = "Nombre DNS-1123: minúsculas, números y guiones."
  }
}

variable "namespace" {
  type = string
}

variable "imagen" {
  description = "Imagen con versión fijada (nunca :latest)"
  type        = string
  validation {
    condition     = !endswith(var.imagen, ":latest") && can(regex(":", var.imagen))
    error_message = "Fija la versión de la imagen (repositorio:versión); :latest no se acepta."
  }
}

variable "replicas" {
  type    = number
  default = 2
}

variable "ip_lb" {
  description = "IP fija del pool de MetalLB; null = Service ClusterIP (solo dentro del clúster)"
  type        = string
  default     = null
}

variable "umbral_errores" {
  description = "Proporción de respuestas 5xx (0-1) a partir de la cual se alerta"
  type        = number
  default     = 0.05
}

variable "cpu_limit" {
  type    = string
  default = "300m"
}

variable "mem_limit" {
  type    = string
  default = "128Mi"
}
