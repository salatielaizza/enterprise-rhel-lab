# ETAPA 2 — CHECKLIST: Administración Linux

> Una etapa **no está completa** hasta marcar TODO: documentación + tests + troubleshooting + diferencias entre versiones + snapshot.
> Rellena las columnas "Resultado obtenido" con lo que veas **de verdad** (pega salidas en `results/etapa2/`).

## Objetivo
Usuarios/grupos con IDs fijos, permisos con ACL, sudo por perfiles, servicio systemd, LVM/XFS, paquetes y logs dominados y automatizados.

## Comandos (orden)
| # | Comando | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 1 | `scripts/lab.sh vm-create dns01` y `ansible01` | VMs creadas (se usarán en Etapas 3-4) | |
| 2 | Práctica **manual** de `administration/*.md` en una VM con snapshot | dominio de cada comando | |
| 3 | `scripts/lab.sh stage2 all` | 5 scripts sin error en cada host | |
| 4 | `scripts/lab.sh test all all` | 0 FAIL (LVM se omite en dns01/ansible01) | |
| 5 | Casos `04-bad-fstab`, `05-permission-denied`, `06-selinux-denial`, `03-service-down` | resueltos con evidencias | |
| 6 | `scripts/lab.sh snapshot create all 2` | `…-stage2-complete` | |

## Documentación
- [ ] users · [ ] permissions · [ ] sudo · [ ] processes · [ ] systemd · [ ] packages · [ ] lvm · [ ] filesystems · [ ] logging

## Criterios de aceptación
- [ ] UID/GID idénticos en todos los hosts (`getent passwd devuser` igual) · [ ] `sudo -l -U devuser/backupuser` limitado · [ ] sudo de arranque eliminado
- [ ] `vg_data` con 3 LV montados por UUID · [ ] `lab-app` activo, con `Restart=on-failure` probado · [ ] Repo local desde ISO probado
- [ ] Recuperación de fstab roto en <5 min · [ ] Diferencias 7/8/9/10 anotadas (journal persistente, cgroups, yum/dnf)

## Errores encontrados y solución
| Error | Causa | Solución |
|---|---|---|
| | | |

## Conocimientos adquiridos (resumen propio)
-
