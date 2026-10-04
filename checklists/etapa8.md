# ETAPA 8 — CHECKLIST: VMware vSphere (ESXi anidado en KVM, vCenter, vMotion, PowerCLI y Ansible)

> Una etapa **no está completa** hasta marcar TODO: documentación + tests + troubleshooting + diferencias + snapshot.
> Rellena "Resultado obtenido" con lo que veas **de verdad** (pega salidas en `results/etapa8/`).
> Plan completo y decisiones: `claude/etapas/etapa8-vmware.md` (documento del proyecto).

## Objetivo
Montar y operar VMware vSphere dentro del lab (ESXi 8 anidado en KVM), integrado con `dns01` (DNS, NTP, NFS)
y `ansible01` (Ansible y PowerCLI), y compararlo con KVM/libvirt. Con licencias realistas:

| Parte | Dónde | Licencia |
|---|---|---|
| `esxi01`: ESXi independiente y permanente | Lab local (fase A) | ESXi gratuito 8.0U3e |
| `esxi02` + `esxi03` + `vcsa01`: clúster, datastore NFS, vMotion | Lab local (fase B) | Evaluación de 60 días |
| HA, DRS, switches distribuidos (vDS) | VMware Hands-on Labs | Gratuito (cuenta Broadcom) |
| Licencias de homelab | — | Objetivo: certificación VCP |

**Un ESXi gratuito NO se puede unir a vCenter** ("License not available to perform the operation"): por eso los
hosts del clúster se instalan con el instalador estándar, que arranca en evaluación.

## Fechas de la evaluación (fase B)
| Elemento | Instalado el | Caduca el (≈ +60 días) | Snapshot hecho el |
|---|---|---|---|
| `esxi02` | | | |
| `esxi03` | | | |
| `vcsa01` | | | — (vive dentro de `esxi02`) |

## Fase 0 — Prerrequisitos (solo lectura)
| # | Comando / acción | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 0.1 | Portal de Broadcom: ¿qué descargas aparecen? | ISO gratuito 8.0U3e seguro; anotar si aparecen el instalador estándar de ESXi 8 y el ISO de VCSA | |
| 0.2 | Añadir `ESXI_FREE_ISO` (y, si los hay, `ESXI_EVAL_ISO` y `VCSA_ISO`) a `~/.config/rhel-lab/isos.conf` | Ver `scripts/isos.conf.example` | |
| 0.3 | `scripts/lab.sh esxi-preflight A` | 0 FAIL (los WARN se leen y se deciden) | |
| 0.4 | `virsh snapshot-create-as dns01 dns01-pre-stage8` y lo mismo para `ansible01` (con las VMs apagadas) | Punto de vuelta antes de tocar nada (la Etapa 7 aún no tiene `*-stage7-complete`) | |

## Fase 1 — DNS
| # | Comando | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 1.1 | `scripts/lab.sh stage4-dns` | Zonas regeneradas con `esxi01-03`, `vcsa01`, `rhel9-vm01` (plantillas de `scripts/stage4/dns/`) | |
| 1.2 | `dig @10.10.10.20 vcsa01.lab.local +short` y `dig @10.10.10.20 -x 10.10.10.63 +short` | `10.10.10.63` y `vcsa01.lab.local.` | |
| 1.3 | `scripts/lab.sh test test_dns.sh all` | 0 FAIL (nada de lo anterior se ha roto) | |

## Fase 2 — `esxi01` a mano (fase A)
| # | Comando / acción | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 2.1 | `scripts/lab.sh esxi-create esxi01 --manual` + consola con `virt-viewer -c qemu:///system esxi01` | Instalador interactivo de ESXi; IP .60/24, gw .1, DNS .20, hostname `esxi01.lab.local` | |
| 2.2 | Host Client `https://10.10.10.60/ui/`: NTP → `10.10.10.20`, datastore en el disco 2, SSH | Configuración hecha a mano, entendida pantalla a pantalla | |
| 2.3 | vSwitch0 → Security: Promiscuous / MAC changes / Forged transmits = Accept | Requisito de ESXi anidado (sin esto, las VMs de dentro no tienen red) | |
| 2.4 | `scripts/lab.sh esxi-status esxi01` | Versión 8.0U3e, licencia gratuita, NTP OK | |

## Fase 3 — `rhel9-vm01` dentro de ESXi
| # | Comando / acción | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 3.1 | Subir el ISO de RHEL 9 al datastore y crear la VM (2 GB, 1 vCPU, 20 GB thin, VMXNET3) | VM creada desde Host Client | |
| 3.2 | Instalar con el kickstart del lab (`scripts/kickstart/rhel9.ks.tpl` renderizado con IP .64 y hostname `rhel9-vm01.lab.local`) + `open-vm-tools` | `ssh adminlab@10.10.10.64` funciona con la clave del lab | |
| 3.3 | `scripts/lab.sh stage8-guest-key` | Clave de `ansible01` en `rhel9-vm01` | |
| 3.4 | `scripts/lab.sh stage8-setup` y, en `ansible01`, `ansible-vault edit` del vault de `~/vmware-lab` | venv, colecciones, PowerCLI; contraseñas reales en el vault | |
| 3.5 | `scripts/lab.sh stage8 guest-baseline` (dos veces) | La 2ª vez `changed=0`: misma base que el resto del lab, con los roles de la Etapa 7 | |
| 3.6 | `scripts/lab.sh stage8 info --tags free` | Versión, CPU, memoria, datastores y VMs de `esxi01` (solo lectura) | |

## Fase 4 — KVM frente a ESXi (documento de comparación)
| Concepto | KVM/libvirt (este lab) | VMware ESXi / vSphere |
|---|---|---|
| Hipervisor | KVM (módulo del kernel) + QEMU | ESXi (tipo 1, VMkernel) |
| Gestión de un host | `virsh`, virt-manager | `esxcli`, `vim-cmd`, Host Client |
| Gestión centralizada | (Etapa 9: Satellite; Etapa 18: OpenShift Virtualization) | vCenter |
| Disco de VM | qcow2 | VMDK |
| Almacenamiento | pool de libvirt | datastore (VMFS, NFS, vSAN) |
| Red | bridge / red NAT de libvirt | vSwitch estándar / distribuido |
| Instalación desatendida | kickstart + `virt-install` | kickstart de ESXi + ISO personalizado |
| Snapshots | `virsh snapshot-*` | snapshots de VM (vCenter / Host Client) |
| Migración en caliente | `virsh migrate --live` | vMotion |
| Automatización | Ansible (`community.libvirt`), bash | Ansible (`community.vmware`), PowerCLI |

## Fase 5 — Automatizar `esxi01`
| # | Comando | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 5.1 | `scripts/lab.sh esxi-iso esxi01 --dry-run` | `KS.CFG` renderizado en `/tmp/esxi01.dryrun.KS.CFG`; revisarlo línea a línea | |
| 5.2 | `scripts/lab.sh esxi-iso esxi01` | `esxi01-ks.iso` en `ISO_DIR` | |
| 5.3 | `scripts/lab.sh esxi-down esxi01` → `esxi-snapshot create esxi01 8` → `esxi-create esxi01 --force` | Reinstalación SIN tocar nada; `/var/log/lab-firstboot.log` termina en "lab-firstboot: terminado" | |
| 5.4 | `scripts/lab.sh test test_vmware.sh ansible01` | 0 FAIL (fase A: herramientas, DNS y `esxi01`) | |

## Fase 6 — Clúster en evaluación (fase B)
| # | Comando | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 6.1 | `scripts/lab.sh down rhel7-app01` … `rhel10-app01` y `scripts/lab.sh esxi-down esxi01` | Solo `dns01` y `ansible01` encendidas | |
| 6.2 | `scripts/lab.sh esxi-preflight B` | 0 FAIL | |
| 6.3 | `scripts/lab.sh esxi-iso esxi02` + `esxi-iso esxi03` + `esxi-create esxi02` + `esxi-create esxi03` | Dos ESXi en evaluación; `esxi-status` muestra la caducidad | |
| 6.4 | `scripts/lab.sh stage8-nfs` + `scripts/lab.sh test test_nfs_datastore.sh dns01` | Export NFS en `dns01`, 0 FAIL | |
| 6.5 | `scripts/lab.sh vcsa-deploy --verify-only` → `--precheck-only` → `vcsa-deploy` | vCenter en `https://vcsa01.lab.local/ui/` (anota la fecha) | |
| 6.6 | Reducir la RAM de VCSA a 10-12 GB (apagado ordenado, editar la VM, encender) y bajar `esxi02` a 14 GB en `vmware.conf` | Sin swap intenso en el host (`free -h`) | |
| 6.7 | `scripts/lab.sh stage8 cluster` (dos veces) + `stage8 esxi-config` | 2ª vez `changed=0`; clúster con 2 hosts y datastore `nfs-vmware` | |

## Fase 7 — vMotion
| # | Comando | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 7.1 | `rhel9-vm01` añadida al inventario de vCenter (mover a `esxi02`/`esxi03` o reinstalar en el clúster) y `scripts/lab.sh stage8 guest` | VM encendida en el clúster | |
| 7.2 | En otra terminal: `ping 10.10.10.64`; después `scripts/lab.sh stage8 vmotion` (varias veces) | La VM cambia de host; se pierden 0-2 paquetes | |
| 7.3 | `scripts/lab.sh stage8 snapshot -e snap_state=present -e snap_name=antes-de-X` / `revert` / `absent` | Snapshots de VMware gestionados desde Ansible | |

## Fase 8 — PowerCLI (en `ansible01`, `pwsh`)
| # | Comando | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 8.1 | `pwsh ~/vmware-lab/powercli/Get-LabReport.ps1` | Tablas + CSV en `~/vmware-lab/reports/` | |
| 8.2 | `pwsh ~/vmware-lab/powercli/Get-LabReport.ps1 -Server esxi01.lab.local -User root` | Informe del ESXi gratuito (solo lectura) | |
| 8.3 | `pwsh ~/vmware-lab/powercli/Move-LabVM.ps1` | vMotion con PowerCLI y tiempo medido; comparar con 7.2 | |
| 8.4 | `pwsh ~/vmware-lab/powercli/Invoke-LabSnapshot.ps1 -Action New -Name ps-snap` | Snapshot desde PowerCLI | |

## Fase 9 — VMware Hands-on Labs (fuera del lab local)
| # | Laboratorio | Qué practicar | Notas propias |
|---|---|---|---|
| 9.1 | vSphere HA | Fallo de host simulado, reinicio de VMs, control de admisión | |
| 9.2 | vSphere DRS | Niveles de automatización, recomendaciones, reglas de afinidad | |
| 9.3 | vSphere Distributed Switch | Crear vDS, port groups, migrar desde vSwitch estándar | |

> Lo practicado en Hands-on Labs se documenta como **practicado en HOL**, nunca como hecho en el lab local.

## Cierre
| # | Comando | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 10.1 | `scripts/lab.sh test test_vmware.sh ansible01` | 0 FAIL (fase B) | |
| 10.2 | `scripts/lab.sh test all all` | 0 FAIL en las 6 VMs RHEL (nada de las etapas 1-7 roto) | |
| 10.3 | `scripts/lab.sh stage8-close` (solo con la Etapa 7 cerrada) | `LAB_STAGE=8` en `dns01` y `ansible01` | |
| 10.4 | `scripts/lab.sh esxi-down all` + `esxi-snapshot create <host> 8` (×3) | `esxiNN-stage8-complete` | |

## Documentación
- [ ] `virtualization/esxi.md` · `virtualization/vcenter.md` · `virtualization/powercli.md`
- [ ] `virtualization/kvm-vs-esxi.md` (tabla de la fase 4 ampliada) · `virtualization/hands-on-labs.md` · `virtualization/vcp.md`
- [ ] `troubleshooting/etapa8/NN-*.md` (casos reales) y `README_troubleshooting_etapa8.md` al cerrar

## Criterios de aceptación
- [ ] `esxi01` reinstalable sin intervención con `esxi-iso` + `esxi-create`
- [ ] vMotion en caliente demostrado con `ping` continuo, desde Ansible y desde PowerCLI
- [ ] Playbooks `cluster`, `esxi-config` y `guest-baseline` idempotentes (2º pase `changed=0`)
- [ ] Ninguna contraseña en el repositorio (vault cifrado solo en `ansible01`; ISO con hash fuera del repo)
- [ ] Sabes explicar: tipo 1 frente a KVM, ESXi gratuito frente a evaluación, vCenter, datastore, vSwitch y políticas
      de seguridad en anidado, vMotion (cómputo y almacenamiento), HA frente a DRS, por qué vCenter exige DNS inverso

## Errores encontrados y solución
| Síntoma | Causa | Solución | Caso de troubleshooting |
|---|---|---|---|
| | | | |

## Ampliaciones futuras
- Migrar los módulos obsoletos de `community.vmware` a `vmware.vmware` (lista en `requirements.yml`).
- Plantilla de `rhel9-vm01` y clonado con `community.vmware.vmware_guest` (personalización de invitado).
- Etapa 12: migrar `rhel9-vm01` de VMware a KVM con `virt-v2v`. Etapa 13: NFS a fondo. Etapa 16: monitorizar ESXi.
