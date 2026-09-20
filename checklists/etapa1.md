# ETAPA 1 — CHECKLIST: Instalación

> Una etapa **no está completa** hasta marcar TODO: documentación + tests + troubleshooting + diferencias entre versiones + snapshot.
> Rellena las columnas "Resultado obtenido" con lo que veas **de verdad** (pega salidas en `results/etapa1/`).

## Objetivo
Cuatro RHEL (7/8/9/10) instalados con kickstart, accesibles por SSH con clave, registrados y con snapshot.

## Comandos (orden)
| # | Comando | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 1 | `scripts/lab.sh host-setup` | KVM/libvirt, pools `lab-isos`/`lab-images`, clave `lab_ed25519` | |
| 2 | `scripts/lab.sh network` | red `lab-net` activa, gateway 10.10.10.1 | |
| 3 | `scripts/lab.sh iso --check` y `scripts/lab.sh iso` | 4 ISOs con SHA-256 correcto | |
| 4 | `scripts/lab.sh vm-create <host> --dry-run` | kickstart y comando `virt-install` sin errores | |
| 5 | `scripts/lab.sh vm-create rhel7-app01` (y 8, 9, 10) | instalación y SSH OK | |
| 6 | `scripts/lab.sh register <host> <usuario>` | suscripción registrada | |
| 7 | `scripts/lab.sh test test_install.sh all` | 0 FAIL | |
| 8 | `scripts/lab.sh snapshot create <host> 1` | `rhelN-stage1-complete` | |

## Documentación y ejercicios
- [ ] `rhel7/8/9/10/installation.md` leídos y ejecutados · [ ] `configuration.md` · [ ] `differences.md` con datos verificados (`lab.sh facts`)
- [ ] Caso de instalación: explicar cada línea del kickstart · [ ] Comparar `/root/anaconda-ks.cfg` de una VM manual

## Criterios de aceptación
- [ ] 4 VMs con SSH por clave (`ssh rhelN-app01`) · [ ] SELinux Enforcing y firewalld activo · [ ] LVM+XFS según diseño · [ ] `test_install.sh` 0 FAIL en las 4
- [ ] 4 snapshots `rhelN-stage1-complete` (`lab.sh status`) · [ ] Sin contraseñas ni tokens en el repositorio (`git grep -i password`)

## Errores encontrados y solución
| Error | Causa | Solución |
|---|---|---|
| | | |

## Conocimientos adquiridos (resumen propio)
-
