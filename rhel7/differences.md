# RHEL 7.9 — Diferencias

Leyenda: **✔** confirmado en documentación oficial consultada · **◦** conocimiento general, **pendiente de verificar en la VM** (`lab.sh facts` + `lab.sh matrix`).
Es la línea base del laboratorio: la columna "cambio" describe lo que cambiará en versiones posteriores.

| Área | RHEL 7.9 | Cambio respecto a — |
|---|---|---|
| Kernel | 3.10 ◦ | — |
| Init | systemd 219 ◦ | — |
| Paquetes | yum 3.x, repos únicos ◦ | — |
| Python del sistema | Python 2.7 en `/usr/bin/python` ◦ | — |
| Red | ifcfg + servicio `network`; `net-tools` presente ◦ | — |
| Firewall | firewalld con backend iptables ◦ | — |
| Hora | chrony y ntpd disponibles ◦ | — |
| SSH | OpenSSH 7.4 ◦ | — |
| Logs | rsyslog + journald; `yum.log` ◦ | — |
| Cgroups | v1 ◦ | — |

## Impacto práctico en el laboratorio
- Instalación: Comandos `install` y `auth --enableshadow --passalgo=sha512` (desaparecen en RHEL 8+).
- Red: Perfiles **ifcfg** (`/etc/sysconfig/network-scripts/`) gestionados por NetworkManager; existe además el servicio heredado `network`.
- Comandos de paquetes: `yum`.
- Soporte: RHEL 7 salió del mantenimiento estándar el 30-jun-2024; solo recibe parches con el complemento ELS de pago ◦. Úsala como **caso de migración**, no como destino.

## Verificado en ejecución real (más allá de la tabla teórica)
- La cuenta de sistema `ftp` existe en `/etc/passwd` pero su directorio home `/var/ftp` **no se crea**
  durante la instalación base (kickstart mínimo `@core`) — a diferencia de RHEL 8/9/10, donde no se
  reprodujo el mismo síntoma. Detectado por `pwck -r`; ver `troubleshooting/22-pwck-usuario-ftp-var-ftp-inexistente.md`.

## A verificar en la VM (rellena en `results/`)
`uname -r`, `systemctl --version | head -1`, `yum --version | head -1`, `python3 --version`, `ssh -V`, `nmcli -f NAME,FILENAME con show`, `stat -fc %T /sys/fs/cgroup`, `ls -d /var/log/journal`.
