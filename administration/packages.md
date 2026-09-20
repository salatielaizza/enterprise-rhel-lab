# Paquetes: rpm, yum/dnf, repositorios y suscripción

## 1. Objetivo
Instalar, consultar y verificar software; entender repositorios y suscripciones Red Hat; montar un **repositorio local desde la ISO**.

## 2. Prerrequisitos
VM instalada. Para repos en línea: `scripts/lab.sh register <host> <usuario-RH>` (Developer Subscription). Para repo local: ISO en `/var/lib/libvirt/lab/isos`.

## 3. Arquitectura
`rpm` = base de datos y paquetes individuales. `yum` (7) / `dnf` (8+) = resolución de dependencias sobre repositorios.
RHEL 8+ divide el contenido en **BaseOS** (sistema) y **AppStream** (aplicaciones, con *módulos*); RHEL 7 usa repos únicos (`rhel-7-server-rpms`, …) ◦.

## 4. Procedimiento manual y comandos
| Comando | Qué hace | Por qué | Salida / fallo |
|---|---|---|---|
| `rpm -qa \| sort`, `rpm -qi bind`, `rpm -ql bind`, `rpm -qf /etc/named.conf` | Inventario / info / ficheros / dueño de un fichero | Saber qué paquete trae qué | `not owned by any package` → fichero manual |
| `rpm -V openssh-server` | Verifica ficheros contra la BD | Detecta cambios (S=tamaño, 5=hash, M=modo…) | `c` marca ficheros de configuración |
| `rpm -q --scripts pkg`, `rpm -qa --last` | Scripts del paquete / últimos instalados | Auditoría | — |
| `sudo subscription-manager register --username USUARIO` | Registra el sistema | Sin registro no hay repos oficiales | `Status: Simple Content Access` o similar |
| `subscription-manager status`, `sudo subscription-manager repos --list-enabled` | Estado / repos activos | Diagnóstico | RHEL 7: puede ser necesario `--enable rhel-7-server-rpms` ◦ |
| `sudo dnf install -y pkg` (7: `yum`) | Instala con dependencias | — | `Error: Unable to find a match` → repo/nombre |
| `dnf repolist`, `dnf info pkg`, `dnf provides '*/dig'`, `dnf search kw` | Consultas | Encontrar paquetes | — |
| `sudo dnf update` / `dnf check-update` / `dnf updateinfo list security` | Actualizar / ver pendientes / avisos de seguridad | Parcheo | — |
| `dnf history`, `sudo dnf history undo N` | Historial y reversión de transacciones | Rollback | `yum history` en 7 |
| `dnf module list`, `dnf module enable\|install nodejs:20` | Módulos (solo 8+) | Varias versiones de una app | No existe en RHEL 7 |
| `sudo dnf install dnf-utils` → `needs-restarting -r`, `yumdownloader` | Utilidades | ¿Hace falta reiniciar? | 7: paquete `yum-utils` |
| `sudo dnf config-manager --disable REPO` | Activa/desactiva repos | Aislar problemas | 7: `yum-config-manager` |

### Repositorio local desde la ISO (sin suscripción)
```bash
# En el host: adjuntar la ISO a la VM (no borres la ISO mientras esté adjunta)
virsh attach-disk rhel9-app01 /var/lib/libvirt/lab/isos/rhel-9.8-x86_64-dvd.iso sda --type cdrom --mode readonly --config --live
# En la VM (8/9/10):
sudo mkdir -p /mnt/dvd && sudo mount -o ro /dev/sr0 /mnt/dvd
sudo tee /etc/yum.repos.d/dvd.repo <<'EOR'
[dvd-baseos]
name=DVD BaseOS
baseurl=file:///mnt/dvd/BaseOS
enabled=1
gpgcheck=1
gpgkey=file:///mnt/dvd/RPM-GPG-KEY-redhat-release
[dvd-appstream]
name=DVD AppStream
baseurl=file:///mnt/dvd/AppStream
enabled=1
gpgcheck=1
gpgkey=file:///mnt/dvd/RPM-GPG-KEY-redhat-release
EOR
# RHEL 7: un solo repo con baseurl=file:///mnt/dvd
```
(El nombre del dispositivo `/dev/sr0` puede variar: `lsblk`.)

## 5. Resultado esperado y validación
`dnf repolist` muestra repos; `dnf install -y tree` funciona; `rpm -V` de un paquete sin cambios no imprime nada.

## 6. Troubleshooting
`This system is not registered` → registrar; `Cannot find a valid baseurl` → red/DNS (`ping cdn.redhat.com`, `getent hosts`); GPG error → falta la clave (`rpm --import`); reloj desfasado rompe TLS (ver `time/chrony.md`).

## 7. Errores comunes
Mezclar repos de otra versión mayor; `--nogpgcheck` como hábito; instalar con `rpm -i` ignorando dependencias; borrar la ISO adjunta.

## 8. Diferencias RHEL 7 / 8 / 9 / 10
`yum` 3.x (7) → `dnf` (8+; `yum` es alias) ◦; módulos y AppStream desde 8 ◦; archivo de log `/var/log/yum.log` (7) vs `/var/log/dnf.log` (8+) ◦; paquete `yum-utils`/`dnf-utils` ◦. En RHEL 10 confirmar la versión de dnf con `dnf --version` (◦ pendiente).

## 9. Automatización
`lab.sh register`; los scripts de Etapa 4 instalan `bind` y `chrony` con `dnf`/`yum`.

## 10. Ejercicio
Monta el repo local en rhel8-app01, instala `tree`; compara `dnf history` con `yum history` en rhel7-app01; verifica un paquete con `rpm -V` tras editar su config; deshaz una instalación con `history undo`.

## 11. Criterios de aceptación
Instalas y verificas paquetes con y sin suscripción, y explicas BaseOS/AppStream.
