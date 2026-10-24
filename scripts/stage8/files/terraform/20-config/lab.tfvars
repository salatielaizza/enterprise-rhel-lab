apps = {
  tienda-web = {
    namespace      = "tienda"
    imagen         = "ghcr.io/stefanprodan/podinfo:6.15.0"
    replicas       = 2
    ip_lb          = "10.10.10.117"
    umbral_errores = 0.02
  }
}
