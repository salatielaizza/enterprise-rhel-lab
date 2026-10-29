# 🧪 Enterprise RHEL Infrastructure Lab

Laboratorio de infraestructura empresarial sobre **KVM/libvirt**, con VMs de **RHEL 7, 8, 9 y 10** para
comparar versiones y practicar administración de sistemas como en un entorno real: instalación
desatendida (kickstart), gestión de usuarios/permisos/systemd/LVM, redes (NetworkManager), servicios
enterprise (DNS/BIND, hora/chrony, SSH/SFTP), seguridad (SELinux, auditoría), automatización con Ansible,
**Kubernetes y OpenShift** (clúster con kubeadm sobre RHEL 9, monitorizado con **Prometheus y Grafana** a
base de averías reales y gestionado como código con **Terraform**), nube pública con **AWS y Azure**,
virtualización con **VMware vSphere**
(ESXi anidado dentro de KVM, vCenter con clúster y vMotion, PowerCLI, y HA/DRS/switches distribuidos en
Hands-on Labs, integrado con el resto del lab, para comparar los dos grandes hipervisores enterprise, cada
vez más relevante dado el cambio de licencias de Broadcom que está empujando a muchas empresas hacia
alternativas basadas en KVM), gestión centralizada (Red Hat Satellite), control de versiones con Git,
servidores web y proxy inverso (Apache httpd, NGINX), migraciones entre versiones (Leapp), almacenamiento
compartido (NFS/CIFS), identidad centralizada (LDAP/Kerberos), alta disponibilidad (Pacemaker/Corosync),
monitorización de todo el lab (Prometheus/Grafana), contenedores con Docker y, como cierre, **CI/CD**
(integración y despliegue continuo aplicado a la propia automatización del laboratorio).

El plan se organiza, de partida, en **20 etapas** (ver tabla más abajo), pero no es un temario cerrado:
puede ampliarse o reordenarse según lo que se quiera practicar. Las Etapas 1 a 7 están
**completas** (validadas con `0 FAIL` en las 6 VMs). Regla del proyecto:
*manual → documentado → repetible → automatizado*.

> 📊 Diagrama interactivo (arquitectura + etapas + flujo Ansible): https://claude.ai/artifact/Nz57fkLXciTwKSpPGWPUMx
> (generado 2026-09-29 00:32 CEST — el contenido puede desactualizarse respecto al repo con el tiempo)

## 🗺️ Estado del proyecto y hoja de ruta

Este repositorio cubre hoy las **Etapas 1 a 10** de un plan de **20 etapas**. Las **Etapas 1 a 7** están
completas y validadas con `scripts/lab.sh test all all` en 0 FAIL en las 6 VMs (`rhel7/8/9/10-app01`,
`dns01`, `ansible01`): 180/181/181/181/167/166 PASS respectivamente tras la Etapa 7, 0 FAIL en todas. Las Etapas 1-4
incluyen BIND, chrony y SSH/SFTP endurecido (caso `etapa4/07` documentado en `troubleshooting/`); las
Etapas 5 y 6 añaden SELinux enforcing, auditd y hardening del SO, más herramientas propias en bash con
temporizador systemd — en el camino se aplicó la lección ya conocida del caso `etapa2/06` (`ausearch`
sin `timeout`) y se encontró y corrigió uno nuevo, el **caso `etapa6/01`** (una función bash que puede
devolver distinto de cero bajo `set -e` y aborta el script), ambos documentados en `troubleshooting/`
(que ahora organiza los casos en un directorio por etapa, numerados desde 01 en cada una). La
**Etapa 7** (automatización con Ansible: `ansible01` como nodo de control, roles idempotentes, Ansible
Vault, `block/rescue`, `serial`, colección propia, inventario dinámico y Molecule con Podman) está
**completa** (2026-10-22): se recorrió primero a mano en 19 fases (documentadas en
`scripts/stage7/README_stage7.md`) y después con `lab.sh`, y dejó **7 casos reales** en
`troubleshooting/etapa7/` (entre ellos, arreglos que solo existían en el nodo de control y se perdían,
un módulo propio incompatible con el Python 2.7 de RHEL 7 y un escenario de Molecule que nunca se había
ejecutado).

La **Etapa 8** pasa a ser **Kubernetes y OpenShift**, ampliada con **Prometheus/Grafana** y **Terraform**: guía
paso a paso en 13 subetapas, ficheros listos para aplicar (`scripts/stage8/files/`), 13 escenarios de averías
para aprender a monitorizar y 8 escenarios de infraestructura como código, todo pendiente de ejecutar. Va justo
después de Ansible porque se apoya en ella (`ansible01` administra el clúster) y porque es lo que más piden las
ofertas de plataforma en Madrid. La **Etapa 9** es **Cloud con AWS y Azure** (pendiente de planificar): va justo
después porque reutiliza Terraform y Kubernetes de la 8, y es lo que más piden las vacantes DevOps en Madrid.
**VMware vSphere pasa a la Etapa 10** (ya tiene su automatización y sus tests escritos: `scripts/stage10/`,
`tests/test_vmware.sh`, `tests/test_nfs_datastore.sh`, `checklists/etapa10.md`, sin ejecutar todavía y con su
documentación de tema en `virtualization/` pendiente) y **Red Hat Satellite a la 11**. VMware condiciona etapas
posteriores: migración VMware → KVM con `virt-v2v` (Etapa 14), NFS como datastore de ESXi (Etapa 15) y
monitorización de ESXi (Etapa 18); la migración de VMs a OpenShift Virtualization se estudia en la Etapa 8.
Satellite centraliza parches, repositorios y suscripciones de todas las VMs RHEL antes de las etapas que más
dependen de ello. El resto de etapas avanzan y el plan pasa a tener 20: el servidor web sigue dividido en dos
(Etapa **13a**: nginx + Gitea + PostgreSQL; Etapa **13b**: httpd + Nextcloud + PostgreSQL), la monitorización de
todo el lab (Etapa 18) parte de lo aprendido en la 8, y la antigua etapa de Kubernetes al final del plan
desaparece porque ahora es la 8. Las Etapas 9 y 11-20 están pendientes, sin empezar — este es un proyecto vivo,
no cerrado.

> **Enfoque de la Etapa 10 (VMware):** la combinación más realista sin licencia de pago es (1) **ESXi
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
| 7 | 🤖 Ansible (automatización, inventario, roles, Vault, Molecule) | ✅ Completa |
| 8 | ☸️ Kubernetes y OpenShift (kubeadm sobre RHEL 9, red, almacenamiento, seguridad, Helm; **Prometheus/Grafana** con averías reales; **Terraform** como IaC; OpenShift Local; GitOps con Argo CD; operación y upgrade) | 📝 Planificada |
| 9 | ☁️ Cloud: AWS y Azure (cuentas seguras y control de costes, redes, cómputo, almacenamiento, Terraform, EKS/AKS, monitorización, CI/CD) | ⏳ Pendiente |
| 10 | 🖥️ VMware vSphere (ESXi 8 anidado en KVM; vCenter en evaluación con clúster y vMotion sobre datastore NFS; PowerCLI y Ansible `community.vmware`; HA, DRS y switches distribuidos en Hands-on Labs; integrado con `dns01`/`ansible01` y comparado con KVM/libvirt) | 📝 Planificada |
| 11 | 🛰️ Red Hat Satellite (repositorios, parches, suscripciones y aprovisionamiento centralizados) | ⏳ Pendiente |
| 12 | 🔀 Git / Infraestructura como código | ⏳ Pendiente |
| 13a | 🧭 Servidor web con nginx — reverse proxy + Gitea (Git self-hosted) + PostgreSQL | ⏳ Pendiente |
| 13b | 🧭 Servidor web con httpd — PHP-FPM + Nextcloud + PostgreSQL | ⏳ Pendiente |
| 14 | 🚚 Migraciones (Leapp entre versiones de RHEL + VMware → KVM con `virt-v2v`) | ⏳ Pendiente |
| 15 | 🗄️ NFS / CIFS (almacenamiento compartido; NFS también como datastore de ESXi) | ⏳ Pendiente |
| 16 | 🔑 LDAP / Kerberos (identidad centralizada) | ⏳ Pendiente |
| 17 | ⚖️ Alta disponibilidad (Pacemaker/Corosync) | ⏳ Pendiente |
| 18 | 📊 Monitorización de todo el lab (Prometheus/Grafana, a partir de la Etapa 8; ESXi incluidos) | ⏳ Pendiente |
| 19 | 📦 Contenedores (Docker) | ⏳ Pendiente |
| 20 | 🔁 CI/CD | ⏳ Pendiente |
| N | 🧰 DevOps: Docker, Kubernetes, Jenkins y monitorización —  (ver [sección final](#-etapa-n--devops-docker-kubernetes-jenkins-y-monitorización)) | 📝 Planificada |
| N2 | 📡 SIEM: Graylog, OpenSearch/Elasticsearch, Syslog, NXLog, Docker, Kubernetes y conversión de VMs VMware ↔ KVM (ver [sección final](#-etapa-n2--siem-graylog-opensearch-syslog-nxlog-contenedores-y-vmware)) | 📝 Planificada |
| N3 | 🎯 Práctica de Ansible sin scripts: proyecto propio desde cero (P1-P10: ad-hoc, playbooks, handlers, roles, Vault, Jinja2, control de errores, colecciones) (ver [sección final](#-etapa-n3--práctica-de-ansible-sin-scripts)) | ✅ Completa |

Los nombres de host, IPs, UID/GID y la estructura de directorios ya fijados en las Etapas 1-4
(ver `architecture/hosts.md`) se mantienen estables para las etapas futuras — por ejemplo,
`ansible01` (10.10.10.30) ya está reservada para la Etapa 7, `k8s-cp01`/`k8s-w01`/`k8s-w02` (10.10.10.100-.102)
y el rango de MetalLB (10.10.10.110-.119) para la Etapa 8, `esxi01`/`esxi02`/`esxi03`/`vcsa01`/`rhel9-vm01`
(10.10.10.60-.64; vCenter y `rhel9-vm01` corren **dentro** de los ESXi) para la Etapa 10, y
`rhel9a-web01`/`rhel9b-web02`/`rhel9-monitor01` (10.10.10.40/.41/.50) para las etapas 13a, 13b y 18.

## 🔧 Contenido de las Etapas 1-10

| Etapa | Contenido | Automatización | Documentación | Guía de troubleshooting y estudio |
|---|---|---|---|---|
| 💿 1 | Instalación de RHEL 7/8/9/10 (+ dns01, ansible01) | `lab.sh host-setup/network/iso/vm-create/register/snapshot` | `rhelN/installation.md`, `checklists/etapa1.md` | [`README_troubleshooting_etapa1.md`](troubleshooting/etapa1/README_troubleshooting_etapa1.md) |
| 👥 2 | Usuarios, permisos, sudo, systemd, LVM/XFS, paquetes, logs | `lab.sh stage2` | `administration/*.md` | [`README_troubleshooting_etapa2.md`](troubleshooting/etapa2/README_troubleshooting_etapa2.md) |
| 🌐 3 | NetworkManager, IP/gateway/DNS/hostname, diagnóstico | `lab.sh stage3` | `networking/networkmanager.md`, `networking/troubleshooting.md` | [`README_troubleshooting_etapa3.md`](troubleshooting/etapa3/README_troubleshooting_etapa3.md) |
| 🔐 4 | BIND (DNS), chrony (hora), SSH/SFTP | `lab.sh stage4-dns`, `stage4-clients` | `networking/dns.md`, `time/chrony.md`, `networking/ssh.md` | [`README_troubleshooting_etapa4.md`](troubleshooting/etapa4/README_troubleshooting_etapa4.md) |
| 🛡️ 5 | SELinux enforcing, reglas de auditd, hardening del SO | `lab.sh stage5` | `security/selinux.md`, `security/audit.md`, `security/hardening.md` | [`README_troubleshooting_etapa5.md`](troubleshooting/etapa5/README_troubleshooting_etapa5.md) |
| 📜 6 | Herramientas propias en bash (`lab-healthcheck.sh`, `lab-logscan.sh`) + temporizador systemd | `lab.sh stage6` | `scripting/bash-avanzado.md` | [`README_troubleshooting_etapa6.md`](troubleshooting/etapa6/README_troubleshooting_etapa6.md) |
| 🤖 7 | ansible01 como nodo de control: roles idempotentes, Ansible Vault, block/rescue/serial, colección propia (módulo+filtro), inventario dinámico, Molecule con Podman | `lab.sh stage7-setup`, `stage7`; `molecule test` (host) | `automation/ansible.md`, recorrido manual en `scripts/stage7/README_stage7.md` | [`README_troubleshooting_etapa7.md`](troubleshooting/etapa7/README_troubleshooting_etapa7.md) |
| ☸️ 8 | Kubernetes con kubeadm (3 nodos RHEL 9, containerd, Calico, MetalLB, Traefik, local-path), RBAC y Pod Security, Helm (Gitea), Prometheus/Grafana con 13 escenarios de averías, Terraform (import, módulos, drift, estado remoto), OpenShift Local, CI y GitOps con Argo CD, upgrade y copias de etcd | A mano (sin comandos `lab.sh` propios); VMs con `lab.sh vm-create/stage2-5/test`; ficheros en `scripts/stage8/files/`; `ci/validar.sh` | [`kubernetes/etapa8-kubernetes-openshift.md`](kubernetes/etapa8-kubernetes-openshift.md), [`checklists/etapa8.md`](checklists/etapa8.md) | [`README_troubleshooting_etapa8.md`](troubleshooting/etapa8/README_troubleshooting_etapa8.md) |
| 🖥️ 10 | ESXi 8 anidado en KVM (gratuito independiente + estándar en evaluación), vCenter (VCSA) con clúster, datastore NFS en `dns01` y vMotion; PowerCLI y Ansible (`community.vmware`/`vmware.vmware`, venv propio con ansible-core ≥ 2.19); `rhel9-vm01` dentro de ESXi con los roles de la Etapa 7; HA/DRS/vDS en Hands-on Labs | `lab.sh esxi-preflight/esxi-iso/esxi-create/esxi-up/esxi-down/esxi-status/esxi-snapshot`, `stage10-nfs`, `vcsa-deploy`, `stage10-setup`, `stage10-guest-key`, `stage10`, `stage10-close` | [`checklists/etapa10.md`](checklists/etapa10.md); `virtualization/*.md` pendiente | [`README_troubleshooting_etapa10.md`](troubleshooting/etapa10/README_troubleshooting_etapa10.md) |

## 🏗️ Arquitectura en una mirada

```
                       Host KVM (Linux Mint 22)  10.10.10.1  (virbr-lab, NAT -> Internet por Wi-Fi)
                                   │  red libvirt "lab-net" 10.10.10.0/24, dominio lab.local
   ┌────────────┬────────────┬─────┴──────┬──────────────┬──────────────────┬─────────────────────┐
rhel7-app01  rhel8-app01  rhel9-app01  rhel10-app01     dns01              ansible01
 .11          .12          .13          .14              .20 BIND + NTP     .30 Ansible (Etapa 7)
                                                         + NFS (Etapa 10)    + kubectl, helm, terraform (Etapa 8)
                                                                            + venv VMware y PowerCLI (Etapa 10)

 Etapa 8 — Kubernetes (opcionales en hosts.conf): k8s-cp01 .100 (k8s-api) · k8s-w01 .101 · k8s-w02 .102
           Service LoadBalancer con MetalLB .110-.119: ingress .110, grafana .111, prometheus .112, alertmanager .113,
           podinfo .114, gitea .115, argocd .116, tienda .117 · pods 10.244.0.0/16 · services 10.96.0.0/12

 Etapa 10 — VMware vSphere: ESXi ANIDADO (VMs de KVM que ejecutan sus propias VMs), también en lab-net
 ┌─────────────────────────────┐   ┌──────────────────── lab-cluster (vCenter) ─────────────────────┐
 │ esxi01 .60  GRATUITO        │   │ esxi02 .61  EVALUACIÓN 60 d        esxi03 .62  EVALUACIÓN 60 d │
 │ independiente (Host Client) │   │  └─ vcsa01 .63  vCenter            vmk1 vMotion .72            │
 │  └─ rhel9-vm01 .64 (fase A) │   │  vmk1 vMotion .71   ◄── vMotion ──► rhel9-vm01 .64 (fase B)    │
 └─────────────────────────────┘   │       datastore NFS compartido «nfs-vmware» ◄── dns01          │
                                   └────────────────────────────────────────────────────────────────┘
   Fase A (ESXi gratuito) convive con el resto del lab · Fase B (vCenter): app01 y esxi01 apagadas
```
Inventario de los ESXi: `scripts/vmware.conf` (fuera de `hosts.conf`, para que `lab.sh … all` nunca los trate como RHEL).
Reservados para etapas futuras: `rhel9a-web01` .40 y `rhel9b-web02` .41 (Etapas 13a/13b), `rhel9-monitor01` .50 (Etapa 18).
Detalle en `architecture/`. Los nombres, IPs y UIDs/GIDs **no cambian** en etapas futuras.

## 📋 Requisitos

- Host Linux con virtualización por hardware (VT-x/AMD-V) y CPU **x86-64-v3** (obligatoria para RHEL 10).
- ~170 GB de disco virtual como máximo (qcow2 *thin*), RAM suficiente para encender las VMs **de forma selectiva**
  (las seis juntas suman ~16 GB).
- Red Hat Developer Subscription (gratuita) y un *offline token* para descargar ISOs (`scripts/download-isos.sh`).
- **Etapa 7:** las 6 VMs encendidas para `stage7-setup`, `stage7 site` y `test all all`. Para Molecule (opcional),
  **Podman** sin root en el host y un venv propio (`~/venvs/molecule` con `molecule`, `molecule-plugins[podman]`,
  `ansible-core` y la colección `containers.podman`; ver `scripts/stage7/README_stage7.md`).

**Etapa 8 (Kubernetes y OpenShift)** — además de lo anterior:

- `dns01` y `ansible01` encendidas + los tres nodos (`k8s-cp01` 4 GiB, `k8s-w01` y `k8s-w02` 5 GiB): ≈ 19 GiB en total.
  Cada nodo con un disco de datos de 40 GB (*thin*) para `vg_data`, containerd, kubelet y volúmenes.
- Salida a Internet en los nodos y en `ansible01` (repositorios `pkgs.k8s.io`, Docker, HashiCorp; imágenes de
  `registry.k8s.io`, `quay.io`, `ghcr.io`; charts de Helm).
- OpenShift Local (8.10, opcional): 4 vCPU y ~11 GiB **con el clúster apagado**, 35 GB de disco en el host y cuenta de
  Red Hat Developer; `crc setup` cambia el host, así que antes se revisa con `crc setup --check-only`.

**Etapa 10 (VMware vSphere)** — además de lo anterior:

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
scripts/lab.sh stage7-setup                                            # Etapa 7: ansible01 como nodo de control (6 VMs encendidas)
scripts/lab.sh stage7 site        && scripts/lab.sh test all all       #          aplica el playbook (repetible, idempotente)
( source ~/venvs/molecule/bin/activate && cd scripts/stage7/files/roles/common && molecule test )   # rol common con Podman (opcional)
scripts/lab.sh snapshot create all 7                                   #          <vm>-stage7-complete
scripts/lab.sh facts all && scripts/lab.sh matrix                      # matriz con DATOS REALES
```

**Etapa 8 — Kubernetes y OpenShift** (a mano, paso a paso, en [`kubernetes/etapa8-kubernetes-openshift.md`](kubernetes/etapa8-kubernetes-openshift.md)):

```bash
for h in k8s-cp01 k8s-w01 k8s-w02; do scripts/lab.sh vm-create "$h"; done   # + register de cada uno
scripts/lab.sh stage4-dns                                                     # zona con k8s-*, k8s-api y las IPs de MetalLB
for h in k8s-cp01 k8s-w01 k8s-w02; do
  scripts/lab.sh stage2 "$h" && scripts/lab.sh stage3 "$h" --lab-dns && scripts/lab.sh stage4-clients "$h" && scripts/lab.sh stage5 "$h"
  scripts/lab.sh test all "$h" && scripts/lab.sh snapshot create "$h" 5
done
# 8.2 en adelante: kubeadm, Calico, MetalLB... a mano desde ansible01 con los ficheros de scripts/stage8/files/
scripts/stage8/files/ci/validar.sh                                            # yamllint, kubeconform, promtool, terraform fmt
```

**Etapa 10 — VMware vSphere** (paso a paso, con resultados esperados, en [`checklists/etapa10.md`](checklists/etapa10.md)):

```bash
# Fase A — ESXi gratuito (convive con el resto del lab)
scripts/lab.sh esxi-preflight A                    # auditoría de SOLO LECTURA del host (nested, RAM, disco, ISOs, DNS)
scripts/lab.sh stage4-dns                          # zonas con esxi01-03, vcsa01 y rhel9-vm01 (A + PTR)
scripts/lab.sh esxi-create esxi01 --manual         # instalación A MANO del ESXi gratuito (consola: virt-viewer)
scripts/lab.sh stage10-setup                       # ansible01: venv, colecciones, PowerCLI; después 'ansible-vault edit'
scripts/lab.sh stage10-guest-key                   # rhel9-vm01 (creada a mano dentro de esxi01) acepta a ansible01
scripts/lab.sh stage10 guest-baseline              # misma base que el resto del lab (roles de la Etapa 7)
scripts/lab.sh esxi-iso esxi01 && scripts/lab.sh esxi-create esxi01 --force   # reinstalación DESATENDIDA
# Fase B — vCenter en evaluación (apaga antes las app01 y esxi01)
scripts/lab.sh esxi-preflight B
scripts/lab.sh esxi-iso all && scripts/lab.sh esxi-create esxi02 && scripts/lab.sh esxi-create esxi03
scripts/lab.sh stage10-nfs                         # disco SCSI + export NFS en dns01
scripts/lab.sh vcsa-deploy --precheck-only && scripts/lab.sh vcsa-deploy   # vCenter en esxi02 (anota la fecha)
scripts/lab.sh stage10 cluster && scripts/lab.sh stage10 esxi-config       # clúster, hosts, NFS, NTP, DNS
scripts/lab.sh stage10 guest && scripts/lab.sh stage10 vmotion             # vMotion en caliente de rhel9-vm01
scripts/lab.sh esxi-down all && scripts/lab.sh esxi-snapshot create esxi02 10  # (y esxi01/esxi03) antes de que caduque
```

**Tests generales** (todos de solo lectura):

```bash
scripts/lab.sh test all all                        # todos los tests aplicables a cada VM según su LAB_STAGE
scripts/lab.sh test test_network.sh rhel9-app01    # un test concreto en una VM concreta
scripts/lab.sh status                              # VMs RHEL: estado, SSH y snapshots
scripts/lab.sh test all k8s-cp01                   # Etapa 8: base del lab en un nodo de Kubernetes (ídem workers)
scripts/stage8/files/ci/validar.sh                 # Etapa 8: manifiestos, reglas y pruebas de alertas, Terraform
scripts/lab.sh esxi-preflight A                    # host: requisitos de la Etapa 10 (o B)
scripts/lab.sh esxi-status                         # ESXi: estado, licencia y CADUCIDAD, NTP, datastores, VMs
scripts/lab.sh test test_vmware.sh ansible01       # Etapa 10: herramientas, DNS y vSphere (según la fase activa)
scripts/lab.sh test test_nfs_datastore.sh dns01    # Etapa 10: export NFS del datastore compartido
scripts/lab.sh stage10 verify                      # Etapa 10: verificación completa de vSphere con Ansible
```

`test all all` muestra al final una tabla por VM (PASS, FAIL, tiempo). Los nodos de Kubernetes no entran en `all`
(son opcionales): se prueban por nombre, `test all k8s-cp01`. Los tests de la Etapa 10 se lanzan sueltos
hasta cerrarla con `lab.sh stage10-close` (que exige la Etapa 7 cerrada); a partir de ahí, `test all all` los incluye.

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
cada `stageN/` tiene su `README_stageN.md` con qué hace cada script, en qué orden, dónde corre y qué toca — la Etapa 1, sin carpeta propia, en `scripts/README_stage1.md`;
`stage8/files/` con los manifiestos, valores de Helm, reglas y dashboards, escenarios de averías y Terraform de la Etapa 8;
`stage10/` con scripts de host para ESXi/vCenter, scripts de `dns01`/`ansible01` y `files/vmware-lab/` (Ansible + PowerCLI);
inventario de ESXi en `vmware.conf`) ·
`scripts/kickstart/` plantillas de instalación · `tests/` pruebas PASS/FAIL de solo lectura ·
`architecture/` · `rhel7/ … rhel10/` · `administration/` · `networking/` · `time/` · `security/` · `scripting/` · `automation/` ·
`kubernetes/` (Etapa 8: guía, Prometheus/Grafana y Terraform) · `virtualization/` (Etapa 10, pendiente) · `devops/` (Etapa N, preparación rápida) ·
`automation/etapaN3-practica-ansible.md` y `scripts/stageN3/` (Etapa N3: práctica de Ansible sin scripts, proyecto de referencia en `files/practica-ansible/` y `validar.sh`) ·
`troubleshooting/` (un directorio por etapa con sus casos y su guía `README_troubleshooting_etapaN.md`; índice en `troubleshooting/README.md`) · `migration/` · `comparison/` · `checklists/` · `results/` (evidencias; `facts/` se genera).

## 🔒 Seguridad

Nunca se guardan contraseñas ni tokens en el repositorio: la contraseña de las VMs se pide al crearlas (o `LAB_PASSWORD`)
y solo se inserta su hash en un kickstart temporal. El *offline token* vive en `~/.config/rhel-lab/offline_token` (modo 600).
El `sudo` sin contraseña del grupo `sysadmins` es una decisión **solo de laboratorio**.
Etapa 8: las contraseñas (Grafana, Gitea) se generan con `openssl rand` y viven solo en Secrets del clúster; el
`kubeconfig` de administrador y el estado de Terraform (con secretos en claro) se quedan en `ansible01` y en el namespace
`tfstate` (`.terraform/`, `*.tfstate` y `*.tfplan` en `.gitignore`); Terraform recibe la contraseña por `TF_VAR_`, nunca
desde un fichero del repositorio.
Etapa 10: la contraseña de root de los ESXi solo se guarda como hash dentro de los ISO generados (fuera del repo: `*.iso` en
`.gitignore`); las de vCenter se piden al desplegar y se borran del JSON temporal al terminar; las que usa Ansible viven
cifradas en el `vault.yml` de `ansible01`, con la misma contraseña de Vault que la Etapa 7. La clave `~/.ssh/lab_esxi_rsa`
es RSA porque el `sshd` de ESXi 8 funciona en modo FIPS (no acepta ed25519).
Etapa N3: el proyecto de referencia solo incluye `vault.yml.example` (valor `CAMBIAR`); el `vault.yml` real, cifrado,
y las colecciones descargadas (`collections/`) están en `.gitignore`. La carpeta local `practica/` tampoco se sube.

## 🧰 Etapa N — DevOps: Docker, Kubernetes, Jenkins y monitorización

> **Estado: 📝 Planificada.** Guía escrita, pendiente de practicar en la VM real. Número de etapa por decidir.

Prueba práctica y adelanto de tecnologías del perfil *Linux Administrator DevOps* en el área de **APS** (*Application Production Support*). Presenta **teoría básica + práctica manual**, sobre
una sola VM, `rhel9-monitor01` (10.10.10.50). Sirve de anticipo de las Etapas 8 (Kubernetes),
18 (monitorización), 19 (Docker) y 20 (CI/CD), que mantienen su planificación completa.

| Bloque | Contenido |
|---|---|
| 0 | Preparar `rhel9-monitor01` (línea en `hosts.conf`, `vm-create`, `stage4-clients`, snapshot) |
| 1 | Docker CE en RHEL 9: imágenes, contenedores, `Dockerfile`, Compose; Docker frente a Podman |
| 2 | Prometheus + Grafana + node-exporter con Compose; `node_exporter` en todo el lab con Ansible; alertas e incidencia simulada |
| 3 | Kubernetes con k3s: Deployments, Services, escalado, *rolling update* y *rollback*, `CrashLoopBackOff` |
| 4 | Jenkins en Docker: pipeline sobre este repositorio con lint, aprobación del cambio y despliegue |
| 5 | ITIL para operación: incidencia, problema, cambio, release, SLA/MTTR y plantilla de PIR |
| 6 | APS y ServiceNow: instancia gratuita de desarrollador, incidencia por Table API, análisis de logs y batch fallido |
| 7 | Repaso: preguntas y vocabulario en inglés |

Guía completa: [`devops/etapaN-devops.md`](devops/etapaN-devops.md).

## 📡 Etapa N2 — SIEM: Graylog, OpenSearch, Syslog, NXLog, contenedores y VMware

> **Estado: 📝 Planificada.** Automatización, tests y guía escritos, pendientes de practicar en el lab real.

Prueba práctica y adelanto de tecnologías: un **SIEM** en una VM nueva, `siem01` (10.10.10.55), alimentado por las
VMs del lab, para practicar su operación, troubleshooting y documentación. Sirve de anticipo de las Etapas 8
(Kubernetes), 14 (VMware → KVM), 18 (monitorización) y 19 (Docker), que mantienen su planificación completa.

| Bloque | Contenido |
|---|---|
| 0 | Preparar `siem01` (host opcional en `hosts.conf`, DNS, `vm-create`, base de las Etapas 1-5, snapshot) |
| 1 | Docker CE en RHEL 9 con SELinux: LVs propios para Docker y k3s, `daemon.json`, contenedores confinados |
| 2 | Graylog 7 + OpenSearch + MongoDB con Docker Compose (secretos aleatorios, mínima exposición); Elasticsearch 9 opcional |
| 3 | Entradas Syslog/GELF por la API REST; herramientas en Python (API, GELF por UDP/TCP, consultas y agregaciones) |
| 4 | rsyslog de todas las VMs → Graylog con Ansible (RFC 5424, cola en disco, SELinux, *rollback*) |
| 5 | NXLog Community Edition: auditd → GELF con campos extraídos, sin privilegios de root |
| 6 | Detección: streams, pipelines, alertas, simulación de fuerza bruta y correlación en Python |
| 7 | Kubernetes (k3s) con Fluent Bit como DaemonSet y una app de ejemplo |
| 8 | VMware: importar, exportar y convertir VMs (VMDK, OVF/OVA, `vmkfstools`, `virt-v2v`, `govc`) |
| 9 | Buenas prácticas de ciberseguridad aplicadas y comprobables |
| 10 | Diagnóstico por capas: infraestructura física, virtual y de conectividad |

Guía completa: [`siem/etapaN2-siem.md`](siem/etapaN2-siem.md).

## 🎯 Etapa N3 — Práctica de Ansible sin scripts

> **Estado: ✅ Completa** (2026-10-29). Diez ejercicios hechos a mano contra las VMs reales y 7 casos reales de troubleshooting.

Consolidación de la Etapa 7: un proyecto Ansible **propio, escrito desde cero y sin `lab.sh`**, con su propio
`ansible.cfg` (`become = False`) e inventario por grupos (`legacy`, `modernos`, `servicios`, `app:children`), operado
contra `rhel7/8/9/10-app01` y `dns01`. No añade hosts ni comandos a `lab.sh`.

| Ejercicio | Contenido |
|---|---|
| P1 | Proyecto mínimo: `ansible.cfg`, inventario con grupos padre, `ping` y `become` |
| P2 | Ad-hoc: patrones (`:!`, `:&`), *facts* filtrados, `copy`/`file`/`fetch`, idempotencia |
| P3 | Primer playbook: paquete, servicio, fichero y handler; límites de `--check` |
| P4 | Variables de grupo, *facts*, `when` y `loop` con `loop_control` |
| P5 | Rol propio con `ansible-galaxy role init`: `defaults`, plantilla, handler y precedencia de variables |
| P6 | Ansible Vault propio: secreto cifrado, `password_hash` con sal fija y `no_log` |
| P7 | Plantillas Jinja2: `if`, `for` y filtros (`default`, `upper`, `map`, `join`) |
| P8 | Control de errores: `failed_when`, `ignore_errors`, `block`/`rescue`/`always`, `check_mode` |
| P9 | Colección de Galaxy (`ansible.posix`) con versión fijada, instalada dentro del proyecto |
| P10 | Ejercicio final: rol completo con usuario, `cron`, plantilla y etiquetas, idempotente |

Guía completa: [`automation/etapaN3-practica-ansible.md`](automation/etapaN3-practica-ansible.md) · Proyecto de
referencia y validación estática: [`scripts/stageN3/`](scripts/stageN3/README_stageN3.md) · Casos y guía de estudio:
[`troubleshooting/etapaN3/`](troubleshooting/etapaN3/README_troubleshooting_etapaN3.md).

## ☸️ Etapa 8 — Kubernetes y OpenShift, con Prometheus/Grafana y Terraform

> **Estado: 📝 Planificada.** Guía, ficheros y escenarios escritos; pendiente de ejecutar en el lab.

Clúster Kubernetes de tres nodos RHEL 9 montado **a mano** con kubeadm y operado como en producción; después,
monitorización y averías reales, infraestructura como código y comparación con OpenShift. Primero a mano y en detalle;
la automatización (Ansible, Terraform, Argo CD) llega al final y solo para lo ya hecho a mano.

| Subetapa | Contenido |
|---|---|
| 8.1 | Contenedores con Podman: rootless, imágenes propias, volúmenes con SELinux, Quadlet |
| 8.2 | kubeadm: LVs propios, swap, firewalld con zona `k8s`, containerd, Calico, `join`, administración desde `ansible01` |
| 8.3 | Objetos: Deployment, ReplicaSet, *rollout* y *undo*, ConfigMap, Secret, Job, DaemonSet |
| 8.4 | Red: Services, CoreDNS, MetalLB (.110-.119), Ingress/Gateway API con Traefik, NetworkPolicies |
| 8.5 | Almacenamiento: PV, PVC, StorageClass con local-path |
| 8.6 | Seguridad: RBAC con certificados, ServiceAccounts, Pod Security, Secrets, SELinux en contenedores |
| 8.7 | Helm: charts, valores, releases; Gitea en el clúster |
| 8.8 | **Prometheus y Grafana**: PromQL, reglas, Alertmanager y 13 escenarios ([guía](kubernetes/monitorizacion-prometheus-grafana.md)) |
| 8.9 | **Terraform**: estado remoto, `import` de lo hecho a mano, módulos, drift ([guía](kubernetes/terraform-iac.md)) |
| 8.10 | OpenShift Local: proyectos, SCC, Routes, S2I; OpenShift Virtualization en teoría |
| 8.11 | CI con `validar.sh` (yamllint, kubeconform, promtool, terraform) y GitOps con Argo CD |
| 8.12 | Operación: drain/uncordon, PodDisruptionBudget, copia y restauración de etcd, upgrade 1.36 → 1.37 |
| 8.13 | Ansible: rol `k8s_node` y reconstrucción de un nodo solo con Ansible |

Guía completa: [`kubernetes/etapa8-kubernetes-openshift.md`](kubernetes/etapa8-kubernetes-openshift.md).
