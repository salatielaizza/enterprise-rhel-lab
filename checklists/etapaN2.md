# ETAPA N2 — CHECKLIST: SIEM (Graylog, OpenSearch/Elasticsearch, Syslog, NXLog, Docker, Kubernetes y VMware)

> Prueba práctica y adelanto de tecnologías. Una etapa **no está completa** hasta marcar TODO:
> documentación + tests + troubleshooting + snapshot.
> Rellena "Resultado obtenido" con lo que veas **de verdad** (pega salidas en `results/etapaN2/` y capturas en `prints/etapaN2/`).
> Guía: [`siem/etapaN2-siem.md`](../siem/etapaN2-siem.md) · Scripts: [`scripts/stageN2/README_stageN2.md`](../scripts/stageN2/README_stageN2.md)

## Objetivo
Montar y operar un SIEM en `siem01` (10.10.10.55) alimentado por las VMs del lab (Syslog, NXLog, Kubernetes),
con detección y alertas, buenas prácticas de seguridad aplicadas y verificables, y conversión de VMs entre KVM y VMware.

## Fase 0 — VM y base del lab (bloque 0)
| # | Comando / acción | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 0.1 | `scripts/lab.sh stage4-dns` + `dig @10.10.10.20 siem01.lab.local +short` y `-x 10.10.10.55` | `10.10.10.55` y `siem01.lab.local.` | |
| 0.2 | `scripts/lab.sh test test_dns.sh all` | 0 FAIL (incluye ya `siem01`) | |
| 0.3 | Alias `Host siem01` en `~/.ssh/lab_config` | `ssh siem01 hostname` responde | |
| 0.4 | `scripts/lab.sh vm-create siem01` + `register` + `stage2/3/4-clients/5 siem01` | VM RHEL 9 instalada e integrada | |
| 0.5 | `scripts/lab.sh test all siem01` | 0 FAIL en la base del lab | |
| 0.6 | `scripts/lab.sh snapshot create siem01 5` | `siem01-stage5-complete` | |
| 0.7 | `scripts/lab.sh siem-preflight` | 0 FAIL (WARN leídos y decididos) | |

## Fase 1 — Docker (bloque 1)
| # | Comando / acción | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 1.1 | `scripts/lab.sh siem-docker` | LVs montados, Docker activo, `vm.max_map_count = 262144` | |
| 1.2 | `ls -Zd /var/lib/docker` · `docker info --format '{{.SecurityOptions}}'` | `container_var_lib_t` · `selinux` | |
| 1.3 | Ejercicio `hello-world` / `nginx` + `docker inspect -f '{{.ProcessLabel}}'` | Etiqueta `container_t` con categorías MCS | |
| 1.4 | Avería: `chcon` incorrecto en `/var/lib/docker` → diagnóstico → `restorecon` | Caso documentado si aparece algo nuevo | |

## Fase 2 — SIEM (bloque 2)
| # | Comando / acción | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 2.1 | `scripts/lab.sh siem-stack` | 3 contenedores; Graylog `ALIVE` | |
| 2.2 | Login en `http://10.10.10.55:9000` con la contraseña de `/root/.siem/graylog-admin.txt` | Acceso como admin | |
| 2.3 | `os_search.py health` · `curl -s 127.0.0.1:9200/_cat/indices?v` | `green`/`yellow`; índice `graylog_0` | |
| 2.4 | Index set: rotación `P1D`, retención 7, 1 shard, 0 réplicas | Anotar el cálculo de disco | |
| 2.5 | Usuario `analista` (rol Reader) + token de API | Login de `analista` sin permisos de admin | |
| 2.6 | (Opcional) `scripts/lab.sh siem-stack --with-elastic` + `ingest-demo` + `search` | Índice `lab-demo` en Elasticsearch | |
| 2.7 | Averías: `vm.max_map_count` bajo; OpenSearch parado (*journal*) | Comportamiento explicado | |

## Fase 3 — Entradas y Python (bloque 3)
| # | Comando / acción | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 3.1 | `scripts/lab.sh siem-inputs` | 4 entradas RUNNING; prueba e2e OK | |
| 3.2 | `gelf_send.py --big 20000` (UDP troceado) y `--proto tcp --count 100` | Mensajes completos en Graylog | |
| 3.3 | `logger --server 10.10.10.55 --port 5140 --udp --rfc5424 ...` | Mensaje Syslog UDP en Graylog | |
| 3.4 | Averías: entrada parada (TCP rechaza, UDP "envía"); `POST` sin `X-Requested-By` | Diferencia explicada | |

## Fase 4 — Syslog con Ansible (bloque 4)
| # | Comando / acción | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 4.1 | `scripts/lab.sh siem-forward --check --diff` | Cambios previstos, sin aplicar | |
| 4.2 | `scripts/lab.sh siem-forward` (dos veces) | 2.º pase `changed=0` | |
| 4.3 | Graylog: `application_name:siem-test` | Un mensaje por VM del grupo `lab` | |
| 4.4 | `scripts/lab.sh test test_siem.sh all` | 0 FAIL en los agentes | |
| 4.5 | Avería SELinux (`semanage port -d ...`) → AVC → playbook | Caso documentado | |
| 4.6 | `siem01` apagada → 50 mensajes → encender | Llegan los 50 con su hora original | |
| 4.7 | Rollback en `rhel8-app01` y reaplicar | Test "no aplica" y vuelta a 0 FAIL | |

## Fase 5 — Detección (bloque 6)
| # | Comando / acción | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 5.1 | Stream "Autenticación" y pipeline "Normalización SSH" | Campos `src_ip`, `ssh_user`, `event_type` | |
| 5.2 | Simulación de 8 usuarios inexistentes desde `rhel7-app01` | 8 eventos `ssh_auth_failure` | |
| 5.3 | Event Definition "Fuerza bruta SSH" (≥5 en 5 min por `src_ip`) | Alerta en **Alerts & Events** | |
| 5.4 | `detect_bruteforce.py --notify` | Alerta `alert_rule:ssh-bruteforce` en Graylog | |
| 5.5 | Dashboard "SIEM del lab" | Captura en `prints/etapaN2/` | |

## Fase 6 — NXLog (bloque 5)
| # | Comando / acción | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 6.1 | `scripts/lab.sh siem-nxlog rhel9-app01 <rpm>` | Servicio activo; evento de prueba | |
| 6.2 | `sudo touch /etc/passwd` en `rhel9-app01` → `audit_key:lab-identity` | Evento con campos `audit_*` | |
| 6.3 | `scripts/lab.sh test test_siem.sh rhel9-app01` | 0 FAIL (agente rsyslog + NXLog) | |
| 6.4 | Averías: permisos de `audit.log`; comentario al final de una directiva | Comportamiento explicado | |

## Fase 7 — Kubernetes (bloque 7)
| # | Comando / acción | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 7.1 | `scripts/lab.sh siem-k8s` | Nodo Ready; Fluent Bit y `pagos-demo` listos; logs en OpenSearch | |
| 7.2 | Graylog: `k8s_namespace_name:demo AND "level=ERROR"` | Un ERROR cada ~50 s | |
| 7.3 | `kubectl -n demo scale deploy/pagos-demo --replicas=3` | 3 valores de `k8s_pod_name` | |
| 7.4 | Averías: puerto incorrecto (cola en disco); sin `spc_t` (AVC); Pod Security | Explicadas | |
| 7.5 | `scripts/lab.sh test test_siem.sh siem01` | 0 FAIL (incluye Kubernetes) | |

## Fase 8 — VMware (bloque 8)
| # | Comando / acción | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 8.1 | `scripts/lab.sh vm-convert export rhel9-app01` (VM apagada) | VMDK sparse + `.sha256` | |
| 8.2 | `vm-convert export ... --format stream` + `qemu-img info` | `create type: streamOptimized` | |
| 8.3 | `vm-convert import <vmdk> rhel9-conv01` + arranque por consola | Arranca; machine-id y claves SSH nuevas | |
| 8.4 | (Etapa 10 fase A) VMDK → `esxi01` con `vmkfstools -i` + VM en Host Client + `open-vm-tools` | Arranca en ESXi con red VMXNET 3 | |
| 8.5 | (Etapa 10 fase A) `virt-v2v -i vmx -it ssh` de `rhel9-vm01` a KVM | `rhel9-vm01-kvm` arranca en KVM | |
| 8.6 | Exportar OVF desde el Host Client y empaquetar OVA; `vm-convert import <ova>` | VM importada | |
| 8.7 | Averías: `--no-prep` (dracut); `govc` contra ESXi gratuito; IP duplicada | Explicadas | |
| 8.8 | Limpieza: `virsh undefine rhel9-conv01 --remove-all-storage` y VMs de prueba en ESXi | Sin restos | |

## Fase 9 — Seguridad e infraestructura (bloques 9 y 10)
| # | Comando / acción | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 9.1 | Ejercicio Docker y firewalld | Conclusión documentada | |
| 9.2 | `ss -ltnup` en `siem01` | Nada del SIEM en 0.0.0.0; 9200 solo en 127.0.0.1 | |
| 9.3 | Diagnóstico por capas de "no llegan logs de X" (bloque 10) | Tabla rellenada con un caso real | |
| 9.4 | Capacidad: `docker stats` con 1, 100 y 1.000 msg/s | Tabla de consumo | |

## Cierre
| # | Comando / acción | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| C.1 | `scripts/lab.sh test all siem01` y `scripts/lab.sh test all all` | 0 FAIL | |
| C.2 | `scripts/lab.sh down siem01` y `virsh snapshot-create-as siem01 siem01-stageN2-complete` (`lab.sh snapshot` solo admite etapas numéricas, 1-20) | Snapshot de cierre | |
| C.3 | Casos reales en `troubleshooting/etapaN2/` + tabla del índice | Enlaces sin romper | |

## Criterios de aceptación
- [ ] `test_siem.sh` en 0 FAIL en `siem01` y en todas las VMs con agente.
- [ ] Mensajes de las 5 VMs del grupo `lab`, de auditd (NXLog) y de Kubernetes visibles en Graylog.
- [ ] Una alerta real (Event Definition) y una de `detect_bruteforce.py` disparadas por la simulación.
- [ ] Una VM convertida KVM → VMDK → KVM y, con la Etapa 10, KVM → ESXi y ESXi → KVM.
- [ ] Ninguna credencial en el repositorio (`git grep -n -i 'password\|secret'` solo encuentra plantillas y nombres de variables).

## Errores encontrados y solución
| Fecha | Síntoma | Causa raíz | Solución | Caso |
|---|---|---|---|---|
| | | | | |

## Conocimientos adquiridos
-

## Ampliaciones futuras
- TLS en las entradas (Syslog 6514, GELF TLS) con certificados de una CA del lab; HTTPS en la web con un proxy inverso.
- Copias de seguridad: `mongodump` y *snapshots* de OpenSearch a un repositorio NFS (Etapa 15).
- Graylog Data Node (opción recomendada por Graylog para producción) en lugar de OpenSearch propio.
- Agentes en Windows con NXLog (`im_msvistalog`) y Sysmon; Graylog Sidecar para gestionar agentes de forma central.
- Métricas del SIEM en Prometheus/Grafana (Etapa 8, y de todo el lab en la Etapa 18) y pipeline de CI que valide compose, manifiestos y playbook (Etapa 20).
