# LVM (PV / VG / LV)

## 1. Objetivo
Crear volúmenes lógicos sobre el disco de datos, ampliarlos en caliente, usar snapshots y saber recuperar metadatos.

## 2. Prerrequisitos
`/dev/vdb` (10 GB) sin uso. **No** funciona en dns01/ansible01 (no tienen disco de datos).

## 3. Arquitectura
```
/dev/vdb ── PV ── vg_data ── lv_application (3G) -> /opt/application/data
                          ├─ lv_logs        (2G) -> /var/log/lab-app
                          └─ lv_backup      (3G) -> /backup      (~2 GB libres en el VG)
vg_system (en vda): lv_root 8G, lv_swap 2G, lv_var 4G (~5 GB libres)
```

## 4. Procedimiento manual y comandos
| Comando | Qué hace | Por qué | Salida / fallo |
|---|---|---|---|
| `lsblk -f`, `sudo wipefs -n /dev/vdb` | Estado del disco / firmas (sin borrar) | Comprobar que está vacío | `wipefs -n` no imprime nada = vacío |
| `sudo pvcreate /dev/vdb`; `pvs` | Crea el PV | Marca el disco para LVM | `Physical volume "/dev/vdb" successfully created` |
| `sudo vgcreate vg_data /dev/vdb`; `vgs` | Crea el VG | Reserva en extensiones (PE, 4 MiB por defecto) | — |
| `sudo lvcreate -n lv_backup -L 3G vg_data`; `lvs` | Crea el LV | Volumen con nombre | `/dev/vg_data/lv_backup` (y `/dev/mapper/vg_data-lv_backup`) |
| `sudo mkfs.xfs /dev/vg_data/lv_backup` | Sistema de ficheros XFS | Formato por defecto de RHEL | — |
| `sudo blkid -s UUID -o value /dev/vg_data/lv_backup` | UUID | Para `/etc/fstab` estable | Ver `filesystems.md` |
| `sudo lvextend -L +1G -r /dev/vg_data/lv_backup` | Amplía LV **y** el sistema de ficheros (`-r`) | Crecimiento en caliente | `Logical volume … successfully resized` + crecimiento de XFS |
| `sudo xfs_growfs /backup` | Crece XFS montado (si no usaste `-r`) | XFS **se amplía por su punto de montaje** | — |
| `sudo lvcreate -s -n lv_backup_snap -L 500M /dev/vg_data/lv_backup` | Snapshot COW | Copia puntual / prueba de cambios | El tamaño (500M) es el espacio para cambios; si se llena, el snapshot se invalida |
| `sudo mount -o ro,nouuid /dev/vg_data/lv_backup_snap /mnt` | Monta snapshot XFS | Mismo UUID que el original → `nouuid` obligatorio | Sin `nouuid`: *wrong fs type / duplicate UUID* |
| `sudo lvconvert --merge vg_data/lv_backup_snap` | Revierte el origen al snapshot | Rollback (se completa al reactivar/desmontar) | — |
| `pvs -o+pv_used`, `vgs`, `lvs -a -o +devices` | Vistas | Capacidad y dispositivos | — |
| `sudo vgcfgbackup` / `vgcfgrestore -l vg_data` | Copias de metadatos en `/etc/lvm/backup` y `archive` | Recuperación tras error | — |

Reducir: **XFS no se puede reducir**. ext4 sí (desmontado): `e2fsck -f`, `resize2fs`, `lvreduce`. Para reducir un XFS: copia, recrea, restaura.

## 5. Resultado esperado y validación
`scripts/stage2/02-lvm.sh`; `test_storage.sh` PASS: 3 LV, montados por UUID, VG con ≥1 GiB libre.

## 6. Troubleshooting
*"Device /dev/vdb excluded by a filter"* → firmas previas o lista de dispositivos (ver Diferencias); LV activo pero sin montar → `mount -a`; `vgs` no ve el VG tras clonar → `vgscan`, `pvscan`; disco perdido → `vgreduce --removemissing` (con cuidado).

## 7. Errores comunes
`lvextend` sin `-r` y olvidar `xfs_growfs`; snapshot demasiado pequeño; intentar `xfs_growfs /dev/vg/lv` (usa el punto de montaje); formatear un disco con datos.

## 8. Diferencias RHEL 7 / 8 / 9 / 10
lvm2 2.02 (7) vs 2.03 (8+) ◦. En RHEL 9 el **fichero de dispositivos** (`/etc/lvm/devices/system.devices`, `lvmdevices`) está activo por defecto ◦: un PV que no figure allí no se ve; `pvcreate` lo añade automáticamente. Verificar en RHEL 10 (◦ pendiente). Un XFS creado en versiones nuevas puede activar características (p. ej. `bigtime`, `inobtcount`) que **kernels antiguos no montan**: comprueba `xfs_info` antes de mover discos entre versiones (◦).

## 9. Automatización
`scripts/stage2/02-lvm.sh`: aborta si el disco está montado o tiene firmas; hace copia de fstab y usa UUID.

## 10. Ejercicio
Amplía `lv_backup` +1G online y verifica con `df -h /backup`; crea un snapshot de `lv_application`, borra datos, monta el snapshot con `nouuid` y recupéralos; crea `lv_ext4` de 500M con ext4, redúcelo a 300M desmontado.

## 11. Criterios de aceptación
Amplías en caliente sin desmontar y explicas por qué XFS no se reduce y qué hace `nouuid`.
