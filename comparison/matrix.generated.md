# Matriz de comparación RHEL 7 / 8 / 9 / 10 (datos REALES de las VMs)

Generada el 2026-10-22T17:15:07+02:00 por `scripts/build-matrix.sh` desde `results/facts/*.env`.
No edites este fichero a mano: regenera con `scripts/lab.sh facts all && scripts/lab.sh matrix`.

| Característica | RHEL 7 | RHEL 8 | RHEL 9 | RHEL 10 |
|---|---|---|---|---|
| Versión (os-release) | Red Hat Enterprise Linux Server 7.9 (Maipo) | Red Hat Enterprise Linux 8.6 (Ootpa) | Red Hat Enterprise Linux 9.8 (Plow) | Red Hat Enterprise Linux 10.2 (Coughlan) |
| Kernel | 3.10.0-1160.el7.x86_64 | 4.18.0-372.9.1.el8.x86_64 | 5.14.0-687.5.3.el9_8.x86_64 | 6.12.0-211.7.3.el10_2.x86_64 |
| Init / systemd | systemd 219 | systemd 239 (239-58.el8) | systemd 252 (252-67.el9_8.2) | systemd 257 (257-23.el10_2.1-gb0ca2bb) |
| glibc | ldd (GNU libc) 2.17 | ldd (GNU libc) 2.28 | ldd (GNU libc) 2.34 | ldd (GNU libc) 2.39 |
| Gestor de paquetes | 3.4.3 [yum] | 4.7.0 [dnf] | 4.14.0 [dnf] | 4.20.0 [dnf] |
| rpm | RPM version 4.11.3 | RPM version 4.14.3 | RPM version 4.16.1.3 | RPM version 4.19.1.1 |
| Python (/usr/bin/python) | Python 2.7.5 | lab-scripts/collect-facts.sh: line 21: python: command not found | Python 3.9.25 | Python 3.12.13 |
| Python 3 (python3) | lab-scripts/collect-facts.sh: line 22: python3: command not found | lab-scripts/collect-facts.sh: line 22: python3: command not found | Python 3.9.25 | Python 3.12.13 |
| platform-python | Python 2.7.5 | Python 3.6.8 | Python 3.9.25 | Python 3.12.13 |
| NetworkManager | 1.18.8-1.el7 | 1.36.0-4.el8 | 1.54.3-2.el9 | 1.56.0-1.el10 |
| Formato de perfiles de red | ifcfg (/etc/sysconfig/network-scripts) | ifcfg (/etc/sysconfig/network-scripts) | keyfile (/etc/NetworkManager/system-connections) | keyfile (/etc/NetworkManager/system-connections) |
| Servicio 'network' (initscripts) | network.service is not a native service, redirecting to /sbin/chkconfig. | Failed to get unit file state for network.service: No such file or directory | Failed to get unit file state for network.service: No such file or directory | not-found |
| net-tools (ifconfig) | ifconfig presente | ifconfig presente | ifconfig presente | ifconfig presente |
| firewalld | 0.6.3 | 0.9.3 | 1.3.4 | 2.4.0 |
| Backend de firewalld | — | FirewallBackend=nftables | FirewallBackend=nftables | FirewallBackend=nftables |
| SELinux | Enforcing | Enforcing | Enforcing | Enforcing |
| OpenSSH | OpenSSH_7.4p1, OpenSSL 1.0.2k-fips  26 Jan 2017 | OpenSSH_8.0p1, OpenSSL 1.1.1k  FIPS 25 Mar 2021 | OpenSSH_9.9p1, OpenSSL 3.5.5 27 Jan 2026 | OpenSSH_9.9p1, OpenSSL 3.5.5 27 Jan 2026 |
| Sincronización horaria | chronyd (chrony) version 3.4 (+CMDMON +NTP +REFCLOCK +RTC +PRIVDROP +SCFILTER +SIGND +ASYNCDNS +SECHASH +IPV6 +DEBUG) | chronyd (chrony) version 4.1 (+CMDMON +NTP +REFCLOCK +RTC +PRIVDROP +SCFILTER +SIGND +ASYNCDNS +NTS +SECHASH +IPV6 +DEBUG) | chronyd (chrony) version 4.8 (+CMDMON +REFCLOCK +RTC +PRIVDROP +SCFILTER +SIGND +NTS +SECHASH +IPV6 +DEBUG) | chronyd (chrony) version 4.8 (+CMDMON +REFCLOCK +RTC +PRIVDROP +SCFILTER +SIGND +NTS +SECHASH +IPV6 +DEBUG) |
| Paquete ntp instalado | package ntp is not installed | package ntp is not installed | package ntp is not installed | package ntp is not installed |
| Sistema de ficheros raíz | xfs | xfs | xfs | xfs |
| LVM2 | 2.02.187(2)-RHEL7 | 2.03.14(2)-RHEL8 | 2.03.33(2)-RHEL9 | 2.03.36(2)-RHEL10 |
| xfsprogs | xfsprogs-4.5.0-22.el7.x86_64 | xfsprogs-5.0.0-10.el8.x86_64 | xfsprogs-6.4.0-7.el9.x86_64 | xfsprogs-6.16.0-1.el10.x86_64 |
| Demonio de logs | rsyslog-8.24.0-55.el7.x86_64 | rsyslog-8.2102.0-7.el8.x86_64 | rsyslog-8.2510.0-2.el9.x86_64 | rsyslog-8.2510.0-5.el10.x86_64 |
| Journal persistente | no (volatil) | no (volatil) | no (volatil) | no (volatil) |
| Modo de arranque | BIOS | BIOS | BIOS | BIOS |
| cgroups (tipo de FS) | tmpfs | tmpfs | cgroup2fs | cgroup2fs |
| Política criptográfica | no aplica | DEFAULT | DEFAULT | DEFAULT |
| Suscripción | Disabled | Disabled | Registered | Registered |
| Repositorios activos | rhel-7-server-rpms/7Server/x86_64  | rhel-8-for-x86_64-appstream-rpms rhel-8-for-x86_64-baseos-rpms  | rhel-9-for-x86_64-appstream-rpms rhel-9-for-x86_64-baseos-rpms  | rhel-10-for-x86_64-appstream-rpms rhel-10-for-x86_64-baseos-rpms  |
