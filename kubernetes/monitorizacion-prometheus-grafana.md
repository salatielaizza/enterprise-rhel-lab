# Etapa 8.8 — Monitorización con Prometheus y Grafana: instalación y escenarios reales

> Parte de la [Etapa 8](etapa8-kubernetes-openshift.md). Se hace con el clúster de la 8.2 funcionando, MetalLB (8.4) y
> `local-path` (8.5). Todo a mano y en este orden; la 8.9 vuelve a desplegar lo mismo con Terraform.
> Ficheros: [`scripts/stage8/files/monitoring/`](../scripts/stage8/files/monitoring/).

## Qué vas a aprender

Prometheus y Grafana se aprenden **operando**: provocas una avería, la ves llegar a las métricas, salta una alerta, la
diagnosticas con `kubectl` y la arreglas. Esta guía tiene 13 escenarios de ese tipo, los que se ven en una guardia real.

| Pieza | Qué hace | Dónde la ves |
|---|---|---|
| **Prometheus** | Cada 30 s *rasca* (`scrape`) el `/metrics` de cada objetivo y guarda las series de tiempo | http://prometheus.lab.local (.112) |
| **Exporters** | Traducen algo a métricas: `node-exporter` (el SO del nodo), `kube-state-metrics` (el estado de los objetos de Kubernetes), el kubelet/cAdvisor (CPU y memoria de cada contenedor) | Status → Targets |
| **Reglas** | *Recording rules* precalculan series; *alerting rules* = consulta + umbral + `for:` | Alerts, Status → Rules |
| **Alertmanager** | Recibe las alertas, las agrupa, silencia, inhibe y las envía (correo, Teams, webhook...) | http://alertmanager.lab.local (.113) |
| **Grafana** | Dibuja dashboards consultando a Prometheus; no guarda métricas | http://grafana.lab.local (.111) |
| **Prometheus Operator** | Convierte objetos de Kubernetes en configuración: `ServiceMonitor` (qué rascar), `PrometheusRule` (reglas) | `kubectl get servicemonitor,prometheusrule -A` |

### PromQL en cinco minutos

```promql
up                                                   # 1 = el objetivo responde, 0 = caído (la consulta más útil)
http_requests_total{namespace="demo"}                # un CONTADOR: solo sube; su valor bruto no dice nada
rate(http_requests_total{namespace="demo"}[5m])      # peticiones/segundo (media de 5 min): así se usan los contadores
sum by (status) (rate(http_requests_total[5m]))      # agregar: tráfico por código de estado
container_memory_working_set_bytes{namespace="demo"} # un GAUGE: sube y baja (memoria en uso ahora)
histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))   # p95 de latencia
kube_pod_container_status_restarts_total > 0         # filtrar: series que cumplen la condición
```

Regla de oro: **contadores con `rate()`**, **gauges tal cual**, **histogramas con `histogram_quantile()`**.

---

## 1. Instalación (a mano)

```bash
# En ansible01 (kubectl y helm configurados en la 8.2/8.7)
kubectl create namespace monitoring
kubectl label namespace monitoring pod-security.kubernetes.io/enforce=privileged   # node-exporter usa hostNetwork/hostPID

# Contraseña de Grafana: aleatoria, en un Secret (el chart la lee; nunca "admin/prom-operator")
GPW="$(openssl rand -base64 18)"; echo "Grafana admin: $GPW"   # apúntala en tu gestor de contraseñas
kubectl -n monitoring create secret generic grafana-admin --from-literal=admin-user=admin --from-literal=admin-password="$GPW"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
cd ~/enterprise-rhel-lab/scripts/stage8/files/monitoring      # tu copia del repo en ansible01
helm show values prometheus-community/kube-prometheus-stack --version 88.6.2 | less   # LEE antes de instalar
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version 88.6.2 -n monitoring -f kube-prometheus-stack-values.yaml --wait --timeout 15m

kubectl -n monitoring get pods -o wide        # operator, prometheus, alertmanager, grafana, kube-state-metrics, node-exporter x3
kubectl -n monitoring get svc | grep LoadBalancer   # .111 grafana, .112 prometheus, .113 alertmanager
```

Después, el resto de piezas del lab:

```bash
kubectl apply -f alertmanager/alert-receiver.yaml         # el "móvil de guardia"
kubectl apply -f servicemonitor-podinfo.yaml              # que Prometheus rasque podinfo
kubectl apply -f rules/podinfo-slo.yaml -f rules/lab-vms.yaml
kubectl apply -f dashboards/podinfo-red.yaml              # dashboard como código
kubectl apply -f ../apps/loadgen.yaml                     # tráfico constante contra podinfo
```

Deja abierta una terminal con la guardia:

```bash
kubectl -n monitoring logs -f deploy/alert-receiver
#   FIRING    critical PodinfoErroresAltos ns=demo pod=- :: podinfo: 12% de respuestas 5xx (umbral 5 %)
#   RESOLVED  critical PodinfoErroresAltos ...
```

**Comprobación inicial** (anótala en el checklist):

- Prometheus → *Status → Targets*: todo `UP`. Si algo sale `DOWN`, es el escenario E00.
- Prometheus → *Alerts*: solo `Watchdog` disparada (es la alerta que **siempre** suena: si un día deja de llegar, el
  sistema de alertas está roto).
- Grafana → *Dashboards*: carpeta con ~25 dashboards de serie + **Lab · podinfo (RED)**.

### Las reglas también se prueban (sin clúster)

```bash
promtool test rules tests/podinfo-slo.test.yaml     # SUCCESS: la alerta salta a los 10 min de un 10 % de errores
```

`promtool` viene en el tarball de Prometheus (GitHub releases). Es lo que un pipeline de CI ejecuta antes de aceptar
una regla nueva (8.11).

---

## 2. Escenarios

Formato de cada uno: **situación** (como te llegaría en una guardia) · **provocar** · **qué ves** · **diagnóstico** ·
**solución** · **qué documentar**. Haz cada escenario, rellena su fila en `checklists/etapa8.md` y, si algo no sale como
dice la guía, ábrelo como caso en `troubleshooting/etapa8/`.

Todos los manifiestos de `scenarios/` llevan la etiqueta `lab/escenario`. Al terminar cada uno, limpia para que sus alertas no
se mezclen con las del siguiente:

```bash
kubectl -n demo delete deploy,svc,servicemonitor,networkpolicy -l lab/escenario     # lo de los escenarios
kubectl -n demo set env deploy/loadgen PATHS="/"                                      # tráfico normal (E04/E05)
```

### E00 — Falsas alarmas el primer día: `TargetDown` del plano de control

**Situación.** Recién instalado, ya hay alertas de `KubeControllerManagerDown`, `KubeSchedulerDown` o `etcd`.

**Por qué pasa.** kubeadm deja esos componentes escuchando métricas solo en `127.0.0.1`. Este lab ya lo evita en
`kubeadm-config.yaml` (`bind-address: 0.0.0.0`, `listen-metrics-urls`, `metricsBindAddress`). Si te salen, es que el
clúster se creó sin ese fichero o firewalld bloquea los puertos.

**Diagnóstico.**
```bash
# En k8s-cp01
sudo ss -ltnp | grep -E ':(10257|10259|2381|10249) '      # ¿127.0.0.1 o 0.0.0.0/*?
sudo firewall-cmd --list-all                              # ¿están abiertos para 10.10.10.0/24?
grep -n bind-address /etc/kubernetes/manifests/kube-*.yaml
```
**Solución.** Editar los manifiestos estáticos de `/etc/kubernetes/manifests/` (el kubelet reinicia el pod solo) y abrir los
puertos solo a la red del lab. **Documenta** el equilibrio entre seguridad (exponer métricas) y observabilidad.

### E01 — `CrashLoopBackOff`: una versión nueva que no arranca

**Situación.** "El servicio de pagos no levanta tras el despliegue de esta mañana."

```bash
kubectl apply -f scenarios/e01-crashloop.yaml
kubectl -n demo get pods -w                      # Running -> Error -> CrashLoopBackOff, RESTARTS sube
```
**Qué ves.**
- Prometheus: `increase(kube_pod_container_status_restarts_total{namespace="demo"}[10m]) > 0` y
  `kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} == 1`.
- Grafana: panel "Reinicios de contenedores" del dashboard del lab.
- Alerta de serie **`KubePodCrashLooping`** (tiene `for: 15m`: tarda; mientras tanto la ves *Pending* en Alerts).

**Diagnóstico.**
```bash
kubectl -n demo describe pod -l app.kubernetes.io/name=e01-crash | sed -n '/State:/,/Events/p'   # Exit Code
kubectl -n demo logs deploy/e01-crash --previous      # el log del arranque que falló: "unknown flag: --puerto"
```
**Solución.** Corregir el parámetro (`--port`) o `kubectl -n demo rollout undo deploy/<app>` si había versión anterior.
**Lección:** `logs --previous` es el log del contenedor que murió; sin `--previous` ves el que está arrancando.

### E02 — `OOMKilled`: la memoria supera el límite

**Situación.** "La aplicación se reinicia sola cada pocos minutos, sin errores en el log."

```bash
kubectl apply -f scenarios/e02-oomkill.yaml
kubectl -n demo get pod -l app.kubernetes.io/name=e02-memoria -w
```
**Qué ves.**
- Prometheus: `kube_pod_container_status_last_terminated_reason{reason="OOMKilled"} == 1` y
  `container_memory_working_set_bytes{namespace="demo",container="app"}` subiendo hasta el límite (128 Mi).
- Alerta propia **`ContenedorOOMKilled`** en la terminal de guardia.

**Diagnóstico.**
```bash
kubectl -n demo describe pod -l app.kubernetes.io/name=e02-memoria | grep -A3 'Last State'   # Reason: OOMKilled, Exit Code: 137
kubectl top pod -n demo          # requiere metrics-server (opcional en el lab; Prometheus da lo mismo)
```
**Solución.** Si la app necesita esa memoria → subir `limits.memory` (y `requests`, para que el scheduler lo tenga en
cuenta). Si es una fuga → no hay límite que la arregle. **Documenta** la diferencia entre `requests` (reserva para
planificar) y `limits` (techo que el kernel aplica con el OOM killer: exit 137 = 128 + SIGKILL 9).

### E03 — CPU throttling: lenta pero "sin errores"

**Situación.** "La API va lenta, la CPU del nodo está al 20 % y no hay errores."

```bash
kubectl apply -f scenarios/e03-cpu-throttling.yaml
```
**Qué ves.**
```promql
# Porcentaje de periodos en que el contenedor quiso CPU y el límite se la negó
sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{namespace="demo"}[5m]))
  / sum by (pod) (rate(container_cpu_cfs_periods_total{namespace="demo"}[5m]))
```
- Alerta de serie **`CPUThrottlingHigh`** (severidad *info*: la ves en *Alerts*, pero no llega a la guardia; la ruta solo
  envía *warning* y *critical*, a propósito).

**Lección.** El nodo tiene CPU libre, pero el **límite** del contenedor (100m) la raciona. Es la causa más común de
"lento sin motivo" en Kubernetes. **Documenta** cuándo quitar límites de CPU (dejando `requests`) y cuándo no.

### E04 — Errores 5xx: el método RED y una alerta de SLO

**Situación.** "Los clientes ven errores intermitentes."

```bash
kubectl -n demo set env deploy/loadgen PATHS="/ /status/500 /status/503"
```
**Qué ves.**
- Grafana, **Lab · podinfo (RED)**: "Tráfico por código de estado" con 500/503 y "% de errores 5xx" cruzando la línea del 5 %.
- A los ~2 min, **`PodinfoErroresAltos`** (crítica) en la terminal de guardia; al quitar los errores, `RESOLVED`.

```promql
podinfo:http_errors:ratio_rate5m                                 # la regla de grabación
sum by (status) (rate(http_requests_total{namespace="demo"}[1m]))   # el desglose
```
**Vuelta atrás:** `kubectl -n demo set env deploy/loadgen PATHS="/"`.
**Lección.** Por qué se alerta sobre el **ratio** de errores (lo que nota el usuario) y no sobre el número absoluto, y
por qué hay `for: 2m` (un error suelto no despierta a nadie).

### E05 — Latencia: percentiles, no medias

```bash
kubectl -n demo set env deploy/loadgen PATHS="/ / / /delay/2"
```
**Qué ves.** En "Latencia p50 / p95 / p99", el p50 casi no se mueve y el p95/p99 sube a ~2 s: 1 de cada 4 peticiones es
lenta. **`PodinfoLatenciaAlta`** (warning). Compara con la media:
```promql
sum(rate(http_request_duration_seconds_sum{namespace="demo"}[5m])) / sum(rate(http_request_duration_seconds_count{namespace="demo"}[5m]))
```
**Lección.** La media esconde a los usuarios lentos; los SLO de latencia se escriben con percentiles.

### E06 — Pod vivo pero no listo (readiness)

```bash
POD=$(kubectl -n demo get pod -l app.kubernetes.io/name=podinfo -o name | head -1)
kubectl -n demo exec "$POD" -- curl -s -X POST http://localhost:9898/readyz/disable
kubectl -n demo get pods -l app.kubernetes.io/name=podinfo        # READY 0/1, STATUS Running
kubectl -n demo get endpointslices -l kubernetes.io/service-name=podinfo -o wide   # solo queda una IP
```
**Qué ves.** `kube_pod_status_ready{namespace="demo",condition="false"} == 1`; la alerta de serie `KubeDeploymentReplicasMismatch`
(tras 15 min). **Lección:** *liveness* reinicia, *readiness* saca del balanceo sin reiniciar. Arreglo:
`kubectl -n demo exec "$POD" -- curl -s -X POST http://localhost:9898/readyz/enable` (o borra el pod).

### E07 — Se cae un nodo

**Situación.** "Ha caído un servidor físico" (aquí, una VM).

```bash
# En el host
virsh shutdown k8s-w02        # apagado limpio; para un fallo "duro": virsh destroy k8s-w02
```
**Qué ves.**
- `kubectl get nodes` → `NotReady` a los ~40 s. Alerta **`KubeNodeNotReady`** (15 min) y `TargetDown` de su node-exporter y
  su kubelet antes.
- `up{job="node-exporter"} == 0` para ese nodo.
- Los pods de k8s-w02 siguen "Running" un rato (el plano de control no puede saber si murieron): a los 5 min
  (`tolerationSeconds: 300`) se marcan para desalojo y se crean de nuevo en k8s-w01.

**Diagnóstico.** `kubectl describe node k8s-w02` (Conditions: `Unknown`, "Kubelet stopped posting node status").
**Vuelta atrás.** `virsh start k8s-w02`. **Documenta** la línea temporal real (cuándo NotReady, cuándo la alerta, cuándo
se movieron los pods) y qué pasa con un pod con PVC `local-path` atado a ese nodo (no se puede mover: E07 + 8.5).

### E08 — Prometheus no ve una aplicación nueva (`ServiceMonitor` ignorado)

**Situación.** "Hemos desplegado el catálogo y en Grafana no sale nada."

```bash
kubectl apply -f scenarios/e08-servicemonitor-ignorado.yaml
```
**Diagnóstico, en orden** (es el método que sirve para cualquier "no veo métricas"):
1. ¿La app expone métricas? Desde dentro del propio pod (sin depender de la red ni de PSA):
   `kubectl -n demo exec deploy/catalogo -- curl -s localhost:9898/metrics | grep -m3 http_requests_total`
2. ¿Prometheus tiene el objetivo? *Status → Targets*: no aparece `serviceMonitor/demo/catalogo`.
3. ¿El Prometheus selecciona ese ServiceMonitor?
   ```bash
   kubectl -n monitoring get prometheus kps-prometheus -o jsonpath='{.spec.serviceMonitorSelector}'; echo
   # {"matchLabels":{"release":"kube-prometheus-stack"}}  -> al ServiceMonitor le falta esa etiqueta (fallo 1)
   kubectl -n demo label servicemonitor catalogo release=kube-prometheus-stack
   ```
4. El objetivo aparece en *Status → Service Discovery*, pero con 0 activos: el ServiceMonitor pide `port: metrics` y el
   Service lo llama `http` (fallo 2).
   ```bash
   kubectl -n demo get svc catalogo -o jsonpath='{.spec.ports[*].name}'; echo        # http
   kubectl -n demo patch servicemonitor catalogo --type=json -p '[{"op":"replace","path":"/spec/endpoints/0/port","value":"http"}]'
   ```
5. Si aplicaste las NetworkPolicies de la 8.4, ahora sale **DOWN** con `context deadline exceeded` y salta `TargetDown`
   (fallo 3): la política "denegar por defecto" de `demo` no deja entrar a Prometheus en `catalogo`, solo en `podinfo`.
   ```bash
   kubectl -n demo get networkpolicy                                   # ninguna selecciona app.kubernetes.io/name=catalogo
   kubectl apply -f scenarios/e08-solucion-networkpolicy.yaml          # abre solo monitoring -> catalogo:9898
   ```
   A los ~30 s, `UP`. Prueba la otra cara: `kubectl -n demo delete networkpolicy podinfo-desde-monitoring` y mira cómo
   podinfo pasa a DOWN y el dashboard se queda sin datos; vuelve a aplicar `../apps/networkpolicies.yaml`.

**Lección.** Etiquetas, nombres de puerto y políticas de red son el 90 % de los "no aparece en Prometheus". Una
NetworkPolicy mal hecha se nota antes en la monitorización que en ningún otro sitio. **Documenta** los 5 pasos.
**Limpieza:** `kubectl delete -f scenarios/e08-solucion-networkpolicy.yaml -f scenarios/e08-servicemonitor-ignorado.yaml`.

### E09 — Despliegue con una imagen que no existe

```bash
kubectl apply -f scenarios/e09-imagen-inexistente.yaml
kubectl -n demo get pods -l app.kubernetes.io/name=e09-version        # ErrImagePull -> ImagePullBackOff
```
**Qué ves.** `kube_pod_container_status_waiting_reason{reason=~"ErrImagePull|ImagePullBackOff"} == 1`;
`KubePodNotReady` y `KubeDeploymentReplicasMismatch` (15 min). **Diagnóstico:** `kubectl describe pod` (Events: "manifest
unknown"). **Lección:** si fuera una *actualización* de un Deployment existente, el rollout se queda a medias y las réplicas
viejas siguen sirviendo: `kubectl rollout status` + `rollout undo`.

### E10 — Disco del nodo lleno: alertas y desalojo de pods

```bash
# En k8s-w01: llenar el LV del kubelet hasta >90 %
df -h /var/lib/kubelet
sudo fallocate -l 5G /var/lib/kubelet/relleno-e10.img      # ajusta el tamaño para dejar <10 % libre
```
**Qué ves.** **`NodoK8sDiscoCasiLleno`** (regla del lab, 2 min) y, más tarde, las de serie `NodeFilesystemAlmostOutOfSpace`.
El kubelet marca `DiskPressure` y **desaloja pods** (`kubectl get pods -A | grep Evicted`; `kubectl describe node k8s-w01`).
**Vuelta atrás:** `sudo rm /var/lib/kubelet/relleno-e10.img` (y `kubectl delete pod -A --field-selector=status.phase=Failed`).
**Lección:** por qué el lab separa `/var/lib/kubelet`, `/var/lib/containerd` y `/var/lib/local-path` en LVs propios
(caso etapa2/11: `/var` lleno), y qué umbrales usa el kubelet (`evictionHard`).

### E11 — Ventana de mantenimiento: silencios, agrupación e inhibición

**Situación.** "Mañana a las 10:00 se reinicia k8s-w02 por parches: que no salte la guardia."

1. Alertmanager → *New Silence*: `instance=~"10.10.10.102.*"` o `node="k8s-w02"`, 30 min, comentario con el número de cambio.
   Repite E07 y comprueba que la terminal de guardia no recibe nada; en *Alerts* siguen visibles (silenciadas).
2. Agrupación: provoca E04 y E05 a la vez y mira cuántos mensajes llegan (`group_by: [alertname, namespace]`).
3. Inhibición: con una alerta *critical* y una *warning* del mismo `alertname`/`namespace`, solo llega la *critical*
   (`inhibit_rules` del fichero de valores).
4. Por CLI: `kubectl -n monitoring exec sts/alertmanager-kps-alertmanager -- amtool silence query --alertmanager.url=http://localhost:9093`

**Documenta** una mini política de guardia: qué es *critical* (despierta) y qué es *warning* (horario laboral).

### E12 — Monitorizar las VMs de fuera del clúster (dns01)

Prometheus no solo vigila Kubernetes. Instala `node_exporter` v1.12.1 en `dns01` (y `ansible01`):

```bash
# En dns01 (como root). Binario oficial + usuario sin privilegios + unidad systemd
curl -sSLO https://github.com/prometheus/node_exporter/releases/download/v1.12.1/node_exporter-1.12.1.linux-amd64.tar.gz
curl -sSL https://github.com/prometheus/node_exporter/releases/download/v1.12.1/sha256sums.txt | grep linux-amd64.tar.gz | sha256sum -c
tar xzf node_exporter-1.12.1.linux-amd64.tar.gz && install -m 0755 node_exporter-1.12.1.linux-amd64/node_exporter /usr/local/bin/
useradd --system --no-create-home --shell /sbin/nologin node_exporter
cat > /etc/systemd/system/node_exporter.service <<'EOF'
[Unit]
Description=Prometheus node_exporter
After=network-online.target
[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter --collector.systemd --collector.systemd.unit-include=(named|chronyd|sshd)\.service
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
restorecon -v /usr/local/bin/node_exporter && systemctl daemon-reload && systemctl enable --now node_exporter
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.10.10.0/24" port port="9100" protocol="tcp" accept' && firewall-cmd --reload
```
El job `lab-vms` ya está en los valores del chart. Comprueba `up{job="lab-vms"}` y después:

```bash
sudo systemctl stop named        # en dns01 -> DNSdelLabParado (1 min); arráncalo y llega RESOLVED
virsh shutdown dns01             # en el host -> VMDelLabCaida
```
**Lección:** la misma plataforma de alertas para contenedores y para servidores clásicos. La Etapa 17 extiende esto a
todo el lab (y a los ESXi de la Etapa 9). Hacerlo con Ansible para todas las VMs es un buen ejercicio de la 8.13.

---

## 3. Grafana: práctica guiada

1. **Explorar**: *Explore* → origen Prometheus → escribe las consultas de PromQL de arriba y cambia el rango de tiempo.
2. **Dashboards de serie**: "Kubernetes / Compute Resources / Namespace (Pods)" (demo), "Node Exporter / Nodes".
   Busca en ellos el efecto de E02, E03 y E07.
3. **Importar** el dashboard comunitario *Node Exporter Full* (ID **1860**): *Dashboards → New → Import*. Compáralo con el
   de serie: ¿qué paneles te ayudarían en E10?
4. **Tu dashboard como código**: edita `dashboards/podinfo-red.yaml` (por ejemplo, un panel de "pods no listos" con
   `sum(kube_pod_status_ready{namespace="demo",condition="false"})`), `kubectl apply` y recarga. Cambiarlo en la web
   **no persiste**: el sidecar vuelve a cargar el ConfigMap.
5. **Variables**: añade una variable `namespace` (`label_values(kube_pod_info, namespace)`) y úsala en las consultas.
6. **Usuarios**: crea un usuario *Viewer* para "el equipo de aplicación" (mínimo privilegio).

## 4. Qué documentar al terminar la 8.8

- Tabla de escenarios del checklist con lo **observado** (tiempos reales hasta la alerta, capturas en `prints/etapa8/`).
- Las consultas PromQL que más te han servido, con una frase de qué responde cada una.
- Cada sorpresa como caso en `troubleshooting/etapa8/NN-*.md` (plantilla del proyecto).
