# 🧪 Enterprise RHEL Infrastructure Lab

Laboratorio de infraestructura empresarial sobre **KVM/libvirt**, con VMs de **RHEL 7, 8, 9 y 10** para
comparar versiones y practicar administración de sistemas como en un entorno real: instalación
desatendida (kickstart), gestión de usuarios/permisos/systemd/LVM, redes (NetworkManager), servicios
enterprise (DNS/BIND, hora/chrony, SSH/SFTP), seguridad (SELinux, auditoría), automatización con Ansible,
control de versiones con Git, servidores web y proxy inverso (Apache httpd, NGINX), migraciones entre
versiones (Leapp), gestión centralizada (Red Hat Satellite), almacenamiento compartido (NFS/CIFS),
identidad centralizada (LDAP/Kerberos), alta disponibilidad (Pacemaker/Corosync), monitorización
(Prometheus/Grafana) y contenedores con Docker. Como cierre, de forma más general y sin entrar en el
mismo nivel de detalle que el resto: **Kubernetes y OpenShift** (orquestación de contenedores en clúster
y la plataforma Kubernetes empresarial de Red Hat construida sobre él, con sus herramientas de
desarrollador y CI/CD integrado, tratadas juntas por lo emparentadas que están), **VMware ESXi avanzado**
(hipervisor tipo 1 alternativo a KVM/libvirt — vCenter, vMotion, DRS/HA, PowerCLI — para comparar
enfoques de virtualización enterprise, cada vez más relevante dado el cambio de licencias de Broadcom que
está empujando a muchas empresas hacia alternativas basadas en KVM) y **CI/CD** (integración y despliegue
continuo aplicado a la propia automatización del laboratorio).

El plan se organiza, de partida, en **19 etapas** (ver tabla más abajo), pero no es un temario cerrado:
puede ampliarse o reordenarse según lo que se quiera practicar. Las Etapas 1 a 6 están
**completas** (validadas con `0 FAIL` en las 6 VMs). Regla del proyecto:
*manual → documentado → repetible → automatizado*.

## 🗺️ Estado del proyecto y hoja de ruta

Este repositorio cubre hoy las **Etapas 1 a 7** de un plan de **19 etapas**. Las **Etapas 1 a 6** están
completas y validadas con `scripts/lab.sh test all all` en 0 FAIL en las 6 VMs (`rhel7/8/9/10-app01`,
`dns01`, `ansible01`): 171/172/172/172/158/153 PASS respectivamente, 0 FAIL en todas. Las Etapas 1-4
incluyen BIND, chrony y SSH/SFTP endurecido (caso 27 documentado en `troubleshooting/`); las Etapas 5 y
6 añaden SELinux enforcing, auditd y hardening del SO, más herramientas propias en bash con
temporizador systemd — en el camino se aplicó la lección ya conocida del caso 20 (`ausearch` sin
`timeout`) y se encontró y corrigió uno nuevo, el **caso 28** (una función bash que puede devolver
distinto de cero bajo `set -e` y aborta el script), ambos documentados en `troubleshooting/`. La
**Etapa 7** (automatización con Ansible: `ansible01` como nodo de control, roles idempotentes, Ansible
Vault) tiene su automatización, tests y documentación escritos, pendiente de ejecutar y validar en las
VMs reales. Las Etapas 8-19 están pendientes, sin empezar — este es un proyecto vivo, no cerrado. La
Etapa 17 fusiona Kubernetes y OpenShift en una sola (encajan de forma natural, ya que OpenShift es la
distribución empresarial de Kubernetes de Red Hat), dejando sitio a la Etapa 18: **VMware ESXi
avanzado**, para comparar KVM/libvirt (lo usado en todo este lab) con el otro gran hipervisor enterprise.

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
| 8 | 🔀 Git / Infraestructura como código | ⏳ Pendiente |
| 9 | 🧭 Servidores web y proxy inverso (Apache httpd, NGINX, balanceo) | ⏳ Pendiente |
| 10 | 🚚 Migraciones entre versiones (Leapp) | ⏳ Pendiente |
| 11 | 🛰️ Red Hat Satellite | ⏳ Pendiente |
| 12 | 🗄️ NFS / CIFS (almacenamiento compartido) | ⏳ Pendiente |
| 13 | 🔑 LDAP / Kerberos (identidad centralizada) | ⏳ Pendiente |
| 14 | ⚖️ Alta disponibilidad (Pacemaker/Corosync) | ⏳ Pendiente |
| 15 | 📊 Monitorización (Prometheus/Grafana) | ⏳ Pendiente |
| 16 | 📦 Contenedores (Docker) | ⏳ Pendiente |
| 17 | ☸️ Kubernetes y OpenShift (orquestación de contenedores + plataforma enterprise de Red Hat) | ⏳ Pendiente |
| 18 | 🖥️ VMware ESXi avanzado (vCenter, vMotion, DRS/HA, PowerCLI — comparado con KVM/libvirt) | ⏳ Pendiente |
| 19 | 🔁 CI/CD | ⏳ Pendiente |

Los nombres de host, IPs, UID/GID y la estructura de directorios ya fijados en las Etapas 1-4
(ver `architecture/hosts.md`) se mantienen estables para las etapas futuras — por ejemplo,
`ansible01` (10.10.10.30) ya está reservada para la Etapa 7, y `rhel9-web01`/`rhel9-monitor01`
(10.10.10.40/.50) para las etapas 9 y 15.

## 🔧 Contenido de las Etapas 1-7

| Etapa | Contenido | Automatización | Documentación |
|---|---|---|---|
| 💿 1 | Instalación de RHEL 7/8/9/10 (+ dns01, ansible01) | `lab.sh host-setup/network/iso/vm-create/register/snapshot` | `rhelN/installation.md`, `checklists/etapa1.md` |
| 👥 2 | Usuarios, permisos, sudo, systemd, LVM/XFS, paquetes, logs | `lab.sh stage2` | `administration/*.md` |
| 🌐 3 | NetworkManager, IP/gateway/DNS/hostname, diagnóstico | `lab.sh stage3` | `networking/networkmanager.md`, `networking/troubleshooting.md` |
| 🔐 4 | BIND (DNS), chrony (hora), SSH/SFTP | `lab.sh stage4-dns`, `stage4-clients` | `networking/dns.md`, `time/chrony.md`, `networking/ssh.md` |
| 🛡️ 5 | SELinux enforcing, reglas de auditd, hardening del SO | `lab.sh stage5` | `security/selinux.md`, `security/audit.md`, `security/hardening.md` |
| 📜 6 | Herramientas propias en bash (`lab-healthcheck.sh`, `lab-logscan.sh`) + temporizador systemd | `lab.sh stage6` | `scripting/bash-avanzado.md` |
| 🤖 7 | ansible01 como nodo de control: roles idempotentes, Ansible Vault, block/rescue/serial, colección propia (módulo+filtro), inventario dinámico, Molecule | `lab.sh stage7-setup`, `stage7` | `automation/ansible.md` |

## 🏗️ Arquitectura en una mirada

```
                       Host KVM (Linux Mint 22)  10.10.10.1  (virbr-lab, NAT -> Internet por Wi-Fi)
                                   │  red libvirt "lab-net" 10.10.10.0/24, dominio lab.local
   ┌────────────┬────────────┬─────┴──────┬─────────────┬───────────┬───────────┐
rhel7-app01  rhel8-app01  rhel9-app01  rhel10-app01    dns01      ansible01
 .11          .12          .13          .14             .20 (BIND+NTP) .30
```
Detalle en `architecture/`. Los nombres, IPs y UIDs/GIDs **no cambian** en etapas futuras.

## 📋 Requisitos

- Host Linux con virtualización por hardware (VT-x/AMD-V) y CPU **x86-64-v3** (obligatoria para RHEL 10).
- ~170 GB de disco virtual como máximo (qcow2 *thin*), RAM suficiente para encender las VMs **de forma selectiva**
  (las seis juntas suman ~16 GB).
- Red Hat Developer Subscription (gratuita) y un *offline token* para descargar ISOs (`scripts/download-isos.sh`).

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
scripts/lab.sh stage2 all && scripts/lab.sh test all all               # Etapa 2  (+ snapshot 2)
scripts/lab.sh stage3 all                                              # Etapa 3  (DNS de arranque 10.10.10.1)
scripts/lab.sh stage4-dns                                              # Etapa 4: BIND + chrony servidor
scripts/lab.sh stage4-clients all                                      #          DNS lab + chrony + SSH
scripts/lab.sh stage5 all                                              # Etapa 5: SELinux + auditd + hardening
scripts/lab.sh stage6 all                                              # Etapa 6: herramientas bash + temporizador systemd
scripts/lab.sh stage7-setup                                            # Etapa 7: ansible01 como nodo de control (una vez)
scripts/lab.sh stage7 site                                             #          aplica el playbook (repetible, idempotente)
scripts/lab.sh test all all                                            # todos los tests aplicables
scripts/lab.sh facts all && scripts/lab.sh matrix                      # matriz con DATOS REALES
```

Ayuda completa: `scripts/lab.sh help`. Las VMs se encienden/apagan con `lab.sh up|down <host|all>`.

## 🎓 Cómo usar este repositorio para aprender

1. Lee el `.md` del tema y **haz el procedimiento a mano** en una VM (tras un snapshot).
2. Provoca y resuelve los casos de `troubleshooting/`.
3. Aplica el script (`lab.sh stageN`) a todas las VMs y pasa los tests.
4. Rellena `checklists/etapaN.md` y crea el snapshot `<nombre>-stageN-complete`.

Una etapa **no está completa** hasta cumplir: documentación + tests + troubleshooting + diferencias entre versiones + snapshot.

## 🔍 Convención de verificación de datos

En las tablas de diferencias entre versiones: **✔** = confirmado en documentación oficial consultada;
**◦** = conocimiento general, *pendiente de verificar en la VM*. La matriz `comparison/matrix.generated.md`
se genera exclusivamente con datos leídos de las VMs (`lab.sh facts`).

## 🗂️ Mapa del repositorio

`scripts/` automatización (host: `lab.sh`, `0N-*.sh`; VMs: `stage2/`, `stage3/`, `stage4/`, `stage5/`, `stage6/`, `stage7/`) ·
`scripts/kickstart/` plantillas de instalación · `tests/` pruebas PASS/FAIL de solo lectura ·
`architecture/` · `rhel7/ … rhel10/` · `administration/` · `networking/` · `time/` · `security/` · `scripting/` · `automation/` ·
`troubleshooting/` · `migration/` · `comparison/` · `checklists/` · `results/` (evidencias; `facts/` se genera).

## 🔒 Seguridad

Nunca se guardan contraseñas ni tokens en el repositorio: la contraseña de las VMs se pide al crearlas (o `LAB_PASSWORD`)
y solo se inserta su hash en un kickstart temporal. El *offline token* vive en `~/.config/rhel-lab/offline_token` (modo 600).
El `sudo` sin contraseña del grupo `sysadmins` es una decisión **solo de laboratorio**.
