# 🧪 Enterprise RHEL Infrastructure Lab

Laboratorio de infraestructura empresarial sobre **KVM/libvirt**, con VMs de **RHEL 7, 8, 9 y 10** para
comparar versiones y practicar administración de sistemas como en un entorno real: instalación
desatendida (kickstart), gestión de usuarios/permisos/systemd/LVM, redes (NetworkManager), servicios
enterprise (DNS/BIND, hora/chrony, SSH/SFTP), seguridad (SELinux, auditoría), automatización con Ansible,
virtualización con **VMware vSphere** (ESXi anidado dentro de KVM, vCenter con clúster y vMotion,
PowerCLI, y HA/DRS/switches distribuidos en Hands-on Labs, integrado con el resto del lab, para comparar los dos grandes hipervisores
enterprise, cada vez más relevante dado el cambio de licencias de Broadcom que está empujando a muchas
empresas hacia alternativas basadas en KVM), gestión centralizada (Red Hat Satellite), control de
versiones con Git, servidores web y proxy inverso (Apache httpd, NGINX), migraciones entre
versiones (Leapp), almacenamiento compartido (NFS/CIFS),
identidad centralizada (LDAP/Kerberos), alta disponibilidad (Pacemaker/Corosync), monitorización
(Prometheus/Grafana) y contenedores con Docker. Como cierre, de forma más general y sin entrar en el
mismo nivel de detalle que el resto: **Kubernetes y OpenShift** (orquestación de contenedores en clúster
y la plataforma Kubernetes empresarial de Red Hat construida sobre él, con sus herramientas de
desarrollador y CI/CD integrado, tratadas juntas por lo emparentadas que están) y **CI/CD** (integración y despliegue
continuo aplicado a la propia automatización del laboratorio).

El plan se organiza, de partida, en **19 etapas** (ver tabla más abajo), pero no es un temario cerrado:
puede ampliarse o reordenarse según lo que se quiera practicar. Las Etapas 1 a 6 están
**completas** (validadas con `0 FAIL` en las 6 VMs). Regla del proyecto:
*manual → documentado → repetible → automatizado*.

> 📊 Diagrama interactivo (arquitectura + etapas + flujo Ansible): https://claude.ai/artifact/Nz57fkLXciTwKSpPGWPUMx
> (generado 2026-09-29 00:32 CEST — el contenido puede desactualizarse respecto al repo con el tiempo)

## 🗺️ Estado del proyecto y hoja de ruta

Este repositorio cubre hoy las **Etapas 1 a 7** de un plan de **19 etapas**. Las **Etapas 1 a 6** están
completas y validadas con `scripts/lab.sh test all all` en 0 FAIL en las 6 VMs (`rhel7/8/9/10-app01`,
`dns01`, `ansible01`): 171/172/172/172/158/153 PASS respectivamente, 0 FAIL en todas. Las Etapas 1-4
incluyen BIND, chrony y SSH/SFTP endurecido (caso `etapa4/07` documentado en `troubleshooting/`); las
Etapas 5 y 6 añaden SELinux enforcing, auditd y hardening del SO, más herramientas propias en bash con
temporizador systemd — en el camino se aplicó la lección ya conocida del caso `etapa2/06` (`ausearch`
sin `timeout`) y se encontró y corrigió uno nuevo, el **caso `etapa6/01`** (una función bash que puede
devolver distinto de cero bajo `set -e` y aborta el script), ambos documentados en `troubleshooting/`
(que ahora organiza los casos en un directorio por etapa, numerados desde 01 en cada una). La
**Etapa 7** (automatización con Ansible: `ansible01` como nodo de control, roles idempotentes, Ansible
Vault) tiene su automatización, tests y documentación escritos, pendiente de ejecutar y validar en las
VMs reales. La **Etapa 8** ya tiene su automatización y sus tests escritos (`scripts/stage8/`,
`tests/test_vmware.sh`, `tests/test_nfs_datastore.sh`, `checklists/etapa8.md`), sin ejecutar todavía en el
lab y con su documentación de tema (`virtualization/`) pendiente; las Etapas 9-19 están pendientes, sin
empezar — este es un proyecto vivo, no cerrado.
**VMware vSphere pasa a ser la Etapa 8** y **Red Hat Satellite la Etapa 9**, justo después de
Ansible. VMware se apoya en ella (`ansible01` gestiona vCenter y las VMs con `community.vmware`) y
condiciona etapas posteriores: migración VMware → KVM con `virt-v2v` (Etapa 12), NFS como datastore de
ESXi (Etapa 13), monitorización de ESXi (Etapa 16) y migración de VMs desde vSphere a OpenShift
Virtualization (Etapa 18). Satellite, a su vez, centraliza parches, repositorios y suscripciones de todas
las VMs RHEL antes de las etapas que más dependen de ello. Para hacerles sitio, las etapas siguientes
avanzan y el plan sigue teniendo 19 etapas. El servidor web sigue dividido en dos (Etapa **11a**: nginx +
Gitea + PostgreSQL; Etapa **11b**: httpd + Nextcloud + PostgreSQL) y la Etapa 18 fusiona Kubernetes y
OpenShift (encajan de forma natural, ya que OpenShift es la distribución empresarial de Kubernetes de
Red Hat).

> **Enfoque de la Etapa 8 (VMware):** la combinación más realista sin licencia de pago es (1) **ESXi
> gratuito** (8.0U3e) como host independiente y permanente; (2) **vCenter y ESXi estándar en evaluación de
> 60 días** para el clúster y vMotion (un ESXi gratuito no puede unirse a vCenter), documentado y
> automatizado para poder reconstruirlo, con snapshot antes de que caduque; (3) los **VMware Hands-on Labs**
> para HA, DRS y switches distribuidos; y (4) la certificación **VCP** como objetivo si se apuesta fuerte
> por VMware. Mientras dure la parte de vCenter se apagan las VMs `app01` (~29 GiB de los 31 GiB del host).

> **Leyenda de estado:** ✅ **Completa** — automatización + tests + documentación hechos y validados con `0 FAIL` en las 6 VMs. 📝 **Planificada** — automatización y documentación ya escritas, pendiente de ejecutar/validar en las VMs reales. ⏳ **Pendiente** — todavía no tiene nada elaborado (sin script, sin documentación).

| Etapa | Contenido | Estado |
|---|---|---|
| 1 | 💿 Instalación (RHEL 7/8/9/10, kickstart, KVM/libvirt) | ✅ Completa |
| 2 | 👥 Administración Linux (usuarios, permisos, sudo, systemd, LVM, paquetes, logs) | ✅ Completa |
| 3 | 🌐 Networking (NetworkManager, diagnóstico por capas) | ✅ Completa |
| 4 | 🔐 Servicios enterprise (DNS/BIND, hora/chrony, SSH/SFTP) | ✅ Completa |
| 5 | 🛡️ Seguridad (SELinux avanzado, auditoría, hardening) | ✅ Completa |
| 6 | 📜 Bash avanzado y scripting | ✅ Completa |
| 7 | 🤖 Ansible (automatización, inventario, roles) | 📝 Planificada |
| 8 | 🖥️ VMware vSphere (ESXi 8 anidado en KVM; vCenter en evaluación con clúster y vMotion sobre datastore NFS; PowerCLI y Ansible `community.vmware`; HA, DRS y switches distribuidos en Hands-on Labs; integrado con `dns01`/`ansible01` y comparado con KVM/libvirt) | ⏳ Pendiente |
| 9 | 🛰️ Red Hat Satellite (repositorios, parches, suscripciones y aprovisionamiento centralizados) | ⏳ Pendiente |
| 10 | 🔀 Git / Infraestructura como código | ⏳ Pendiente |
| 11a | 🧭 Servidor web con nginx — reverse proxy + Gitea (Git self-hosted) + PostgreSQL | ⏳ Pendiente |
| 11b | 🧭 Servidor web con httpd — PHP-FPM + Nextcloud + PostgreSQL | ⏳ Pendiente |
| 12 | 🚚 Migraciones (Leapp entre versiones de RHEL + VMware → KVM con `virt-v2v`) | ⏳ Pendiente |
| 13 | 🗄️ NFS / CIFS (almacenamiento compartido; NFS también como datastore de ESXi) | ⏳ Pendiente |
| 14 | 🔑 LDAP / Kerberos (identidad centralizada) | ⏳ Pendiente |
| 15 | ⚖️ Alta disponibilidad (Pacemaker/Corosync) | ⏳ Pendiente |
| 16 | 📊 Monitorización (Prometheus/Grafana) | ⏳ Pendiente |
| 17 | 📦 Contenedores (Docker) | ⏳ Pendiente |
| 18 | ☸️ Kubernetes y OpenShift (orquestación de contenedores + plataforma enterprise de Red Hat) | ⏳ Pendiente |
| 19 | 🔁 CI/CD | ⏳ Pendiente |

Los nombres de host, IPs, UID/GID y la estructura de directorios ya fijados en las Etapas 1-4
(ver `architecture/hosts.md`) se mantienen estables para las etapas futuras — por ejemplo,
`ansible01` (10.10.10.30) ya está reservada para la Etapa 7, `esxi01`/`esxi02`/`esxi03`/`vcsa01`/`rhel9-vm01`
(10.10.10.60-.64; vCenter y `rhel9-vm01` corren **dentro** de los ESXi) para la Etapa 8, y
`rhel9a-web01`/`rhel9b-web02`/`rhel9-monitor01` (10.10.10.40/.41/.50) para las etapas 11a, 11b y 16.

## 🔧 Contenido de las Etapas 1-8

| Etapa | Contenido | Automatización | Documentación | Guía de troubleshooting y estudio |
|---|---|---|---|---|
| 💿 1 | Instalación de RHEL 7/8/9/10 (+ dns01, ansible01) | `lab.sh host-setup/network/iso/vm-create/register/snapshot` | `rhelN/installation.md`, `checklists/etapa1.md` | [`README_troubleshooting_etapa1.md`](troubleshooting/etapa1/README_troubleshooting_etapa1.md) |
| 👥 2 | Usuarios, permisos, sudo, systemd, LVM/XFS, paquetes, logs | `lab.sh stage2` | `administration/*.md` | [`README_troubleshooting_etapa2.md`](troubleshooting/etapa2/README_troubleshooting_etapa2.md) |
| 🌐 3 | NetworkManager, IP/gateway/DNS/hostname, diagnóstico | `lab.sh stage3` | `networking/networkmanager.md`, `networking/troubleshooting.md` | [`README_troubleshooting_etapa3.md`](troubleshooting/etapa3/README_troubleshooting_etapa3.md) |
| 🔐 4 | BIND (DNS), chrony (hora), SSH/SFTP | `lab.sh stage4-dns`, `stage4-clients` | `networking/dns.md`, `time/chrony.md`, `networking/ssh.md` | [`README_troubleshooting_etapa4.md`](troubleshooting/etapa4/README_troubleshooting_etapa4.md) |
| 🛡️ 5 | SELinux enforcing, reglas de auditd, hardening del SO | `lab.sh stage5` | `security/selinux.md`, `security/audit.md`, `security/hardening.md` | [`README_troubleshooting_etapa5.md`](troubleshooting/etapa5/README_troubleshooting_etapa5.md) |
| 📜 6 | Herramientas propias en bash (`lab-healthcheck.sh`, `lab-logscan.sh`) + temporizador systemd | `lab.sh stage6` | `scripting/bash-avanzado.md` | [`README_troubleshooting_etapa6.md`](troubleshooting/etapa6/README_troubleshooting_etapa6.md) |
| 🤖 7 | ansible01 como nodo de control: roles idempotentes, Ansible Vault, block/rescue/serial, colección propia (módulo+filtro), inventario dinámico, Molecule | `lab.sh stage7-setup`, `stage7` | `automation/ansible.md` | Se crea al cerrar la etapa (índice actual: [`etapa7/README.md`](troubleshooting/etapa7/README.md)) |
| 🖥️ 8 | ESXi 8 anidado en KVM (gratuito independiente + estándar en evaluación), vCenter (VCSA) con clúster, datastore NFS en `dns01` y vMotion; PowerCLI y Ansible (`community.vmware`/`vmware.vmware`, venv propio con ansible-core ≥ 2.19); `rhel9-vm01` dentro de ESXi con los roles de la Etapa 7; HA/DRS/vDS en Hands-on Labs | `lab.sh esxi-preflight/esxi-iso/esxi-create/esxi-up/esxi-down/esxi-status/esxi-snapshot`, `stage8-nfs`, `vcsa-deploy`, `stage8-setup`, `stage8-guest-key`, `stage8`, `stage8-close` | [`checklists/etapa8.md`](checklists/etapa8.md); `virtualization/*.md` pendiente | Se crea al cerrar la etapa |

## 🏗️ Arquitectura en una mirada

```
                       Host KVM (Linux Mint 22)  10.10.10.1  (virbr-lab, NAT -> Internet por Wi-Fi)
                                   │  red libvirt "lab-net" 10.10.10.0/24, dominio lab.local
   ┌────────────┬────────────┬─────┴──────┬──────────────┬──────────────────┬─────────────────────┐
rhel7-app01  rhel8-app01  rhel9-app01  rhel10-app01     dns01              ansible01
 .11          .12          .13          .14              .20 BIND + NTP     .30 Ansible (Etapa 7)
                                                         + NFS (Etapa 8)    + venv VMware y PowerCLI (Etapa 8)

 Etapa 8 — VMware vSphere: ESXi ANIDADO (VMs de KVM que ejecutan sus propias VMs), también en lab-net
 ┌─────────────────────────────┐   ┌──────────────────── lab-cluster (vCenter) ─────────────────────┐
 │ esxi01 .60  GRATUITO        │   │ esxi02 .61  EVALUACIÓN 60 d        esxi03 .62  EVALUACIÓN 60 d │
 │ independiente (Host Client) │   │  └─ vcsa01 .63  vCenter            vmk1 vMotion .72            │
 │  └─ rhel9-vm01 .64 (fase A) │   │  vmk1 vMotion .71   ◄── vMotion ──► rhel9-vm01 .64 (fase B)    │
 └─────────────────────────────┘   │       datastore NFS compartido «nfs-vmware» ◄── dns01          │
                                   └────────────────────────────────────────────────────────────────┘
   Fase A (ESXi gratuito) convive con el resto del lab · Fase B (vCenter): app01 y esxi01 apagadas
```
Inventario de los ESXi: `scripts/vmware.conf` (fuera de `hosts.conf`, para que `lab.sh … all` nunca los trate como RHEL).
Reservados para etapas futuras: `rhel9a-web01` .40 y `rhel9b-web02` .41 (Etapas 11a/11b), `rhel9-monitor01` .50 (Etapa 16).
Detalle en `architecture/`. Los nombres, IPs y UIDs/GIDs **no cambian** en etapas futuras.

## 📋 Requisitos

- Host Linux con virtualización por hardware (VT-x/AMD-V) y CPU **x86-64-v3** (obligatoria para RHEL 10).
- ~170 GB de disco virtual como máximo (qcow2 *thin*), RAM suficiente para encender las VMs **de forma selectiva**
  (las seis juntas suman ~16 GB).
- Red Hat Developer Subscription (gratuita) y un *offline token* para descargar ISOs (`scripts/download-isos.sh`).

**Etapa 8 (VMware vSphere)** — además de lo anterior:

| Recurso | Fase A: ESXi gratuito | Fase B: vCenter + clúster en evaluación |
|---|---|---|
| VMs encendidas | `dns01` + `ansible01` + `esxi01` (+ las `app01` si hay margen) | `dns01` + `ansible01` + `esxi02` + `esxi03` (**`app01` y `esxi01` apagadas**) |
| RAM asignada | ~15 GiB (≈ 26 GiB con las 4 `app01`) | ~27-29 GiB de 31 GiB (VCSA "tiny" pide 14 GB; reducida a 10-12 GB tras instalar) |
| vCPU | `esxi01`: 4 | `esxi02`: 4 · `esxi03`: 4 (12 hilos en el host) |
| Disco virtual máximo (qcow2 *thin*) | `esxi01`: 40 + 80 GB | `esxi02`: 40 + 120 GB · `esxi03`: 40 GB · disco NFS de `dns01`: 60 GB |
| Uso real estimado | 15-25 GB | 70-100 GB (VCSA es lo que más ocupa) |
| Disco libre recomendado | ≥ 70 GB | ≥ 130 GB (regla del lab: no bajar nunca de 50 GB libres) |

- Virtualización **anidada** activa (`/sys/module/kvm_intel/parameters/nested` = `Y`), QEMU con NIC `vmxnet3`;
  si ESXi da PSOD al arrancar, `kvm.ignore_msrs=1` (cambio en el host: siempre con confirmación).
- Herramientas del host: `xorriso`, `envsubst` (`gettext-base`), `dig` (`bind9-dnsutils`); en la fase B, `jq` y `udisksctl`.
- ISOs de Broadcom (cuenta gratuita): ESXi 8.0U3e **gratuito**; para la fase B, el instalador **estándar** de ESXi 8 y el
  ISO de **VCSA 8**, que solo se descargan con derecho de evaluación o licencia. Rutas en `~/.config/rhel-lab/isos.conf`
  (claves `ESXI_FREE_ISO`, `ESXI_EVAL_ISO`, `VCSA_ISO`; ver `scripts/isos.conf.example`).
- `ansible01` necesita salida a Internet (PyPI, Ansible Galaxy y el repositorio de PowerShell de Microsoft).
- Todo se comprueba antes de empezar, en solo lectura: `scripts/lab.sh esxi-preflight A` (o `B`).

## 🚀 Puesta en marcha (orden exacto)

Si has descargado un zip (no un tarball) restaura los permisos: `find . -name '*.sh' -exec chmod +x {} +`

```bash
scripts/lab.sh host-setup            # KVM, pools, clave SSH. Cierra sesión y vuelve a entrar (grupos libvirt/kvm)
scripts/lab.sh network               # red lab-net
mkdir -p ~/.config/rhel-lab && cp scripts/isos.conf.example ~/.config/rhel-lab/isos.conf
scripts/lab.sh iso --check           # valida token, config y checksums (no descarga)
scripts/lab.sh iso                   # ~42 GB; reanudable; verifica SHA-256
scripts/lab.sh vm-create rhel9-app01 --dry-run   # revisa el comando y el kickstart sin instalar
scripts/lab.sh vm-create rhel9-app01             # instalación desatendida (10-25 min)
scripts/lab.sh register rhel9-app01 <tu-usuario-Red-Hat>
scripts/lab.sh test test_install.sh rhel9-app01
scripts/lab.sh snapshot create rhel9-app01 1     # rhel9-stage1-complete
```

Repite `vm-create`/`register`/`test`/`snapshot` con rhel7-app01, rhel8-app01 y rhel10-app01. Después:

```bash
scripts/lab.sh vm-create dns01 ; scripts/lab.sh vm-create ansible01   # antes de 'stage2 all' (o aplica stage2 solo a las app01)
scripts/lab.sh stage2 all         && scripts/lab.sh test all all       # Etapa 2  (+ snapshot 2)
scripts/lab.sh stage3 all         && scripts/lab.sh test all all       # Etapa 3  (DNS de arranque 10.10.10.1)
scripts/lab.sh stage4-dns                                              # Etapa 4: BIND + chrony servidor
scripts/lab.sh stage4-clients all && scripts/lab.sh test all all       #          DNS lab + chrony + SSH
scripts/lab.sh stage5 all         && scripts/lab.sh test all all       # Etapa 5: SELinux + auditd + hardening
scripts/lab.sh stage6 all         && scripts/lab.sh test all all       # Etapa 6: herramientas bash + temporizador systemd
scripts/lab.sh stage7-setup                                            # Etapa 7: ansible01 como nodo de control (una vez)
scripts/lab.sh stage7 site        && scripts/lab.sh test all all       #          aplica el playbook (repetible, idempotente)
scripts/lab.sh facts all && scripts/lab.sh matrix                      # matriz con DATOS REALES
```

**Etapa 8 — VMware vSphere** (paso a paso, con resultados esperados, en [`checklists/etapa8.md`](checklists/etapa8.md)):

```bash
# Fase A — ESXi gratuito (convive con el resto del lab)
scripts/lab.sh esxi-preflight A                    # auditoría de SOLO LECTURA del host (nested, RAM, disco, ISOs, DNS)
scripts/lab.sh stage4-dns                          # zonas con esxi01-03, vcsa01 y rhel9-vm01 (A + PTR)
scripts/lab.sh esxi-create esxi01 --manual         # instalación A MANO del ESXi gratuito (consola: virt-viewer)
scripts/lab.sh stage8-setup                        # ansible01: venv, colecciones, PowerCLI; después 'ansible-vault edit'
scripts/lab.sh stage8-guest-key                    # rhel9-vm01 (creada a mano dentro de esxi01) acepta a ansible01
scripts/lab.sh stage8 guest-baseline               # misma base que el resto del lab (roles de la Etapa 7)
scripts/lab.sh esxi-iso esxi01 && scripts/lab.sh esxi-create esxi01 --force   # reinstalación DESATENDIDA
# Fase B — vCenter en evaluación (apaga antes las app01 y esxi01)
scripts/lab.sh esxi-preflight B
scripts/lab.sh esxi-iso all && scripts/lab.sh esxi-create esxi02 && scripts/lab.sh esxi-create esxi03
scripts/lab.sh stage8-nfs                          # disco SCSI + export NFS en dns01
scripts/lab.sh vcsa-deploy --precheck-only && scripts/lab.sh vcsa-deploy   # vCenter en esxi02 (anota la fecha)
scripts/lab.sh stage8 cluster && scripts/lab.sh stage8 esxi-config         # clúster, hosts, NFS, NTP, DNS
scripts/lab.sh stage8 guest && scripts/lab.sh stage8 vmotion               # vMotion en caliente de rhel9-vm01
scripts/lab.sh esxi-down all && scripts/lab.sh esxi-snapshot create esxi02 8   # (y esxi01/esxi03) antes de que caduque
```

**Tests generales** (todos de solo lectura):

```bash
scripts/lab.sh test all all                        # todos los tests aplicables a cada VM según su LAB_STAGE
scripts/lab.sh test test_network.sh rhel9-app01    # un test concreto en una VM concreta
scripts/lab.sh status                              # VMs RHEL: estado, SSH y snapshots
scripts/lab.sh esxi-preflight A                    # host: requisitos de la Etapa 8 (o B)
scripts/lab.sh esxi-status                         # ESXi: estado, licencia y CADUCIDAD, NTP, datastores, VMs
scripts/lab.sh test test_vmware.sh ansible01       # Etapa 8: herramientas, DNS y vSphere (según la fase activa)
scripts/lab.sh test test_nfs_datastore.sh dns01    # Etapa 8: export NFS del datastore compartido
scripts/lab.sh stage8 verify                       # Etapa 8: verificación completa de vSphere con Ansible
```

`test all all` muestra al final una tabla por VM (PASS, FAIL, tiempo). Los tests de la Etapa 8 se lanzan sueltos
hasta cerrarla con `lab.sh stage8-close` (que exige la Etapa 7 cerrada); a partir de ahí, `test all all` los incluye.

Ayuda completa: `scripts/lab.sh help`. Las VMs se encienden/apagan con `lab.sh up|down <host|all>`, y los ESXi,
de forma ordenada, con `lab.sh esxi-up|esxi-down <esxi0N|all>`.

## 🎓 Cómo usar este repositorio para aprender

1. Lee el `.md` del tema y **haz el procedimiento a mano** en una VM (tras un snapshot).
2. Estudia la guía de la etapa (`troubleshooting/etapaN/README_troubleshooting_etapaN.md`: comandos de los
   scripts y de los tests explicados, chuleta síntoma → comandos y preguntas de repaso) y provoca y resuelve
   sus casos de troubleshooting.
3. Aplica el script (`lab.sh stageN`) a todas las VMs y pasa los tests.
4. Rellena `checklists/etapaN.md` y crea el snapshot `<nombre>-stageN-complete`.

Una etapa **no está completa** hasta cumplir: documentación + tests + troubleshooting + diferencias entre versiones + snapshot.

## 🔍 Convención de verificación de datos

En las tablas de diferencias entre versiones: **✔** = confirmado en documentación oficial consultada;
**◦** = conocimiento general, *pendiente de verificar en la VM*. La matriz `comparison/matrix.generated.md`
se genera exclusivamente con datos leídos de las VMs (`lab.sh facts`).

## 🗂️ Mapa del repositorio

`scripts/` automatización (host: `lab.sh`, `0N-*.sh`; VMs: `stage2/`, `stage3/`, `stage4/`, `stage5/`, `stage6/`, `stage7/`;
`stage8/` con scripts de host para ESXi/vCenter, scripts de `dns01`/`ansible01` y `files/vmware-lab/` (Ansible + PowerCLI);
inventario de ESXi en `vmware.conf`) ·
`scripts/kickstart/` plantillas de instalación · `tests/` pruebas PASS/FAIL de solo lectura ·
`architecture/` · `rhel7/ … rhel10/` · `administration/` · `networking/` · `time/` · `security/` · `scripting/` · `automation/` ·
`virtualization/` (Etapa 8, pendiente) ·
`troubleshooting/` (un directorio por etapa con sus casos y su guía `README_troubleshooting_etapaN.md`; índice en `troubleshooting/README.md`) · `migration/` · `comparison/` · `checklists/` · `results/` (evidencias; `facts/` se genera).

## 🔒 Seguridad

Nunca se guardan contraseñas ni tokens en el repositorio: la contraseña de las VMs se pide al crearlas (o `LAB_PASSWORD`)
y solo se inserta su hash en un kickstart temporal. El *offline token* vive en `~/.config/rhel-lab/offline_token` (modo 600).
El `sudo` sin contraseña del grupo `sysadmins` es una decisión **solo de laboratorio**.
Etapa 8: la contraseña de root de los ESXi solo se guarda como hash dentro de los ISO generados (fuera del repo: `*.iso` en
`.gitignore`); las de vCenter se piden al desplegar y se borran del JSON temporal al terminar; las que usa Ansible viven
cifradas en el `vault.yml` de `ansible01`, con la misma contraseña de Vault que la Etapa 7. La clave `~/.ssh/lab_esxi_rsa`
es RSA porque el `sshd` de ESXi 8 funciona en modo FIPS (no acepta ed25519).
