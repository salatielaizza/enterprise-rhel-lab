# =============================================================================
# Etapa 8.9 — Terraform, capa 20-config: configuración que usa los CRDs de 10-plataforma
#   pool de IPs de MetalLB y aplicaciones monitorizadas (módulo app-monitorizada).
# Se ejecuta en ansible01, como adminlab, con el kubeconfig del clúster.
#
# Dos capas (dos "raíces", dos estados) a propósito: los recursos de 20-config usan
# CRDs (IPAddressPool, ServiceMonitor...) que instala ESTA capa, y kubernetes_manifest
# necesita el CRD ya en el clúster para hacer el plan (escenario T6).
# =============================================================================
terraform {
  required_version = ">= 1.9"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.4"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }
}
