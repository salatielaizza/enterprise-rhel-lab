# RHEL 10.2 — Instalación

## 1. Objetivo
Instalar **RHEL 10.2** (`rhel10-app01`) de forma reproducible con kickstart y dejar la VM lista para la Etapa 2.

## 2. Prerrequisitos
- Host preparado (`lab.sh host-setup`, `lab.sh network`) y la ISO descargada y verificada (`lab.sh iso --only 10`).
- Recursos: 3 GB de RAM, disco de sistema 20 GB (+ 10 GB de datos en los `app01`). CPU del host con x86-64-v3.

## 3. Arquitectura / decisiones de instalación
| Decisión | Valor | Motivo |
|---|---|---|
| ISO | `rhel-10.2-x86_64-dvd.iso` (10,3 GB) | DVD completo: permite repo local sin red |
| SHA-256 | `e15cb333529c332e76e4b1b946efe3515c99f996546675aec18e8effdf2540a5` | Verificado por `download-isos.sh` (valor del portal de Red Hat) |
| Método | Kickstart (`scripts/kickstart/rhel10.ks.tpl`) + `virt-install --location` | Repetible |
| Idioma / teclado / zona | `en_US.UTF-8` / `es` / `Europe/Madrid` (`LAB_TZ`) | Mensajes en inglés = fáciles de buscar |
| Firmware / CPU | BIOS (SeaBIOS) / `host-passthrough` | Simplicidad; requisito de RHEL 10 |
| Disco `vda` (20 GB) | `/boot` 1 GiB XFS + LVM `vg_system`: `lv_root` 8 GiB, `lv_swap` 2 GiB, `lv_var` 4 GiB (XFS) | Espacio libre en el VG (~5 GiB) para ejercicios |
| Disco `vdb` (10 GB) | Sin tocar | Lo usa la Etapa 2 (LVM) |
| Hostname / red | `rhel10-app01.lab.local`, IP 10.10.10.14/24, gw 10.10.10.1, DNS 10.10.10.1 (arranque) | Ver `architecture/` |
| Usuarios | `adminlab` (UID 1001, wheel) + clave SSH; `root` con contraseña (modo emergencia); ambas se piden al crear la VM | Sin secretos en el repo |
| SELinux / firewall | Enforcing / firewalld activo con `ssh` | Punto de partida enterprise |
| Paquetes | `@^minimal-environment` + herramientas de administración y diagnóstico | Ver la sección `%packages` del kickstart |
| Servicios | sshd, chronyd, qemu-guest-agent | — |

## 4. Procedimiento (automatizado)
```bash
scripts/lab.sh vm-create rhel10-app01 --dry-run   # revisa el comando y /tmp/rhel10-app01.dryrun.ks
scripts/lab.sh vm-create rhel10-app01             # pide la contraseña; instala; espera al SSH
scripts/lab.sh register rhel10-app01 <usuario-Red-Hat>
scripts/lab.sh test test_install.sh rhel10-app01
scripts/lab.sh snapshot create rhel10-app01 1      # rhel10-stage1-complete
```
Seguir el progreso: `virsh console rhel10-app01` (salir con `Ctrl+]`).

## 5. Procedimiento manual equivalente (para aprender Anaconda)
`virt-manager` → nueva VM desde ISO, 2 vCPU, RAM 3 GB, disco 20 GB virtio, red `lab-net`; en el instalador: idioma inglés, teclado español, zona horaria, destino **personalizado** (LVM, XFS, layout de la tabla), red con IP estática, contraseña de root, usuario `adminlab` como administrador, SELinux por defecto. Cada línea del kickstart corresponde a una de estas pantallas.

## 6. Validación
`lab.sh test test_install.sh <host>` (versión, SELinux, firewalld, sshd, LVM, XFS, swap, adminlab) y a mano: `cat /etc/redhat-release; uname -r; lsblk -f; getenforce; firewall-cmd --list-all`.

## 7. Troubleshooting de la instalación
- `virt-install` no encuentra la ISO o falla por permisos → la ISO debe estar en `/var/lib/libvirt/lab/isos` (no en `$HOME`).
- Anaconda dice que no encuentra el medio → añade `inst.repo=cdrom` a `--extra-args` (comprobar con `virsh console`).
- La VM no arranca tras borrar la ISO → `virsh domblklist <vm> --details`; el script expulsa la ISO al terminar (`change-media --eject`).
- SSH no responde tras instalar → `virsh console`, revisar `/root/ks-post.log`, IP/gateway (`ip a`), firewall.
- Error de `ksvalidator`/paquetes → `%packages --ignoremissing` omite los ausentes: comprueba qué falta con `rpm -q <paquete>`.

## 8. Diferencias específicas de 10
- Exige CPU **x86-64-v3** ✔ → la VM usa `--cpu host-passthrough` (el modelo QEMU por defecto no lo cumple).
- Las opciones `inst.vnc*` del instalador se sustituyen por **`inst.rdp`** ✔ (no afecta: instalamos por consola serie).
- `--os-variant`: el osinfo-db de Ubuntu 24.04 puede no conocer RHEL 10; `02-create-vm.sh` prueba `rhel10.x` y recurre a `rhel9-unknown`/`generic`.
- Red: **ifcfg eliminado**: solo keyfile ✔; **`dhclient` eliminado** ✔ (NetworkManager usa su cliente interno).
- Repositorios: BaseOS + AppStream tras registrar (o repo local desde la ISO).
- Soporte: Versión más reciente; útil para descubrir cambios antes de migrar.

## 9. Automatización futura
Ansible (Etapa 7) sustituirá los scripts de post-instalación; el kickstart se mantiene como base de aprovisionamiento.

## 10. Ejercicio
Instala una VM extra manualmente con Anaconda y compara `anaconda-ks.cfg` (`/root/anaconda-ks.cfg`) con el kickstart del repositorio.

## 11. Criterios de aceptación
`test_install.sh` PASS; snapshot `rhel10-stage1-complete`; puedes explicar cada línea del kickstart.
