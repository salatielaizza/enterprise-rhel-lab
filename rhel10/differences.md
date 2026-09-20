# RHEL 10.2 — Diferencias

Leyenda: **✔** confirmado en documentación oficial consultada · **◦** conocimiento general, **pendiente de verificar en la VM** (`lab.sh facts` + `lab.sh matrix`).
Comparación con la versión anterior (RHEL 9.8).

| Área | RHEL 10.2 | Cambio respecto a RHEL 9.8 |
|---|---|---|
| Kernel | 6.12 ✔ | 5.14 → 6.12 ✔ |
| Python del sistema | Python 3.12 ✔ | 3.9 → 3.12 ✔ |
| Arquitectura de CPU | x86-64-v3 obligatorio ✔ | v2 → v3 ✔ |
| Red | ifcfg eliminado; `dhclient` eliminado ✔ | ifcfg → solo keyfile ✔ |
| SSH | OpenSSH 9.9 ✔ | 8.7 → 9.9 ✔ |
| Instalador | `inst.vnc` → `inst.rdp` ✔ | VNC → RDP ✔ |
| systemd, dnf, firewalld, chrony, cgroups, crypto | confirmar con `lab.sh facts` ◦ | pendiente ◦ |

## Impacto práctico en el laboratorio
- Instalación: Exige CPU **x86-64-v3** ✔ → la VM usa `--cpu host-passthrough` (el modelo QEMU por defecto no lo cumple).
- Red: **ifcfg eliminado**: solo keyfile ✔; **`dhclient` eliminado** ✔ (NetworkManager usa su cliente interno).
- Comandos de paquetes: `dnf`.
- Soporte: Versión más reciente; útil para descubrir cambios antes de migrar.

## A verificar en la VM (rellena en `results/`)
`uname -r`, `systemctl --version | head -1`, `dnf --version | head -1`, `python3 --version`, `ssh -V`, `nmcli -f NAME,FILENAME con show`, `stat -fc %T /sys/fs/cgroup`, `ls -d /var/log/journal`.
