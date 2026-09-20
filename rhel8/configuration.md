# RHEL 8.10 — Configuración base tras la instalación

## 1. Objetivo
Dejar `rhel8-app01` registrado, actualizado y coherente con el resto del laboratorio antes de las Etapas 2-4.

## 2. Prerrequisitos
Instalación completada (`rhel8/installation.md`), acceso `ssh rhel8-app01`.

## 3. Arquitectura
Registro Red Hat (Developer Subscription) → repos → actualización → herramientas → verificación de servicios base.

## 4. Procedimiento y comandos
| Paso | Comando | Notas |
|---|---|---|
| Registro | `scripts/lab.sh register rhel8-app01 <usuario>` | La contraseña se pide en la VM, no en la línea de comandos |
| Estado | `sudo subscription-manager status` | Repos: **BaseOS** + **AppStream** (con módulos) tras registrar ◦. |
| Actualizar | `sudo dnf -y update && sudo reboot` | `dnf` (`yum` es alias) ; snapshot **antes** |
| Herramientas | `rpm -q chrony bind-utils tcpdump lvm2 xfsprogs acl` | Vienen del kickstart |
| Servicios | `systemctl is-active sshd chronyd firewalld NetworkManager` | Todos `active` |
| SELinux | `getenforce` | `Enforcing` |
| Red | `nmcli -f NAME,FILENAME con show` | Formato de perfil: Perfiles **ifcfg** por defecto ◦ (`network-scripts` en desuso) |
| Inventario | `scripts/lab.sh facts rhel8-app01` | Alimenta la matriz de comparación |

## 5. Resultado esperado y validación
`lab.sh test test_install.sh <host>` PASS; `results/facts/<host>.env` generado.

## 6. Troubleshooting
Sin repos → `packages.md` (repo local desde ISO). Reloj desfasado → errores TLS (ver `time/chrony.md`).

## 7. Errores comunes
Actualizar sin snapshot; mezclar repos de otra versión; olvidar que los cambios de red requieren `nmcli con up`.

## 8. Diferencias
Ver `rhel8/differences.md` y `comparison/matrix.md`.

## 9. Automatización
`lab.sh register`, `lab.sh facts`.

## 10. Ejercicio
Ejecuta `dnf history` tras actualizar y deshaz la última transacción en una VM con snapshot.

## 11. Criterios de aceptación
Sistema actualizado, registrado y con los servicios base activos.
