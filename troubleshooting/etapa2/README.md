# Troubleshooting — Etapa 2 (administración Linux)

Ver formato y regla general en [`troubleshooting/README.md`](../README.md).

| Caso | Tema |
|---|---|
| [01 service-down](01-service-down.md) | Servicio parado (sshd) y servicio que se cae (lab-app) |
| [02 bad-fstab](02-bad-fstab.md) | fstab con UUID erróneo → modo emergencia |
| [03 permission-denied](03-permission-denied.md) | ACL/permisos: acceso denegado |
| [04 selinux-denial](04-selinux-denial.md) | Etiqueta SELinux incorrecta → 203/EXEC |
| [05 findmnt-multiple-args-exit1](05-findmnt-multiple-args-exit1.md) | `stage2/02-lvm.sh` se detiene tras "Montajes:": `findmnt` con varias rutas devuelve 1 |
| [06 ausearch-colgado-timeout](06-ausearch-colgado-timeout.md) | `test_services.sh` se cuelga indefinidamente: `ausearch` sin responder |
| [07 acl-heredada-lab-app-env-modo-650](07-acl-heredada-lab-app-env-modo-650.md) | `lab-app.env` queda en 650 en vez de 640: ACL heredada del directorio config |
| [08 pwck-usuario-ftp-var-ftp-inexistente](08-pwck-usuario-ftp-var-ftp-inexistente.md) | `pwck`: usuario `ftp` sin `/var/ftp` (solo RHEL 7) |
| [09 journalctl-u-no-encuentra-lab-app-rhel8](09-journalctl-u-no-encuentra-lab-app-rhel8.md) | `journalctl -u` no encuentra heartbeats en RHEL 8; usar `-t` |

Nota: el caso 01 (`service-down`) también se apoya en habilidades de la Etapa 3 (diagnóstico de red
antes de descartar firewall); el caso 06 (`ausearch-colgado-timeout`) apareció encadenado detrás de
[etapa3/06](../etapa3/06-ssh-lento-usedns-fqdn-inexistente.md).
