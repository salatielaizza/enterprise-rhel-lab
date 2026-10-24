# ☸️ Etapa 8 — Kubernetes y OpenShift (`scripts/stage8/`)

> **Estado: 🚧 Pendiente.** Guía paso a paso: [`kubernetes/etapa8-kubernetes-openshift.md`](../../kubernetes/etapa8-kubernetes-openshift.md).
> Checklist: [`checklists/etapa8.md`](../../checklists/etapa8.md).

## Qué hay aquí

Esta etapa se hace **a mano**: no hay comandos `lab.sh stage8-*` (todavía). Esta carpeta guarda los **ficheros** que la
guía aplica con `kubectl`, `helm` y `terraform` desde `ansible01`, para que todo lo desplegado esté en el repositorio y
revisado, no escrito sobre la marcha en la terminal.

Las VMs sí usan `lab.sh` (`vm-create`, `stage2`-`stage5`, `test`, `snapshot`) con `k8s-cp01`, `k8s-w01` y `k8s-w02`,
que son **opcionales** en `scripts/hosts.conf` (no entran en `all`).

## Ficheros

| Fichero | Subetapa | Qué es |
|---|---|---|
| `files/cluster/kubeadm-config.yaml` | 8.2 | Configuración de `kubeadm init`: endpoint `k8s-api.lab.local`, redes de pods/servicios, métricas del plano de control fuera de 127.0.0.1, cgroups de systemd, rotación de logs |
| `files/cluster/calico-custom-resources.yaml` | 8.2 | Red de pods con el operador de Calico (VXLAN, 10.244.0.0/16) |
| `files/cluster/metallb-pool.yaml` | 8.4 | IPs .110-.119 del lab para los Service `LoadBalancer` (anuncio L2/ARP) |
| `files/apps/podinfo.yaml` | 8.3 | Aplicación de ejemplo con métricas y averías provocables (`demo`, Pod Security `restricted`) |
| `files/apps/loadgen.yaml` | 8.4, 8.8 | Generador de tráfico; `PATHS` decide si pide errores o respuestas lentas |
| `files/apps/networkpolicies.yaml` | 8.4 | Denegar por defecto en `demo` y abrir solo lo necesario |
| `files/apps/gitea-values.yaml` | 8.7 | Valores de Helm para Gitea en una sola réplica con SQLite |
| `files/monitoring/kube-prometheus-stack-values.yaml` | 8.8 | Prometheus, Alertmanager (rutas de guardia, inhibición) y Grafana; job `lab-vms` para las VMs de fuera del clúster |
| `files/monitoring/servicemonitor-podinfo.yaml` | 8.8 | Qué y cómo rasca Prometheus en podinfo |
| `files/monitoring/rules/*.yaml` | 8.8 | Reglas de grabación y alertas propias (RED de podinfo, VMs del lab, disco de los nodos) |
| `files/monitoring/dashboards/podinfo-red.yaml` | 8.8 | Dashboard de Grafana como código (ConfigMap que carga el sidecar) |
| `files/monitoring/alertmanager/alert-receiver.yaml` | 8.8 | "Móvil de guardia": webhook que imprime las alertas en su log |
| `files/monitoring/scenarios/e*.yaml` | 8.8 | Averías de los escenarios E01, E02, E03, E08 y E09 (etiqueta `lab/escenario`) |
| `files/monitoring/tests/*` | 8.8, 8.11 | Pruebas unitarias de las alertas con `promtool test rules` |
| `files/terraform/10-plataforma/` | 8.9 | Namespaces con cuotas, MetalLB y kube-prometheus-stack como código (estado en el clúster) |
| `files/terraform/20-config/` | 8.9 | Pool de MetalLB y aplicaciones monitorizadas (usa CRDs de la capa 10) |
| `files/terraform/modules/app-monitorizada/` | 8.9 | Módulo: Deployment + Service + ServiceMonitor + alerta de errores |
| `files/ci/validar.sh` | 8.11 | "CI" local: yamllint, kubeconform, promtool y terraform fmt/validate. Solo lee |

## Cómo se usan

```bash
# En ansible01, con el repositorio clonado (o copiado) en ~/enterprise-rhel-lab
cd ~/enterprise-rhel-lab/scripts/stage8/files
kubectl apply -f apps/podinfo.yaml                          # cada subetapa de la guía dice qué aplicar y en qué orden
ci/validar.sh                                               # antes de subir cualquier cambio de esta carpeta
```

Los ficheros de `cluster/` se copian con `scp` a `k8s-cp01` (la guía lo indica en la 8.2).

## Qué se ha validado sin clúster

`ci/validar.sh` en verde: YAML (yamllint), manifiestos (kubeconform contra la API 1.36), reglas y pruebas de alertas
(promtool) y formato de Terraform. **No** se han podido comprobar aquí `terraform validate` ni `helm template` (los
providers y charts se descargan al ejecutarlos en `ansible01`): son lo primero que se hace en la 8.9 (T1) y la 8.8.

## Snapshots

`*-stage5-complete` de los tres nodos antes de la 8.2 y `*-stage8-complete` al cerrar la etapa
(`scripts/lab.sh snapshot create k8s-cp01 8`, ídem workers). Entre medias, `virsh snapshot-create-as` con los nodos apagados.
