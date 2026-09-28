# Etapa 6 · Caso 01 — `lab-healthcheck.timer` fallaba: `log()` devolvía 1 bajo `set -e` sin `-v`

## Objetivo

Determinar por qué `lab-healthcheck.service` (Etapa 6, instalado por
`scripts/lab.sh stage6 all`) fallaba (`status=1/FAILURE`) en los 6 hosts al
ejecutarse a través de `lab-healthcheck.timer`, pese a que el propio script
(`lab-healthcheck.sh`) parecía correcto a simple vista y pasaba `bash -n` sin
errores.

## Preparación

- Etapa 5 completada y validada en los 6 hosts.
- `scripts/lab.sh stage6 all` instala `/usr/local/sbin/lab-healthcheck.sh`,
  `/usr/local/sbin/lab-logscan.sh` y un `lab-healthcheck.timer` (systemd) que
  ejecuta el healthcheck cada 5 minutos, sin pasarle ningún argumento (o sea,
  siempre con `VERBOSE=0`, sin `-v`).
- Copia de seguridad antes de tocar nada:
  ```bash
  cp scripts/stage6/files/lab-healthcheck.sh scripts/stage6/files/lab-healthcheck.sh.bak
  cp scripts/stage6/files/lab-logscan.sh scripts/stage6/files/lab-logscan.sh.bak
  ```

## Síntoma

Tras `scripts/lab.sh stage6 all`, en los 6 hosts:
```
Job for lab-healthcheck.service failed because the control process exited
with error code. See "systemctl status lab-healthcheck.service" and
"journalctl -xeu lab-healthcheck.service" for details.
```
Y cada 5-6 minutos, el temporizador repetía el mismo fallo indefinidamente:
```
$ sudo systemctl status lab-healthcheck.service --no-pager
Active: failed (Result: exit-code) ...
Process: ... ExecStart=/usr/local/sbin/lab-healthcheck.sh (code=exited, status=1/FAILURE)
```

## Hipótesis descartadas

- **"Es el mismo tipo de fallo que los casos etapa2/06 / etapa4/07, hay que envolver algo en
  `timeout` o arreglar comillas anidadas."** Se descartó: no hay ningún
  `ausearch` ni comillas anidadas en `lab-healthcheck.sh`.
- **Primera hipótesis (incorrecta) del propio asistente**: que dos líneas
  sueltas de la forma `condición && comando` bajo `set -e` bastaban por sí
  solas para abortar el script, en cualquier contexto. Se comprobó con
  evidencia real que **no es así a nivel de script**: la línea equivalente en
  `scripts/stage5/02-audit-rules.sh` (`[[ -f "$RULES" ]] && cp -a ...`) nunca
  abortó ese script, y la línea `[[ "$HOST" == dns01 ]] && SERVICES+=(named)`
  de `lab-healthcheck.sh` tampoco impidió que el script llegara a registrar la
  primera línea de log (`servicio sshd activo`) antes de abortar. El problema
  real estaba un nivel más adentro: no en un `&&` suelto a nivel de script,
  sino en el valor de retorno de una **función**.
- **"El healthcheck detecta un problema real (un servicio caído, disco
  lleno)."** Se descartó: ejecutado a mano con `sudo
  /usr/local/sbin/lab-healthcheck.sh -v` terminaba con `exit code: 0` y todas
  las comprobaciones en `[OK]`.

## Diagnóstico

- `sudo cat /var/log/lab-healthcheck.log` mostró, en cada ejecución periódica,
  **exactamente una línea** antes del aviso de aborto:
  ```
  2026-09-28 00:31:10 [OK] servicio sshd activo
  2026-09-28 00:31:10 [ERROR] healthcheck abortado inesperadamente (línea 29)
  ```
  Es decir: el script abortaba justo después de la **primera** llamada a
  `log()`, siempre, en los 6 hosts.
- Ejecutado a mano **con** `-v` (`VERBOSE=1`), el mismo script terminaba
  perfectamente (`exit code: 0`), con las 6 comprobaciones en `[OK]`.
- Eso aisló el problema a la única diferencia entre ambas ejecuciones:
  `VERBOSE=0` (systemd, sin flags) frente a `VERBOSE=1` (`-v` a mano).
- La función `log()` terminaba con esta línea:
  ```bash
  [[ $VERBOSE -eq 1 ]] && printf '[%s] %s\n' "$level" "$*"
  ```
  Con `VERBOSE=0` esa condición es falsa, así que **la función entera
  devuelve el código de salida 1** (el de la condición, al ser el último
  comando ejecutado dentro de la función). Con `VERBOSE=1` la condición
  siempre es verdadera, `printf` se ejecuta y `log()` siempre devuelve 0 — por
  eso el fallo era invisible en la prueba manual con `-v`.
  `log OK "servicio sshd activo"` es una llamada de función normal, **no**
  forma parte de ningún `&&`/`||`/`if` en el punto donde se invoca; bajo
  `set -e`, un comando (incluida una llamada a función) que devuelve
  distinto de 0 en ese contexto aborta el script inmediatamente. Por eso el
  guion se detenía justo ahí, tras el primer `log`.

## Causa raíz

Un `[[ condición ]] && comando` como **última línea de una función**, cuando
la condición es falsa, hace que la función devuelva un código de salida
distinto de cero aunque no haya ocurrido ningún error real. Si esa función se
llama luego como una sentencia normal bajo `set -e` (que es el caso de todas
las llamadas a `log()` en este script), el script aborta.

Esto es distinto — y más sutil — que el "gotcha" ya conocido de
`condición && comando` **suelto directamente en el script** (fuera de una
función), que en la práctica no abortó ni en este mismo script (la línea de
`SERVICES+=(named)`) ni en `stage5/02-audit-rules.sh` (la línea del `cp -a`
del backup).

## Solución aplicada

En `scripts/stage6/files/lab-healthcheck.sh`, dentro de `log()`:

Antes:
```bash
log() {  # log NIVEL mensaje...
  local level="$1"; shift
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$LOG"
  [[ $VERBOSE -eq 1 ]] && printf '[%s] %s\n' "$level" "$*"
}
```

Después:
```bash
log() {  # log NIVEL mensaje...
  local level="$1"; shift
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$LOG"
  if [[ $VERBOSE -eq 1 ]]; then
    printf '[%s] %s\n' "$level" "$*"
  fi
}
```
Un `if` sin `else` siempre devuelve 0 cuando la condición es falsa (el
resultado de un `if`/`fi` vacío en la rama no tomada es éxito), así que
`log()` ya no puede devolver 1 solo por no estar en modo verboso.

Por consistencia (aunque no causó ningún fallo observado) también se
aplicó el mismo estilo explícito a `[[ "$HOST" == dns01 ]] && SERVICES+=(named)`
en el mismo fichero, y a `[[ -n "$ip" ]] && COUNT["$ip"]=...` en
`lab-logscan.sh`: ninguna de las dos causó el problema, pero conviene evitar
el patrón `condición && comando` como sentencia suelta de forma sistemática,
tanto a nivel de script como dentro de funciones, para no depender de esta
diferencia de comportamiento tan poco intuitiva.

## Validación

- `bash -n` en ambos ficheros: sin errores.
- `scripts/lab.sh stage6 all` en los 6 hosts: sin ningún
  "Job for lab-healthcheck.service failed".
- `sudo systemctl status lab-healthcheck.service`: `Active: inactive (dead)`
  con `status=0/SUCCESS` (los `Type=oneshot` quedan "inactive" tras terminar
  bien, no "active"; solo el timer permanece activo).
- `sudo tail -5 /var/log/lab-healthcheck.log`: las 5 comprobaciones en `[OK]`,
  sin ninguna línea `[ERROR] healthcheck abortado`.

## Prevención

- Dentro de una función, nunca terminar con `condición && comando` si la
  función se va a llamar como sentencia normal en un script con `set -e`:
  usar siempre un `if` explícito (o forzar el retorno con `... || true` al
  final de la función si de verdad el resultado de esa comprobación es
  irrelevante).
- Probar un script pensado para `systemd`/`cron` **en las mismas condiciones**
  en que se va a ejecutar ahí (sin TTY, sin flags interactivos como `-v`), no
  solo con las opciones "cómodas" que se usan al probarlo a mano — el propio
  flag `-v` de este script ocultó el fallo durante la prueba manual.
- Ante un fallo de un `.service`, mirar primero el log de la propia
  aplicación (aquí, `/var/log/lab-healthcheck.log`) además de
  `journalctl -xeu`: el punto exacto donde se corta la secuencia de líneas
  (aquí, justo tras la primera) suele señalar la línea culpable mejor que el
  mensaje genérico de systemd.
