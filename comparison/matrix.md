# Matriz de comparación RHEL 7 / 8 / 9 / 10

**Estado**: valores de documentación, **pendientes de verificar en las VMs**. La versión con datos reales se genera con
`scripts/lab.sh facts all && scripts/lab.sh matrix` → `comparison/matrix.generated.md` (esa es la que cuenta).

Leyenda: **✔** confirmado en documentación oficial consultada · **◦** conocimiento general, sin verificar · **—** aún sin dato.

| Característica | RHEL 7 | RHEL 8 | RHEL 9 | RHEL 10 |
|---|---|---|---|---|
| Kernel | 3.10 ◦ | 4.18 ◦ | 5.14 ✔ | 6.12 ✔ |
| Init | systemd 219 ◦ | systemd 239 ◦ | systemd — | systemd — |
| Gestor de paquetes | yum ◦ | dnf (yum = alias) ◦ | dnf ◦ | dnf — |
| Python del sistema | 2.7 ◦ | 3.6 (platform-python) ◦ | 3.9 ◦ | 3.12 ✔ |
| Red (perfiles) | ifcfg + `network` ◦ | ifcfg ◦ | keyfile (ifcfg deprecado) ✔ | solo keyfile (ifcfg eliminado) ✔ |
| NetworkManager | — | — | — | — |
| Cliente DHCP `dhclient` | presente ◦ | presente ◦ | presente ◦ | eliminado ✔ |
| Firewall | firewalld/iptables ◦ | firewalld/nftables ◦ | firewalld/nftables ◦ | — |
| SELinux | Enforcing ◦ | Enforcing ◦ | Enforcing ◦ | Enforcing ◦ |
| OpenSSH | 7.4 ◦ | 8.0 ◦ | 8.7 ✔ | 9.9 ✔ |
| Sincronización horaria | chrony (+ntpd) ◦ | chrony ◦ | chrony ◦ | chrony — |
| Sistema de ficheros por defecto | XFS ◦ | XFS ◦ | XFS ◦ | XFS ◦ |
| Logs | rsyslog + journald ◦ | rsyslog + journald ◦ | rsyslog + journald ◦ | — |
| Repositorios | repos por canal ◦ | BaseOS + AppStream ◦ | BaseOS + AppStream ◦ | BaseOS + AppStream ◦ |
| Arranque | GRUB2, BIOS/UEFI ◦ | GRUB2 + BLS ◦ | GRUB2 + BLS ◦ | — |
| Cgroups | v1 ◦ | v1 ◦ | v2 ◦ | v2 ◦ |
| CPU mínima | x86-64 ◦ | x86-64 ◦ | x86-64-v2 ✔ | **x86-64-v3** ✔ |

Qué comprobar en cada VM para promover un ◦ a dato real: `uname -r`, `systemctl --version`, `dnf|yum --version`, `python --version; python3 --version`,
`NetworkManager --version`, `nmcli -f NAME,FILENAME con show`, `firewall-cmd --version`, `grep FirewallBackend /etc/firewalld/firewalld.conf`,
`ssh -V`, `chronyd --version`, `ls -d /var/log/journal`, `stat -fc %T /sys/fs/cgroup` (todo ello lo recoge `collect-facts.sh`).
