# RHEL 7.9 — Instalación

## 1. Objetivo
Instalar **RHEL 7.9** (`rhel7-app01`) de forma reproducible con kickstart y dejar la VM lista para la Etapa 2.

## 2. Prerrequisitos
- Host preparado (`lab.sh host-setup`, `lab.sh network`) y la ISO descargada y verificada (`lab.sh iso --only 7`).
- Recursos: 2 GB de RAM, disco de sistema 20 GB (+ 10 GB de datos en los `app01`). 

## 3. Arquitectura / decisiones de instalación
| Decisión | Valor | Motivo |
|---|---|---|
| ISO | `rhel-server-7.9-x86_64-dvd.iso` (4,21 GB) | DVD completo: permite repo local sin red |
| SHA-256 | `e373d3efe1a6e3f6d6de105d32c2632ee661363d6fe0c24285379b85f99437cb` | Verificado por `download-isos.sh` (valor del portal de Red Hat) |
| Método | Kickstart (`scripts/kickstart/rhel7.ks.tpl`) + `virt-install --location` | Repetible |
| Idioma / teclado / zona | `en_US.UTF-8` / `es` / `Europe/Madrid` (`LAB_TZ`) | Mensajes en inglés = fáciles de buscar |
| Firmware / CPU | BIOS (SeaBIOS) / `host-passthrough` | Simplicidad; requisito de RHEL 10 |
| Disco `vda` (20 GB) | `/boot` 1 GiB XFS + LVM `vg_system`: `lv_root` 8 GiB, `lv_swap` 2 GiB, `lv_var` 4 GiB (XFS) | Espacio libre en el VG (~5 GiB) para ejercicios |
| Disco `vdb` (10 GB) | Sin tocar | Lo usa la Etapa 2 (LVM) |
| Hostname / red | `rhel7-app01.lab.local`, IP 10.10.10.11/24, gw 10.10.10.1, DNS 10.10.10.1 (arranque) | Ver `architecture/` |
| Usuarios | `adminlab` (UID 1001, wheel) + clave SSH; `root` con contraseña (modo emergencia); ambas se piden al crear la VM | Sin secretos en el repo |
| SELinux / firewall | Enforcing / firewalld activo con `ssh` | Punto de partida enterprise |
| Paquetes | `@core` + herramientas de administración y diagnóstico | Ver la sección `%packages` del kickstart |
| Servicios | sshd, chronyd, qemu-guest-agent | — |

## 4. Procedimiento (automatizado)
```bash
scripts/lab.sh vm-create rhel7-app01 --dry-run   # revisa el comando y /tmp/rhel7-app01.dryrun.ks
scripts/lab.sh vm-create rhel7-app01             # pide la contraseña; instala; espera al SSH
scripts/lab.sh register rhel7-app01 <usuario-Red-Hat>
scripts/lab.sh test test_install.sh rhel7-app01
scripts/lab.sh snapshot create rhel7-app01 1      # rhel7-stage1-complete
```
Seguir el progreso: `virsh console rhel7-app01` (salir con `Ctrl+]`).

## 5. Procedimiento manual equivalente (para aprender Anaconda)
`virt-manager` → nueva VM desde ISO, 2 vCPU, RAM 2 GB, disco 20 GB virtio, red `lab-net`; en el instalador: idioma inglés, teclado español, zona horaria, destino **personalizado** (LVM, XFS, layout de la tabla), red con IP estática, contraseña de root, usuario `adminlab` como administrador, SELinux por defecto. Cada línea del kickstart corresponde a una de estas pantallas.

## 6. Validación
`lab.sh test test_install.sh <host>` (versión, SELinux, firewalld, sshd, LVM, XFS, swap, adminlab) y a mano: `cat /etc/redhat-release; uname -r; lsblk -f; getenforce; firewall-cmd --list-all`.

## 7. Troubleshooting de la instalación
- `virt-install` no encuentra la ISO o falla por permisos → la ISO debe estar en `/var/lib/libvirt/lab/isos` (no en `$HOME`).
- Anaconda dice que no encuentra el medio → añade `inst.repo=cdrom` a `--extra-args` (comprobar con `virsh console`).
- La VM no arranca tras borrar la ISO → `virsh domblklist <vm> --details`; el script expulsa la ISO al terminar (`change-media --eject`).
- SSH no responde tras instalar → `virsh console`, revisar `/root/ks-post.log`, IP/gateway (`ip a`), firewall.
- Error de `ksvalidator`/paquetes → `%packages --ignoremissing` omite los ausentes: comprueba qué falta con `rpm -q <paquete>`.

## 8. Diferencias específicas de 7
- Comandos `install` y `auth --enableshadow --passalgo=sha512` (desaparecen en RHEL 8+).
- `keyboard --vckeymap=es --xlayouts='es'`; `timezone … --utc`.
- Anaconda solo admite instalación de texto muy limitada: todo se decide en el kickstart.
- Grupo de paquetes mínimo: `@core`.
- Red: Perfiles **ifcfg** (`/etc/sysconfig/network-scripts/`) gestionados por NetworkManager; existe además el servicio heredado `network`.
- Repositorios: Repos separados por canal (`rhel-7-server-rpms`, `-extras-rpms`, `-optional-rpms`); tras registrar puede ser necesario `subscription-manager repos --enable rhel-7-server-rpms` ◦.
- Soporte: RHEL 7 salió del mantenimiento estándar el 30-jun-2024; solo recibe parches con el complemento ELS de pago ◦. Úsala como **caso de migración**, no como destino.

## 9. Automatización futura
Ansible (Etapa 7) sustituirá los scripts de post-instalación; el kickstart se mantiene como base de aprovisionamiento.

## 10. Ejercicio
Instala una VM extra manualmente con Anaconda y compara `anaconda-ks.cfg` (`/root/anaconda-ks.cfg`) con el kickstart del repositorio.

## 11. Criterios de aceptación
`test_install.sh` PASS; snapshot `rhel7-stage1-complete`; puedes explicar cada línea del kickstart.
