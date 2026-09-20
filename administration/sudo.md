# sudo y separación de privilegios

## 1. Objetivo
Delegar privilegios con el **mínimo necesario**: editar sudoers de forma segura, usar `sudoers.d`, alias de comandos,
y auditar quién ejecutó qué.

## 2. Prerrequisitos
Usuarios y grupos de `users.md`; una consola de recuperación (`virsh console`) por si te bloqueas.

## 3. Arquitectura
| Fichero (`/etc/sudoers.d/`) | Grupo | Permite |
|---|---|---|
| `10-sysadmins` | sysadmins | Todo, sin contraseña (**solo laboratorio**) |
| `20-developers` | developers | `systemctl status/start/stop/restart lab-app` y `journalctl -u lab-app` (comandos exactos) |
| `30-backup` | backup | Solo `/usr/local/sbin/lab-backup.sh` |
El sudo de arranque del kickstart (`90-adminlab-bootstrap`) se elimina al terminar la Etapa 2.

## 4. Procedimiento manual y comandos
| Comando | Qué hace | Por qué | Salida / fallo |
|---|---|---|---|
| `sudo visudo` | Edita `/etc/sudoers` con bloqueo y validación | Un error de sintaxis puede dejarte sin sudo | Si hay error ofrece reeditar (`e`), salir (`x`) o forzar (`Q`, **no**) |
| `sudo visudo -f /etc/sudoers.d/20-developers` | Edita un fichero de `sudoers.d` con validación | Un fichero por perfil | — |
| `visudo -cf FICHERO` | Valida un fichero sin instalarlo | Patrón de los scripts: validar en temporal y luego `install -m 0440` | "parsed OK" |
| `sudo -l` / `sudo -l -U devuser` | Lista qué puede ejecutar el usuario | Auditoría de perfiles | Debe mostrar solo los comandos delegados |
| `sudo -ll` | Formato largo (con runas, tags) | Depuración | — |
| `sudo -k` | Olvida el ticket de sudo | Probar que pide contraseña | — |
| `sudo journalctl _COMM=sudo` / `sudo grep sudo /var/log/secure` | Auditoría | Quién ejecutó qué | Cada ejecución queda registrada (authpriv) |

Sintaxis: `quien  donde=(como_quien)  [TAG:] comandos`. Ejemplo: `%developers ALL=(root) NOPASSWD: DEV_SERVICE`.
Reglas: los ficheros de `sudoers.d` con `.` o `~` en el nombre **se ignoran**; deben ser 0440 root:root; el último match gana.

## 5. Resultado esperado y validación
`scripts/lab.sh stage2 <host>`; `scripts/lab.sh test test_users.sh <host>`. Manual: como devuser, `sudo systemctl restart lab-app` funciona y `sudo systemctl restart sshd` pide contraseña/deniega.

## 6. Troubleshooting
- *"sudo: unable to resolve host"*: el hostname no resuelve (ver `networking/troubleshooting.md`).
- *"user is not in the sudoers file"*: falta el grupo (`id`) o el fichero está mal nombrado (`ls /etc/sudoers.d`).
- Sudoers roto y sin acceso: entrar por `virsh console` como root (por eso el kickstart fija contraseña de root) y corregir con `visudo`.

## 7. Errores comunes
Comodines (`*`) en argumentos (permiten inyectar opciones); dar `rsync`, `tar`, `vim`, `less`, `find` con sudo (son equivalentes a root: escapan a shell); `NOPASSWD: ALL` a grupos amplios; editar sudoers con un editor normal.

## 8. Diferencias RHEL 7 / 8 / 9 / 10
Sintaxis compatible en las cuatro. Versiones de sudo distintas (comprobar con `sudo -V | head -1`) ◦; la directiva `@includedir` (1.9.1+) frente a `#includedir` puede variar según versión ◦.

## 9. Automatización
`scripts/stage2/04-sudo.sh`: valida con `visudo -cf` **antes** de instalar y no elimina el sudo de arranque si adminlab no está en `sysadmins`.

## 10. Ejercicio
1. Como sysadmin añade a `20-developers` el permiso `journalctl -u lab-app *` y razona por qué el comodín es un riesgo.
2. Escribe un sudoers **inválido** en un temporal y comprueba que `visudo -cf` lo rechaza.
3. Como backupuser ejecuta el script y verifica el registro en `/var/log/secure`.

## 11. Criterios de aceptación
Los tres perfiles funcionan; sabes explicar por qué `sudo rsync` ≠ least privilege.
