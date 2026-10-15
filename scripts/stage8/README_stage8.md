# 🖥️ Etapa 8 — VMware vSphere (`scripts/stage8/`)

## Qué hace esta etapa

Monta **VMware vSphere dentro del laboratorio** con ESXi 8 anidado en KVM (VMs de KVM que ejecutan sus
propias VMs), lo integra con `dns01` (DNS, NTP y un datastore NFS) y con `ansible01` (Ansible y PowerCLI),
y lo compara con KVM/libvirt. Se hace en dos fases, por licencias y por RAM:

| Fase | Qué | Licencia | Encendido |
|---|---|---|---|
| A | `esxi01` independiente y permanente + `rhel9-vm01` dentro | ESXi gratuito 8.0U3e | Convive con el resto del lab |
| B | `esxi02` + `esxi03` + vCenter (`vcsa01`): clúster, datastore NFS, vMotion | Evaluación de 60 días | `app01` y `esxi01` **apagadas** (~27-29 GiB) |

HA, DRS y switches distribuidos se practican en los **VMware Hands-on Labs**. Un ESXi gratuito **no puede
unirse a vCenter**, por eso los hosts del clúster se instalan con el instalador estándar.

## Diferencias con las demás carpetas `stageN/`

- La mayoría de scripts corren **en el host** (los ESXi no son RHEL: no se les hace `push` ni `run_remote`).
- Los ESXi tienen su propio inventario, [`scripts/vmware.conf`](../vmware.conf), **fuera de `hosts.conf`**:
  así `lab.sh <cualquier comando> all` nunca los trata como VMs RHEL.
- Los scripts de host cargan `vmware-lib.sh` (que a su vez carga `../lib.sh`).
- `LAB_STAGE=8` **no** se marca hasta cerrar la Etapa 7 (`99-mark-stage.sh` lo comprueba).

## Scripts del host (Linux Mint)

| Script | `lab.sh` | Qué hace | Qué modifica |
|---|---|---|---|
| `vmware-lib.sh` | — | Funciones comunes: inventario (`vmw_row`, `vmw_targets`), `esxi_ssh`, `wait_https`, rutas de ISOs, clave RSA de ESXi | — |
| `00-preflight.sh [A\|B]` | `esxi-preflight` | Auditoría de **solo lectura**: nested, `ignore_msrs`, herramientas, `vmxnet3`, red, RAM, disco, ISOs, DNS A/PTR | Nada |
| `01-esxi-iso.sh <host\|all> [--dry-run]` | `esxi-iso` | Extrae el ISO con `xorriso`, añade `KS.CFG` (de `files/ks-esxi.cfg.tpl`), apunta `BOOT.CFG` (BIOS y UEFI) al kickstart y reconstruye el ISO | Crea `ISO_DIR/<host>-ks.iso` (con el hash de root: fuera del repo) y `~/.ssh/lab_esxi_rsa` si no existe |
| `02-create-esxi.sh <host> [--manual] [--force] [--dry-run]` | `esxi-create` | `virt-install` con q35, discos **SATA**, NIC **vmxnet3**, `host-passthrough`, BIOS; `--manual` usa el ISO original (instalación a mano) | Crea la VM y sus qcow2 en `lab-images`; `--force` pide escribir el nombre antes de borrar |
| `03-esxi-power.sh <up\|down> <host\|all>` | `esxi-up` / `esxi-down` | Apagado **ordenado**: VMs internas → modo mantenimiento → `poweroff`; nunca `virsh destroy` | Estado de los ESXi |
| `04-esxi-status.sh [host\|all]` | `esxi-status` | Estado, versión, **licencia y caducidad**, NTP, datastores, VMs, snapshots, RAM/disco del host | Nada |
| `05-esxi-snapshot.sh <acción> <host> [etapa]` | `esxi-snapshot` | Snapshots `<host>-stage8-complete`; exige el ESXi **apagado** | Snapshots internos |
| `06-dns01-nfs-disk.sh [--dry-run]` | `stage8-nfs` (1º) | Añade a `dns01` un disco de 60 GB por **virtio-SCSI** (serie `labnfs`) | Volumen `dns01-nfs.qcow2` y definición de `dns01` |
| `07-vcsa-deploy.sh [--verify-only\|--precheck-only]` | `vcsa-deploy` | Despliega vCenter "tiny" en `esxi02` con el instalador CLI; monta el ISO con `udisksctl` (sin sudo) | Contraseñas en un JSON temporal 0600 que se borra al salir; logs en `~/.local/state/rhel-lab/` |

## Scripts de las VMs (vía `push` + `run_remote`)

| Script | Corre en | `lab.sh` | Qué hace |
|---|---|---|---|
| `10-nfs-datastore.sh` | `dns01` | `stage8-nfs` (2º) | `vg_nfs/lv_vmware` (XFS) en `/srv/nfs/vmware`, fstab por UUID, export `rw,no_root_squash` a `.60-.62`, firewalld y SELinux |
| `20-vmware-control-setup.sh [--no-powercli]` | `ansible01` | `stage8-setup` | Venv propio `~/.venvs/vmware` (Python ≥ 3.11 + **ansible-core ≥ 2.19** + pyVmomi), colecciones, proyecto `~/vmware-lab`, vault con `CAMBIAR`, PowerShell + PowerCLI |
| `21-run-playbook.sh <playbook> [args]` | `ansible01` | `stage8 <playbook>` | Lanza el playbook como `adminlab` con el venv |
| `99-mark-stage.sh` | `dns01`, `ansible01` | `stage8-close` | `set_stage 8`, solo si `LAB_STAGE ≥ 7` |

`lab.sh stage8-guest-key` copia la clave de `ansible01` a `rhel9-vm01` (VM dentro de ESXi).

## `files/`

| Ruta | Contenido |
|---|---|
| `ks-esxi.cfg.tpl` | Kickstart de ESXi: red, hash de root, `%firstboot` (NTP y DNS → `dns01`, SSH, clave RSA, seguridad del vSwitch para anidado, `vmk1` de vMotion en la pila `vmotion`, datastore VMFS6 en el disco 2) |
| `vcsa-deploy.json.tpl` | Plantilla del instalador de VCSA (`__version` leído del propio ISO) |
| `vmware-lab/` → `~adminlab/vmware-lab` | Proyecto Ansible **aparte** de `ansible-lab` (para que `stage7-setup` no lo pise): `ansible.cfg` (incluye los roles de la Etapa 7), `requirements.yml`, `inventory/`, `playbooks/` y `powercli/` |

| Playbook (`lab.sh stage8 …`) | Qué hace |
|---|---|
| `info` (`00-info.yml`) | Inventario de solo lectura: `--tags free` (esxi01) o `--tags vcenter` |
| `cluster` (`10-cluster.yml`) | Datacenter, clúster, hosts en evaluación y datastore NFS |
| `esxi-config` (`20-esxi-config.yml`) | NTP, servicio `ntpd` y DNS de los hosts, desde vCenter |
| `guest` (`30-guest.yml`) | Enciende `rhel9-vm01` y espera a SSH |
| `vmotion` (`40-vmotion.yml`) | vMotion al otro host (y al datastore NFS si hace falta) |
| `snapshot` (`50-snapshot.yml`) | Snapshots de VMware: `-e snap_state=list\|present\|revert\|absent` |
| `guest-baseline` (`60-guest-baseline.yml`) | Roles `common` + `lab_users` de la Etapa 7 en `rhel9-vm01` |
| `verify` (`90-verify.yml`) | Verificación de solo lectura, una etiqueta por comprobación (la usa `test_vmware.sh`) |

PowerCLI (`pwsh` en `ansible01`): `Connect-Lab.ps1`, `Get-LabReport.ps1` (CSV), `Move-LabVM.ps1` (vMotion
medido) e `Invoke-LabSnapshot.ps1`.

## Orden de ejecución (resumen)

```bash
# Fase A
scripts/lab.sh esxi-preflight A
scripts/lab.sh stage4-dns
scripts/lab.sh esxi-create esxi01 --manual
scripts/lab.sh stage8-setup                   # y después 'ansible-vault edit' en ansible01
scripts/lab.sh stage8-guest-key && scripts/lab.sh stage8 guest-baseline
scripts/lab.sh esxi-iso esxi01 && scripts/lab.sh esxi-create esxi01 --force
# Fase B (app01 y esxi01 apagadas)
scripts/lab.sh esxi-preflight B
scripts/lab.sh esxi-iso all && scripts/lab.sh esxi-create esxi02 && scripts/lab.sh esxi-create esxi03
scripts/lab.sh stage8-nfs
scripts/lab.sh vcsa-deploy --precheck-only && scripts/lab.sh vcsa-deploy
scripts/lab.sh stage8 cluster && scripts/lab.sh stage8 esxi-config
scripts/lab.sh stage8 guest && scripts/lab.sh stage8 vmotion
```

El detalle, con resultado esperado y obtenido, está en el checklist.

## Lección aprendida en esta etapa

Con `set -o pipefail`, `comando | grep -q` puede dar un **falso fallo**: `grep -q` termina en el primer
acierto, el comando recibe SIGPIPE (141) y la tubería entera falla. En esta carpeta la salida se guarda
primero en una variable y se busca sobre ella (caso [`etapa8/01`](../../troubleshooting/etapa8/01-preflight-pipefail-sigpipe.md)).

## Cómo se verifica

```bash
scripts/lab.sh esxi-preflight A                    # host (o B)
scripts/lab.sh esxi-status                         # ESXi
scripts/lab.sh test test_vmware.sh ansible01       # herramientas, DNS y vSphere según la fase activa
scripts/lab.sh test test_nfs_datastore.sh dns01    # export NFS
scripts/lab.sh stage8 verify
```

## Documentación relacionada

- Checklist: [`checklists/etapa8.md`](../../checklists/etapa8.md)
- Comandos explicados y casos reales: [`troubleshooting/etapa8/README_troubleshooting_etapa8.md`](../../troubleshooting/etapa8/README_troubleshooting_etapa8.md)
- Tema: `virtualization/` (pendiente)
