# 👥 Etapa 2 — Administración Linux (`scripts/stage2/`)

## Qué hace esta etapa

Deja cada VM con la base de administración de un servidor real: usuarios y grupos con **UID/GID fijos**,
LVM + XFS en el disco de datos, un escenario de permisos (setgid, sticky, ACL), perfiles de `sudo` de mínimo
privilegio y una aplicación de prueba gestionada por **systemd** (`lab-app.service`).

## Cómo se lanza

```bash
scripts/lab.sh stage2 <host|all>
```

`lab.sh` copia los scripts a `~/lab-scripts` de la VM (`push`) y los ejecuta **como root** (`sudo -n`), uno
detrás de otro, en el orden de la tabla. Todos usan `set -euo pipefail`: se paran en el primer error.

## Scripts (en orden)

| # | Script | Qué hace | Qué modifica | Copia / idempotencia |
|---|---|---|---|---|
| 1 | `01-users-groups.sh` | Grupos `sysadmins`/`developers`/`application`/`backup` (GID 2001-2004) y usuarios `devuser`/`appuser`/`backupuser` (UID 1002-1004, **bloqueados**); `adminlab` → `sysadmins`; `chage` de ejemplo | `/etc/passwd`, `/etc/group`, `/etc/shadow` | Comprueba antes de crear (`getent`, `id`) |
| 2 | `02-lvm.sh` | `/dev/vdb` → `vg_data` con `lv_application` (3G), `lv_logs` (2G), `lv_backup` (3G) en XFS, montados por **UUID** | Disco de datos, `/etc/fstab`, puntos de montaje | Aborta si el disco tiene algo montado o firmas (`wipefs -n`); `/etc/fstab.lab-bak`; se salta en hosts sin disco de datos (`dns01`, `ansible01`) |
| 3 | `03-permissions.sh` | Dueños y modos (2750, 2770, 3770), ACL de lectura para `developers` (normal y por defecto), `lab-app.env` en 0640 | `/opt/application`, `/backup`, `/var/log/lab-app` | `setfacl -b` antes de fijar el modo exacto (caso `etapa2/07`) |
| 4 | `04-sudo.sh` | Perfiles en `/etc/sudoers.d/` (10-sysadmins, 20-developers, 30-backup), script fijo `/usr/local/sbin/lab-backup.sh` y **borra el sudo de arranque** del kickstart | `/etc/sudoers.d/`, `/usr/local/sbin/lab-backup.sh` | Cada fichero se valida con `visudo -cf` **antes** de instalarlo; aborta si `adminlab` no está en `sysadmins` (para no quedarte sin sudo) |
| 5 | `05-systemd-app.sh` | Crea `lab-app.sh` (latido periódico) y `lab-app.service` (`Restart=on-failure`, `User=appuser`, `NoNewPrivileges`) | `/opt/application/bin/`, `/etc/systemd/system/lab-app.service` | Crea el script en su sitio (no `mv` desde `/tmp`: caso `etapa2/04`) y `restorecon` |

Cada script termina con `set_stage 2` (marca `LAB_STAGE=2` en `/etc/lab-release`; nunca la baja).

## Requisitos previos

- Etapa 1 completa (`adminlab` con clave SSH y sudo de arranque).
- Orden obligatorio: **02 antes de 03** — al montar un volumen, el directorio toma los permisos de la raíz
  del sistema de ficheros montado, no los del directorio original.

## Ejecución manual (sin `lab.sh`)

```bash
ssh rhel9-app01
sudo bash ~/lab-scripts/stage2/01-users-groups.sh     # (tras 'lab.sh stage2' o un 'push' previo)
```

## Cómo se verifica

```bash
scripts/lab.sh test all <host|all>     # test_users, test_permissions, test_storage, test_services
```

## Documentación relacionada

- Checklist: [`checklists/etapa2.md`](../../checklists/etapa2.md)
- Tema: [`administration/`](../../administration/users.md) (users, permissions, sudo, lvm, filesystems, systemd, logging)
- Comandos explicados y 11 casos (9 reales y 2 escenarios de ampliación de almacenamiento): [`troubleshooting/etapa2/README_troubleshooting_etapa2.md`](../../troubleshooting/etapa2/README_troubleshooting_etapa2.md)
