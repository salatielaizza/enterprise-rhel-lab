# 🧪 Enterprise RHEL Infrastructure Lab

Laboratorio para **comparar RHEL 7, 8, 9 y 10** y practicar administración empresarial sobre KVM/libvirt.
El plan cubre las **Etapas 1-4** (instalación, administración Linux, networking, servicios enterprise
básicos); por ahora la Etapa 1 está **completa** y la Etapa 2 **en operación** (ejecutada en las 6 VMs,
con algunos `FAIL` de test aún en investigación); las Etapas 3 y 4 siguen **planificadas**. Regla del
proyecto: *manual → documentado → repetible → automatizado*.

## 🗺️ Estado del proyecto y hoja de ruta

Este repositorio cubre hoy las **Etapas 1 y 2** de un plan de **19 etapas** (Etapa 1 completa, Etapa 2
en operación con validación en curso). Las Etapas 3 y 4 ya tienen su automatización y documentación
escritas, pero siguen **planificadas**, pendientes de ejecutar; las Etapas 5-19 están planificadas pero
**no empezadas** — este es un proyecto vivo, no cerrado.

| Etapa | Contenido | Estado |
|---|---|---|
| 1 | 💿 Instalación (RHEL 7/8/9/10, kickstart, KVM/libvirt) | ✅ Completa |
| 2 | 👥 Administración Linux (usuarios, permisos, sudo, systemd, LVM, paquetes, logs) | 🟡 En operación |
| 3 | 🌐 Networking (NetworkManager, diagnóstico por capas) | ⏳ Planificada |
| 4 | 🔐 Servicios enterprise (DNS/BIND, hora/chrony, SSH/SFTP) | ⏳ Planificada |
| 5 | 🛡️ Seguridad (SELinux avanzado, auditoría, hardening) | ⏳ Planificada |
| 6 | 📜 Bash avanzado y scripting | ⏳ Planificada |
| 7 | 🤖 Ansible (automatización, inventario, roles) | ⏳ Planificada |
| 8 | 🔀 Git / Infraestructura como código | ⏳ Planificada |
| 9 | 🧭 NGINX (proxy inverso, balanceo) | ⏳ Planificada |
| 10 | 🚚 Migraciones entre versiones (Leapp) | ⏳ Planificada |
| 11 | 🛰️ Red Hat Satellite | ⏳ Planificada |
| 12 | 🗄️ NFS / CIFS (almacenamiento compartido) | ⏳ Planificada |
| 13 | 🔑 LDAP / Kerberos (identidad centralizada) | ⏳ Planificada |
| 14 | ⚖️ Alta disponibilidad (Pacemaker/Corosync) | ⏳ Planificada |
| 15 | 📊 Monitorización (Prometheus/Grafana) | ⏳ Planificada |
| 16 | 📦 Contenedores (Podman) | ⏳ Planificada |
| 17 | ☸️ Kubernetes | ⏳ Planificada |
| 18 | 🔴 OpenShift | ⏳ Planificada |
| 19 | 🔁 CI/CD | ⏳ Planificada |

Los nombres de host, IPs, UID/GID y la estructura de directorios ya fijados en las Etapas 1-4
(ver `architecture/hosts.md`) se mantienen estables para las etapas futuras — por ejemplo,
`ansible01` (10.10.10.30) ya está reservada para la Etapa 7, y `rhel9-web01`/`rhel9-monitor01`
(10.10.10.40/.50) para las etapas 9 y 15.

## 🔧 Contenido de las Etapas 1-4 (automatización y documentación ya escritas)

| Etapa | Contenido | Automatización | Documentación |
|---|---|---|---|
| 💿 1 | Instalación de RHEL 7/8/9/10 (+ dns01, ansible01) | `lab.sh host-setup/network/iso/vm-create/register/snapshot` | `rhelN/installation.md`, `checklists/etapa1.md` |
| 👥 2 | Usuarios, permisos, sudo, systemd, LVM/XFS, paquetes, logs | `lab.sh stage2` | `administration/*.md` |
| 🌐 3 | NetworkManager, IP/gateway/DNS/hostname, diagnóstico | `lab.sh stage3` | `networking/networkmanager.md`, `networking/troubleshooting.md` |
| 🔐 4 | BIND (DNS), chrony (hora), SSH/SFTP | `lab.sh stage4-dns`, `stage4-clients` | `networking/dns.md`, `time/chrony.md`, `networking/ssh.md` |

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

`scripts/` automatización (host: `lab.sh`, `0N-*.sh`; VMs: `stage2/`, `stage3/`, `stage4/`) ·
`scripts/kickstart/` plantillas de instalación · `tests/` pruebas PASS/FAIL de solo lectura ·
`architecture/` · `rhel7/ … rhel10/` · `administration/` · `networking/` · `time/` · `troubleshooting/` ·
`migration/` · `comparison/` · `checklists/` · `results/` (evidencias; `facts/` se genera).

## 🔒 Seguridad

Nunca se guardan contraseñas ni tokens en el repositorio: la contraseña de las VMs se pide al crearlas (o `LAB_PASSWORD`)
y solo se inserta su hash en un kickstart temporal. El *offline token* vive en `~/.config/rhel-lab/offline_token` (modo 600).
El `sudo` sin contraseña del grupo `sysadmins` es una decisión **solo de laboratorio**.
