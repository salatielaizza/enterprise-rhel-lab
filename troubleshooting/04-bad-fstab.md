# 04 — /etc/fstab erróneo: arranque en modo emergencia

**Objetivo**: recuperar un sistema que no arranca por fstab.
**Preparación**: snapshot de rhel9-app01 (con Etapa 2); contraseña de root conocida; `virsh console rhel9-app01`.

## Cómo provocar
`sudo cp /etc/fstab /etc/fstab.pre-lab`; cambia un carácter del UUID de `/backup` en `/etc/fstab`; `sudo reboot`.

## Síntoma
En consola: `Dependency failed for /backup` / `Timed out waiting for device` y `You are in emergency mode… Give root password for maintenance`.

## Hipótesis
UUID inexistente, disco no presente, sistema de ficheros dañado, opción de montaje inválida.

## Diagnóstico
```bash
# (contraseña de root)
journalctl -xb | grep -i -E 'mount|fstab|dependency'
systemctl --failed
blkid ; lsblk -f                      # UUID reales
grep backup /etc/fstab                # el UUID no coincide con blkid
```

## Causa raíz
La entrada de fstab apunta a un UUID que no existe; al ser un montaje obligatorio (sin `nofail`), `local-fs.target` falla.

## Solución
```bash
mount -o remount,rw /
cp /etc/fstab.pre-lab /etc/fstab      # o corregir el UUID con el de blkid
systemctl daemon-reload ; mount -a    # sin errores
reboot
```

## Validación
`findmnt /backup`; `scripts/lab.sh test test_storage.sh rhel9-app01`.

## Prevención
Copia previa de fstab, `mount -a` **antes** de reiniciar, `nofail`/`x-systemd.device-timeout` en discos no críticos, UUID en lugar de `/dev/vdX`.
