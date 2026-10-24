# Escenario T2 — ADOPTAR lo que se creó a mano en la 8.4 y la 8.8, sin borrarlo ni recrearlo.
# Descomenta, ejecuta 'terraform plan' y lee el resultado ANTES de aplicar:
#   "will be imported" = Terraform pasa a gestionarlo; si además sale "will be updated in-place",
#   el código no describe exactamente lo que hay en el clúster: decide quién tiene razón.
# Con los import aplicados, vuelve a comentarlos (ya están en el estado).
#
# import {
#   to = kubernetes_namespace_v1.plataforma["monitoring"]
#   id = "monitoring"
# }
# import {
#   to = kubernetes_namespace_v1.plataforma["metallb-system"]
#   id = "metallb-system"
# }
# import {
#   to = kubernetes_namespace_v1.equipo["demo"]
#   id = "demo"
# }
# import {
#   to = kubernetes_namespace_v1.equipo["tienda"]   # creado a mano en la 8.6 (RBAC de dev-tienda)
#   id = "tienda"
# }
# import {
#   to = kubernetes_secret_v1.grafana_admin
#   id = "monitoring/grafana-admin"
# }
# import {
#   to = helm_release.metallb
#   id = "metallb-system/metallb"
# }
# import {
#   to = helm_release.kube_prometheus_stack
#   id = "monitoring/kube-prometheus-stack"
# }
