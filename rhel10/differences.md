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
| Particionado en BIOS | Anaconda usa **GPT por defecto incluso con firmware BIOS** ✔ (verificado en este lab) | RHEL 7/8/9 usan MBR automático en BIOS; RHEL 10 no |
| systemd, dnf, firewalld, chrony, cgroups, crypto | confirmar con `lab.sh facts` ◦ | pendiente ◦ |

## Impacto práctico en el laboratorio
- **[VERIFICADO en hardware]** Con firmware BIOS, el kickstart de RHEL 10 necesita una partición `biosboot` de 1 MiB explícita antes de `/boot` (`part biosboot --fstype=biosboot --size=1 --ondisk=vda`), algo que RHEL 7/8/9 no necesitan con el mismo diseño de disco. Sin ella, Anaconda se detiene en modo desatendido esperando una decisión en "Installation Destination" y la instalación nunca termina (solo se nota si se abre la consola serie a tiempo; si no, `virt-install --wait` la mata en silencio al expirar el plazo). Caso completo en `troubleshooting/15-rhel10-bios-gpt-biosboot.md`.
- Instalación: Exige CPU **x86-64-v3** ✔ → la VM usa `--cpu host-passthrough` (el modelo QEMU por defecto no lo cumple).
- Red: **ifcfg eliminado**: solo keyfile ✔; **`dhclient` eliminado** ✔ (NetworkManager usa su cliente interno).
- Comandos de paquetes: `dnf`.
- Soporte: Versión más reciente; útil para descubrir cambios antes de migrar.

## A verificar en la VM (rellena en `results/`)
`uname -r`, `systemctl --version | head -1`, `dnf --version | head -1`, `python3 --version`, `ssh -V`, `nmcli -f NAME,FILENAME con show`, `stat -fc %T /sys/fs/cgroup`, `ls -d /var/log/journal`.
