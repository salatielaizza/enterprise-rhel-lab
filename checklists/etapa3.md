# ETAPA 3 — CHECKLIST: Networking

> Una etapa **no está completa** hasta marcar TODO: documentación + tests + troubleshooting + diferencias entre versiones + snapshot.
> Rellena las columnas "Resultado obtenido" con lo que veas **de verdad** (pega salidas en `results/etapa3/`).

## Objetivo
Red estática coherente con NetworkManager y metodología de diagnóstico por capas dominada.

## Comandos (orden)
| # | Comando | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 1 | `scripts/lab.sh stage3 all` | perfil `lab0`, IP/gw/hostname correctos, DNS 10.10.10.1 | |
| 2 | `scripts/lab.sh test test_network.sh all` | 0 FAIL | |
| 3 | `nmcli -f NAME,FILENAME con show` en las 4 versiones | ifcfg (7, 8) vs keyfile (9, 10) documentado | |
| 4 | Casos 02, 03, 09, 10, 11, 12 | cada uno diagnosticado con hipótesis y evidencia | |
| 5 | `scripts/lab.sh snapshot create all 3` | `…-stage3-complete` | |

## Documentación
- [ ] `networking/networkmanager.md` · [ ] `networking/troubleshooting.md` · [ ] `architecture/network.md` revisado

## Criterios de aceptación
- [ ] Ping entre todas las VMs y al gateway · [ ] Salida a Internet · [ ] Sabes distinguir *refused* / *No route to host* / *timeout*
- [ ] Sabes por qué `getent` y `dig` pueden discrepar · [ ] Los 6 casos resueltos sin ayuda

## Errores encontrados y solución
| Error | Causa | Solución |
|---|---|---|
| | | |

## Conocimientos adquiridos (resumen propio)
-
