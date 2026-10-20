# Etapa 2 · Caso 11 — `/var` lleno: ampliar un volumen del sistema (`vg_system`) en caliente

**Objetivo**: resolver un `/var` lleno en el disco del **sistema** operativo, en dos variantes:

- **Parte A**: el VG del sistema tiene espacio libre → `lvextend -r` directo.
- **Parte B (avanzada)**: el VG del sistema está a 0 → se amplía el **disco virtual** (lo que en una
  empresa hace el equipo de VMware desde vCenter) y se hace crecer la partición y el PV: `growpart` +
  `pvresize` + `lvextend -r`.

Cuando `/var` se llena, fallan a la vez los logs, el journal, `dnf`/`yum`, las colas de correo, las bases de
datos y muchas aplicaciones: es una de las incidencias más comunes en producción.

**Preparación**:
- `rhel9-app01` con la Etapa 2 aplicada (sirve cualquier VM del lab: todas tienen `vg_system`).
- Snapshot de práctica con la VM apagada, en el **host**:
  ```bash
  scripts/lab.sh down rhel9-app01            # espera a "shut off": virsh domstate rhel9-app01
  virsh -c qemu:///system snapshot-create-as rhel9-app01 rhel9-pre-caso11 --description "Antes del caso etapa2/11"
  scripts/lab.sh up rhel9-app01
  ```

Disposición de partida que deja el kickstart en un disco `vda` de 20 GB:

```
vda1 /boot (1G)        [RHEL 10: vda1 biosboot, vda2 /boot]
vda2 PV → vg_system    [RHEL 10: vda3]   ≈ 19 GiB
        ├─ lv_root  8G  → /
        ├─ lv_swap  2G  → swap
        └─ lv_var   4G  → /var
        VFree ≈ 5 GiB
```

## Cómo provocar

Dentro de la VM, como root:

```bash
vgs vg_system                                       # anota VFree (≈ 5 GiB)
avail=$(df --output=avail -BM /var | tail -1 | tr -dc '0-9')
fallocate -l $((avail - 80))M /var/tmp/relleno-caso11.img   # deja /var con ~80 MB libres
```

## Síntoma

```bash
df -hT /var                                         # Use% 98-99 %
dnf makecache                                       # errores de escritura en /var/cache/dnf
logger "prueba caso 11" ; journalctl -n 3           # el journal puede avisar de que no hay espacio
```

## Hipótesis

1. Logs o journal sin rotar ni limitar.
2. Caché de paquetes acumulada (`/var/cache/dnf`).
3. Ficheros borrados pero aún abiertos por un proceso.
4. Datos legítimos de una aplicación (base de datos, colas, ficheros de una interfaz) → hay que ampliar.

## Diagnóstico

```bash
df -hT /var ; df -i /var
du -xh --max-depth=2 /var 2>/dev/null | sort -h | tail -15   # -x: no entra en otros montajes
find /var -xdev -type f -size +200M -exec ls -lh {} + 2>/dev/null
journalctl --disk-usage                             # tamaño del journal
du -sh /var/cache/dnf                               # caché de paquetes
lsof +L1 2>/dev/null | grep /var                    # borrados pero abiertos (ocupan hasta reiniciar el proceso)
vgs vg_system ; lvs vg_system                       # ¿queda espacio para ampliar?
```

**Orden correcto en una incidencia**: primero liberar lo que sea seguro liberar (es inmediato y no cambia la
infraestructura) y después ampliar si el volumen se ha quedado pequeño para el uso real.

```bash
journalctl --vacuum-size=200M                       # recorta el journal a 200 MB
dnf clean all                                       # vacía la caché de paquetes
```

En este escenario, `relleno-caso11.img` hace de "datos legítimos": liberar no basta y hay que ampliar.

## Causa raíz

`lv_var` se dimensionó en 4 GiB al instalar y el uso real lo ha superado. El VG del sistema todavía tiene
espacio sin asignar (Parte A) o ya no le queda (Parte B).

## Solución — Parte A: el VG tiene espacio libre

```bash
lvextend -r -L +2G /dev/vg_system/lv_var            # LV + XFS, montado y en uso
df -hT /var                                          # 4 GiB → 6 GiB, sin desmontar
vgs vg_system                                        # VFree ≈ 3 GiB
```

Lo mismo sirve para la raíz: `lvextend -r -L +1G /dev/vg_system/lv_root`. XFS se amplía en caliente
también en `/`; lo que **no** se puede es reducirlo.

## Solución — Parte B (avanzada): el VG está a 0, se amplía el disco virtual

Primero, deja el VG del sistema sin espacio libre, como pasaría en producción:

```bash
lvextend -r -l +100%FREE /dev/vg_system/lv_var      # VFree = 0
fallocate -l 2G /var/tmp/relleno2-caso11.img         # vuelve a llenarlo
lvextend -r -L +1G /dev/vg_system/lv_var            # "Insufficient free space"
```

**1. En el host: ampliar el disco virtual de 20 a 25 GB, con la VM encendida** ◦

```bash
virsh -c qemu:///system blockresize rhel9-app01 vda 25G
virsh -c qemu:///system domblkinfo rhel9-app01 vda   # Capacity ≈ 26843545600 (25 GiB)
```

Las VMs del lab tienen snapshots **internos** dentro del propio qcow2. Las versiones antiguas de QEMU no
permiten redimensionar una imagen con snapshots internos; la del host (8.2) debería permitir hacerla
crecer ◦. Si `blockresize` falla con un mensaje sobre *snapshots*, anótalo como hallazgo y haz solo la Parte A.

**2. En la VM: el disco crece, pero la partición y el PV no**

```bash
lsblk /dev/vda                                       # vda 25G; la partición del PV sigue en ~19G
pvs                                                  # PSize sin cambios
```

Identifica la partición del PV en la salida de `pvs` (`/dev/vda2`; en RHEL 10, `/dev/vda3`).

**3. Hacer crecer la partición, el PV y el LV**

```bash
dnf install -y cloud-utils-growpart                  # 'growpart' (en RHEL 7: yum install cloud-utils-growpart)
growpart /dev/vda 2                                   # disco y NÚMERO de partición, separados (RHEL 10: 3)
lsblk /dev/vda                                       # la partición ya ocupa todo el disco
pvresize /dev/vda2                                   # el PV crece hasta el tamaño de la partición
vgs vg_system                                        # VFree ≈ 5 GiB
lvextend -r -L +3G /dev/vg_system/lv_var
df -hT /var
```

`growpart` y `pvresize` funcionan **en caliente**, con la partición en uso. Si no puedes instalar
`cloud-utils-growpart` (sin repositorios), la alternativa es `parted /dev/vda resizepart 2 100%`, que pide
confirmación al ser una partición en uso.

## Validación

```bash
df -hT / /var
lvs vg_system ; vgs vg_system ; pvs
findmnt --verify                                     # fstab coherente (no ha cambiado nada en él)
```

Desde el host: `scripts/lab.sh test test_storage.sh rhel9-app01` → 0 FAIL. Después, `reboot` y comprobar
que todo monta y que los tamaños se mantienen.

## Volver al estado inicial

En el host:

```bash
scripts/lab.sh down rhel9-app01                    # espera a "shut off"
virsh -c qemu:///system snapshot-revert rhel9-app01 rhel9-pre-caso11
virsh -c qemu:///system snapshot-delete rhel9-app01 rhel9-pre-caso11
scripts/lab.sh up rhel9-app01
```

Tras la Parte B, revisa `virsh -c qemu:///system domblkinfo rhel9-app01 vda` ◦: si el disco virtual sigue
en 25 GB después de revertir, no es un problema (el espacio extra queda sin particionar, invisible para la
VM), pero conviene saberlo.

## Prevención

- Separar `/var` (y, en servidores de aplicación, el directorio de datos) en su propio LV: así un `/var`
  lleno no llena también `/`. El kickstart del lab ya lo hace.
- Limitar el journal (`SystemMaxUse=` en `/etc/systemd/journald.conf`) y revisar `logrotate`.
- Dejar espacio libre en el VG del sistema y monitorizar con umbrales y tendencia.
- En plataformas virtuales, ampliar el disco **antes** de quedarse sin margen en el VG, con un cambio
  planificado y no durante una incidencia.

## Diferencias RHEL 7 / 8 / 9 / 10

- **Particiones**: RHEL 7, 8 y 9 instalan en BIOS con tabla MBR (`/boot` en `vda1`, PV en `vda2`). RHEL 10
  usa GPT con una partición `biosboot` delante (PV en `vda3`). Comprueba siempre el número con `pvs` y
  `lsblk` antes de `growpart` ◦.
- **`growpart` en MBR**: en un disco MBR, una partición primaria no puede pasar de 2 TiB; no afecta a este
  lab, pero sí a servidores grandes ◦.
- **Fichero de dispositivos (RHEL 9 y 10)**: `pvresize` no cambia el disco, así que no hay que tocar
  `lvmdevices` ◦.
- **Paquetes**: `yum` en RHEL 7 y `dnf` en 8, 9 y 10; `cloud-utils-growpart` está en los repositorios de
  las cuatro ◦ (en RHEL 7 puede requerir el repositorio *extras*).

## Lo que se pregunta en una entrevista

- *"/var está al 100 %. ¿Qué miras primero?"* → `df -hT`, `du -xh`, `lsof +L1`, journal y caché; liberar lo
  seguro y, si no basta, ampliar.
- *"Te han ampliado el disco en VMware. ¿Qué haces en Linux para usar ese espacio?"* → `lsblk` →
  `growpart` → `pvresize` → `lvextend -r` → `df -h`, todo en caliente.
- *"¿Se puede reducir un XFS?"* → No; solo copiar, recrear y restaurar. Por eso se amplía poco a poco.
