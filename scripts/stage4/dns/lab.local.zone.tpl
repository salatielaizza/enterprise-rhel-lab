; Zona directa lab.local — el serial (@@SERIAL@@) lo genera 01-setup-dns.sh (AAMMDDhhmm)
$TTL 3600
@       IN  SOA dns01.lab.local. hostmaster.lab.local. (
                @@SERIAL@@ ; serial
                3600       ; refresh
                900        ; retry
                604800     ; expire
                300 )      ; TTL negativo
        IN  NS  dns01.lab.local.

kvm-host        IN  A   10.10.10.1
rhel7-app01     IN  A   10.10.10.11
rhel8-app01     IN  A   10.10.10.12
rhel9-app01     IN  A   10.10.10.13
rhel10-app01    IN  A   10.10.10.14
dns01           IN  A   10.10.10.20
ansible01       IN  A   10.10.10.30

; Etapa 8 — Kubernetes/OpenShift. k8s-api = controlPlaneEndpoint de kubeadm (hoy el único nodo de
; control; con un segundo nodo de control solo cambia este registro). .110-.119 = pool de MetalLB.
k8s-cp01        IN  A   10.10.10.100
k8s-w01         IN  A   10.10.10.101
k8s-w02         IN  A   10.10.10.102
k8s-api         IN  A   10.10.10.100
ingress         IN  A   10.10.10.110
grafana         IN  A   10.10.10.111
prometheus      IN  A   10.10.10.112
alertmanager    IN  A   10.10.10.113
podinfo         IN  A   10.10.10.114
gitea           IN  A   10.10.10.115
argocd          IN  A   10.10.10.116
tienda          IN  A   10.10.10.117

; Etapa 9 — VMware vSphere. Se crean ANTES de instalar: vCenter exige A y PTR correctos
; desde el primer momento (su instalador falla en la fase 2 si no los encuentra).
esxi01          IN  A   10.10.10.60
esxi02          IN  A   10.10.10.61
esxi03          IN  A   10.10.10.62
vcsa01          IN  A   10.10.10.63
rhel9-vm01      IN  A   10.10.10.64

; Etapa N2 — SIEM (Graylog + OpenSearch, k3s). Docker publica las entradas en esta IP.
siem01          IN  A   10.10.10.55
graylog         IN  CNAME siem01

; Infraestructura futura (reservada; NO crear registros hasta instalar el host):
;rhel9-web01     IN  A   10.10.10.40
;rhel9-monitor01 IN  A   10.10.10.50
