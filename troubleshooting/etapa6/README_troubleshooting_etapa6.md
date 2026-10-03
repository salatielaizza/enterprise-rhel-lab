# 📜 Troubleshooting y guía de estudio — Etapa 6 (bash avanzado y scripting)

Ver formato y regla general en [`troubleshooting/README.md`](../README.md).

Este documento tiene dos usos:

1. **Índice de los casos reales** de troubleshooting de la Etapa 6.
2. **Base de estudio**: todos los comandos y patrones de bash que usan los scripts y el test de esta
   etapa, con una explicación sencilla de qué hace cada uno y para qué sirve.

> Regla del proyecto: *manual → documentado → repetible → automatizado*. Las herramientas de esta
> etapa se pueden lanzar a mano (`sudo /usr/local/sbin/lab-healthcheck.sh -v`); el temporizador de
> systemd solo las programa.

---

## 1. Casos documentados

| Caso | Tema |
|---|---|
| [01 log-verbose-set-e-lab-healthcheck](01-log-verbose-set-e-lab-healthcheck.md) 🔎 | `lab-healthcheck.timer` fallaba: función `log()` devolvía 1 bajo `set -e` sin `-v` |

🔎 = encontrado de forma orgánica al ejecutar contra las VMs reales.

Relacionados de otras etapas (el mismo tipo de trampa de bash):
[etapa2/05](../etapa2/05-findmnt-multiple-args-exit1.md) (código de salida inesperado de un comando
bajo `set -e`) y [etapa3/07](../etapa3/07-tabla-resumen-tests-set-e-command-substitution.md)
(`out="$(...)"; ec=$?` con `set -e`).

---

## 2. Flujo de la etapa (orden exacto)

| # | Comando | Script que ejecuta | Dónde corre |
|---|---|---|---|
| 1 | `scripts/lab.sh stage6 <host\|all>` | `stage6/01-bash-tools.sh` (instala `files/lab-healthcheck.sh` y `files/lab-logscan.sh`) | VM (root) |
| 2 | (automático) | `lab-healthcheck.timer` → `lab-healthcheck.service` cada 5 min | VM |
| 3 | `scripts/lab.sh test all <host\|all>` | `run_all.sh` → añade `test_bash_tools.sh` | VM |
| 4 | `scripts/lab.sh snapshot create <host> 6` | `scripts/03-snapshot.sh` | Host |

---

## 3. Comandos de los scripts, explicados

### 3.1 `01-bash-tools.sh` — instalación y temporizador

| Comando | Qué hace | Por qué |
|---|---|---|
| `install -m 0750 -o root -g root files/lab-healthcheck.sh /usr/local/sbin/` | Copia con permisos y dueño en un paso | `/usr/local/sbin` = herramientas propias de administración, fuera de lo que gestiona `rpm` |
| `bash -n /usr/local/sbin/lab-healthcheck.sh` | Comprueba la sintaxis **sin ejecutar** | Si hay un error de sintaxis, el script de instalación se para (`set -e`) |
| `touch /var/log/lab-healthcheck.log` + `chmod 0644` | Crea el log vacío | |
| `Type=oneshot` (en el `.service`) | El servicio ejecuta algo y termina | No es un demonio: no se espera que siga corriendo |
| `OnBootSec=1min` (en el `.timer`) | Primera ejecución 1 min después de arrancar | |
| `OnUnitActiveSec=5min` | Repite 5 min después de la última ejecución | |
| `Unit=lab-healthcheck.service` | Qué servicio lanza el temporizador | Por defecto, el del mismo nombre |
| `WantedBy=timers.target` | Se activa al arrancar al hacer `enable` | Se habilita el **timer**, no el service |
| `systemctl daemon-reload` | Relee las unidades nuevas | |
| `systemctl enable --now lab-healthcheck.timer` | Habilita y arranca el temporizador | |
| `systemctl start lab-healthcheck.service \|\| true` | Primera ejecución inmediata | `\|\| true`: si falla, no corta la instalación (se verá en los tests) |

**Por qué un timer de systemd y no cron:** queda registro en el journal
(`journalctl -u lab-healthcheck.service`), se ve cuándo fue la última y la próxima ejecución
(`systemctl list-timers`), se puede lanzar a mano con `systemctl start`, y hereda las opciones de
seguridad de las unidades systemd.

### 3.2 `lab-healthcheck.sh` — patrones de bash

| Línea / patrón | Qué hace | Por qué |
|---|---|---|
| `set -euo pipefail` | `-e` sale al primer error; `-u` error si se usa una variable no definida; `pipefail` un pipe falla si falla **cualquier** comando, no solo el último | Que el script no siga como si nada tras un fallo |
| `while getopts ":vt:" opt; do case "$opt" in ...` | Lee opciones `-v` y `-t <valor>` | `:` inicial = errores silenciosos gestionados por el propio script; `t:` = `-t` lleva argumento (`$OPTARG`) |
| `log() { local level="$1"; shift; ... }` | Función con variable local | `local` evita pisar variables globales; `shift` quita el primer argumento y deja el resto en `$*` |
| `printf '%s [%s] %s\n' "$(date ...)" ... >> "$LOG"` | Escribe en el log con fecha | `printf` es más predecible que `echo` |
| `if [[ $VERBOSE -eq 1 ]]; then ... fi` | Imprime solo en modo verbose | **No** `[[ ... ]] && printf`: si es la última línea de la función y la condición es falsa, la función devuelve 1 y `set -e` aborta (caso 01) |
| `trap 'log ERROR "... (línea $LINENO)"' ERR` | Ejecuta algo cuando un comando falla | Deja constancia en el log de dónde se rompió |
| `declare -a SERVICES=(sshd chronyd)` + `SERVICES+=(named)` | Array y añadir un elemento | La lista de servicios depende del host |
| `for svc in "${SERVICES[@]}"` | Recorre el array | Las comillas en `"${arr[@]}"` mantienen cada elemento separado aunque tenga espacios |
| `systemctl is-active --quiet "$svc"` | 0 si está activo | |
| `df -P "$mnt" \| awk 'NR==2{gsub("%","",$5); print $5}'` | Porcentaje de uso del disco | `-P` = formato POSIX, siempre en una línea (evita que nombres largos partan la salida) |
| `(( use >= DISK_THRESHOLD ))` | Comparación aritmética | Dentro de `(( ))` no hace falta `$` |
| `nproc` / `awk '{print $1}' /proc/loadavg` | CPUs y carga media de 1 minuto | Carga > nº de CPUs = hay procesos esperando |
| `exit $FAILED` | 0 si todo bien, 1 si algo falló | systemd marca el servicio como `failed` si sale con 1 |

### 3.3 `lab-logscan.sh` — patrones de bash

| Línea / patrón | Qué hace | Por qué |
|---|---|---|
| `declare -A COUNT=()` | Array **asociativo** (diccionario clave → valor) | Contar intentos por IP |
| `date -d "-60 minutes" '+%Y-%m-%d %H:%M:%S'` | Fecha de hace 60 minutos | Formato que entiende `journalctl --since` |
| `journalctl -u sshd --since "$SINCE"` | Logs de sshd desde esa fecha | Fuente fiable en RHEL 7-10, con o sin rsyslog |
| `grep -E 'Failed (password\|publickey)'` | Filtra intentos fallidos | |
| `grep -Eo 'from [0-9.]+' \| awk '{print $2}'` | Extrae solo la IP | `-o` imprime solo lo que coincide, no la línea entera |
| `while IFS= read -r ip; do ... done < <(...)` | Lee línea a línea desde una **process substitution** | Con `cmd \| while`, el bucle corre en un subshell y el array se pierde al salir. Con `< <(cmd)` el bucle corre en el shell actual |
| `IFS= read -r` | Lee la línea tal cual | `IFS=` no recorta espacios; `-r` no interpreta `\` |
| `COUNT["$ip"]=$(( ${COUNT["$ip"]:-0} + 1 ))` | Incrementa el contador | `:-0` = 0 si la clave aún no existe (necesario con `set -u`) |
| `${#COUNT[@]}` | Número de elementos | |
| `for ip in "${!COUNT[@]}"` | Recorre las **claves** (`!`) | |
| `sort -rn` | Ordena numérico (`-n`) de mayor a menor (`-r`) | |

---

## 4. Comandos del test (`tests/test_bash_tools.sh`), explicados

Se lanza con `scripts/lab.sh test all <host|all>`. `run_all.sh` lo añade a partir de `LAB_STAGE=6`.

| Comprobación | Comando manual equivalente | Qué demuestra |
|---|---|---|
| Herramientas instaladas y ejecutables | `test -x /usr/local/sbin/lab-healthcheck.sh` (`ls -l`) | `-x` = existe y tiene permiso de ejecución |
| Sin errores de sintaxis (×2) | `bash -n /usr/local/sbin/lab-logscan.sh` | |
| El healthcheck devuelve 0 | `sudo /usr/local/sbin/lab-healthcheck.sh -v; echo $?` | El sistema está sano **y** el script no aborta por un fallo propio (caso 01) |
| Timer activo y habilitado | `systemctl is-active lab-healthcheck.timer; systemctl is-enabled lab-healthcheck.timer` | |
| El log tiene contenido | `test -s /var/log/lab-healthcheck.log` (`tail /var/log/lab-healthcheck.log`) | Al menos una ejecución real |

---

## 5. Comandos de diagnóstico del caso real y de scripts en general

| Comando | Qué hace | Caso / uso |
|---|---|---|
| `systemctl status lab-healthcheck.service --no-pager` | Resultado de la última ejecución | 01 — `status=1/FAILURE` |
| `journalctl -xeu lab-healthcheck.service` | Log del servicio con explicaciones (`-x`), desde el final (`-e`) | 01 |
| `systemctl list-timers lab-healthcheck.timer` | Última y próxima ejecución | |
| `bash -x /usr/local/sbin/lab-healthcheck.sh` | Ejecuta mostrando cada comando antes de lanzarlo | La forma más rápida de ver en qué línea se para un script |
| `echo $?` justo después de un comando | Código de salida del último comando | 0 = éxito; cualquier otro = fallo |
| `bash -n script.sh` | Solo comprueba sintaxis | Antes de instalar o ejecutar |
| `shellcheck script.sh` | Análisis estático: detecta comillas que faltan, variables sin usar, trampas de `set -e`... | Recomendado en el host (no viene en RHEL por defecto) |
| `PS4='+ ${LINENO}: ' bash -x script.sh` | Como `-x`, pero con el número de línea | |

---

## 6. Trampas de `set -e` (resumen de lo aprendido en el proyecto)

| Patrón | Qué pasa | Alternativa |
|---|---|---|
| `[[ cond ]] && cmd` como última línea de una función | Si `cond` es falsa, la función devuelve 1 → aborta (caso 01) | `if [[ cond ]]; then cmd; fi` |
| `out="$(cmd)"; ec=$?` | Si `cmd` falla, `set -e` aborta antes de llegar a `ec=$?` (etapa3/07) | `if out="$(cmd)"; then ec=0; else ec=$?; fi` |
| Un comando que devuelve ≠ 0 sin que sea un error (ej. `findmnt` con varias rutas, `grep` sin coincidencias) | Aborta (etapa2/05) | `cmd \|\| true` cuando el fallo es aceptable, o comprobarlo en un `if` |
| `cmd \| while read ...; do arr+=(...); done` | El array queda vacío fuera del bucle (subshell) | `while read ...; done < <(cmd)` |
| Comando que puede colgarse (ej. `ausearch`) | El script se queda esperando para siempre (etapa2/06) | `timeout N cmd` |

---

## 7. Chuleta: síntoma → primeros comandos

| Síntoma | Primeros comandos |
|---|---|
| El servicio del timer sale `failed` | `systemctl status <svc>`, `journalctl -u <svc> -n 30`, ejecutar el script a mano con `bash -x` |
| El script funciona con `-v` y falla sin él | Buscar `&& ` como última línea de una función (caso 01) |
| El script se para sin mensaje | `bash -x`, revisar `set -e` y el `trap ERR` |
| El timer no se ejecuta | `systemctl list-timers`, `systemctl is-enabled <timer>` (¿se habilitó el timer o el service?) |
| Un array queda vacío tras un bucle | ¿Se usó `cmd \| while`? Pasar a `< <(cmd)` |
| `unbound variable` | `set -u`: usar `${VAR:-valor_por_defecto}` |

---

## 8. Preguntas de repaso

1. ¿Qué hace cada parte de `set -euo pipefail`?
2. ¿Por qué `[[ cond ]] && cmd` puede abortar un script con `set -e`?
3. ¿Qué diferencia hay entre `cmd | while read` y `while read ... < <(cmd)`?
4. ¿Para qué sirve `trap ... ERR`?
5. ¿Qué hace el `:` inicial en `getopts ":vt:"`?
6. ¿Qué diferencia hay entre `"${arr[@]}"` y `"${!arr[@]}"` en un array asociativo?
7. ¿Por qué `df -P` y no `df` a secas dentro de un script?
8. ¿Qué ventajas tiene un timer de systemd frente a cron?
9. ¿Qué diferencia hay entre habilitar el `.timer` y habilitar el `.service`?
10. ¿Qué diferencia hay entre `bash -n`, `bash -x` y `shellcheck`?
