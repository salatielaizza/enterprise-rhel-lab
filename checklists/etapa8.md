# ETAPA 8 — CHECKLIST: Kubernetes y OpenShift, con Prometheus/Grafana y Terraform

> Una etapa **no está completa** hasta marcar TODO: documentación + tests + troubleshooting + snapshot.
> Rellena "Resultado obtenido" con lo que veas **de verdad** (salidas en `results/etapa8/`, capturas en `prints/etapa8/`).
> Guía: [`kubernetes/etapa8-kubernetes-openshift.md`](../kubernetes/etapa8-kubernetes-openshift.md).

## Objetivo
Clúster Kubernetes de 3 nodos (RHEL 9, kubeadm, containerd, Calico) operado como en producción: red, almacenamiento,
seguridad y Helm; monitorizado con Prometheus/Grafana provocando averías reales; gestionado como código con Terraform;
comparado con OpenShift; con CI/GitOps y automatización con Ansible de lo que antes se hizo a mano.

## Versiones usadas (anota las reales)
| Componente | Prevista | Usada |
|---|---|---|
| Kubernetes | v1.36.5 → v1.37.x | |
| containerd.io | (repo de Docker) | |
| Calico | v3.32.1 | |
| MetalLB (chart) | 0.16.1 | |
| Traefik (chart) | (la de `helm search`) | |
| local-path-provisioner | v0.0.37 | |
| Helm | 4.x | |
| Gitea (chart) | (la de `helm search`) | |
| kube-prometheus-stack | 88.6.2 | |
| Terraform | 1.16.x | |
| Argo CD | v3.5.2 | |
| OpenShift Local (crc) | | |

## 8.1 Podman
| # | Prueba | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 1 | `podman run` de podinfo rootless en ansible01 | Responde en :8080; el proceso es de `adminlab` en el host | |
| 2 | Imagen propia desde UBI 9 con `USER 1001` | `podman build` + `podman history` con las capas | |
| 3 | Volumen con y sin `:Z` | Sin `:Z`, `Permission denied` (AVC); con `:Z`, contexto `container_file_t` | |
| 4 | `podman kube generate` y Quadlet | YAML de Pod; contenedor arrancado por systemd tras reiniciar | |

## 8.2 Clúster con kubeadm
| # | Prueba | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 5 | `lab.sh test all k8s-*` antes de Kubernetes | 0 FAIL en los 3 nodos; snapshots `*-stage5-complete` | |
| 6 | LVs `lv_containerd` 16G, `lv_kubelet` 6G, `lv_localpath` 8G montados | `df -h` y `/etc/fstab`; contexto SELinux restaurado | |
| 7 | Swap desactivada, módulos y sysctl | `swapon --show` vacío; `ip_forward = 1` | |
| 8 | Zona `k8s` de firewalld | Orígenes del lab, pods y servicios; SSH sigue funcionando | |
| 9 | containerd con `SystemdCgroup = true` | `systemctl is-active containerd`; `crictl info` | |
| 10 | `kubeadm init --config kubeadm-config.yaml` | Fases completas; comando `join` | |
| 11 | Calico | `kubectl get tigerastatus` todo `AVAILABLE`; nodo `Ready` | |
| 12 | `join` de los workers | `kubectl get nodes`: 3 Ready, v1.36.5 | |
| 13 | kubectl y Helm en ansible01 | `kubectl get nodes` desde ansible01; `helm version` | |
| 14 | Salud | `/readyz?verbose` ok; `kubeadm certs check-expiration`; `test all k8s-cp01` 0 FAIL | |

## 8.3 a 8.7
| # | Prueba | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 15 | podinfo en `demo`: borrar un pod, escalar, *rollout* y *undo* | Recreación automática; ReplicaSets nuevo y viejo; vuelta atrás | |
| 16 | Job en `demo` con `kubectl create job` | Rechazado por Pod Security; corregido con YAML `restricted` | |
| 17 | DNS de pods | `podinfo.demo.svc.cluster.local` y `dns01.lab.local` resuelven | |
| 18 | MetalLB | `podinfo` con `EXTERNAL-IP 10.10.10.114`; `curl http://podinfo.lab.local` | |
| 19 | Ingress con Traefik (.110) | podinfo por `http://ingress.lab.local` con `Host`; también con `HTTPRoute` | |
| 20 | NetworkPolicies | loadgen y red del lab permitidos; `intruso` desde `default` con timeout | |
| 21 | local-path | PVC `WaitForFirstConsumer` → `Bound`; datos sobreviven al pod; directorio en `/var/lib/local-path` | |
| 22 | RBAC `dev-tienda` | `can-i create deployments -n tienda` yes; en `demo` y nodos no | |
| 23 | SELinux en contenedores (`enable_selinux = true` en un worker) | `container_t` con MCS por pod; AVC encontrados y arreglados con `semanage fcontext` | |
| 24 | Gitea con Helm | Pod Running, PVC Bound, http://gitea.lab.local; `upgrade` + `rollback` | |

## 8.8 Prometheus y Grafana ([escenarios](../kubernetes/monitorizacion-prometheus-grafana.md))
| # | Escenario | Alerta / señal esperada | Tiempo hasta la alerta y observaciones |
|---|---|---|---|
| 25 | Instalación | Targets UP; solo `Watchdog`; dashboard "Lab · podinfo (RED)" | |
| 26 | `promtool test rules` | SUCCESS | |
| 27 | E00 falsos `TargetDown` | Ninguno (o explicado y corregido) | |
| 28 | E01 CrashLoopBackOff | `KubePodCrashLooping`; `logs --previous` | |
| 29 | E02 OOMKilled | `ContenedorOOMKilled`; exit 137 | |
| 30 | E03 CPU throttling | `CPUThrottlingHigh` (info, no llega a la guardia) | |
| 31 | E04 errores 5xx | `PodinfoErroresAltos` FIRING y RESOLVED en la guardia | |
| 32 | E05 latencia | `PodinfoLatenciaAlta`; p95/p99 frente a media | |
| 33 | E06 readiness | Pod `0/1` fuera de los EndpointSlices | |
| 34 | E07 nodo caído | `NotReady`, `KubeNodeNotReady`, pods recreados a los ~5 min | |
| 35 | E08 ServiceMonitor ignorado (3 fallos) | Etiqueta, nombre de puerto y NetworkPolicy encontrados | |
| 36 | E09 imagen inexistente | `ImagePullBackOff` | |
| 37 | E10 disco lleno | `NodoK8sDiscoCasiLleno`; `DiskPressure` y desalojos | |
| 38 | E11 silencio, agrupación e inhibición | Nada en la guardia durante el silencio | |
| 39 | E12 node_exporter en dns01 | `up{job="lab-vms"}` = 1; `DNSdelLabParado` al parar `named` | |
| 40 | Grafana: Node Exporter Full (1860), panel nuevo como código, variable `namespace`, usuario Viewer | Panel persistente tras recargar | |

## 8.9 Terraform ([escenarios](../kubernetes/terraform-iac.md))
| # | Escenario | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 41 | T1 `init` + `plan` | Plan que quiere crear lo existente; no se aplica | |
| 42 | T2 `import` + `apply` | 7 importados, 0 destruidos; después `No changes` | |
| 43 | T3 módulo (capa 20) | Pool importado; `tienda-web` en .117 con ServiceMonitor y alerta | |
| 44 | T4 drift | El plan detecta réplicas y etiqueta; decisión documentada | |
| 45 | T5 bloqueo | Segunda ejecución esperando o `Error acquiring the state lock` | |
| 46 | T6 CRD inexistente | `no matches for kind "Application"` en el plan | |
| 47 | T7 `prevent_destroy` y `moved` | Destrucción rechazada; renombrado sin destruir | |
| 48 | T8 Terraform frente a Ansible | Tabla propia razonada | |

## 8.10 a 8.13
| # | Prueba | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 49 | `crc setup --check-only` | Lista de cambios que haría en el host, revisada antes de seguir | |
| 50 | podinfo en OpenShift | Rechazo por SCC `restricted-v2` con `runAsUser: 100`; funciona sin él; Route creada | |
| 51 | `ci/validar.sh` | RESULTADO: OK; y FALLO al romper algo a propósito | |
| 52 | Argo CD | `Application` Synced/Healthy; `selfHeal` deshace un `scale` manual | |
| 53 | drain/uncordon con PodDisruptionBudget | El drain respeta `minAvailable` | |
| 54 | Copia y restauración de etcd | Namespace borrado vuelve tras restaurar | |
| 55 | Upgrade 1.36 → 1.37 | 3 nodos en v1.37; sin corte de podinfo | |
| 56 | Ansible: rol `k8s_node` y reconstrucción de k8s-w02 | `changed=0` la 2.ª vez; nodo `Ready` solo con Ansible | |

## Documentación
- [ ] `kubernetes/etapa8-kubernetes-openshift.md` con las notas propias de cada subetapa
- [ ] `kubernetes/monitorizacion-prometheus-grafana.md` y `kubernetes/terraform-iac.md` con lo observado
- [ ] `scripts/stage8/README_stage8.md` actualizado (estado y versiones reales)
- [ ] `troubleshooting/etapa8/` con los casos reales y su índice

## Criterios de aceptación
- [ ] Sabes explicar: plano de control y nodos, qué hace cada componente, kubelet y pods estáticos, CNI, Services y kube-proxy, Ingress/Gateway, PV/PVC/StorageClass, RBAC y Pod Security
- [ ] Sabes explicar: Prometheus (pull, exporters, PromQL, reglas, Alertmanager), RED/USE, por qué se alerta por síntomas y no por causas
- [ ] Sabes explicar: estado de Terraform, plan, import, drift, módulos, y cuándo Terraform, Ansible o GitOps
- [ ] Sabes explicar diferencias Kubernetes/OpenShift: SCC, Routes, proyectos, operadores, S2I
- [ ] `ci/validar.sh` en verde y ningún secreto (contraseñas, kubeconfig, tfstate) en el repositorio
- [ ] `scripts/lab.sh test all <nodo>` con 0 FAIL en los 3 nodos y snapshots `*-stage8-complete`

## Errores encontrados y solución
| Error | Causa | Solución |
|---|---|---|
| | | |
