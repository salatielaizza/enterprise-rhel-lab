# SELinux avanzado (Etapa 5)

## Objetivo
Mantener SELinux en modo Enforcing en los 6 hosts, ajustar booleans de forma consciente (nunca "a ciegas"), sanear contextos de los directorios propios del lab, y saber diagnosticar una denegación real con `ausearch`/`sealert`/`audit2allow`.

## Preparación
- Etapas 1-4 completadas.
- `scripts/stage5/01-selinux-hardening.sh` (ejecutado por `lab.sh stage5 <host|all>`) deja el sistema en Enforcing, aplica los booleans documentados y re-aplica los contextos de `/srv/sftp/*/upload` (SFTP enjaulado, Etapa 4).

## Procedimiento manual y comandos
| Comando | Qué hace | Por qué | Salida / fallo |
|---|---|---|---|
| `getenforce` / `sestatus` | Modo actual y política cargada | Primer vistazo | `Enforcing` / `targeted` |
| `sudo setenforce 1\|0` | Cambia el modo **en caliente** (no persiste) | Depurar sin reiniciar | `Disabled` no se puede activar así: hace falta editar `/etc/selinux/config` y reiniciar |
| `sudo vi /etc/selinux/config` (`SELINUX=enforcing`) | Modo persistente | Sobrevive a reinicios | — |
| `getsebool -a` / `sudo setsebool -P <bool> on\|off` | Ver/fijar un boolean (persistente con `-P`) | Activar una excepción concreta y documentada, no desactivar SELinux | Ej.: `ssh_chroot_rw_homedirs` (Etapa 4) |
| `ls -Z`, `ps -Z`, `id -Z` | Contexto de fichero/proceso/usuario | Ver `usuario:rol:tipo:nivel` | El **tipo** (3er campo) es el que casi siempre importa |
| `sudo semanage fcontext -a -t <tipo> '<patrón>'` + `sudo restorecon -R <ruta>` | Fija el contexto **esperado** de una ruta no estándar | Sin esto, `restorecon` no sabría qué contexto poner | Ej.: `/srv/sftp/[^/]+/upload(/.*)?` -> `user_home_t` |
| `sudo ausearch -m avc -ts recent` | Denegaciones AVC recientes | Primer paso ante cualquier "Permission denied" sospechoso | Ninguna línea = no hay denegaciones |
| `sudo sealert -a /var/log/audit/audit.log` (si `setroubleshoot-server` instalado) | Explica la denegación en lenguaje humano y sugiere el `semanage`/`audit2allow` a aplicar | Mucho más rápido que interpretar el AVC a mano | No viene instalado por defecto en un *minimal install* |
| `sudo ausearch -m avc -ts recent \| audit2allow -M lab_custom` + `sudo semodule -i lab_custom.pp` | Genera **e instala** un módulo de política a medida a partir de denegaciones reales | Excepción mínima y auditable, en vez de `setenforce 0` | Revisa SIEMPRE el `.te` generado antes de instalar: `audit2allow` puede sugerir permisos más amplios de lo necesario |

## Automatización
`scripts/stage5/01-selinux-hardening.sh`: fuerza Enforcing (en caliente y persistente), aplica los booleans de un array documentado en el propio script, re-aplica contextos del lab, y guarda una foto de las denegaciones AVC del día en `/var/log/lab-selinux-baseline.log` (para comparar antes/después de un cambio).

## Verificación
`tests/test_selinux.sh`: Enforcing activo y persistente, boolean `ssh_chroot_rw_homedirs=on`, contexto correcto de la jaula SFTP, existe la foto de denegaciones.

## Troubleshooting relacionado
Ver caso [`etapa2/04-selinux-denial.md`](../troubleshooting/etapa2/04-selinux-denial.md) (denegación por etiqueta incorrecta → `203/EXEC`) y caso [`etapa4/07`](../troubleshooting/etapa4/07-sftpdemo-falsos-positivos-pwck-y-test-ssh.md) (un `HOME` relativo bajo `ChrootDirectory` NO es un problema de SELinux, aunque el síntoma —"no puedo entrar"— se parezca).

## Errores comunes
Desactivar SELinux (`setenforce 0` permanente o `SELINUX=disabled`) en vez de investigar la denegación concreta; instalar un módulo `audit2allow` sin revisar qué permisos concede realmente; olvidar `restorecon` tras mover/copiar ficheros (`cp -a` preserva el contexto de origen, que puede ser incorrecto en el destino).

## Diferencias RHEL 7 / 8 / 9 / 10
Política `targeted` por defecto en las cuatro. `setroubleshoot-server`/`sealert` no siempre viene preinstalado (◦, confirmar por host con `collect-facts.sh`). El paquete de utilidades (`policycoreutils-python-utils`, que trae `semanage`) tiene nombres consistentes desde RHEL 7, pero conviene confirmarlo la primera vez en cada versión (◦).

## Prevención
Nunca "solucionar" una denegación desactivando SELinux; documentar cada boolean y cada `fcontext` añadido (con su motivo); comparar la foto de denegaciones antes/después de cualquier cambio grande.

## Relevancia profesional
SELinux aparece de forma recurrente en entrevistas de administración de sistemas Red Hat/Linux, tanto como pregunta directa ("elabora sobre SELinux") como en forma de incidencia real a resolver (permisos que fallan sin motivo aparente) — ver el compendio de [Red Hat Linux System Administrator Interview Questions (Whizlabs)](https://www.whizlabs.com/blog/red-hat-linux-system-administrator-interview-questions/) y las guías de certificación [RHCSA (WebAsha)](https://www.webasha.com/blog/top-rhcsa-red-hat-certified-system-administrator-interview-questions-answers). Saber diagnosticar con `ausearch`/`audit2allow` en vez de desactivar SELinux suele ser justo lo que distingue a un candidato junior de uno con experiencia real en producción.

## Ampliaciones futuras
Cuando se despliegue Apache httpd o NGINX (Etapa 9), repetir este mismo ejercicio con booleans propios de servidor web (`httpd_can_network_connect`, `httpd_can_sendmail`, etc.) y contextos de contenido (`httpd_sys_content_t`) para comparar el mismo flujo de diagnóstico sobre un servicio distinto a SSH.
