# Usuarios y grupos

## 1. Objetivo
Crear, modificar y auditar usuarios y grupos; entender `/etc/passwd`, `/etc/group`, `/etc/shadow`, `/etc/gshadow`,
`/etc/login.defs` y `chage`; mantener **UID/GID idénticos en todos los hosts**.

## 2. Prerrequisitos
VM instalada (Etapa 1), acceso como `adminlab` con sudo, snapshot `…-stage1-complete`.

## 3. Arquitectura
Grupos: sysadmins 2001, developers 2002, application 2003, backup 2004. Usuarios: adminlab 1001, devuser 1002,
appuser 1003, backupuser 1004 (ver `architecture/hosts.md`). Los IDs fijos evitan que un fichero "pertenezca" a
usuarios distintos según el host (crítico en NFS, Etapa 12, y LDAP, Etapa 13).

## 4. Procedimiento manual y comandos
| Comando | Qué hace | Por qué | Salida esperada / si falla |
|---|---|---|---|
| `sudo groupadd -g 2002 developers` | Crea el grupo con GID fijo | GID igual en todos los hosts | Sin salida. `groupadd: GID '2002' already exists` → GID ocupado (`getent group 2002`) |
| `sudo useradd -m -u 1002 -g developers -s /bin/bash devuser` | Crea usuario, home y grupo primario | UID fijo y home con `/etc/skel` | Sin salida. `useradd: UID 1002 is not unique` → elige otro o revisa `getent passwd 1002` |
| `sudo usermod -aG sysadmins adminlab` | **Añade** un grupo secundario | `-a` es imprescindible | `id adminlab` muestra el grupo. Sin `-a` se **sustituyen** todos los secundarios (adminlab perdería `wheel`) |
| `sudo passwd devuser` | Define la contraseña | Las cuentas nuevas del lab están bloqueadas | "passwd: all authentication tokens updated successfully" |
| `sudo usermod -L devuser` / `-U` | Bloquea / desbloquea (antepone `!` en shadow) | Cierre temporal de acceso | `passwd -S devuser` → `LK` (locked) / `PS` |
| `sudo chage -M 90 -m 1 -W 7 devuser` | Caducidad máx. 90 días, mín. 1, aviso 7 | Política de contraseñas | `sudo chage -l devuser` lista los valores |
| `sudo chage -d 0 devuser` | Fuerza cambiar la contraseña en el próximo login | Alta de usuario nuevo | Al entrar pide nueva contraseña |
| `id devuser`, `groups devuser`, `getent passwd devuser` | Consultan identidad (incluye LDAP/SSSD futuro) | Preferir `getent` a `grep /etc/passwd` | UID, GID y grupos coherentes |
| `sudo pwck -r` / `sudo grpck -r` | Verifican consistencia de ficheros de cuentas | Detectar entradas huérfanas | Sin salida = correcto |
| `sudo userdel -r olduser` | Borra usuario y home | Baja de personal | Ficheros sueltos: `find / -xdev -nouser` |

Anatomía: `/etc/passwd` = `nombre:x:UID:GID:comentario:home:shell`. `/etc/shadow` = `nombre:hash:último_cambio:mín:máx:aviso:inactividad:caducidad:` (modo 000 en RHEL; solo root lo lee vía capacidades del sistema).
Un hash que empieza por `!` o `*` = no se puede iniciar sesión con contraseña.

## 5. Resultado esperado y validación
`scripts/lab.sh stage2 <host>` y `scripts/lab.sh test test_users.sh <host>` → todo PASS.

## 6. Troubleshooting
- *"user X is currently used by process"* al borrar: `pgrep -u X`, `pkill -u X`.
- Un usuario "perdió" grupos: se usó `usermod -G` o `-aG` sin `-a`; restaurar con `usermod -aG grupo1,grupo2 usuario`.
- Ficheros con propietario numérico tras `userdel`: `find / -xdev -nouser -ls`.

## 7. Errores comunes
Olvidar `-a`; crear el mismo usuario con UID distinto en cada host; editar `/etc/passwd` a mano sin `vipw`; dejar cuentas de servicio con shell interactiva y contraseña.

## 8. Diferencias RHEL 7 / 8 / 9 / 10
- Comandos idénticos (shadow-utils). El intervalo de UID de usuarios normales empieza en 1000 (`UID_MIN` en `/etc/login.defs`) ◦.
- Configuración de autenticación: `authconfig` (7) → `authselect` (8+) ◦.
- Algoritmo de hash por defecto y `CREATE_HOME`: comprobar en cada VM con `grep -E 'ENCRYPT_METHOD|CREATE_HOME' /etc/login.defs` y anotar (◦ pendiente).

## 9. Automatización
`scripts/stage2/01-users-groups.sh` (idempotente; usa `usermod -aG`; cuentas nuevas bloqueadas).

## 10. Ejercicio
1. Crea `tempuser` (UID 1500) con caducidad a 7 días (`chage -E $(date -d '+7 days' +%F)`), bloquéalo, desbloquéalo y bórralo.
2. Rompe a propósito los grupos de adminlab con `usermod -G developers adminlab` **en una VM con snapshot**, entra por consola y repáralo.
3. Crea un fichero como devuser, borra a devuser **sin** `-r` y localiza el fichero huérfano.

## 11. Criterios de aceptación
`test_users.sh` PASS en los 4 hosts; sabes explicar por qué los UID son fijos y qué ocurre sin `-a`.
