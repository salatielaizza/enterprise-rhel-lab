# ETAPA 4 — CHECKLIST: Servicios enterprise (DNS, hora, SSH)

> Una etapa **no está completa** hasta marcar TODO: documentación + tests + troubleshooting + diferencias entre versiones + snapshot.
> Rellena las columnas "Resultado obtenido" con lo que veas **de verdad** (pega salidas en `results/etapa4/`).

## Objetivo
DNS interno (BIND), hora jerárquica (chrony) y SSH endurecido con SFTP funcionando y verificados.

## Comandos (orden)
| # | Comando | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 1 | `scripts/lab.sh stage4-dns` | named activo; A/PTR locales correctos; chrony servidor | |
| 2 | `scripts/lab.sh stage4-clients all` | DNS 10.10.10.20, chrony cliente, sshd endurecido, nueva sesión SSH OK | |
| 3 | `scripts/lab.sh test all all` | 0 FAIL (incluye `test_dns`, `test_time`, `test_ssh`) | |
| 4 | `scripts/lab.sh host-dns` (opcional) | el host resuelve `*.lab.local` con `resolvectl query` | |
| 5 | `sftp sftpdemo@10.10.10.13` | jaula: solo `/` y `upload/` | |
| 6 | Casos 01, 07, 08, 13, 14 | resueltos con evidencias | |
| 7 | `scripts/lab.sh facts all && scripts/lab.sh matrix` | `comparison/matrix.generated.md` con datos reales | |
| 8 | `scripts/lab.sh snapshot create all 4` | `…-stage4-complete` | |

## Documentación
- [ ] `networking/dns.md` · [ ] `time/chrony.md` · [ ] `networking/ssh.md` · [ ] `comparison/matrix.md` reconciliada con la matriz generada · [ ] `migration/…md` revisado

## Criterios de aceptación
- [ ] Todos los hosts resuelven A y PTR de todos · [ ] Todos sincronizados con dns01 (`^*`) · [ ] root y contraseña denegados por SSH · [ ] Nunca perdiste el acceso al cambiar sshd
- [ ] Valores ◦ de `differences.md` promovidos a ✔ o corregidos con datos reales · [ ] Repositorio en Git con historial limpio

## Errores encontrados y solución
| Error | Causa | Solución |
|---|---|---|
| | | |

## Conocimientos adquiridos (resumen propio)
-
