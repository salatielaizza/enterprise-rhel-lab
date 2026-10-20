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
| 5 | Casos `01-service-down`, `02-bad-fstab`, `03-permission-denied`, `04-selinux-denial` | resueltos con evidencias | |
| 6 | `scripts/lab.sh snapshot create all 2` | `…-stage2-complete` | |
| 7 | Caso `10-vg-data-sin-espacio-nuevo-disco` en `rhel9-app01` (snapshot `rhel9-pre-caso10`) | `vg_data` con 2 PV, `/backup` ampliado en caliente, `test_storage.sh` 0 FAIL; estado inicial restaurado y qcow2 de práctica borrado | |
| 8 | Caso `11-var-lleno-ampliar-vg-system`, partes A y B (snapshot `rhel9-pre-caso11`) | `/var` ampliado en caliente; en la B, disco a 25 GB, `growpart` + `pvresize`; estado inicial restaurado | |

## Documentación
- [ ] users · [ ] permissions · [ ] sudo · [ ] processes · [ ] systemd · [ ] packages · [ ] lvm · [ ] filesystems · [ ] logging

## Criterios de aceptación
- [ ] UID/GID idénticos en todos los hosts (`getent passwd devuser` igual) · [ ] `sudo -l -U devuser/backupuser` limitado · [ ] sudo de arranque eliminado
- [ ] `vg_data` con 3 LV montados por UUID · [ ] `lab-app` activo, con `Restart=on-failure` probado · [ ] Repo local desde ISO probado
- [ ] Recuperación de fstab roto en <5 min · [ ] Ampliación con disco nuevo (`pvcreate` + `vgextend` + `lvextend -r`) y de `/var` en `vg_system` sin desmontar · [ ] Diferencias 7/8/9/10 anotadas (journal persistente, cgroups, yum/dnf)

## Errores encontrados y solución
| Error | Causa | Solución |
|---|---|---|
| | | |

## Conocimientos adquiridos (resumen propio)
-
