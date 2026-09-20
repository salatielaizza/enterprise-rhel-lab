# Logs: journald, rsyslog y auditoría

## 1. Objetivo
Encontrar rápidamente la causa de un fallo con `journalctl`, `/var/log/*` y `ausearch`; controlar la persistencia del journal.

## 2. Prerrequisitos
`lab-app` desplegado (genera latidos y fallos a voluntad).

## 3. Arquitectura
`journald` recoge stdout/stderr de servicios y logs del kernel (binario, con filtros). `rsyslog` escribe ficheros de texto:
`/var/log/messages` (general), `/var/log/secure` (autenticación, sudo, sshd), `/var/log/cron`, `/var/log/audit/audit.log` (auditd/SELinux), `/var/log/dnf.log` (8+) o `/var/log/yum.log` (7) ◦.

## 4. Procedimiento manual y comandos
| Comando | Qué hace | Por qué | Salida / fallo |
|---|---|---|---|
| `journalctl -u lab-app -n 20 --no-pager` | Últimas líneas de una unidad | Primer vistazo | Latidos `heartbeat N …` |
| `journalctl -u lab-app -f` | Seguir en vivo | Ver eventos al reproducirlos | — |
| `journalctl -p err -b` | Errores (prioridad ≤ err) del arranque actual | Filtrar ruido | — |
| `journalctl --since "10 min ago" --until now` | Ventana temporal | Correlacionar con un incidente | — |
| `journalctl -b -1`, `--list-boots` | Arranque anterior | Solo si el journal es persistente | Vacío/1 sola entrada = volátil |
| `journalctl -k`, `dmesg -T` | Kernel | Discos, red, OOM | — |
| `journalctl _COMM=sshd`, `-t sudo`, `_SYSTEMD_UNIT=named.service` | Filtros por campo | Precisión | — |
| `sudo journalctl --disk-usage`, `--vacuum-size=100M` | Espacio del journal | Limitar | — |
| `logger -t prueba "hola"` | Escribe un mensaje | Probar la cadena de logging | Aparece en journal y (con rsyslog) en `/var/log/messages` |
| `sudo tail -f /var/log/secure` | Autenticación | Depurar SSH/sudo | `Failed publickey`, `Accepted publickey` |
| `sudo ausearch -m avc -ts recent`; `sudo aureport -a` | Denegaciones SELinux | Causa nº1 de "permisos raros" | Ver `troubleshooting/06-selinux-denial.md` |

Journal persistente: `sudo mkdir -p /var/log/journal && sudo systemd-tmpfiles --create --prefix /var/log/journal && sudo systemctl restart systemd-journald` (o `Storage=persistent` en `/etc/systemd/journald.conf`).
Rotación: `logrotate` (`/etc/logrotate.conf`, `/etc/logrotate.d/`); prueba en seco con `logrotate -d /etc/logrotate.conf`.

## 5. Resultado esperado y validación
Puedes reconstruir la línea temporal de un fallo de `lab-app` (`LAB_APP_CRASH_AFTER=3`) solo con `journalctl` y `systemctl status`.

## 6. Troubleshooting
Sin logs de un servicio → ¿escribe a fichero y no a stdout? ¿`SyslogIdentifier`? Journal "vacío" tras reiniciar → volátil. Disco lleno por logs → `du -xh /var/log | sort -h | tail`, `--vacuum-size`.

## 7. Errores comunes
Buscar solo en `/var/log/messages` (los servicios modernos van al journal); no acotar por tiempo; borrar `/var/log` a mano en vez de rotar.

## 8. Diferencias RHEL 7 / 8 / 9 / 10
Journal volátil o persistente por defecto: **compruébalo en cada VM** (`ls -d /var/log/journal`; `collect-facts.sh` lo registra) ◦. Log de paquetes: `yum.log` vs `dnf.log` ◦. La opción `journalctl --list-boots` depende de la persistencia.

## 9. Automatización
`collect-facts.sh` registra la persistencia del journal por versión.

## 10. Ejercicio
Provoca 3 caídas de `lab-app` y elabora un informe (hora, código de salida, reinicios); habilita el journal persistente, reinicia y consulta `-b -1`; localiza en `/var/log/secure` tu último `sudo`.

## 11. Criterios de aceptación
Resuelves los casos `03-service-down` y `06-selinux-denial` usando solo logs.
