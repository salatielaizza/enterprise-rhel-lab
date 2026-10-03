# 👥 Troubleshooting y guía de estudio — Etapa 2 (administración Linux)

Ver formato y regla general en [`troubleshooting/README.md`](../README.md).

Este documento tiene dos usos:

1. **Índice de los casos reales** de troubleshooting de la Etapa 2.
2. **Base de estudio**: todos los comandos que usan los scripts y los tests de esta etapa, con
   una explicación sencilla de qué hace cada uno y para qué sirve al diagnosticar.

> Regla del proyecto: *manual → documentado → repetible → automatizado*. Cada comando de esta
> guía se puede lanzar a mano dentro de una VM (como root); los scripts solo los encadenan.

---

## 1. Casos documentados

| Caso | Tema |
|---|---|
| [01 service-down](01-service-down.md) | Servicio parado (sshd) y servicio que se cae (lab-app) |
| [02 bad-fstab](02-bad-fstab.md) | fstab con UUID erróneo → modo emergencia |
| [03 permission-denied](03-permission-denied.md) | ACL/permisos: acceso denegado |
| [04 selinux-denial](04-selinux-denial.md) | Etiqueta SELinux incorrecta → 203/EXEC |
| [05 findmnt-multiple-args-exit1](05-findmnt-multiple-args-exit1.md) 🔎 | `stage2/02-lvm.sh` se detiene tras "Montajes:": `findmnt` con varias rutas devuelve 1 |
| [06 ausearch-colgado-timeout](06-ausearch-colgado-timeout.md) 🔎 | `test_services.sh` se cuelga indefinidamente: `ausearch` sin responder |
| [07 acl-heredada-lab-app-env-modo-650](07-acl-heredada-lab-app-env-modo-650.md) 🔎 | `lab-app.env` queda en 650 en vez de 640: ACL heredada del directorio config |
| [08 pwck-usuario-ftp-var-ftp-inexistente](08-pwck-usuario-ftp-var-ftp-inexistente.md) 🔎 | `pwck`: usuario `ftp` sin `/var/ftp` (solo RHEL 7) |
| [09 journalctl-u-no-encuentra-lab-app-rhel8](09-journalctl-u-no-encuentra-lab-app-rhel8.md) 🔎 | `journalctl -u` no encuentra heartbeats en RHEL 8; usar `-t` |

🔎 = encontrado de forma orgánica al ejecutar contra las VMs reales.

Nota: el caso 01 (`service-down`) también se apoya en habilidades de la Etapa 3 (diagnóstico de red
antes de descartar firewall); el caso 06 (`ausearch-colgado-timeout`) apareció encadenado detrás de
[etapa3/06](../etapa3/06-ssh-lento-usedns-fqdn-inexistente.md).

---

## 2. Flujo de la etapa (orden exacto)

| # | Comando | Script que ejecuta | Dónde corre |
|---|---|---|---|
| 1 | `scripts/lab.sh stage2 <host\|all>` | `stage2/01-users-groups.sh` | VM (root vía `sudo -n`) |
| 2 | (mismo comando) | `stage2/02-lvm.sh` | VM |
| 3 | (mismo comando) | `stage2/03-permissions.sh` | VM |
| 4 | (mismo comando) | `stage2/04-sudo.sh` | VM |
| 5 | (mismo comando) | `stage2/05-systemd-app.sh` | VM |
| 6 | `scripts/lab.sh test all <host\|all>` | `tests/run_all.sh` → `test_users`, `test_permissions`, `test_storage`, `test_services` | VM |
| 7 | `scripts/lab.sh snapshot create <host> 2` | `scripts/03-snapshot.sh` | Host |

`lab.sh stage2` primero copia los scripts a `~/lab-scripts` de la VM (`push`, con `scp -O -r`) y
después lanza cada uno con `ssh ... "sudo -n bash lab-scripts/stage2/0X-....sh"`. El orden importa:
los permisos (03) van **después** de LVM (02), porque al montar un volumen el directorio toma los
permisos de la raíz del sistema de ficheros montado, no los del directorio original.

Todos los scripts cargan `common.sh` (`require_root`, `say`, `fatal`, `set_stage`) y usan
`set -euo pipefail`: se paran en el primer comando que falle.

---

## 3. Comandos de los scripts, explicados

### 3.1 `01-users-groups.sh` — usuarios y grupos con UID/GID fijos

| Comando | Qué hace | Por qué |
|---|---|---|
| `getent group sysadmins` | Consulta si el grupo existe (en `/etc/group` o en cualquier fuente NSS) | `getent` respeta LDAP/SSSD; leer solo `/etc/group` no (importante en la Etapa 13) |
| `groupadd -g 2001 sysadmins` | Crea el grupo con un **GID fijo** | Los mismos IDs en todos los hosts: imprescindible para NFS, LDAP y Ansible |
| `id devuser` | Muestra UID, GID y grupos; si el usuario no existe, falla | Comprobación idempotente |
| `useradd -m -u 1002 -g developers -s /bin/bash -c "Lab devuser" devuser` | Crea el usuario | `-m` crea el home, `-u` UID fijo, `-g` grupo **primario**, `-s` shell, `-c` comentario (GECOS) |
| `usermod -L devuser` | Bloquea la contraseña (pone `!` delante del hash en `/etc/shadow`) | Cuenta sin contraseña utilizable hasta que hagas `passwd devuser` |
| `usermod -aG sysadmins adminlab` | Añade un grupo **secundario** | Sin `-a`, `-G` sustituye todos los grupos secundarios (adminlab perdería `wheel`) |
| `chage -M 90 -m 1 -W 7 devuser` | Política de caducidad: máx. 90 días, mín. 1 día entre cambios, aviso 7 días antes | Ver con `chage -l devuser` |
| `set_stage 2` (de `common.sh`) | Escribe `LAB_STAGE=2` en `/etc/lab-release` si era menor | `run_all.sh` decide qué tests lanzar según ese valor |

### 3.2 `02-lvm.sh` — LVM + XFS en el disco de datos `/dev/vdb`

| Comando | Qué hace | Por qué |
|---|---|---|
| `test -b /dev/vdb` (`[[ -b ... ]]`) | ¿Existe ese dispositivo de bloques? | `dns01` y `ansible01` no tienen disco de datos: se salta LVM sin error |
| `vgs vg_data` | Muestra el grupo de volúmenes; falla si no existe | Idempotencia: si ya existe, no se crea nada |
| `lsblk -no MOUNTPOINT /dev/vdb` | Puntos de montaje del disco y sus particiones | Seguridad: aborta si hay algo montado |
| `wipefs -n /dev/vdb` | Lista firmas (particiones, sistemas de ficheros, LVM) **sin borrar** (`-n` = no-act) | Seguridad: aborta si el disco ya tiene datos |
| `pvcreate -y /dev/vdb` | Convierte el disco en volumen físico (PV) | Capa 1 de LVM |
| `vgcreate vg_data /dev/vdb` | Crea el grupo de volúmenes (VG) | Capa 2: un "bolsa" de espacio |
| `lvcreate -y -n lv_application -L 3G vg_data` | Crea un volumen lógico (LV) de 3 GiB | Capa 3: lo que se formatea y se monta. Quedan ~2 GiB libres para ejercicios de ampliación |
| `mkfs.xfs -q /dev/vg_data/lv_application` | Crea el sistema de ficheros XFS | XFS puede **crecer** pero **no encoger** |
| `cp -a /etc/fstab /etc/fstab.lab-bak` | Copia de seguridad conservando permisos y fechas | Antes de tocar un fichero crítico, siempre |
| `blkid -s UUID -o value /dev/vg_data/lv_application` | Devuelve solo el UUID del sistema de ficheros | En fstab se usa UUID: los nombres `/dev/...` pueden cambiar entre arranques |
| `printf 'UUID=%s %s xfs defaults 0 0\n' ... >> /etc/fstab` | Añade la línea de montaje | Campos: dispositivo, punto, tipo, opciones, dump, fsck (XFS no usa fsck al arrancar: `0`) |
| `systemctl daemon-reload` | Regenera las unidades `.mount` que systemd crea a partir de fstab | Sin esto systemd avisa de que fstab cambió |
| `mount -a` | Monta todo lo de fstab que no esté montado | **Prueba de fuego**: si falla aquí, fallaría también al reiniciar (caso 02) |
| `restorecon -RF /opt/application/data ...` | Reaplica las etiquetas SELinux por defecto (`-F` fuerza también usuario/rol) | Un sistema de ficheros recién creado no tiene las etiquetas de su ruta |
| `findmnt -no TARGET,SOURCE,FSTYPE /backup` | Muestra qué está montado ahí, desde dónde y con qué tipo | **Uno por uno**: con varias rutas a la vez devuelve 1 (caso 05) |

### 3.3 `03-permissions.sh` — permisos, setgid, sticky y ACL

| Comando | Qué hace | Por qué |
|---|---|---|
| `chown appuser:application /opt/application` | Cambia propietario y grupo | |
| `chmod 2750 /opt/application` | `2` = **setgid**, `7` dueño rwx, `5` grupo r-x, `0` otros nada | En un directorio, setgid hace que lo creado dentro herede el **grupo** del directorio |
| `chmod 3770 /backup` | `3` = setgid (2) + **sticky** (1) | Sticky: cada uno solo puede borrar **sus** ficheros, aunque el directorio sea compartido (como `/tmp`) |
| `setfacl -m g:developers:rx /opt/application/config` | Añade una ACL: el grupo `developers` puede leer y entrar | Da acceso a un segundo grupo sin cambiar el grupo propietario |
| `setfacl -m d:g:developers:rx /opt/application/config` | ACL **por defecto** (`d:`): la heredan los ficheros nuevos | Cuidado: también hereda la `x` y altera la máscara (caso 07) |
| `setfacl -b fichero` | Elimina todas las ACL extendidas del fichero | Se limpia `lab-app.env` antes de fijar su modo exacto (solución del caso 07) |
| `chmod 0640 lab-app.env` + `setfacl -m g:developers:r lab-app.env` | Modo exacto y luego solo lectura para developers | Con ACL, el grupo que muestra `ls -l` es en realidad la **máscara** |
| `restorecon -R /opt/application /backup /var/log/lab-app` | Etiquetas SELinux por defecto | |
| `ls -ld <dir>` | Permisos del directorio en sí (no de su contenido) | El `+` al final del modo indica que tiene ACL |
| `getfacl -p /opt/application/config` | Muestra todas las ACL (`-p` no quita la `/` inicial) | Las líneas `default:` son las heredables |

### 3.4 `04-sudo.sh` — perfiles de sudo

| Comando | Qué hace | Por qué |
|---|---|---|
| `id -nG adminlab \| grep -qw sysadmins` | ¿adminlab está en `sysadmins`? | Si no, al borrar el sudo de arranque te quedarías sin sudo: el script aborta antes |
| `mktemp` | Crea un fichero temporal con nombre único | Se escribe ahí, no directamente en `/etc/sudoers.d/` |
| `visudo -cf /tmp/fichero` | Valida la **sintaxis** de un fichero sudoers sin instalarlo | Un sudoers roto = nadie tiene sudo |
| `install -m 0440 -o root -g root tmp /etc/sudoers.d/10-sysadmins` | Copia con modo, dueño y grupo en un paso | sudo ignora ficheros de `sudoers.d` con permisos incorrectos |
| `Cmnd_Alias DEV_SERVICE = /usr/bin/systemctl status lab-app, ...` | Lista de comandos **exactos**, con ruta absoluta | Sin comodines: `systemctl *` permitiría `systemctl edit` y escalar a root |
| `%developers ALL=(root) NOPASSWD: DEV_SERVICE, DEV_LOGS` | Regla: grupo (`%`), en cualquier host, como root, sin contraseña, solo esos comandos | Mínimo privilegio |
| `/usr/local/sbin/lab-backup.sh` (`chmod 0750`, dueño root) | Script fijo que el grupo `backup` puede ejecutar como root | Dar `tar` o `rsync` libres con sudo equivale a dar root |
| `visudo -c` | Valida **toda** la configuración (`/etc/sudoers` + `sudoers.d`) | Comprobación global antes de borrar el sudo de arranque |
| `sudo -l -U adminlab` | Lista lo que un usuario puede ejecutar con sudo | `-U` consulta a otro usuario (solo root) |

### 3.5 `05-systemd-app.sh` — aplicación y unidad systemd

| Comando / directiva | Qué hace | Por qué |
|---|---|---|
| `cat > /opt/application/bin/lab-app.sh <<'EOF'` | Crea el script **en su ubicación final** | Crear en sitio (no `mv` desde `/tmp`) evita heredar la etiqueta SELinux de `/tmp` (caso 04) |
| `trap '...; exit 0' TERM` (dentro de la app) | Captura la señal de parada | `systemctl stop` envía SIGTERM: la app sale limpia y systemd no lo cuenta como fallo |
| `sleep "$interval" & wait $!` | Duerme en segundo plano y espera | `wait` sí se interrumpe con la señal; un `sleep` en primer plano retrasaría la parada |
| `restorecon -R /opt/application/bin` | Etiqueta `bin_t` en el script | systemd (`init_t`) solo puede ejecutar ciertos tipos |
| `Type=simple` | El proceso de `ExecStart` es el servicio | |
| `User=appuser` / `Group=application` | Ejecuta sin privilegios de root | |
| `EnvironmentFile=-/opt/.../lab-app.env` | Carga variables; el `-` hace que no falle si no existe | |
| `Restart=on-failure` + `RestartSec=5` | Reinicia si sale con error, a los 5 s | Base del caso 01 (`LAB_APP_CRASH_AFTER`) |
| `SyslogIdentifier=lab-app` | Etiqueta de los mensajes en el journal | Por eso `journalctl -t lab-app` sí los encuentra (caso 09) |
| `NoNewPrivileges=yes` / `PrivateTmp=yes` | El proceso no puede ganar privilegios; tiene su propio `/tmp` | Endurecimiento básico de la unidad |
| `WantedBy=multi-user.target` | Se engancha al arranque normal al hacer `enable` | |
| `systemctl daemon-reload` | Relee los ficheros de unidad | Obligatorio tras crear o modificar una unidad |
| `systemctl enable lab-app` / `restart lab-app` | Habilita en el arranque / reinicia ahora | |
| `systemctl --no-pager --lines=5 status lab-app` | Estado, PID y últimas 5 líneas de log | `--no-pager` evita que se quede esperando en `less` dentro de un script |
| `systemctl is-active --quiet lab-app` | Devuelve 0 si está activo, sin imprimir nada | Ideal para scripts y tests |

---

## 4. Comandos de los tests, explicados

Se lanzan con `scripts/lab.sh test all <host|all>` (o uno suelto: `lab.sh test test_users.sh <host>`).
`run_all.sh` lee `LAB_STAGE` de `/etc/lab-release` y, a partir de 2, añade estos cuatro tests.
Cada `check` da **PASS** si el comando sale con código 0. Todos son de **solo lectura** (como mucho
crean y borran un fichero temporal para probar permisos).

### 4.1 `test_users.sh`

| Comprobación | Comando manual equivalente | Qué demuestra |
|---|---|---|
| Grupo con GID fijo (×4) | `getent group sysadmins \| cut -d: -f3` | GID 2001-2004 iguales en todas las VMs |
| Usuario con UID fijo (×4) | `id -u devuser` | UID 1001-1004 |
| adminlab en `sysadmins` y `wheel` | `id -nG adminlab` | `-aG` no borró `wheel` |
| Grupo primario (×3) | `id -gn devuser` | `-g` del `useradd` |
| Caducidad 90 días | `chage -l devuser` | Política aplicada |
| `/etc/shadow` sin permisos para otros | `stat -c %a /etc/shadow` | Modo `0`, `600` o `640` (varía por versión de RHEL) |
| `pwck` sin errores | `pwck -r` | Coherencia de `/etc/passwd` y `/etc/shadow`; `-r` = solo lectura (caso 08) |
| `grpck` sin errores | `grpck -r` | Coherencia de `/etc/group` y `/etc/gshadow` |
| sudoers válido | `visudo -c` | |
| Ficheros `10-`, `20-`, `30-` presentes y `90-adminlab-bootstrap` eliminado | `ls -l /etc/sudoers.d/` | |
| Perfiles de sudo | `sudo -l -U adminlab`, `sudo -l -U devuser`, `sudo -l -U backupuser` | Cada perfil tiene **solo** lo suyo |
| `lab-backup.sh` = `root:750` | `stat -c %U:%a /usr/local/sbin/lab-backup.sh` | Nadie más puede modificar lo que se ejecuta como root |

### 4.2 `test_permissions.sh`

| Comprobación | Comando manual equivalente | Qué demuestra |
|---|---|---|
| Dueño, grupo y modo (×5) | `stat -c %U:%G:%a /opt/application` | Formato `usuario:grupo:modo` |
| setgid en `data` | `test -g /opt/application/data` | `-g` = bit setgid |
| sticky en `/backup` | `test -k /backup` | `-k` = sticky bit |
| ACL y ACL por defecto en `config` | `getfacl -p /opt/application/config` | Líneas `group:developers:r-x` y `default:group:developers:r-x` |
| `lab-app.env` = `root:application:640` | `stat -c %U:%G:%a .../lab-app.env` | Caso 07 resuelto |
| Acceso **funcional** | `su -s /bin/bash -c 'test -r .../lab-app.env' devuser` | Prueba real como ese usuario, no solo leyendo permisos. `-s` fuerza shell (algunos usuarios no tienen) |
| `nobody` no entra | `su -s /bin/bash -c 'ls /opt/application' nobody` | Otros = sin acceso |
| Etiqueta `bin_t` en el script | `ls -Z /opt/application/bin/lab-app.sh` (o `stat -c %C`) | Caso 04 |
| `/backup` sin `unlabeled_t` | `ls -dZ /backup` | `restorecon` aplicado tras crear el XFS |

### 4.3 `test_storage.sh`

| Comprobación | Comando manual equivalente | Qué demuestra |
|---|---|---|
| VG y LV existen | `vgs vg_data`, `lvs vg_data` | |
| ≥ 1 GiB libre en el VG | `vgs --units g -o vg_free vg_data` | Espacio para practicar `lvextend` |
| Montado desde su LV y en XFS | `findmnt -no SOURCE,FSTYPE /backup` | |
| fstab usa UUID y no `/dev/...` | `grep -E '/backup' /etc/fstab` | Montajes estables entre arranques |
| Copia `/etc/fstab.lab-bak` | `ls -l /etc/fstab.lab-bak` | Vía de recuperación del caso 02 |
| `vg_system`, `/` y `/var` en XFS | `lvs vg_system`, `findmnt -no FSTYPE /var` | Lo dejado por el kickstart sigue intacto |
| `findmnt --verify` sin errores | `findmnt --verify` | Revisa fstab **sin montar nada** (si la versión lo soporta; RHEL 7 no) |
| swap activa | `swapon --show` | |
| Ninguna unidad `.mount` en `failed` | `systemctl list-units --type=mount --state=failed` | |

### 4.4 `test_services.sh`

| Comprobación | Comando manual equivalente | Qué demuestra |
|---|---|---|
| Servicios base activos | `systemctl is-active sshd chronyd firewalld rsyslog NetworkManager auditd` | |
| `lab-app` activo y habilitado | `systemctl is-active lab-app; systemctl is-enabled lab-app` | |
| `Restart=on-failure` | `systemctl show lab-app -p Restart` | `show` lee la configuración **efectiva**, no el fichero |
| Corre como `appuser` | `ps -o user= -p "$(systemctl show lab-app -p MainPID --value)"` | El PID principal pertenece al usuario sin privilegios |
| Escribe en el journal | `journalctl -t lab-app -n 1 --no-pager` | `-t` filtra por identificador, fiable también en RHEL 8 (caso 09) |
| Escribe en `app.log` | `test -s /var/log/lab-app/app.log` | `-s` = existe y no está vacío |
| Sin unidades en `failed` | `systemctl --failed` | |
| Sin AVC recientes de lab-app | `timeout 8 ausearch -m avc -ts recent \| grep lab-app` | `timeout` evita que el test se cuelgue (caso 06) |
| `named` activo (solo `dns01`) | `systemctl is-active named` | Se añade al llegar a la Etapa 4 |

---

## 5. Comandos de diagnóstico de los casos reales

| Comando | Qué hace | Caso |
|---|---|---|
| `ss -ltnp \| grep :22` | Puertos TCP en escucha y el proceso que los abre | 01 — vacío = `sshd` no escucha |
| `systemctl status <servicio>` | Estado, PID, código de salida y últimas líneas | 01 — `code=exited, status=3` |
| `journalctl -u <unidad> -n 30` | Últimas 30 líneas de una unidad | 01 |
| `systemctl show lab-app -p Restart,RestartUSec,NRestarts` | Política de reinicio y **cuántas veces** se ha reiniciado | 01 |
| `journalctl -xb \| grep -iE 'mount\|fstab\|dependency'` | Errores del arranque actual con explicación (`-x`) | 02 |
| `systemctl --failed` | Unidades que han fallado | 02 |
| `blkid` / `lsblk -f` | UUID **reales** de cada sistema de ficheros | 02 — comparar con fstab |
| `mount -o remount,rw /` | Remonta `/` en lectura-escritura | 02 — en modo emergencia `/` está en solo lectura |
| `namei -l <ruta>` | Permisos de **cada** directorio de la ruta | 03 — basta un directorio sin `x` para bloquear todo |
| `ls -lZ <fichero>` | Permisos + etiqueta SELinux | 04 |
| `ausearch -m avc -ts recent` | Denegaciones SELinux recientes | 03/04 — si no hay AVC, no es SELinux |
| `setenforce 0` → probar → `setenforce 1` | Pasa **temporalmente** a Permissive para confirmar si es SELinux | 04 — solo para diagnosticar; nunca dejarlo así |
| `matchpathcon <ruta>` | Etiqueta SELinux que **debería** tener esa ruta | 04 |
| `findmnt <ruta>` (uno por uno) + `echo $?` | Ver el código de salida real | 05 |
| `timeout 8 <comando>` | Corta el comando a los 8 s | 06 |
| `stat -c "%U:%G:%a" <fichero>` + `getfacl -p <fichero>` | Modo numérico y ACL, incluida la `mask` | 07 |
| `pwck -r` | Revisión de usuarios en solo lectura | 08 |
| `journalctl -t lab-app` / `_SYSTEMD_UNIT=lab-app.service` / `-o verbose` | Filtrar por identificador, por campo exacto, o ver todos los campos | 09 |

---

## 6. Chuleta: síntoma → primeros comandos

| Síntoma | Primeros comandos |
|---|---|
| Un servicio no arranca | `systemctl status X`, `journalctl -u X -n 50`, `ausearch -m avc -ts recent` |
| `status=203/EXEC` | `ls -lZ <ExecStart>`, `restorecon -v <ExecStart>`, ¿tiene `x`? |
| Un servicio se reinicia en bucle | `systemctl show X -p NRestarts`, `journalctl -u X` |
| La VM arranca en modo emergencia | `journalctl -xb`, `systemctl --failed`, `blkid` frente a `/etc/fstab` |
| "Permission denied" de un usuario | `id <usuario>`, `namei -l <ruta>`, `getfacl -p <ruta>`, `ausearch -m avc` |
| Un fichero tiene un modo distinto al esperado | `getfacl -p <fichero>` (¿ACL heredada? ¿`mask`?) |
| sudo no deja ejecutar algo | `sudo -l -U <usuario>`, `visudo -c` |
| No hay sitio en un volumen | `df -hT`, `vgs`, `lvextend -r -L +1G vg_data/lv_X` |
| `mount -a` falla | `findmnt --verify`, `blkid`, comparar UUID |

---

## 7. Preguntas de repaso

1. ¿Qué pasa si haces `usermod -G sysadmins adminlab` sin `-a`?
2. ¿Qué hace el bit setgid en un directorio? ¿Y el sticky bit?
3. ¿Qué diferencia hay entre una ACL normal y una ACL por defecto (`d:`)?
4. ¿Qué es la `mask` de una ACL y por qué cambia lo que muestra `ls -l`?
5. ¿Por qué se usa UUID en `/etc/fstab` y no `/dev/vg_data/...`?
6. ¿Por qué hay que lanzar `mount -a` después de editar fstab, y no reiniciar directamente?
7. ¿Por qué validar con `visudo -cf` antes de instalar un fichero en `sudoers.d`?
8. ¿Por qué no se da `tar` o `rsync` por sudo al grupo `backup`?
9. ¿Por qué `mv` desde `/tmp` puede romper un servicio con SELinux y `cp` no?
10. ¿Qué diferencia hay entre `journalctl -u` y `journalctl -t`?
11. ¿Se puede encoger un XFS? ¿Y ampliarlo?
