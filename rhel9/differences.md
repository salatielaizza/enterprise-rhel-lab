# RHEL 9.8 — Diferencias

Leyenda: **✔** confirmado en documentación oficial consultada · **◦** conocimiento general, **pendiente de verificar en la VM** (`lab.sh facts` + `lab.sh matrix`).
Comparación con la versión anterior (RHEL 8.10).

| Área | RHEL 9.8 | Cambio respecto a RHEL 8.10 |
|---|---|---|
| Kernel | 5.14 ✔ | 4.18 → 5.14 ✔ |
| Init | systemd (versión: confirmar en VM) ◦ | — |
| Paquetes | dnf 4 ◦ | — |
| Python del sistema | Python 3.9 ◦ | 3.6 → 3.9 ◦ |
| Red | **keyfile** por defecto; ifcfg deprecado ✔ | ifcfg → keyfile ✔ |
| Firewall | firewalld nftables; backend iptables en desuso ◦ | — |
| SSH | OpenSSH 8.7 ✔ | 8.0 → 8.7 ✔ |
| Cripto | OpenSSL 3 y políticas más estrictas (SHA-1) ◦ | endurecimiento ◦ |
| Cgroups | v2 por defecto ◦ | v1 → v2 ◦ |
| LVM | fichero de dispositivos activo por defecto ◦ | nuevo ◦ |

## Impacto práctico en el laboratorio
- Instalación: Mismo kickstart que RHEL 8 (validado con `ksvalidator -v RHEL9`).
- Red: Perfiles **keyfile** por defecto ✔ (`/etc/NetworkManager/system-connections/`); **ifcfg está deprecado** pero aún soportado ✔.
- Comandos de paquetes: `dnf`.
- Soporte: Versión objetivo típica de producción hoy; base de dns01 y ansible01.

## A verificar en la VM (rellena en `results/`)
`uname -r`, `systemctl --version | head -1`, `dnf --version | head -1`, `python3 --version`, `ssh -V`, `nmcli -f NAME,FILENAME con show`, `stat -fc %T /sys/fs/cgroup`, `ls -d /var/log/journal`.
