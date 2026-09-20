# Permisos: modos, bits especiales, umask y ACL

## 1. Objetivo
Controlar el acceso a ficheros con propietario/grupo/otros, **setuid/setgid/sticky**, `umask` y **ACL**, y saber
distinguir un problema de permisos clásico de uno de ACL o de SELinux.

## 2. Prerrequisitos
`users.md` hecho (grupos/usuarios existen) y `stage2/02-lvm.sh` aplicado (los puntos de montaje ya son sistemas de ficheros propios).

## 3. Arquitectura (escenario del laboratorio)
| Ruta | Propietario | Modo | Extra |
|---|---|---|---|
| `/opt/application` | appuser:application | 2750 | setgid; ACL developers r-x |
| `/opt/application/config` | root:application | 2750 | ACL developers r-x (+ por defecto) |
| `/opt/application/data` | appuser:application | 2770 | ACL developers r-x (+ por defecto); LV `lv_application` |
| `/backup` | root:backup | 3770 | setgid + sticky; LV `lv_backup` |
| `/var/log/lab-app` | appuser:application | 2770 | LV `lv_logs` |

## 4. Procedimiento manual y comandos
| Comando | Qué hace | Por qué | Salida / fallo |
|---|---|---|---|
| `ls -ld /backup` | Muestra modo y dueños | Punto de partida de cualquier diagnóstico | `drwxrws--T` = setgid (`s`) + sticky (`T`, sin `x` para otros) |
| `sudo chmod 2770 /opt/application/data` | Modo octal con setgid | El 2 inicial = setgid: los ficheros nuevos heredan el **grupo** del directorio | `stat -c %a` → 2770 |
| `sudo chmod g+s DIR` / `chmod +t DIR` | Activa setgid / sticky en simbólico | Equivalente al octal | — |
| `sudo chown appuser:application FILE` | Cambia propietario y grupo | Los dos a la vez | `Operation not permitted` si no eres root |
| `umask` / `umask 027` | Muestra/cambia la máscara | Quita permisos a ficheros nuevos (666 y 777 menos la máscara) | En RHEL, usuarios con grupo privado (UID>199) tienen 002; root y otros 022 (`/etc/profile`) |
| `sudo setfacl -m g:developers:rx DIR` | Añade una ACL de grupo | Dar acceso a un grupo **sin** cambiar propietario/grupo | `getfacl DIR` → `group:developers:r-x` |
| `sudo setfacl -m d:g:developers:rx DIR` | ACL **por defecto** | Los ficheros nuevos la heredan | `getfacl` → `default:group:developers:r-x` |
| `getfacl -p FILE` | Lista ACL | Un `+` al final de `ls -l` avisa de que hay ACL | La **máscara** limita los permisos efectivos |
| `sudo setfacl -b FILE` | Elimina todas las ACL | Limpieza | — |
| `ls -Z FILE`, `sudo restorecon -Rv DIR` | Contexto SELinux / restaurarlo | Un permiso POSIX correcto no basta si SELinux niega | `ausearch -m avc -ts recent` |

Bits especiales: **setuid** (4) en ficheros ejecutables: corre con el UID del dueño (`/usr/bin/passwd`); **setgid** (2): en ficheros, con el GID
del grupo; en **directorios**, hereda el grupo; **sticky** (1) en directorios: solo el dueño del fichero (o root) puede borrarlo (`/tmp`).
Permisos de directorio: `r` listar, `w` crear/borrar entradas, `x` **atravesar** (imprescindible en toda la ruta).

## 5. Resultado esperado y validación
`scripts/stage2/03-permissions.sh`; `scripts/lab.sh test test_permissions.sh <host>`. Comprobaciones manuales:
`su -s /bin/bash -c 'cat /opt/application/config/lab-app.env' devuser` (permitido por ACL) y
`su -s /bin/bash -c 'touch /opt/application/config/x' devuser` (denegado).

## 6. Troubleshooting (problemas deliberados)
1. **Servicio no lee su configuración**: `chmod 600 lab-app.env` (root:root). `journalctl -u lab-app` → error de lectura. Ver `troubleshooting/05-permission-denied.md`.
2. **"Permission denied" con permisos aparentemente correctos**: falta `x` en un directorio superior → `namei -l /ruta/completa`.
3. **Los ficheros nuevos no son del grupo esperado**: falta setgid en el directorio.
4. **Alguien borra ficheros ajenos en `/backup`**: falta sticky.
5. **ACL "no funciona"**: la máscara la limita (`getfacl` → `#effective:`).

## 7. Errores comunes
`chmod -R 777`; olvidar que `chmod` sobre un fichero con ACL modifica la **máscara**; mover ficheros con `mv` y creer que heredan el contexto SELinux del destino (conservan el de origen).

## 8. Diferencias RHEL 7 / 8 / 9 / 10
Semántica de permisos y ACL idéntica en las cuatro. XFS soporta ACL por defecto en todas ◦. SELinux (targeted, enforcing) es igual de determinante en las cuatro; lo que cambia es el conjunto de tipos/booleanos de la política ◦ (verificar con `sesearch`/`semanage` si hace falta).

## 9. Automatización
`scripts/stage2/03-permissions.sh` (idempotente) y `tests/test_permissions.sh`.

## 10. Ejercicio
Con snapshot previo: (a) quita `x` a `/opt/application` y observa qué falla y por qué; (b) crea `/opt/application/data/informe.txt` como appuser y comprueba que el grupo es `application`;
(c) borra el setgid y repite; (d) intenta que backupuser borre un fichero creado por root en `/backup` (sticky); (e) usa `getfacl` para explicar la máscara tras `chmod 640` sobre un fichero con ACL.

## 11. Criterios de aceptación
`test_permissions.sh` PASS; sabes resolver los 5 problemas de la sección 6 en menos de 5 minutos cada uno.
