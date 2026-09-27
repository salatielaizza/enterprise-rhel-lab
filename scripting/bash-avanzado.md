# Bash avanzado y scripting (Etapa 6)

## Objetivo
Escribir herramientas de administración propias con patrones de bash "de producción" (manejo de errores, opciones, estructuras de datos) y desplegarlas como una unidad systemd programada, en vez de un cron pelado.

## Preparación
Etapas 1-5 completadas. `scripts/stage6/01-bash-tools.sh` instala `lab-healthcheck.sh` y `lab-logscan.sh` en `/usr/local/sbin/`, junto con `lab-healthcheck.timer` (systemd) que ejecuta el healthcheck cada 5 minutos.

## Técnicas cubiertas (con el motivo, no solo la sintaxis)
| Técnica | Dónde se usa | Por qué importa |
|---|---|---|
| `set -euo pipefail` | Cabecera de ambos scripts | Falla rápido y ruidoso en vez de continuar con datos a medias; `pipefail` evita que un error a mitad de un pipe (`cmd1 \| cmd2`) pase desapercibido |
| `trap 'comando' ERR` | `lab-healthcheck.sh` | Registra en el log **por qué** se abortó el script, con el número de línea (`$LINENO`), en vez de morir en silencio |
| `getopts` | Ambos scripts (`-v`, `-t`, `-m`) | Forma estándar de parsear opciones cortas en bash; más robusto que comparar `"$1"` a mano |
| Arrays (indexados y asociativos) | `SERVICES=(...)` y `COUNT["$ip"]` | Estructura de datos real en vez de variables sueltas o concatenar cadenas |
| Aritmética `(( ))` | Comparación de umbral de disco | Más legible y menos propenso a errores que `[ "$a" -ge "$b" ]` para cálculos |
| Process substitution (`< <(...)`) | `lab-logscan.sh` | El `while read` corre en el shell **actual**, no en un subshell — así el array `COUNT` sobrevive al bucle (un `cmd \| while read` clásico pierde las variables al salir) |
| Evitar parsear `ls` | En ningún sitio se hace `for f in $(ls ...)` | Nombres con espacios/comodines rompen ese patrón; se usa `journalctl`/`awk`/globbing real |
| Unidad `.service` + `.timer` en vez de `cron` | `lab-healthcheck.timer` | Se integra con `systemctl status`/`journalctl -u`, permite `OnBootSec`/`OnUnitActiveSec`, y no depende de que `crond` esté corriendo |

## Verificación
`tests/test_bash_tools.sh`: ambos scripts instalados, ejecutables y sin errores de sintaxis (`bash -n`); el healthcheck se ejecuta y devuelve 0; el timer está activo y habilitado; el log tiene contenido.

## Depuración (ejercicio)
Rompe algo a propósito (por ejemplo, borra una comilla en `lab-healthcheck.sh`) y depúralo con:
- `bash -n script.sh` — solo sintaxis, no ejecuta nada.
- `bash -x script.sh` — traza cada comando ejecutado (muy verboso, pero exacto).
- `shellcheck script.sh` (si está instalado) — avisa de errores comunes que `bash -n` no detecta, como el del caso 27 de este mismo proyecto: comillas anidadas que cambian el momento en que se expande `$?`.

## Errores comunes
Parsear `ls` o la salida "bonita" de un comando en vez de una forma pensada para *scripting*; usar `cmd | while read` esperando que las variables sobrevivan al bucle; no comprobar `$?` (o no usar `set -e`) y seguir ejecutando pasos sobre un error ya ocurrido; scripts que solo se han probado "en caliente" a mano y nunca con `bash -n`/`shellcheck` antes de desplegarlos (ver casos `25` y `27` de este proyecto, ambos por ediciones manuales sin esa doble comprobación).

## Diferencias RHEL 7 / 8 / 9 / 10
Bash 4.2 (RHEL 7) frente a 4.4+ en RHEL 8-10 ◦: los arrays asociativos y `getopts` usados aquí funcionan igual en las cuatro. `systemd` con soporte de `.timer` está presente en las cuatro versiones.

## Relevancia profesional
El scripting en bash con manejo de errores real (`set -euo pipefail`, `trap`, código de salida) es uno de los temas más preguntados en entrevistas de sysadmin/DevOps junior-mid, normalmente como ejercicio práctico en vivo ("escribe un script que...") — ver la guía de [Linux Shell Scripting Interview Questions (LinuxTeck)](https://www.linuxteck.com/linux-shell-scripting-interview-questions/), que sitúa estas habilidades en un rango salarial de referencia de 85.000-145.000 $ (mercado EE.UU., 2026) para los roles que las dominan bien. Automatizar con *systemd timers* en vez de `cron` es además una respuesta habitual a "¿cómo lo harías en un sistema moderno?" en esas mismas entrevistas.

## Ampliaciones futuras
Un script que dé de alta/baja usuarios de prueba de forma controlada (practicar automatización de altas/bajas con validación de entrada); extender `lab-logscan.sh` para analizar logs de un servidor web (Apache httpd/NGINX) cuando se despliegue en la Etapa 9, aplicando las mismas técnicas (arrays, process substitution) a un formato de log distinto (access log en vez de `journalctl`).
