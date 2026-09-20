# Inventario de hosts

Fuente única: `scripts/hosts.conf`.

| Host | RHEL | IP | vCPU | RAM | Disco sistema | Disco datos | Papel |
|---|---|---|---|---|---|---|---|
| rhel7-app01 | 7.9 | 10.10.10.11 | 2 | 2 GB | 20 GB | 10 GB | Servidor de aplicaciones (comparación) |
| rhel8-app01 | 8.10 | 10.10.10.12 | 2 | 3 GB | 20 GB | 10 GB | Servidor de aplicaciones |
| rhel9-app01 | 9.8 | 10.10.10.13 | 2 | 3 GB | 20 GB | 10 GB | Servidor de aplicaciones |
| rhel10-app01 | 10.2 | 10.10.10.14 | 2 | 3 GB | 20 GB | 10 GB | Servidor de aplicaciones |
| dns01 | 9 | 10.10.10.20 | 1 | 2 GB | 20 GB | — | BIND + servidor NTP |
| ansible01 | 9 | 10.10.10.30 | 2 | 3 GB | 30 GB | — | Nodo de control (Etapa 7) |
| *rhel9-web01* | 9 | 10.10.10.40 | — | — | — | — | Reservado (NGINX) |
| *rhel9-monitor01* | 9 | 10.10.10.50 | — | — | — | — | Reservado (Prometheus/Grafana) |

Sizing total (6 VMs): 11 vCPU, ~16 GB RAM, ≤170 GB virtuales (qcow2 *thin*). Enciende solo las que uses.

## Distribución de disco (kickstart)
`vda` (sistema): `/boot` 1 GiB XFS + PV → `vg_system`: `lv_root` 8 GiB XFS, `lv_swap` 2 GiB, `lv_var` 4 GiB XFS, **~5 GiB libres**
para ejercicios de ampliación. `vdb` (datos, sin tocar por el instalador) → Etapa 2: `vg_data`.

## Usuarios y grupos (iguales en todos los hosts)
| Usuario | UID | Grupo primario | Otros grupos |
|---|---|---|---|
| adminlab (kickstart) | 1001 | adminlab | wheel, sysadmins |
| devuser | 1002 | developers (2002) | — |
| appuser | 1003 | application (2003) | — |
| backupuser | 1004 | backup (2004) | — |
| sftpdemo (Etapa 4) | 1005 | sftponly (2005) | — |

Grupo `sysadmins` = GID 2001.

## Nombres estables
Snapshots: `rhel7-stage1-complete`, `rhel10-stage3-complete`, `dns01-stage4-complete`… Conexión NetworkManager: `lab0`.
Ficheros de respaldo: `*.lab-bak`, `*.lab-orig`.
