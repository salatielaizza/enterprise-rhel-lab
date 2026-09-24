# 23 — `journalctl -u lab-app` no encuentra los heartbeats en RHEL 8 (usar `-t` en su lugar)

**Objetivo**: reconocer que `journalctl -u <servicio>` puede no encontrar mensajes de un proceso que sí
está escribiendo correctamente al journal, cuando el campo `_SYSTEMD_UNIT` no se etiqueta bien para los
hijos de un proceso `Type=simple` en versiones más antiguas de `systemd-journald`.

**Preparación**: Etapa 2 aplicada (`lab-app.service` activo, escribiendo heartbeats cada 5s).

## Síntoma

`scripts/lab.sh test all all` reportaba, **solo en `rhel8-app01`** (ninguna otra versión, incluido RHEL 7
que usa una versión de systemd aún más antigua):
```
FAIL  lab-app escribe en el journal
```
A pesar de que `/var/log/lab-app/app.log` sí mostraba heartbeats recientes y `systemctl status lab-app`
confirmaba el servicio `active (running)` con normalidad.

## Hipótesis descartadas

1. El proceso dejó de escribir. Descartada: `sudo tail -5 /var/log/lab-app/app.log` mostraba heartbeats
   con timestamp del segundo exacto de la comprobación.
2. Journal lleno o rotado. Descartada: `journalctl --disk-usage` → 8.0M, sin problema de espacio.
3. Límite de tasa (`RateLimit`) silenciando mensajes repetidos. Descartada: `RateLimitIntervalSec`/
   `RateLimitBurst` estaban comentados (valores por defecto, muy por encima de 1 mensaje/5s).

## Diagnóstico que dio con la causa

```bash
ssh rhel8-app01 'sudo journalctl -u lab-app -n 10 --no-pager'
# Solo aparecía la línea "Started ..." de systemd; ningún heartbeat

ssh rhel8-app01 'sudo journalctl -t lab-app -n 10 --no-pager'
# TODOS los heartbeats aparecen correctamente, con SYSLOG_IDENTIFIER=lab-app

ssh rhel8-app01 'sudo journalctl _SYSTEMD_UNIT=lab-app.service -n 5 --no-pager'
# -- No entries --   <- confirma: ningún mensaje del proceso lleva ese campo

ssh rhel8-app01 'sudo journalctl -u lab-app -n 3 --no-pager -o verbose'
# El único mensaje que aparece con -u es el de "Started ...", emitido por PID 1 (systemd) con
# _SYSTEMD_UNIT=init.scope (el cgroup de quien EMITE el mensaje, no el UNIT=lab-app.service al que
# se refiere, que es un campo distinto).
```

`journalctl -u` filtra por el campo `_SYSTEMD_UNIT` (el cgroup real del proceso que escribió el mensaje);
`journalctl -t` filtra por `SYSLOG_IDENTIFIER` (la etiqueta que el propio proceso declara, vía
`SyslogIdentifier=lab-app` en la unidad). Los heartbeats de `lab-app.sh` llegan al journal con
`SYSLOG_IDENTIFIER` correcto, pero **sin** `_SYSTEMD_UNIT=lab-app.service`.

## Causa raíz

El bucle de `lab-app.sh` usa el patrón `sleep "$interval" & wait $!`, que crea un subproceso hijo nuevo en
cada iteración. `systemd-journald` de RHEL 8 (systemd 239) no etiqueta de forma fiable el campo
`_SYSTEMD_UNIT` en los mensajes de estos procesos hijos de una unidad `Type=simple`, a pesar de que el
cgroup real del proceso (confirmado con `systemd-cgls`, no mostrado aquí) sí es el correcto
(`/system.slice/lab-app.service`). Las demás versiones probadas (RHEL 9, RHEL 10, e incluso RHEL 7 con
systemd 219, aún más antiguo) no reproducen el problema — parece una particularidad específica de la
versión de systemd de RHEL 8, no un patrón que empeore monótonamente con la antigüedad.

## Solución aplicada

`tests/test_services.sh`:
```diff
-check "lab-app escribe en el journal" bash -c 'journalctl -u lab-app -n 1 --no-pager -q | grep -q heartbeat'
+check "lab-app escribe en el journal" bash -c 'journalctl -t lab-app -n 1 --no-pager -q | grep -q heartbeat'
```
Cambiar el filtro de `-u` (por unidad) a `-t` (por `SyslogIdentifier`), que sí funciona de forma
consistente en las 4 versiones de RHEL soportadas por el laboratorio. Aplicado a las 6 VMs.

## Validación

```bash
ssh rhel8-app01 'sudo bash lab-scripts/tests/test_services.sh'
# --- test_services en rhel8-app01: 14 PASS, 0 FAIL
```

## Prevención

Al escribir comprobaciones de journal para servicios propios, preferir `-t <SyslogIdentifier>` sobre
`-u <unidad>` cuando el servicio pueda generar subprocesos (patrones como `comando & wait`, `xargs`,
pipelines dentro del propio script) — es más robusto entre versiones de systemd, ya que depende de una
etiqueta que el propio proceso declara explícitamente (`SyslogIdentifier=` en la unidad) en vez de una
inferencia de cgroup que puede fallar según la versión del journald. Alternativa de diseño a considerar en
etapas futuras: evitar crear un subproceso nuevo en cada iteración del bucle (por ejemplo, con `sleep` sin
`&`/`wait` si no hace falta capturar señales de forma tan granular), lo que también eliminaría la causa de
raíz, no solo el síntoma en el test.
