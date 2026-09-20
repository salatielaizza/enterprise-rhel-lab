# Sistemas de ficheros y /etc/fstab

## 1. Objetivo
Montar sistemas de ficheros de forma persistente y segura (UUID), elegir XFS/ext4 y **recuperarse de un fstab roto**.

## 2. Prerrequisitos
`lvm.md` hecho. Contraseña de root conocida (modo emergencia).

## 3. Arquitectura
XFS por defecto en las cuatro versiones. `/etc/fstab` = 6 campos: `dispositivo punto tipo opciones dump fsck-orden`. systemd genera las unidades `.mount` desde fstab.

## 4. Procedimiento manual y comandos
| Comando | Qué hace | Por qué | Salida / fallo |
|---|---|---|---|
| `lsblk -f`, `blkid`, `findmnt`, `df -hT`, `du -sh /var/*` | Ver discos, UUID, montajes, uso | Diagnóstico | `findmnt --verify` valida fstab (7 no lo trae: util-linux 2.23) ◦ |
| `sudo cp -a /etc/fstab /etc/fstab.bak` | Copia previa | **Siempre** antes de tocar fstab | — |
| `UUID=… /backup xfs defaults 0 0` | Línea de fstab | UUID no cambia si cambia el orden de discos (a diferencia de `/dev/vdb`) | — |
| `sudo systemctl daemon-reload && sudo mount -a` | Regenera unidades y monta todo | Probar fstab **sin reiniciar** | Sin salida = OK; error = corrige antes de reiniciar |
| `sudo mount -o remount,ro /backup` / `umount /backup` | Remontar / desmontar | `target is busy` → `lsof +f -- /backup` / `fuser -vm /backup` | — |
| `xfs_info /backup`, `xfs_repair` (desmontado), `fsck.ext4 -f` | Información / reparación | XFS no usa `fsck` | Nunca `xfs_repair` sobre montado |
| `sudo mkfs.ext4 /dev/vg_data/lv_ext4` + `resize2fs` | ext4 y su redimensionado | Comparar con XFS (ext4 sí reduce, desmontado) | — |
| Opciones: `nofail`, `x-systemd.device-timeout=10s`, `noatime`, `ro`, `nosuid,nodev,noexec` | Comportamiento del montaje | `nofail` evita que un disco no crítico bloquee el arranque | — |

## 5. Resultado esperado y validación
`test_storage.sh` PASS (UUID en fstab, sin rutas `/dev/…`, sin unidades `.mount` fallidas).

## 6. Troubleshooting — fstab roto (ejercicio obligatorio; ver `troubleshooting/04-bad-fstab.md`)
Síntoma: arranca en *emergency mode* ("Give root password for maintenance") por un UUID inexistente. Solución: contraseña de root en consola → `mount -o remount,rw /` → corregir `/etc/fstab` (`blkid` para el UUID correcto) → `systemctl daemon-reload` → `mount -a` → `reboot`.

## 7. Errores comunes
Editar fstab y reiniciar sin `mount -a`; usar `/dev/vdb` en lugar de UUID; olvidar `nofail` en discos no críticos (decisión consciente: en el lab **no** se usa para poder practicar el fallo); crear el punto de montaje sin restaurar contexto SELinux.

## 8. Diferencias RHEL 7 / 8 / 9 / 10
XFS por defecto en todas ◦. `findmnt --verify` no existe en RHEL 7 ◦. Contraseña de root: en las instalaciones del lab está definida por el kickstart; sin ella el modo emergencia no permite entrar.

## 9. Automatización
`stage2/02-lvm.sh` añade fstab por UUID y guarda `/etc/fstab.lab-bak`.

## 10. Ejercicio
Con snapshot: cambia un dígito de un UUID en fstab, reinicia y repáralo; añade `nofail` y repite para ver la diferencia; monta un LV con `ro,noexec` y prueba ejecutar un script.

## 11. Criterios de aceptación
Reparas un arranque en emergencia en <5 min y explicas UUID vs `/dev/…`.
