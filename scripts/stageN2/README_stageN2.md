# 📡 Etapa N2 — SIEM (`scripts/stageN2/`)

## Qué hace esta etapa

Prueba práctica y adelanto de tecnologías: monta un **SIEM** en una VM nueva, `siem01` (10.10.10.55), con
**Graylog 7 + OpenSearch + MongoDB** en **Docker Compose** (y **Elasticsearch 9** opcional), lo alimenta con las
VMs del lab por **Syslog** (rsyslog, desplegado con **Ansible**), **NXLog CE** (auditd) y **Fluent Bit** desde
**Kubernetes** (k3s), y añade la conversión de VMs entre **KVM y VMware** (VMDK, OVA, `vmkfstools`, `virt-v2v`).
Las herramientas de API, GELF y detección están en **Python** (solo biblioteca estándar).

Guía completa con teoría, práctica y averías provocadas: [`siem/etapaN2-siem.md`](../../siem/etapaN2-siem.md).

## Diferencias con las demás carpetas `stageN/`

- `siem01` es un host **opcional** de `hosts.conf` (8.ª columna `opcional`): `lab.sh … all` no la incluye, pero
  todos los comandos funcionan con su nombre (`vm-create siem01`, `stage5 siem01`, `test all siem01`).
- Los scripts corren en **tres sitios**: `siem01` (servidor), `ansible01` (reenvío de rsyslog a todo el lab) y la
  VM agente que se elija (NXLog); `30-vm-convert.sh` corre en el **host**.
- **No marca `LAB_STAGE`**: el test `test_siem.sh` se activa por el **papel** de la VM (servidor o agente).
- Los secretos se generan en `siem01` (`/opt/siem/.env`, `/root/.siem/*`, 0600) y nunca pasan por el repositorio.

## Cómo se lanza

```bash
scripts/lab.sh siem-preflight                 # siem01, solo lectura
scripts/lab.sh siem-docker                    # LVs + Docker CE
scripts/lab.sh siem-stack [--with-elastic]    # Graylog + OpenSearch + MongoDB (+ Elasticsearch)
scripts/lab.sh siem-inputs                    # entradas por API + prueba de extremo a extremo
scripts/lab.sh siem-forward [--check --diff]  # rsyslog de todo el lab -> Graylog (Ansible)
scripts/lab.sh siem-nxlog rhel9-app01 <rpm>   # agente NXLog CE
scripts/lab.sh siem-k8s                       # k3s + Fluent Bit + app de ejemplo
scripts/lab.sh vm-convert export|import|inspect ...   # host: KVM <-> VMware
```

## Scripts

| Script | Corre en | `lab.sh` | Qué hace | Qué modifica / seguridad |
|---|---|---|---|---|
| `siem-lib.sh` | — | — | Funciones comunes: IP de `siem01` desde `hosts.conf`, `backup`, `require_host`, `randpw`, `fw_rich`, `wait_for` | — |
| `00-preflight.sh` | `siem01` | `siem-preflight` | RAM, vCPU, espacio en `vg_system`, SELinux, chrony, DNS A/PTR, repos, salida a Docker/k3s, conflictos | **Nada** (sin `set -e`: enseña todas las comprobaciones) |
| `01-docker-host.sh` | `siem01` | `siem-docker` | LVs `lv_docker` (35 GB) y `lv_rancher` (10 GB) por UUID + `restorecon`; Docker CE del repo oficial; `daemon.json` (driver `overlay2`, sin *containerd image store*: caso `etapaN2/03`); `vm.max_map_count` | `fstab`, `daemon.json` y `90-siem.conf` con `.lab-bak.<fecha>`; retira podman/runc |
| `02-graylog-stack.sh [--with-elastic]` | `siem01` | `siem-stack` | `/opt/siem` + `.env` con secretos aleatorios (solo si no existe), `compose config/pull/up`, espera a `ALIVE`, firewalld | `.env` 0600; contraseña de admin en `/root/.siem/graylog-admin.txt`; se niega a usar `admin` |
| `03-graylog-inputs.sh` | `siem01` | `siem-inputs` | `graylog_inputs.py` (4 entradas), puertos en la IP del lab, GELF TCP+UDP con marcador buscado en OpenSearch | Solo crea entradas que faltan |
| `04-k3s-fluentbit.sh` | `siem01` | `siem-k8s` | k3s `--selinux` sin Traefik (instalador descargado y con SHA-256 antes de ejecutar), zona trusted para pods/servicios, kubeconfig de `adminlab`, Fluent Bit + `pagos-demo`, comprobación en OpenSearch | firewalld; `~adminlab/.kube/config` 0600 |
| `10-nxlog-agent.sh <rpm>` | VM agente | `siem-nxlog <host> <rpm>` | Instala NXLog CE, `log_group = nxlog` en auditd, plantilla validada con `nxlog -v` (si falla, restaura), evento de prueba con `auditctl -m` | `auditd.conf` y `nxlog.conf` con copia; el agente NO corre como root |
| `20-siem-forward.sh [args]` | `ansible01` | `siem-forward` | Copia `files/siem-lab` a `~adminlab/siem-lab` y lanza el playbook como `adminlab` | Lo que haga el playbook (abajo) |
| `30-vm-convert.sh` | **host** | `vm-convert` | `export` (copia → `virt-customize` → `virt-sysprep` → VMDK sparse/stream + SHA-256), `import` (`virt-v2v`, sin red), `inspect` | Nunca toca la VM original; exige que esté apagada; salida en `~/lab-export` |

## `files/`

| Ruta | Contenido |
|---|---|
| `graylog/docker-compose.yml` | Servicios `mongodb`, `opensearch`, `graylog` y `elasticsearch` (perfil `elastic`); versiones fijadas; *healthchecks*; puertos solo en 127.0.0.1 o en la IP del lab |
| `graylog/env.example` | Plantilla del `.env` (con `CAMBIAR`); el real lo genera `02-graylog-stack.sh` |
| `python/graylog_inputs.py` | API REST de Graylog: crear/arrancar/listar entradas de forma idempotente |
| `python/gelf_send.py` | Emisor GELF por UDP (zlib + troceado) y TCP (byte nulo), con marcador |
| `python/os_search.py` | API de OpenSearch/Elasticsearch: `health`, `indices`, `search`, `count`, `top` (agregación) e `ingest-demo` (`_bulk`) |
| `python/detect_bruteforce.py` | Regla de correlación: fallos SSH por IP en Syslog y auditd; `--notify` reenvía la alerta por GELF |
| `siem-lab/` → `~adminlab/siem-lab` | Proyecto Ansible aparte (usa el inventario y el Vault de la Etapa 7): `playbooks/siem-forwarding.yml` + plantilla de rsyslog |
| `nxlog/nxlog.conf.tpl` | Agente NXLog: `im_file` de `audit.log` → campos `audit_*` con regex → `om_tcp` GELF |
| `k8s/10-fluent-bit.yaml` | Namespace `logging`, RBAC de solo lectura, ConfigMap (YAML de Fluent Bit) y DaemonSet (`spc_t`) |
| `k8s/20-demo-app.yaml` | Namespace `demo` (Pod Security *restricted*) y `pagos-demo` (logs de ejemplo, contenedor sin privilegios) |

## Playbook `siem-forwarding.yml`

| Tarea | Detalle |
|---|---|
| Paquetes | `rsyslog` y `policycoreutils-python(-utils)` según RHEL 7 u 8+ |
| SELinux | `tcp/5140` como `syslogd_port_t` (comprobación con un solo `awk`, sin `grep -q` tras una tubería) |
| Configuración | `/etc/rsyslog.d/90-siem-forward.conf`: `omfwd` TCP, RFC 5424, cola en disco, reintentos infinitos |
| Validación | *Handlers* en orden: `rsyslogd -N1` y, solo si pasa, reinicio de rsyslog |
| Prueba | `logger -p authpriv.notice -t siem-test` con un marcador común a todos los hosts |
| *Rollback* | `-e siem_state=absent`: borra la configuración y la etiqueta del puerto |

## Requisitos previos

- Etapas 1-5 en `siem01` (usuarios, red, DNS/hora/SSH, SELinux) y DNS regenerado (`lab.sh stage4-dns`).
- `siem01` registrada en Red Hat y con salida a Internet (Docker Hub, `download.docker.com`, `get.k3s.io`).
- `siem-forward`: Etapa 7 preparada (`lab.sh stage7-setup`). `siem-nxlog`: RPM de NXLog CE para RHEL 9 descargado en el host.
- `vm-convert`: `qemu-utils`, `libguestfs-tools` y `virt-v2v` en el host; la parte ESXi, la fase A de la Etapa 9.

## Lecciones del proyecto aplicadas aquí

- `if …; then …; fi` en vez de `[[ ]] && …` al final de funciones (caso `etapa6/01`).
- Nada de `comando | grep -q` con `pipefail` (caso `etapa9/01`): `awk` que lee toda la entrada.
- `ausearch` siempre con `timeout` (caso `etapa2/06`).
- La fuente de verdad del proyecto Ansible es git: se recopia en cada ejecución (caso `etapa7/03`).
- DNS comparado con `dig @dns01` y `getent ahostsv4`, nunca con la primera línea de `getent hosts` (caso `etapaN2/02`).
- Un LV dedicado no sirve si el servicio escribe en otra ruta: comprobar con `du` dónde crece de verdad (caso `etapaN2/03`).

## Cómo se verifica

```bash
scripts/lab.sh siem-preflight
scripts/lab.sh test test_siem.sh siem01        # servidor (+ Kubernetes si está instalado)
scripts/lab.sh test test_siem.sh all           # agentes rsyslog/NXLog en las VMs del lab
scripts/lab.sh test all siem01                 # base del lab + SIEM en siem01
```

## Documentación relacionada

- Guía: [`siem/etapaN2-siem.md`](../../siem/etapaN2-siem.md)
- Checklist: [`checklists/etapaN2.md`](../../checklists/etapaN2.md)
- Comandos explicados y averías: [`troubleshooting/etapaN2/README_troubleshooting_etapaN2.md`](../../troubleshooting/etapaN2/README_troubleshooting_etapaN2.md)
- Base que reutiliza: Etapa 5 (auditd y SELinux, [`README_stage5.md`](../stage5/README_stage5.md)), Etapa 7 (Ansible, [`README_stage7.md`](../stage7/README_stage7.md)) y Etapa 9 (ESXi, [`README_stage9.md`](../stage9/README_stage9.md))
