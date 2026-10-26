# Etapa 8 — Kubernetes y OpenShift, con Prometheus/Grafana y Terraform

> **Estado: 🚧 Pendiente.** Se hace **a mano y en detalle**; la automatización (Ansible, Terraform, GitOps) llega al
> final de la etapa y solo para lo que ya se ha hecho a mano. Checklist: [`checklists/etapa8.md`](../checklists/etapa8.md).
> Ficheros: [`scripts/stage8/`](../scripts/stage8/README_stage8.md). Casos reales: [`troubleshooting/etapa8/`](../troubleshooting/etapa8/README_troubleshooting_etapa8.md).

## Objetivo

Montar un clúster **Kubernetes** de 3 nodos sobre RHEL 9 con `kubeadm`, operarlo como en una empresa (red, almacenamiento,
seguridad, Helm, actualizaciones, copias de etcd), **monitorizarlo con Prometheus y Grafana** provocando averías reales,
**gestionarlo como código con Terraform** y conocer las diferencias con **OpenShift** (Red Hat OpenShift Local).

Es la combinación que más piden las ofertas de sistemas y plataforma en Madrid para perfiles Linux: Kubernetes u OpenShift,
Prometheus/Grafana, Terraform y Ansible, y GitOps/CI-CD.

## Arquitectura

```text
                         red del lab 10.10.10.0/24 (virbr-lab)
 ┌───────────┬───────────┬─────────────┬─────────────┬─────────────┐
 │ dns01 .20 │ansible01  │ k8s-cp01    │ k8s-w01     │ k8s-w02     │
 │ BIND      │ .30       │ .100        │ .101        │ .102        │
 │ chrony    │ kubectl   │ control     │ worker      │ worker      │
 │ node_exp. │ helm      │ plane+etcd  │             │             │
 │           │ terraform │ (k8s-api)   │             │             │
 └───────────┴───────────┴─────────────┴─────────────┴─────────────┘
   Pods 10.244.0.0/16 (Calico, VXLAN)   Services 10.96.0.0/12   LoadBalancer (MetalLB L2) .110-.119
```

| Nombre (lab.local)                        | IP                 | Qué es                                                      | Subetapa |
| ----------------------------------------- | ------------------ | ----------------------------------------------------------- | -------- |
| `k8s-cp01` / `k8s-api`                    | .100               | Plano de control (API, etcd, scheduler, controller-manager) | 8.2      |
| `k8s-w01`, `k8s-w02`                      | .101, .102         | Nodos de trabajo                                            | 8.2      |
| `ingress`                                 | .110               | Controlador de entrada (Traefik)                            | 8.4      |
| `grafana` / `prometheus` / `alertmanager` | .111 / .112 / .113 | kube-prometheus-stack                                       | 8.8      |
| `podinfo`                                 | .114               | Aplicación de ejemplo                                       | 8.3-8.4  |
| `gitea`                                   | .115               | Git dentro del clúster                                      | 8.7      |
| `argocd`                                  | .116               | GitOps                                                      | 8.11     |
| `tienda`                                  | .117               | App creada con Terraform                                    | 8.9      |

Los tres nodos están en `scripts/hosts.conf` como **opcionales**: `lab.sh ... all` no los incluye; se nombran siempre.

### Recursos (host con 31 GiB)

| Conjunto                         | RAM         | Notas                                                          |
| -------------------------------- | ----------- | -------------------------------------------------------------- |
| `dns01` + `ansible01`            | 5 GiB       | Siempre encendidas en esta etapa (DNS, hora y nodo de control) |
| Clúster (cp01 4 GiB + 2 × 5 GiB) | 14 GiB      | Total ≈ 19 GiB: caben también las `app01` si hace falta        |
| OpenShift Local (8.10)           | 10,5-11 GiB | **Con el clúster apagado** (`lab.sh down k8s-w01`, etc.)       |

Cada nodo tiene un disco de datos de 40 GB: la Etapa 2 usa 8 GB (`vg_data`) y la 8.2 crea `lv_containerd` (16 GB),
`lv_kubelet` (6 GB) y `lv_localpath` (8 GB). Así un disco lleno de imágenes o de volúmenes no llena `/var` (4 GB).

### Versiones fijadas (octubre de 2026)

| Componente                    | Versión                                                                         | Dónde                                  |
| ----------------------------- | ------------------------------------------------------------------------------- | -------------------------------------- |
| Kubernetes                    | v1.36.5 (repositorio `pkgs.k8s.io` v1.36); upgrade a 1.37 en la 8.12            | `cluster/kubeadm-config.yaml`          |
| containerd                    | `containerd.io` del repositorio de Docker para RHEL                             | 8.2                                    |
| Calico (operador Tigera)      | v3.32.1                                                                         | `cluster/calico-custom-resources.yaml` |
| MetalLB (chart)               | 0.16.1                                                                          | 8.4 y `terraform/10-plataforma`        |
| local-path-provisioner        | v0.0.37                                                                         | 8.5                                    |
| kube-prometheus-stack (chart) | 88.6.2                                                                          | 8.8 y `terraform/10-plataforma`        |
| podinfo                       | 6.15.0                                                                          | `apps/podinfo.yaml`                    |
| node_exporter (VMs)           | v1.12.1                                                                         | 8.8, E12                               |
| Argo CD                       | v3.5.2                                                                          | 8.11                                   |
| Terraform                     | 1.16.x (repositorio de HashiCorp); providers `kubernetes ~> 3.4`, `helm ~> 3.3` | 8.9                                    |

Antes de instalar cada pieza, **comprueba** que esa versión sigue siendo la recomendada (notas de la versión) y anota en el
checklist la que uses de verdad. Nunca `latest`.

## Reglas de trabajo de la etapa

1. Cada subetapa: hacer → comprobar → anotar en el checklist (resultado **obtenido**, no el esperado).
2. Lo que no salga como dice la guía es un caso de `troubleshooting/etapa8/NN-*.md` (plantilla de siempre).
3. Antes de una subetapa con riesgo, snapshot de los tres nodos **apagados** (un snapshot de un clúster encendido no es
   consistente): `lab.sh down k8s-cp01` (y los workers) y, en el host, `virsh snapshot-create-as k8s-cp01 --name k8s-cp01-antes-8.6`.
   `lab.sh snapshot create <nodo> 5` y `... 8` quedan para los hitos (`*-stage5-complete`, `*-stage8-complete`).
4. **El host no se toca** salvo en la 8.10 (OpenShift Local), y ahí con revisión previa de solo lectura.

---

## 8.1 Contenedores con Podman (en ansible01)

Antes de orquestar contenedores hay que entenderlos sin Kubernetes. Podman viene con RHEL y no necesita demonio ni root.

```bash
# En ansible01, como adminlab (sin sudo)
podman run -d --name web -p 8080:9898 ghcr.io/stefanprodan/podinfo:6.15.0
curl -s localhost:8080 | head -5;  podman ps;  podman logs web;  podman inspect web | less
podman exec web ps                      # dentro del contenedor: un solo proceso
ps -ef | grep podinfo                   # fuera: es un proceso más del host, del usuario adminlab
podman top web user huser               # usuario dentro (app) y fuera (un subuid de adminlab)
podman rm -f web
```

Ejercicios (anótalos en el checklist):

- **Imagen propia** con un `Containerfile` (`FROM registry.access.redhat.com/ubi9/ubi-minimal`, un script de bash de la
  Etapa 6, `USER 1001`), `podman build -t lab/saludo:1.0 .`, `podman history`, `podman image inspect`.
- **Volúmenes y SELinux**: `podman run -v ~/datos:/datos:Z ...` y compara `ls -Z ~/datos` con y sin `:Z`
  (sin él, `Permission denied` aunque los permisos Unix sean correctos: la Etapa 5 en acción).
- **Pod de Podman** con dos contenedores (`podman pod create`) y `podman kube generate`: el YAML resultante ya es un Pod de
  Kubernetes. Es el puente a la 8.2.
- **Servicio systemd con Quadlet**: `~/.config/containers/systemd/saludo.container` + `systemctl --user daemon-reload` +
  `loginctl enable-linger adminlab`. El contenedor arranca con la VM sin Kubernetes.

**Qué documentar:** imagen frente a contenedor, capas, rootless y subuid, por qué `:Z`, y qué aporta Kubernetes que
Podman + systemd no tiene (varios nodos, reprogramación si un nodo cae, Services, escalado declarativo).

---

## 8.2 Clúster con kubeadm

### 8.2.1 Las VMs (desde el host, con lab.sh)

```bash
scripts/lab.sh vm-create k8s-cp01 && scripts/lab.sh vm-create k8s-w01 && scripts/lab.sh vm-create k8s-w02
for h in k8s-cp01 k8s-w01 k8s-w02; do scripts/lab.sh register "$h" <usuario-RH>; done
scripts/lab.sh stage4-dns                          # recarga la zona: ya trae k8s-*, k8s-api, ingress, grafana...
for h in k8s-cp01 k8s-w01 k8s-w02; do
  scripts/lab.sh stage2 "$h" && scripts/lab.sh stage3 "$h" --lab-dns && scripts/lab.sh stage4-clients "$h" && scripts/lab.sh stage5 "$h"
done
for h in k8s-cp01 k8s-w01 k8s-w02; do scripts/lab.sh test all "$h"; done      # base del lab: 0 FAIL
dig +short k8s-api.lab.local @10.10.10.20                                     # 10.10.10.100
```

Snapshot de los tres antes de seguir (`scripts/lab.sh snapshot create k8s-cp01 5`, ídem workers: los apaga, crea
`*-stage5-complete` y los enciende): si la 8.2 sale mal, se vuelve aquí.

### 8.2.2 Preparar cada nodo (los tres; como root)

**Almacenamiento propio para contenedores, kubelet y volúmenes:**

```bash
vgs vg_data                                     # ~40 GB, 8 GB usados por la Etapa 2
lvcreate -y -n lv_containerd -L 16G vg_data
lvcreate -y -n lv_kubelet    -L 6G  vg_data
lvcreate -y -n lv_localpath  -L 8G  vg_data
for lv in containerd kubelet localpath; do mkfs.xfs -q /dev/vg_data/lv_$lv; done
mkdir -p /var/lib/containerd /var/lib/kubelet /var/lib/local-path
cat >> /etc/fstab <<'EOF'
/dev/vg_data/lv_containerd  /var/lib/containerd  xfs  defaults  0 0
/dev/vg_data/lv_kubelet     /var/lib/kubelet     xfs  defaults  0 0
/dev/vg_data/lv_localpath   /var/lib/local-path  xfs  defaults  0 0
EOF
systemctl daemon-reload && mount -a && restorecon -Rv /var/lib/containerd /var/lib/kubelet /var/lib/local-path
df -h /var/lib/containerd /var/lib/kubelet /var/lib/local-path
```

**Swap fuera** (el kubelet, por defecto, no arranca con swap activa):

```bash
swapon --show
swapoff -a
vim /etc/fstab                                  # comenta la línea de swap (lv_swap del kickstart)
systemctl daemon-reload && swapon --show        # vacío
```

**Módulos y sysctl** que necesita la red de pods:

```bash
cat > /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay && modprobe br_netfilter
cat > /etc/sysctl.d/90-k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system | grep -E 'bridge-nf-call-iptables|ip_forward'
```

**NetworkManager** no debe gestionar las interfaces que crea Calico:

```bash
cat > /etc/NetworkManager/conf.d/calico.conf <<'EOF'
[keyfile]
unmanaged-devices=interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico;interface-name:vxlan-v6.calico;interface-name:wireguard.cali;interface-name:wg-v6.cali
EOF
systemctl reload NetworkManager
```

**firewalld**: en vez de apagarlo, una zona `k8s` para la red del lab y las redes del clúster (si el origen es de esas
redes, firewalld usa esta zona; el resto del mundo sigue en `public`):

```bash
firewall-cmd --permanent --new-zone=k8s
for src in 10.10.10.0/24 10.244.0.0/16 10.96.0.0/12; do firewall-cmd --permanent --zone=k8s --add-source=$src; done
firewall-cmd --permanent --zone=k8s --add-service=ssh                     # ¡la zona nueva sustituye a public para el lab!
firewall-cmd --permanent --zone=k8s --add-port={10250/tcp,10249/tcp,9100/tcp,4789/udp,5473/tcp,7946/tcp,7946/udp,9091/tcp}
# Solo en k8s-cp01:  API, etcd y métricas del plano de control
firewall-cmd --permanent --zone=k8s --add-port={6443/tcp,2379-2380/tcp,2381/tcp,10257/tcp,10259/tcp}
# Solo en los workers: NodePort
firewall-cmd --permanent --zone=k8s --add-port=30000-32767/tcp
firewall-cmd --reload && firewall-cmd --get-active-zones && firewall-cmd --zone=k8s --list-all
```

| Puerto | Para qué |
|---|---|
| 6443 | API de Kubernetes |
| 2379-2380 / 2381 | etcd (clientes y pares) / métricas de etcd |
| 10250 | API del kubelet (logs, exec, métricas) |
| 10257 / 10259 / 10249 | métricas de controller-manager / scheduler / kube-proxy |
| 4789/udp, 5473 | VXLAN de Calico, Typha |
| 7946 tcp+udp | memberlist de MetalLB (elige qué nodo anuncia cada IP) |
| 9100, 9091 | node-exporter, métricas de Calico (felix) |

> Si después algo de la red de pods falla (CoreDNS no llega a la API, pods que no se ven entre nodos), **firewalld es el
> primer sospechoso**: `firewall-cmd --get-active-zones`, `journalctl -k | grep -i reject` y un caso de troubleshooting.

**containerd** (paquete `containerd.io` del repositorio de Docker; RHEL no lo trae):

```bash
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf install -y containerd.io
containerd config default > /etc/containerd/config.toml       # el del paquete trae el plugin CRI desactivado
vim /etc/containerd/config.toml       # busca /SystemdCgroup y ponlo a true (mismo driver de cgroups que el kubelet)
grep -n 'SystemdCgroup\|enable_selinux' /etc/containerd/config.toml
systemctl enable --now containerd && systemctl status containerd --no-pager
```

> `enable_selinux = false` (por defecto) hace que los contenedores corran con el contexto del propio containerd. SELinux
> sigue en *enforcing* en el SO (la Etapa 5 no se rompe), pero no aísla los contenedores entre sí. En la 8.6 lo activas y
> ves qué se rompe: es un ejercicio, no un descuido.

**kubeadm, kubelet y kubectl** v1.36:

```bash
cat > /etc/yum.repos.d/kubernetes.repo <<'EOF'
[kubernetes]
name=Kubernetes v1.36
baseurl=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
dnf install -y kubelet-1.36.5 kubeadm-1.36.5 kubectl-1.36.5 --disableexcludes=kubernetes
systemctl enable kubelet            # se reiniciará en bucle hasta el init/join: es normal
crictl --runtime-endpoint unix:///run/containerd/containerd.sock info | head
```

El `exclude=` impide que un `dnf update` rutinario suba Kubernetes por sorpresa: las actualizaciones del clúster se
hacen a propósito (8.12).

### 8.2.3 Inicializar el plano de control (k8s-cp01)

```bash
# Desde el host: subir el fichero de configuración
scp scripts/stage8/files/cluster/kubeadm-config.yaml adminlab@k8s-cp01.lab.local:
# En k8s-cp01 (root). Léelo antes: cada decisión está comentada.
kubeadm config validate --config ~adminlab/kubeadm-config.yaml
kubeadm config images pull --config ~adminlab/kubeadm-config.yaml
kubeadm init --config ~adminlab/kubeadm-config.yaml --upload-certs | tee /root/kubeadm-init.log
```

Lee la salida: fases (`preflight`, `certs`, `kubeconfig`, `control-plane`, `etcd`, `upload-config`, `bootstrap-token`,
`addons`) y el comando `kubeadm join` del final. Después:

```bash
# kubectl para adminlab en k8s-cp01
mkdir -p ~adminlab/.kube && cp /etc/kubernetes/admin.conf ~adminlab/.kube/config && chown -R adminlab: ~adminlab/.kube
# Como adminlab
kubectl get nodes                          # NotReady: falta la red de pods
kubectl -n kube-system get pods -o wide    # coredns en Pending (por la misma razón)
ls /etc/kubernetes/manifests/              # pods ESTÁTICOS: el kubelet los arranca sin API
```

**Red de pods (Calico con su operador):**

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/tigera-operator.yaml
kubectl create -f calico-custom-resources.yaml             # (súbelo antes con scp, como kubeadm-config.yaml)
watch kubectl get tigerastatus                             # AVAILABLE True en todo
kubectl get nodes                                          # Ready
```

### 8.2.4 Unir los workers

```bash
# En k8s-cp01: el token del init caduca en 24 h; genera uno nuevo cuando lo necesites
kubeadm token create --print-join-command
# En k8s-w01 y k8s-w02 (root): pega el comando
kubeadm join k8s-api.lab.local:6443 --token ... --discovery-token-ca-cert-hash sha256:...
# En k8s-cp01
kubectl get nodes -o wide                                  # 3 x Ready, misma versión, containerd://...
kubectl label node k8s-w01 k8s-w02 node-role.kubernetes.io/worker=
```

### 8.2.5 Administrar desde ansible01

```bash
# En ansible01 (root): mismo repositorio de Kubernetes, solo kubectl
dnf install -y kubectl-1.36.5 --disableexcludes=kubernetes     # (crea antes el .repo de 8.2.2)
# Como adminlab
mkdir -p ~/.kube && scp adminlab@k8s-cp01.lab.local:.kube/config ~/.kube/config && chmod 600 ~/.kube/config
kubectl get nodes;  kubectl config get-contexts             # kubernetes-admin@lab-k8s
dnf list --installed bash-completion && echo 'source <(kubectl completion bash)' >> ~/.bashrc
```

**Helm** (lo usan la 8.4, 8.7 y 8.8; en la 8.7 se explica a fondo). Binario oficial con suma de verificación:

```bash
HELM_VERSION=v4.x.y      # la última 4.x estable de https://github.com/helm/helm/releases (anótala en el checklist)
curl -fsSLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum" | sha256sum -c
tar xzf "helm-${HELM_VERSION}-linux-amd64.tar.gz" && sudo install -m 0755 linux-amd64/helm /usr/local/bin/helm
helm version
```

> `admin.conf` es **cluster-admin** con un certificado que dura un año: trátalo como la contraseña de root. En la 8.6
> creas un usuario con permisos limitados para el día a día.

**Comprobación de la 8.2:** `kubectl get nodes` (3 Ready), `kubectl get pods -A` (todo Running),
`kubectl get --raw='/readyz?verbose'`, `kubectl -n kube-system get cm kubeadm-config -o yaml` (tu configuración),
`kubeadm certs check-expiration` (en cp01). Y `scripts/lab.sh test all k8s-cp01` sigue en 0 FAIL: la base del lab no se
rompe por montar Kubernetes encima.

---

## 8.3 Objetos de Kubernetes

Todo en el namespace `demo` (Pod Security `restricted`: los pods tienen que cumplir buenas prácticas para entrar).

```bash
cd ~/enterprise-rhel-lab/scripts/stage8/files        # tu copia del repo en ansible01 (git clone o scp)
kubectl apply -f apps/podinfo.yaml
kubectl -n demo get deploy,rs,pods,svc -o wide --show-labels
kubectl explain deployment.spec.strategy             # la documentación, en el propio clúster
```

| Ejercicio | Comandos | Qué observar |
|---|---|---|
| Jerarquía Deployment → ReplicaSet → Pod | `kubectl -n demo delete pod <uno>` | El ReplicaSet crea otro en segundos (estado deseado) |
| Escalar | `kubectl -n demo scale deploy/podinfo --replicas=4`; `get pods -o wide -w` | Reparto entre k8s-w01 y k8s-w02 |
| Actualización progresiva | `kubectl -n demo set env deploy/podinfo PODINFO_UI_MESSAGE="versión 2"`; `rollout status`; `rollout history` | Un ReplicaSet nuevo sube mientras el viejo baja: sin corte |
| Vuelta atrás | `kubectl -n demo rollout undo deploy/podinfo` | Vuelve el ReplicaSet anterior |
| ConfigMap y Secret | `kubectl -n demo create configmap podinfo-cfg --from-literal=PODINFO_UI_COLOR=#34577c`; `set env --from=configmap/podinfo-cfg`; `create secret generic` | `kubectl get secret -o yaml`: base64 **no** es cifrado |
| Etiquetas y selectores | `kubectl get pods -l 'app.kubernetes.io/name in (podinfo)'`; quita la etiqueta a un pod | El pod sale del ReplicaSet y del Service, y se crea otro |
| Job y CronJob | `kubectl -n demo create job pi --image=busybox:1.37 -- sh -c 'echo hola'` | **Falla por Pod Security**: lee el mensaje y corrígelo con un YAML que cumpla `restricted` |
| DaemonSet | `kubectl -n kube-system get ds` | calico-node, kube-proxy: uno por nodo |
| Eventos y descripción | `kubectl -n demo get events --sort-by=.lastTimestamp`; `kubectl describe` | La primera fuente de diagnóstico, siempre |

**Qué documentar:** la tabla con lo observado, y en una frase: Pod, ReplicaSet, Deployment, Service, ConfigMap, Secret,
Job, DaemonSet, namespace, etiqueta. Es el vocabulario de cualquier entrevista técnica de plataforma.

---

## 8.4 Red: Services, DNS, MetalLB, Ingress y NetworkPolicies

**Services y DNS interno:**

```bash
kubectl -n demo get svc podinfo; kubectl -n demo get endpointslices -l kubernetes.io/service-name=podinfo
kubectl run dnstest -it --rm --image=busybox:1.37 --restart=Never -- nslookup podinfo.demo.svc.cluster.local
kubectl run dnstest -it --rm --image=busybox:1.37 --restart=Never -- nslookup dns01.lab.local   # CoreDNS reenvía a dns01
kubectl -n kube-system get cm coredns -o yaml          # 'forward . /etc/resolv.conf' del nodo
```

(El namespace `default` no tiene Pod Security `restricted`: por eso aquí sí funciona `kubectl run` sin más.)

Mientras no haya MetalLB, el Service `podinfo` (tipo LoadBalancer) se queda en `EXTERNAL-IP <pending>`, pero ya tiene un
NodePort: `curl http://k8s-w01.lab.local:<nodeport>` funciona. Es la diferencia entre ClusterIP, NodePort y LoadBalancer.

**MetalLB** (las IPs .110-.119 de la red del lab, anunciadas por ARP):

```bash
kubectl create namespace metallb-system
kubectl label namespace metallb-system pod-security.kubernetes.io/enforce=privileged
helm repo add metallb https://metallb.github.io/metallb && helm repo update
helm install metallb metallb/metallb --version 0.16.1 -n metallb-system --wait
kubectl apply -f cluster/metallb-pool.yaml
kubectl -n demo get svc podinfo                       # EXTERNAL-IP 10.10.10.114
curl -s http://podinfo.lab.local | head               # desde el host o ansible01
arping -c2 -I virbr-lab 10.10.10.114                  # (en el host) ¿qué MAC responde? la de un nodo
```

`apps/podinfo.yaml` usa `externalTrafficPolicy: Local`: el tráfico solo entra por nodos con un pod de podinfo y conserva la
IP real del cliente. Compruébalo: `kubectl -n demo logs deploy/podinfo | grep -m3 remote` con `Local` y con `Cluster`.

**Ingress** con Traefik. `ingress-nginx` se ha retirado (anuncio en noviembre de 2025, sin mantenimiento desde marzo de
2026); las alternativas habituales son Traefik y los controladores de **Gateway API**, su sucesora.

```bash
kubectl create namespace traefik
helm repo add traefik https://traefik.github.io/charts && helm repo update
helm search repo traefik/traefik                      # fija la versión que vas a usar y anótala
helm install traefik traefik/traefik -n traefik --version <versión> \
  --set service.annotations."metallb\.io/loadBalancerIPs"=10.10.10.110
```

Crea un `Ingress` (y, como segunda práctica, un `HTTPRoute` de Gateway API) que publique podinfo por nombre en
`http://ingress.lab.local/` con la cabecera `Host`, y compara: una IP por servicio (LoadBalancer) frente a una IP para
muchos servicios (Ingress/Gateway).

**NetworkPolicies** (Calico las aplica; sin ellas, cualquier pod habla con cualquier pod):

```bash
kubectl apply -f apps/loadgen.yaml                    # tráfico constante desde dentro del namespace
kubectl apply -f apps/networkpolicies.yaml
# Desde loadgen: permitido
kubectl -n demo exec deploy/loadgen -- wget -qO- -T3 http://podinfo | head -3
# Desde otro namespace: bloqueado
kubectl run intruso -it --rm --image=busybox:1.37 --restart=Never -- wget -qO- -T3 http://podinfo.demo   # timeout
# Desde la red del lab (MetalLB): permitido por el ipBlock
curl -s -m3 http://podinfo.lab.local | head -3
```

Anota qué pasaría si borraras `podinfo-desde-monitoring` (spoiler: escenario E08 de la 8.8).

---

## 8.5 Almacenamiento: PV, PVC y StorageClass

Sin almacenamiento compartido, el lab usa **local-path-provisioner**: crea cada volumen como un directorio en el nodo
donde arranca el pod, en el LV `lv_localpath` de la 8.2.

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.37/deploy/local-path-storage.yaml
kubectl -n local-path-storage edit configmap local-path-config     # "paths":["/var/lib/local-path"]
kubectl -n local-path-storage rollout restart deploy/local-path-provisioner
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get storageclass                                            # local-path (default), WaitForFirstConsumer
```

Ejercicios:

1. Un PVC de 1Gi en `demo` + un Deployment de 1 réplica que escriba la fecha cada 10 s en el volumen (YAML que cumpla
   `restricted`). Mira el PVC en `Pending` hasta que existe el pod (*WaitForFirstConsumer*) y después `Bound`.
2. Borra el pod: el nuevo lee los datos anteriores. ¿En qué nodo está? `kubectl get pv -o yaml | grep -A5 nodeAffinity`.
3. `ls /var/lib/local-path/` en ese nodo: el volumen es un directorio. Contexto SELinux: `ls -Z`.
4. Piensa (y comprueba en el E07 de la 8.8) qué pasa si ese nodo cae: el pod **no** puede ir a otro nodo.
5. `reclaimPolicy: Delete`: borra el PVC y comprueba que el directorio desaparece.

**Qué documentar:** PV/PVC/StorageClass, `WaitForFirstConsumer`, `ReadWriteOnce`, por qué en producción se usa
almacenamiento de red (NFS, Ceph, cabinas con CSI; la Etapa 15 monta NFS) y que `local-path` **no publica métricas de
volumen** (`kubelet_volume_stats_*` sale vacío: lo verás en la 8.8).

---

## 8.6 Seguridad: RBAC, Pod Security, Secrets y SELinux

**Un usuario que no es administrador** (`dev-tienda`, con permisos solo en el namespace `tienda`):

```bash
kubectl create namespace tienda
openssl genrsa -out dev-tienda.key 3072
openssl req -new -key dev-tienda.key -subj "/CN=dev-tienda/O=equipo-tienda" -out dev-tienda.csr
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata: {name: dev-tienda}
spec:
  request: $(base64 -w0 < dev-tienda.csr)
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 2592000          # 30 días
  usages: [client auth]
EOF
kubectl certificate approve dev-tienda
kubectl get csr dev-tienda -o jsonpath='{.status.certificate}' | base64 -d > dev-tienda.crt
kubectl create rolebinding equipo-tienda-edit --clusterrole=edit --group=equipo-tienda -n tienda
# kubeconfig propio y pruebas
kubectl config set-credentials dev-tienda --client-certificate=dev-tienda.crt --client-key=dev-tienda.key --embed-certs
kubectl config set-context dev-tienda --cluster=lab-k8s --user=dev-tienda --namespace=tienda
kubectl --context dev-tienda auth can-i create deployments            # yes
kubectl --context dev-tienda auth can-i get pods -n demo              # no
kubectl --context dev-tienda auth can-i get nodes                     # no
kubectl auth can-i --list --as=dev-tienda --as-group=equipo-tienda -n tienda
```

**ServiceAccounts:** los pods también tienen identidad. Crea una ServiceAccount en `demo` con un Role que solo permita
`get/list pods`, úsala en un pod con `kubectl` y comprueba que no puede borrar nada. `automountServiceAccountToken: false`
cuando un pod no necesita hablar con la API.

**Pod Security Admission:**

```bash
kubectl label --dry-run=server --overwrite ns demo pod-security.kubernetes.io/enforce=restricted   # avisos de lo que ya incumple
kubectl -n demo run root --image=busybox:1.37 --restart=Never -- sleep 60      # rechazado: lee el mensaje entero
```

Niveles `privileged` / `baseline` / `restricted`, y modos `enforce` / `audit` / `warn`. ¿Por qué `monitoring` y
`metallb-system` son `privileged`?

**Secrets:** `kubectl get secret -o yaml | base64 -d`: cualquiera con `get secrets` en el namespace los lee, y en etcd
están **en claro** salvo que se configure cifrado en reposo (`EncryptionConfiguration` en el apiserver). Ampliación:
activarlo en k8s-cp01 y comprobar con `etcdctl get /registry/secrets/...` que ya no se lee el valor.

**SELinux en los contenedores** (ejercicio del aviso de la 8.2): pon `enable_selinux = true` en la sección CRI de
`/etc/containerd/config.toml` de **un** worker, reinicia containerd, drena y vuelve a habilitar el nodo
(`kubectl drain/uncordon`, 8.12). Mira con `ps -eZ | grep podinfo` el contexto `container_t` con categorías MCS distintas
por pod, y busca en `ausearch -m AVC -ts recent` qué se rompe (normalmente, volúmenes `hostPath` y local-path sin la
etiqueta `container_file_t`). Arréglalo con `semanage fcontext` + `restorecon`, nunca con `setenforce 0`. Es un caso de
troubleshooting de los buenos.

---

## 8.7 Helm: charts, valores y releases

Helm es el gestor de paquetes de Kubernetes: un **chart** es una plantilla de manifiestos, los **valores** la
personalizan y cada instalación es una **release** con historial.

```bash
helm list -A                                           # metallb y traefik ya son releases
helm -n metallb-system history metallb
helm -n metallb-system get values metallb --all | less
helm show chart metallb/metallb --version 0.16.1
helm template metallb metallb/metallb --version 0.16.1 | less     # lo que Helm aplicaría, sin aplicarlo
```

**Gitea** (repositorio Git dentro del clúster; la 8.11 lo usa para GitOps):

```bash
kubectl create namespace gitea
kubectl label namespace gitea pod-security.kubernetes.io/enforce=baseline
kubectl -n gitea create secret generic gitea-admin --from-literal=username=gitea-admin \
  --from-literal=password="$(openssl rand -base64 18)"          # apúntala antes de perderla de vista
helm repo add gitea-charts https://dl.gitea.com/charts/ && helm repo update
helm search repo gitea-charts/gitea                              # fija la versión y anótala
helm show values gitea-charts/gitea --version <versión> > /tmp/gitea-defaults.yaml
diff <(grep -E '^[a-z]' /tmp/gitea-defaults.yaml) <(grep -E '^[a-z]' apps/gitea-values.yaml)   # claves de primer nivel
helm install gitea gitea-charts/gitea -n gitea --version <versión> -f apps/gitea-values.yaml --wait --timeout 10m
kubectl -n gitea get pods,pvc,svc                                # PVC local-path Bound; LB .115
```

Entra en http://gitea.lab.local, crea la organización `lab` y el repositorio `k8s-apps`. Después:
`helm upgrade` cambiando un valor (p. ej. `resources`), `helm history`, `helm rollback gitea 1` y compara.

**Qué documentar:** chart, valores, release, revisión; `helm template` como herramienta de revisión; y por qué todos los
`helm install` del lab fijan `--version`.

---

## 8.8 Monitorización con Prometheus y Grafana

Guía completa con instalación y **13 escenarios reales** (CrashLoopBackOff, OOMKilled, CPU throttling, errores 5xx,
latencia, nodo caído, disco lleno, ServiceMonitor ignorado, NetworkPolicy que deja ciego a Prometheus, silencios de
Alertmanager, VMs fuera del clúster...): **[monitorizacion-prometheus-grafana.md](monitorizacion-prometheus-grafana.md)**.

## 8.9 Infraestructura como código con Terraform

Guía completa con 8 escenarios (plan, `import` de lo hecho a mano, módulos, drift, bloqueo de estado, CRDs,
`prevent_destroy`/`moved`, Terraform frente a Ansible): **[terraform-iac.md](terraform-iac.md)**.

---

## 8.10 OpenShift: Red Hat OpenShift Local (CRC) en el host

OpenShift es Kubernetes con todo lo que en la 8.2-8.9 has montado a mano ya integrado (red, registro de imágenes,
monitorización, rutas, consola web, actualizaciones gestionadas) y con seguridad más estricta por defecto.

**Requisitos:** 4 vCPU, ~10,5-11 GiB de RAM y 35 GB de disco **en el host**; cuenta gratuita de Red Hat Developer para
descargar `crc` y el *pull secret* (console.redhat.com → OpenShift → Local). Apaga el clúster kubeadm antes.

> **Antes de nada, en modo de solo lectura:** `crc setup` **modifica el host** (configura libvirt y su red `crc`,
> un `dnsmasq` de NetworkManager para `*.crc.testing` y `*.apps-crc.testing`, y grupos del usuario). Primero
> `crc setup --check-only` y anota qué dice que cambiaría. Decide con esa lista delante; si algo te preocupa, se queda
> en teoría y se practica en el Developer Sandbox de Red Hat (OpenShift en la nube, gratuito y temporal).

```bash
crc config set memory 11264 && crc config set cpus 4
crc setup --check-only            # SOLO LECTURA: revisa
crc setup                         # (tras revisarlo) cambios en el host
crc start -p ~/Descargas/pull-secret.txt
eval "$(crc oc-env)" && oc login -u developer https://api.crc.testing:6443
crc console --credentials
```

Ejercicios comparando con Kubernetes "a pelo":

| Ejercicio | OpenShift | Lo equivalente en el lab |
|---|---|---|
| `oc new-project tienda` | Proyecto = namespace con RBAC, cuotas y SCC listos | 8.6 a mano |
| Despliega `apps/podinfo.yaml` sin tocarlo | **Falla**: el SCC `restricted-v2` no admite `runAsUser: 100` (OpenShift asigna un UID del rango del proyecto). Quita `runAsUser` y vuelve a probar | Pod Security `restricted` (aquí sí valía) |
| `oc expose svc/podinfo` | **Route** con nombre `*.apps-crc.testing` | Ingress + Traefik + DNS (8.4) |
| `oc new-app` desde el repo de Gitea o GitHub (S2I) | Construye la imagen dentro del clúster | No hay: Podman fuera del clúster (8.1) |
| Consola web: *Observe* | Prometheus/Alertmanager integrados (en CRC desactivados por defecto: `crc config set enable-cluster-monitoring true`, pide 14 GiB) | 8.8 entero |
| `oc adm top`, `oc get clusteroperators`, `oc get clusterversion` | El clúster se gestiona con operadores y versiones del propio OpenShift | `kubeadm upgrade` (8.12) |

**OpenShift Virtualization** (KubeVirt) ejecuta VMs como objetos de Kubernetes y es la alternativa de Red Hat a vSphere
tras la compra de VMware por Broadcom. CRC no la soporta (no hay virtualización anidada suficiente): se estudia en teoría
y se relaciona con la Etapa 10 (VMware) y la 14 (migraciones). Anota en el checklist sus conceptos: `VirtualMachine`,
`DataVolume`, migración en vivo, Migration Toolkit for Virtualization.

`crc stop` al terminar; `crc delete` si necesitas liberar el disco. `crc cleanup` deshace lo que hizo `crc setup` en el host.

---

## 8.11 CI/CD y GitOps (Gitea + Argo CD)

**CI: validar antes de aplicar.** `scripts/stage8/files/ci/validar.sh` hace lo que haría un pipeline con cada cambio de la
etapa: `yamllint`, `kubeconform` (manifiestos frente al esquema de la API 1.36), `promtool` (reglas + pruebas unitarias de
alertas) y `terraform fmt`/`validate`. Sin clúster y sin tocar nada.

```bash
scripts/stage8/files/ci/validar.sh              # en ansible01 (instala antes yamllint, kubeconform y promtool)
#   == 3. promtool ... OK tests unitarios de alertas ... RESULTADO: OK
```

Rompe algo a propósito (un umbral de alerta en `rules/podinfo-slo.yaml` sin regenerar la copia de `tests/`, una coma en
un YAML, `terraform fmt` sin aplicar) y comprueba que lo detecta. Ampliación: un *runner* de Gitea Actions que lo ejecute
en cada `push` al repositorio `lab/k8s-apps`.

**CD con GitOps:** Argo CD vigila un repositorio Git y hace que el clúster coincida con él.

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.2/manifests/install.yaml
kubectl -n argocd patch svc argocd-server -p '{"spec":{"type":"LoadBalancer"},"metadata":{"annotations":{"metallb.io/loadBalancerIPs":"10.10.10.116"}}}'
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

1. Sube a `lab/k8s-apps` en Gitea una carpeta `podinfo-gitops/` con un Deployment y un Service (namespace `gitops`).
2. En Argo CD (https://argocd.lab.local): repositorio `http://gitea-http.gitea.svc.cluster.local/lab/k8s-apps.git` y una
   `Application` con *sync* automático, `prune` y `selfHeal`.
3. **Drift con autocorrección:** `kubectl -n gitops scale deploy/podinfo --replicas=5` y mira cómo Argo CD lo devuelve al
   valor de Git en segundos. Compáralo con el T4 de Terraform (allí el drift solo se ve al hacer `plan`).
4. **Despliegue = commit:** cambia `replicas` o un `env` en Gitea y mira cómo se aplica solo. **Vuelta atrás = `git revert`**.

**Qué documentar:** CI frente a CD, *push* (Terraform/Ansible/`kubectl apply`) frente a *pull* (GitOps), y quién debería
gestionar qué en el lab (plataforma con Terraform, aplicaciones con Argo CD).

---

## 8.12 Operación del clúster: mantenimiento, actualización y copias de etcd

**Mantenimiento de un nodo** (lo que se hace antes de parchear el SO):

```bash
kubectl drain k8s-w02 --ignore-daemonsets --delete-emptydir-data   # saca los pods (respetando PodDisruptionBudgets)
# en k8s-w02: dnf update -y && reboot   (Kubernetes está excluido del update)
kubectl uncordon k8s-w02
```
Crea un `PodDisruptionBudget` (`minAvailable: 1`) para podinfo y repite: el drain espera en vez de dejarte sin servicio.

**Copia de etcd** (todo el estado del clúster está ahí):

```bash
# En k8s-cp01 (root). etcdctl viene en la imagen de etcd; se usa desde el propio pod estático
kubectl -n kube-system exec etcd-k8s-cp01 -- etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /var/lib/etcd/snapshot-$(date +%F).db
ls -lh /var/lib/etcd/snapshot-*.db        # cópialo FUERA del nodo (ansible01): una copia en el mismo disco no es copia
```
Ejercicio de restauración (con snapshot de la VM antes): crea un namespace `borrame`, haz la copia, bórralo y restaura con
`etcdutl snapshot restore` en un directorio nuevo apuntando el manifiesto de etcd a él. El namespace vuelve.

**Actualización 1.36 → 1.37** (una versión menor cada vez; primero el plano de control, después los workers):

```bash
# k8s-cp01: repositorio v1.37 en /etc/yum.repos.d/kubernetes.repo
dnf install -y kubeadm-1.37.* --disableexcludes=kubernetes
kubeadm upgrade plan                       # lee qué va a cambiar
kubeadm upgrade apply v1.37.<z>
kubectl drain k8s-cp01 --ignore-daemonsets && dnf install -y kubelet-1.37.* kubectl-1.37.* --disableexcludes=kubernetes
systemctl daemon-reload && systemctl restart kubelet && kubectl uncordon k8s-cp01
# cada worker: drain -> kubeadm upgrade node -> kubelet -> uncordon
```
Antes de subir, comprueba la compatibilidad de Calico, MetalLB y kube-prometheus-stack con 1.37, y mira en Grafana
cómo se ve el upgrade (reinicios, nodos `SchedulingDisabled`). **Certificados:** `kubeadm certs check-expiration`
(caducan al año; el upgrade los renueva).

**Ampliación (opcional): Velero** para copias de objetos y volúmenes con destino S3 (MinIO en `dns01` o en el host).

---

## 8.13 Automatizar lo aprendido con Ansible

Con todo hecho a mano al menos una vez, en `ansible01` (proyecto `~/ansible-lab`, Etapa 7):

1. Rol `k8s_node`: LVs, swap, módulos, sysctl, NetworkManager, zona `k8s` de firewalld, containerd, paquetes v1.36.
   Criterio: **idempotente** (`changed=0` la segunda vez) y válido con `--check`.
2. Playbook `k8s-cluster.yml`: `kubeadm init` solo si no existe `/etc/kubernetes/admin.conf`, Calico, y `join` de los
   workers con un token generado al vuelo (`delegate_to: k8s-cp01`).
3. Rol `node_exporter` para las VMs del lab (lo de E12) y su `firewalld`.
4. **Prueba de fuego:** `kubeadm reset` + snapshot `stage5` en `k8s-w02` y reconstruirlo solo con Ansible hasta `Ready`.

En el checklist: qué hace ahora Ansible, qué Terraform y qué Argo CD (es el T8 de la 8.9 llevado a la práctica).
Si más adelante merece la pena, `lab.sh` tendrá comandos `stage8-*` que llamen a estos playbooks, como en la Etapa 7.

---

## Cierre de la etapa

- [ ] `checklists/etapa8.md` completo, con resultados **obtenidos**.
- [ ] `scripts/stage8/files/ci/validar.sh` en verde.
- [ ] `scripts/lab.sh test all <nodo>` con 0 FAIL en los tres nodos (la base del lab sigue sana).
- [ ] Casos reales en `troubleshooting/etapa8/` y su índice actualizado.
- [ ] Snapshots `*-stage8-complete` de los tres nodos (apagados).
