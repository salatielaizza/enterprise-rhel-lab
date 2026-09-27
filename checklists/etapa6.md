# ETAPA 6 — CHECKLIST: Bash avanzado y scripting

> Una etapa **no está completa** hasta marcar TODO: documentación + tests + troubleshooting + diferencias entre versiones + snapshot.
> Rellena las columnas "Resultado obtenido" con lo que veas **de verdad** (pega salidas en `results/etapa6/`).

## Objetivo
Escribir y desplegar herramientas propias en bash "de producción" (`set -euo pipefail`, `trap`, `getopts`, arrays, systemd timer en vez de cron) y saber depurarlas.

## Comandos (orden)
| # | Comando | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 1 | `scripts/lab.sh stage6 all` | herramientas instaladas y `lab-healthcheck.timer` activo en los 6 hosts | |
| 2 | `scripts/lab.sh test all all` | 0 FAIL (incluye `test_bash_tools`) | |
| 3 | `sudo /usr/local/sbin/lab-healthcheck.sh -v` | salida con OK/FAIL por cada comprobación | |
| 4 | `sudo /usr/local/sbin/lab-logscan.sh -m 60` | recuento de intentos SSH fallidos por IP (o "sin intentos") | |
| 5 | `sudo systemctl status lab-healthcheck.timer` | próxima ejecución programada | |
| 6 | Ejercicio: rompe el script a propósito (ver `scripting/bash-avanzado.md`) y depúralo con `bash -x` | identificas la causa | |
| 7 | `scripts/lab.sh snapshot create all 6` | `…-stage6-complete` | |

## Documentación
- [ ] `scripting/bash-avanzado.md`

## Criterios de aceptación
- [ ] `bash -n`/`shellcheck` limpios en ambos scripts · [ ] El timer se ejecuta cada 5 min sin intervención · [ ] Sabes explicar `set -euo pipefail`, `trap`, `getopts` y por qué se evita parsear `ls`
- [ ] Repositorio en Git con historial limpio

## Errores encontrados y solución
| Error | Causa | Solución |
|---|---|---|
| | | |

## Conocimientos adquiridos (resumen propio)
-

## Ampliaciones futuras (fuera del alcance actual de esta etapa)
- Pruebas que creen usuarios de prueba de forma controlada, para practicar automatización de altas/bajas.
- Extender `lab-logscan.sh` para analizar logs de un servidor web (Apache httpd/NGINX) cuando se despliegue en la Etapa 9, comparando el mismo enfoque de scripting sobre un servicio distinto a SSH.
