# RHEL 8.10 — Diferencias

Leyenda: **✔** confirmado en documentación oficial consultada · **◦** conocimiento general, **pendiente de verificar en la VM** (`lab.sh facts` + `lab.sh matrix`).
Comparación con la versión anterior (RHEL 7.9).

| Área | RHEL 8.10 | Cambio respecto a RHEL 7.9 |
|---|---|---|
| Kernel | 4.18 ◦ | 3.10 → 4.18 ◦ |
| Init | systemd 239 ◦ | 219 → 239 ◦ |
| Paquetes | dnf; `yum` es alias; BaseOS/AppStream y módulos ◦ | yum → dnf ◦ |
| Python del sistema | `platform-python` 3.6 para herramientas; sin `/usr/bin/python` por defecto ◦ | Python 2 desaparece ◦ |
| Red | ifcfg por defecto; `network-scripts` en desuso ◦ | `net-tools` fuera por defecto ◦ |
| Firewall | firewalld con backend nftables ◦ | iptables → nftables ◦ |
| Hora | solo chrony (`ntpd` eliminado) ◦ | ntpd → chrony ◦ |
| SSH | OpenSSH 8.0 ◦ | 7.4 → 8.0 ◦ |
| Cripto | políticas criptográficas del sistema ◦ | nuevo en 8 ◦ |
| Cgroups | v1 por defecto ◦ | — |

## Impacto práctico en el laboratorio
- Instalación: Desaparecen `install` y `auth`; la autenticación pasa a `authselect` ◦.
- Red: Perfiles **ifcfg** por defecto ◦ (`network-scripts` en desuso); `net-tools` no se instala por defecto ◦.
- Comandos de paquetes: `dnf`.
- Soporte: RHEL 8.10 es la última menor de RHEL 8 ◦.

## A verificar en la VM (rellena en `results/`)
`uname -r`, `systemctl --version | head -1`, `dnf --version | head -1`, `python3 --version`, `ssh -V`, `nmcli -f NAME,FILENAME con show`, `stat -fc %T /sys/fs/cgroup`, `ls -d /var/log/journal`.
