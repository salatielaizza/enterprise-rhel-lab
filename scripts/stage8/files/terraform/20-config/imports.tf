# Escenario T3 — el pool de MetalLB ya se creó a mano en la 8.4 (cluster/metallb-pool.yaml).
# Sin estos import, el apply fallaría con "already exists". Descomenta, revisa el plan y aplica;
# después vuelve a comentarlos (ya están en el estado).
# El id de kubernetes_manifest es "apiVersion=...,kind=...,namespace=...,name=...".
#
# import {
#   to = kubernetes_manifest.metallb_pool
#   id = "apiVersion=metallb.io/v1beta1,kind=IPAddressPool,namespace=metallb-system,name=lab-pool"
# }
# import {
#   to = kubernetes_manifest.metallb_l2
#   id = "apiVersion=metallb.io/v1beta1,kind=L2Advertisement,namespace=metallb-system,name=lab-l2"
# }
