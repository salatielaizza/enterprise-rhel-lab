# Migración RHEL 7 → 8 → 9 → 10 (estrategia y uso del laboratorio)

> Documento de **planificación**. Los procedimientos con Leapp y las pruebas de aplicación se ejecutarán en la Etapa 10 (migraciones); aquí se fija el marco y qué evidencias recoge el laboratorio desde ya. Marcas: ✔ confirmado · ◦ por verificar.

## 1. Objetivo
Decidir *cómo* llevar una aplicación de RHEL 7 a 9 o 10 con riesgo controlado, y usar las cuatro VMs como banco de pruebas de compatibilidad.

## 2. Prerrequisitos
Etapas 1-4 completas y `lab-app` desplegada en las cuatro `app01` (misma aplicación, mismos UID/GID, misma estructura de directorios).

## 3. Estrategias
| Estrategia | Cuándo | Riesgo | Herramienta |
|---|---|---|---|
| **In-place** (actualizar el mismo servidor) | Servidores con estado difícil de reconstruir | Medio-alto; un salto de versión mayor cada vez (7→8→9→10) ◦ | Leapp (`leapp preupgrade` / `upgrade`) ◦ |
| **Reprovisionar (blue/green)** | Aplicaciones reproducibles (nuestro caso) | Bajo; permite volver atrás cambiando DNS | Kickstart + Ansible + `rsync` de datos |
| **Convivencia con corte por DNS** | Migración gradual | Bajo | TTL bajos en BIND (`networking/dns.md`) |
RHEL 7 → 9 **no** se hace en un salto in-place: o se encadena 7→8→9 o se reprovisiona ◦.

## 4. Lista de comprobación previa (inventario)
| Qué | Comando | Por qué |
|---|---|---|
| Paquetes y versiones | `rpm -qa --qf '%{NAME}-%{VERSION}\n' \| sort` | Detectar software fuera de repos |
| Servicios habilitados | `systemctl list-unit-files --state=enabled` | Qué debe existir en destino |
| Puertos y procesos | `ss -tulpn` | Dependencias de red y firewall |
| Usuarios/UID/GID | `getent passwd; getent group` | Coherencia de propiedad de ficheros |
| Sistemas de ficheros | `lsblk -f; xfs_info /punto` | Características XFS que el kernel destino/origen no monte ◦ |
| Cron/timers | `crontab -l; systemctl list-timers` | Tareas programadas |
| Red | `nmcli con show; ip r` | Formato de perfiles (ifcfg → keyfile) |
| Firewall y SELinux | `firewall-cmd --list-all; getenforce; semanage fcontext -l -C` | Reglas y contextos personalizados |
| Hora y DNS | `chronyc sources; cat /etc/resolv.conf` | Servicios de infraestructura |

## 5. Cambios que suelen romper cosas
| Área | 7 → 8 | 8 → 9 | 9 → 10 |
|---|---|---|---|
| Python | Python 2 ya no es el del sistema ◦ | Python 3.9 ◦ | **Python 3.12** ✔ |
| Red | `network-scripts` en desuso ◦ | keyfile por defecto, ifcfg deprecado ✔ | **ifcfg eliminado, dhclient eliminado** ✔ |
| Hora | `ntpd` → chrony ◦ | — | — |
| Firewall | iptables → nftables ◦ | backend iptables en desuso ◦ | verificar ◦ |
| Paquetes | yum → dnf, AppStream/módulos ◦ | — | verificar ◦ |
| SSH/cripto | OpenSSH 7.4 → 8.0 ◦ | OpenSSH 8.7 ✔, políticas más estrictas ◦ | OpenSSH 9.9 ✔ |
| Hardware | — | — | **CPU x86-64-v3 obligatoria** ✔ |
| Cgroups | v1 ◦ | v2 por defecto ◦ | v2 ◦ |

## 6. Procedimiento de ensayo con el laboratorio (blue/green)
1. Baseline: `lab.sh facts all` (estado real de cada versión) y `lab.sh test all all`.
2. Desplegar la **misma** `lab-app` (unidad + script + `.env`) en 7, 8, 9 y 10: mismas rutas, usuarios, ACL y permisos (Etapa 2). Observa qué difiere (SELinux, systemd, rutas de comandos en sudoers).
3. Migrar datos con `rsync -aHAX --numeric-ids` (conserva ACL, xattrs/contexto y UID/GID numéricos) de `/opt/application/data` entre hosts.
4. Cambiar el registro DNS del servicio (TTL bajo) y validar con `test_dns.sh`.
5. Plan de vuelta atrás: snapshot previo + DNS al origen.

## 7. Troubleshooting
Servicio no arranca en destino → `journalctl -u`, `ausearch -m avc`, rutas de binarios (`/usr/bin` vs `/bin`), `EnvironmentFile`. Usuarios con UID distinto → ficheros con dueño incorrecto (`find -nouser`). Cliente antiguo no conecta a un sshd nuevo → algoritmos deshabilitados por la política criptográfica.

## 8. Errores comunes
Migrar sin inventario; saltar versiones mayores en in-place; olvidar cambiar formatos de red (RHEL 10); no probar en el hardware/CPU de destino; no revisar contextos SELinux personalizados.

## 9. Automatización futura
Etapa 7 (Ansible: inventario y roles por versión) y Etapa 10 (Leapp, pruebas de compatibilidad, runbooks).

## 10. Ejercicio (pregunta de entrevista)
*"¿Cómo migrarías esta aplicación de RHEL 7 a RHEL 9?"* Redacta el plan con: inventario, estrategia elegida y por qué, orden de pasos, validaciones, riesgos y vuelta atrás, apoyándote en las diferencias medidas con `lab.sh facts`.

## 11. Criterios de aceptación
Presentas un plan de migración con criterios de éxito medibles y evidencias (`results/`).
