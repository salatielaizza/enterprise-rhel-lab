# 💿 Etapa 1 — Instalación (scripts del host)

> La Etapa 1 no tiene carpeta `scripts/stage1/`: sus scripts corren **en el host** (Linux Mint), no dentro
> de las VMs, y viven en la raíz de `scripts/`. Este README explica cuáles son de esta etapa y cómo encajan.

## Qué hace esta etapa

Prepara el host como hipervisor KVM/libvirt, crea la red `lab-net`, descarga y verifica las ISOs de RHEL y
crea las VMs (`rhel7/8/9/10-app01`, `dns01`, `ansible01`) con instalación **desatendida por kickstart**.
Al terminar, cada VM tiene SSH por clave, SELinux en Enforcing, firewalld activo, LVM + XFS y la marca
`LAB_STAGE=1` en `/etc/lab-release`.

## Cómo se lanza

Siempre a través de `scripts/lab.sh` (punto de entrada único), como **usuario normal** (los scripts usan
`sudo` solo donde hace falta):

```bash
scripts/lab.sh host-setup                         # una vez; después cierra sesión y vuelve a entrar
scripts/lab.sh network
scripts/lab.sh iso --check && scripts/lab.sh iso
scripts/lab.sh vm-create rhel9-app01 --dry-run    # revisa el kickstart y el comando sin instalar
scripts/lab.sh vm-create rhel9-app01              # (y el resto de hosts, o 'all')
scripts/lab.sh register rhel9-app01 <usuario-RH>
scripts/lab.sh snapshot create rhel9-app01 1
```

## Scripts de la etapa (en orden)

| # | Fichero | Lo lanza | Qué hace | Qué modifica |
|---|---|---|---|---|
| 0 | `00-host-audit.sh` | a mano | Auditoría de **solo lectura** del host (CPU, RAM, disco, KVM, libvirt con `virsh -r`) | Solo escribe el informe `evidence/host/host-audit-<fecha>.txt` |
| 1 | `00-host-setup.sh` | `lab.sh host-setup` | Comprueba VT-x y x86-64-v3, instala KVM/libvirt, añade tu usuario a `libvirt`/`kvm`, crea los pools `lab-isos`/`lab-images`, la clave `~/.ssh/lab_ed25519` y `~/.ssh/lab_config` | Paquetes del host, grupos de tu usuario, `/var/lib/libvirt/lab/`, `~/.ssh/` (añade `Include` a `~/.ssh/config`) |
| 2 | `01-create-network.sh` | `lab.sh network` | Define la red NAT `lab-net` (10.10.10.0/24, **sin DHCP**, bridge `virbr-lab`) y comprueba el gateway real | Red de libvirt (no toca la red del host); aborta si ya hay una ruta 10.10.10.0/24 |
| 3 | `download-isos.sh` | `lab.sh iso` | Descarga las ISOs **por checksum** con la API de Red Hat y verifica SHA-256 (reanudable) | Solo escribe en `ISO_DIR`; nunca sobrescribe una ISO distinta |
| 4 | `02-create-vm.sh` | `lab.sh vm-create` | Lee la fila del host en `hosts.conf`, renderiza `kickstart/rhelN.ks.tpl` con `envsubst` y lanza `virt-install`; expulsa la ISO y espera al SSH | Crea la VM y sus discos qcow2 en `lab-images` (`--force` la borra antes, con sus discos) |
| 5 | `03-snapshot.sh` | `lab.sh snapshot` | Snapshots con nombre estable `<host>-stageN-complete`; apaga por ACPI antes de crear | Snapshots internos del qcow2 |
| — | `lab.sh register` | `lab.sh register` | `subscription-manager register` en la VM (la contraseña se teclea en la VM) | Suscripción de la VM |

### Ficheros de apoyo (no se ejecutan solos)

| Fichero | Para qué |
|---|---|
| `lab.sh` | Punto de entrada único de todas las etapas (`scripts/lab.sh help`) |
| `lib.sh` | Constantes y funciones de los scripts **del host** (`LAB_NET`, `SSH_OPTS`, `host_row`, `wait_ssh`...) |
| `common.sh` | Funciones de los scripts que corren **dentro de las VMs** (`require_root`, `say`, `fatal`, `set_stage`) |
| `hosts.conf` | **Única fuente de verdad** del inventario: nombre, versión, IP, vCPU, RAM, disco, disco de datos |
| `kickstart/rhelN.ks.tpl` | Instalación desatendida por versión (RHEL 10 añade la partición `biosboot`: caso `etapa1/01`) |
| `isos.conf.example` | Plantilla de `~/.config/rhel-lab/isos.conf` (directorio y checksums de las ISOs) |
| `collect-facts.sh` / `build-matrix.sh` | `lab.sh facts` / `lab.sh matrix`: datos reales de cada VM → `comparison/matrix.generated.md` |

## Requisitos previos

- CPU con VT-x/AMD-V y **x86-64-v3** (obligatoria para RHEL 10).
- Red Hat Developer Subscription y un *offline token* en `~/.config/rhel-lab/offline_token` (modo 600).
- Tras `host-setup`, **cerrar sesión y volver a entrar** para que los grupos `libvirt`/`kvm` tengan efecto.

## Seguridad

- Las contraseñas de root y `adminlab` se piden una vez (o `LAB_PASSWORD`) y solo su **hash** va al kickstart
  temporal; nunca al repositorio.
- El token de Red Hat se pasa a `curl` por stdin: no aparece en `ps` ni en el historial.
- El `sudo` sin contraseña que deja el kickstart es **de arranque**: lo sustituye la Etapa 2 (`stage2/04-sudo.sh`).

## Cómo se verifica

```bash
scripts/lab.sh test test_install.sh <host|all>    # tests/test_install.sh
scripts/lab.sh status                             # estado, SSH y snapshots de cada VM
```

## Documentación relacionada

- Checklist: [`checklists/etapa1.md`](../checklists/etapa1.md)
- Instalación por versión: [`rhel7`](../rhel7/installation.md) · [`rhel8`](../rhel8/installation.md) ·
  [`rhel9`](../rhel9/installation.md) · [`rhel10`](../rhel10/installation.md)
- Arquitectura: [`architecture/`](../architecture/architecture.md)
- Comandos explicados y casos reales: [`troubleshooting/etapa1/README_troubleshooting_etapa1.md`](../troubleshooting/etapa1/README_troubleshooting_etapa1.md)
