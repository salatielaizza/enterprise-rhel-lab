# 🛡️ Troubleshooting y guía de estudio — Etapa 5 (seguridad: SELinux, auditd, hardening)

Ver formato y regla general en [`troubleshooting/README.md`](../README.md).

Este documento tiene dos usos:

1. **Índice de los casos reales** de troubleshooting de la Etapa 5.
2. **Base de estudio**: todos los comandos que usan los scripts y los tests de esta etapa, con
   una explicación sencilla de qué hace cada uno y para qué sirve al diagnosticar.

> Regla del proyecto: *manual → documentado → repetible → automatizado*. Cada comando de esta
> guía se puede lanzar a mano dentro de una VM (como root); los scripts solo los encadenan.

---

## 1. Casos documentados

La Etapa 5 se ejecutó y validó con 0 FAIL en las 6 VMs **sin incidencias propias**, así que todavía
no tiene casos numerados. Si aparece alguno, se añade aquí como `01-slug.md`.

Casos de otras etapas que practican lo mismo que esta:

| Caso | Relación con la Etapa 5 |
|---|---|
| [etapa2/04 selinux-denial](../etapa2/04-selinux-denial.md) | Etiqueta SELinux incorrecta → `203/EXEC`: diagnóstico completo con `ausearch`, `matchpathcon`, `restorecon` |
| [etapa2/06 ausearch-colgado-timeout](../etapa2/06-ausearch-colgado-timeout.md) | Por qué `ausearch` se usa **siempre** con `timeout` (también en `stage5/01`) |
| [etapa4/02 ssh-failure](../etapa4/02-ssh-failure.md) | Variante SELinux: `authorized_keys` con tipo incorrecto |

---

## 2. Flujo de la etapa (orden exacto)

| # | Comando | Script que ejecuta | Dónde corre |
|---|---|---|---|
| 1 | `scripts/lab.sh stage5 <host\|all>` | `stage5/01-selinux-hardening.sh` | VM (root) |
| 2 | (mismo comando) | `stage5/02-audit-rules.sh` | VM |
| 3 | (mismo comando) | `stage5/03-os-hardening.sh` (el último: hace `set_stage 5`) | VM |
| 4 | `scripts/lab.sh test all <host\|all>` | `run_all.sh` → añade `test_selinux`, `test_audit`, `test_hardening` | VM |
| 5 | `scripts/lab.sh snapshot create <host> 5` | `scripts/03-snapshot.sh` | Host |

Cada fichero que se toca se copia antes como `<fichero>.lab-bak.<AAAAMMDDhhmmss>`.

---

## 3. Comandos de los scripts, explicados

### 3.1 `01-selinux-hardening.sh` — SELinux en Enforcing

| Comando | Qué hace | Por qué |
|---|---|---|
| `getenforce` | Modo actual: `Enforcing`, `Permissive` o `Disabled` | Enforcing = bloquea y registra; Permissive = solo registra; Disabled = apagado |
| `setenforce 1` | Pasa a Enforcing **en caliente** (no persistente) | Si está `Disabled` no sirve: hay que cambiar el fichero y **reiniciar** |
| `cp -a /etc/selinux/config ...lab-bak.<fecha>` | Copia de seguridad | |
| `sed -i -E 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config` | Modo **persistente** tras reiniciar | `setenforce` solo dura hasta el próximo arranque |
| `getsebool ssh_chroot_rw_homedirs` | Valor actual de un booleano | Los booleanos activan o desactivan partes de la política sin escribir reglas |
| `setsebool -P ssh_chroot_rw_homedirs on` | Cambia el booleano; `-P` = persistente | Sin `-P` se pierde al reiniciar |
| `semanage fcontext -a -t user_home_t '/srv/sftp/[^/]+/upload(/.*)?'` | Añade una regla de etiquetado a la **base de datos** de la política | Si ya existe, `-a` falla y se usa `-m` (modificar) |
| `restorecon -R /srv/sftp` | Aplica a los ficheros las etiquetas que dice la política | `semanage` define la regla; `restorecon` la aplica |
| `restorecon -R /opt/application /var/log/lab-app` | Repone etiquetas de los directorios del lab | Defensivo, por si una operación manual las rompió |
| `timeout 15 ausearch -m avc,user_avc -ts today > /var/log/lab-selinux-baseline.log` | Guarda las denegaciones SELinux de hoy | "Foto" para comparar después; con `timeout` porque `ausearch` puede colgarse |

### 3.2 `02-audit-rules.sh` — auditd y reglas de vigilancia

| Comando | Qué hace | Por qué |
|---|---|---|
| `command -v auditctl` | ¿Está instalado `audit`? | |
| `dnf install -y audit` (o `yum` en RHEL 7) | Instala el paquete | |
| `systemctl enable --now auditd` | Habilita y arranca | |
| `cat > /etc/audit/rules.d/lab-hardening.rules` | Escribe las reglas en un fichero de `rules.d/` | **Nunca** se edita `/etc/audit/audit.rules`: se regenera a partir de `rules.d/` |
| `-w /etc/passwd -p wa -k lab-identity` | Vigila un fichero (`-w`) en escritura (`w`) y cambio de atributos (`a`), con la etiqueta `lab-identity` (`-k`) | La clave permite buscar luego con `ausearch -k lab-identity` |
| `-w /etc/sudoers.d/ -p wa -k lab-sudo` | Vigila un **directorio** entero | Cualquier fichero nuevo o cambiado en `sudoers.d` queda registrado |
| `augenrules --load` | Une todos los `rules.d/*.rules` en `audit.rules` y los carga en el kernel | |
| `auditctl -l` | Lista las reglas **cargadas en el kernel** | Es la comprobación real: un fichero puede existir y no estar cargado |

### 3.3 `03-os-hardening.sh` — contraseñas, caducidad, sysctl y aviso legal

| Comando / ajuste | Qué hace | Por qué |
|---|---|---|
| `minlen = 12` en `/etc/security/pwquality.conf` | Longitud mínima de contraseña | Lo aplica PAM al hacer `passwd` |
| `dcredit/ucredit/lcredit/ocredit = -1` | Obliga a al menos 1 dígito, 1 mayúscula, 1 minúscula y 1 símbolo | Valor **negativo** = mínimo obligatorio; positivo = "crédito" que reduce la longitud exigida |
| `grep -Eq "^minlen[[:space:]]*="` → `sed -i` o `echo >>` | Si la línea existe la cambia; si no, la añade | Idempotente: no duplica líneas |
| `PASS_MAX_DAYS 90`, `PASS_MIN_DAYS 1`, `PASS_WARN_AGE 7` en `/etc/login.defs` | Caducidad por defecto | **Solo afecta a usuarios creados después**; para los existentes se usa `chage` |
| `net.ipv4.conf.all.accept_source_route = 0` | Ignora paquetes con ruta impuesta por el origen | Técnica antigua para saltarse filtros |
| `net.ipv4.conf.all.accept_redirects = 0` | Ignora redirecciones ICMP | Evita que alguien cambie tus rutas desde fuera |
| `net.ipv4.conf.all.rp_filter = 1` | Descarta paquetes cuya IP de origen no encaja con la interfaz de entrada | Protección básica contra IP falsificadas |
| `net.ipv4.icmp_echo_ignore_broadcasts = 1` | No responde a pings a direcciones de broadcast | Evita ataques de amplificación (smurf) |
| `kernel.randomize_va_space = 2` | Aleatorización completa de la memoria (ASLR) | Dificulta la explotación de fallos de memoria |
| `/etc/sysctl.d/98-lab-hardening.conf` | Fichero propio con esos valores | `/etc/sysctl.d/` = persistente; `sysctl -w` sería solo en caliente |
| `sysctl --system` | Carga **todos** los ficheros de configuración de sysctl | Aplica sin reiniciar |
| `/etc/issue` | Aviso legal que se muestra antes del login en consola | Requisito habitual de auditorías |
| `set_stage 5` | Marca `LAB_STAGE=5` | Solo en el último script de la etapa |

---

## 4. Comandos de los tests, explicados

Se lanzan con `scripts/lab.sh test all <host|all>`. `run_all.sh` los añade a partir de `LAB_STAGE=5`.
Todos son de **solo lectura**. Estos tests definen funciones cortas y se las pasan a `check` (en vez
de `bash -c "..."`), para evitar problemas de comillas anidadas.

### 4.1 `test_selinux.sh`

| Comprobación | Comando manual equivalente | Qué demuestra |
|---|---|---|
| SELinux instalado | `command -v getenforce` | |
| Modo Enforcing **ahora** | `getenforce` | |
| Enforcing **tras reiniciar** | `grep ^SELINUX= /etc/selinux/config` | Lo que vale ahora y lo que valdrá al arrancar son cosas distintas |
| Booleano `ssh_chroot_rw_homedirs=on` | `getsebool ssh_chroot_rw_homedirs` | |
| `upload` con tipo `user_home_t` | `ls -Zd /srv/sftp/*/upload` | La regla de `semanage` se aplicó |
| Foto de AVC presente | `ls -l /var/log/lab-selinux-baseline.log` | |

### 4.2 `test_audit.sh`

| Comprobación | Comando manual equivalente | Qué demuestra |
|---|---|---|
| `auditctl` disponible | `command -v auditctl` | |
| `auditd` activo y habilitado | `systemctl is-active auditd; systemctl is-enabled auditd` | |
| Reglas cargadas (×4) | `auditctl -l` | Las reglas están **en el kernel**, no solo en un fichero |
| Fichero de reglas del lab | `ls -l /etc/audit/rules.d/lab-hardening.rules` | |

### 4.3 `test_hardening.sh`

| Comprobación | Comando manual equivalente | Qué demuestra |
|---|---|---|
| `minlen >= 12` | `grep minlen /etc/security/pwquality.conf` | |
| `PASS_MAX_DAYS <= 90` | `grep ^PASS_MAX_DAYS /etc/login.defs` | |
| sysctl (×3) | `sysctl -n net.ipv4.conf.all.accept_source_route` | `-n` imprime solo el valor; es el valor **en vigor**, no el del fichero |
| Fichero de sysctl presente | `ls -l /etc/sysctl.d/98-lab-hardening.conf` | Persistencia |
| Aviso en `/etc/issue` | `cat /etc/issue` | |

---

## 5. Comandos de diagnóstico de SELinux y auditd

Estos son los comandos que se usan para investigar cuando algo falla con SELinux o cuando hay que
averiguar quién cambió un fichero vigilado.

### 5.1 SELinux

| Comando | Qué hace |
|---|---|
| `sestatus` | Estado completo: modo actual, modo del fichero de configuración y política cargada |
| `ls -Z <fichero>` / `ls -dZ <dir>` | Etiqueta del fichero: `usuario:rol:tipo:nivel`. El **tipo** (`_t`) es lo que importa |
| `ps -eZ \| grep <proceso>` | Etiqueta (dominio) de un proceso en ejecución |
| `matchpathcon <ruta>` | Etiqueta que **debería** tener según la política |
| `restorecon -Rv <ruta>` | Repone la etiqueta correcta y muestra qué cambia |
| `timeout 10 ausearch -m avc -ts recent` | Denegaciones de los últimos 10 minutos |
| `timeout 10 ausearch -m avc -ts today -c <comando>` | Denegaciones de hoy para un ejecutable concreto |
| `sealert -a /var/log/audit/audit.log` | Explica las denegaciones en lenguaje natural y propone soluciones (paquete `setroubleshoot-server`) |
| `audit2why < <(ausearch -m avc -ts recent)` | Explica **por qué** se denegó |
| `getsebool -a \| grep <palabra>` | Busca booleanos relacionados |
| `semanage fcontext -l \| grep <ruta>` | Reglas de etiquetado que afectan a una ruta |
| `semanage port -l \| grep <puerto>` | Qué puertos puede usar cada tipo de servicio |
| `setenforce 0` → probar → `setenforce 1` | Confirmar si un fallo es de SELinux. **Solo para diagnosticar**, nunca como solución |

**Orden recomendado ante un `Permission denied` con permisos correctos:**
`ausearch -m avc` → `ls -Z` + `matchpathcon` → ¿etiqueta distinta? `restorecon` →
¿no es etiqueta? `getsebool -a` → ¿ningún booleano encaja? `audit2allow` (último recurso, revisando
qué permite).

### 5.2 auditd

| Comando | Qué hace |
|---|---|
| `timeout 10 ausearch -k lab-identity -ts today` | Cambios de hoy en `passwd`, `shadow` o `group` |
| `timeout 10 ausearch -k lab-sudo -i` | Cambios en sudoers; `-i` traduce UID y llamadas a nombres legibles |
| `aureport -k` | Resumen de eventos agrupados por clave |
| `aureport --auth` / `--login` | Resumen de autenticaciones e inicios de sesión |
| `auditctl -s` | Estado del subsistema de auditoría (activo, eventos perdidos, etc.) |
| `tail -f /var/log/audit/audit.log` | Ver eventos en directo |

**Ejercicio de comprobación:** en una VM, `sudo touch /etc/sudoers.d/prueba && sudo rm /etc/sudoers.d/prueba`
y después `sudo timeout 10 ausearch -k lab-sudo -ts recent -i`. Deben aparecer ambas operaciones
con tu usuario (`auid`), aunque las hicieras con sudo.

---

## 6. Chuleta: síntoma → primeros comandos

| Síntoma | Primeros comandos |
|---|---|
| `Permission denied` con permisos Unix correctos | `timeout 10 ausearch -m avc -ts recent`, `ls -Z`, `matchpathcon` |
| Un servicio da `203/EXEC` | `ls -Z <ExecStart>`, `restorecon -v <ExecStart>` |
| Un servicio no puede usar un puerto nuevo | `semanage port -l \| grep <puerto>`, `semanage port -a -t <tipo> -p tcp <puerto>` |
| SELinux vuelve a Permissive tras reiniciar | `grep ^SELINUX= /etc/selinux/config` |
| `setenforce 1` dice "SELinux is disabled" | Cambiar `/etc/selinux/config`, crear `/.autorelabel` y reiniciar |
| Un booleano vuelve a su valor al reiniciar | Se cambió sin `-P` |
| Una regla de audit no aparece | `auditctl -l`, `augenrules --load`, ¿regla en `/etc/audit/rules.d/`? |
| `ausearch` se queda colgado | Usar siempre `timeout N ausearch ...` |
| Un sysctl no se mantiene tras reiniciar | Se aplicó con `sysctl -w`; pasarlo a `/etc/sysctl.d/` |
| La política de contraseñas no se aplica a un usuario existente | `login.defs` solo afecta a altas nuevas: `chage -M 90 <usuario>` |

---

## 7. Preguntas de repaso

1. ¿Qué diferencia hay entre Enforcing, Permissive y Disabled?
2. ¿Por qué `setenforce 1` no sirve si SELinux está en Disabled?
3. ¿Qué diferencia hay entre `semanage fcontext` y `restorecon`? ¿Y con `chcon`?
4. ¿Qué es un booleano de SELinux y qué hace la opción `-P`?
5. ¿Por qué no se edita `/etc/audit/audit.rules` a mano?
6. ¿Para qué sirve la clave `-k` de una regla de auditoría?
7. ¿Qué significa `-p wa` en una regla `-w`?
8. ¿Qué diferencia hay entre `dcredit = -1` y `dcredit = 1` en `pwquality.conf`?
9. ¿Por qué cambiar `PASS_MAX_DAYS` no afecta a los usuarios que ya existen?
10. ¿Qué diferencia hay entre `sysctl -w` y un fichero en `/etc/sysctl.d/`?
11. ¿Por qué `setenforce 0` nunca es una solución?
