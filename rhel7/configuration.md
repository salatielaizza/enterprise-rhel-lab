# RHEL 7.9 — Configuración base tras la instalación

## 1. Objetivo
Dejar `rhel7-app01` registrado, actualizado y coherente con el resto del laboratorio antes de las Etapas 2-4.

## 2. Prerrequisitos
Instalación completada (`rhel7/installation.md`), acceso `ssh rhel7-app01`.

## 3. Arquitectura
Registro Red Hat (Developer Subscription) → repos → actualización → herramientas → verificación de servicios base.

## 4. Procedimiento y comandos
| Paso | Comando | Notas |
|---|---|---|
| Registro | `scripts/lab.sh register rhel7-app01 <usuario>` | La contraseña se pide en la VM, no en la línea de comandos |
| Estado | `sudo subscription-manager status` | Repos: Repos separados por canal (`rhel-7-server-rpms`, `-extras-rpms`, `-optional-rpms`); tras registrar puede ser necesario `subscription-manager repos --enable rhel-7-server-rpms` ◦. |
| Actualizar | `sudo yum -y update && sudo reboot` | `yum` ; snapshot **antes** |
| Herramientas | `rpm -q chrony bind-utils tcpdump lvm2 xfsprogs acl` | Vienen del kickstart |
| Servicios | `systemctl is-active sshd chronyd firewalld NetworkManager` | Todos `active` |
| SELinux | `getenforce` | `Enforcing` |
| Red | `nmcli -f NAME,FILENAME con show` | Formato de perfil: Perfiles **ifcfg** (`/etc/sysconfig/network-scripts/`) gestionados por NetworkManager |
| Inventario | `scripts/lab.sh facts rhel7-app01` | Alimenta la matriz de comparación |

## 5. Resultado esperado y validación
`lab.sh test test_install.sh <host>` PASS; `results/facts/<host>.env` generado.

## 6. Troubleshooting
Sin repos → `packages.md` (repo local desde ISO). Reloj desfasado → errores TLS (ver `time/chrony.md`).

## 7. Errores comunes
Actualizar sin snapshot; mezclar repos de otra versión; olvidar que RHEL 7 está fuera de mantenimiento estándar.

## 8. Diferencias
Ver `rhel7/differences.md` y `comparison/matrix.md`.

## 9. Automatización
`lab.sh register`, `lab.sh facts`.

## 10. Ejercicio
Ejecuta `yum history` tras actualizar y deshaz la última transacción en una VM con snapshot.

## 11. Criterios de aceptación
Sistema actualizado, registrado y con los servicios base activos.
