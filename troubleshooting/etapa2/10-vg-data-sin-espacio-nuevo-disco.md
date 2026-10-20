# Etapa 2 · Caso 10 — `/backup` lleno y `vg_data` sin espacio: añadir un disco nuevo al VG

**Objetivo**: resolver el caso más habitual de almacenamiento en producción: un sistema de ficheros se
llena y el grupo de volúmenes ya no tiene espacio libre. La solución es añadir un disco nuevo (`pvcreate` +
`vgextend`) y ampliar el volumen en caliente (`lvextend -r`), **sin desmontar ni parar el servicio**.

**Preparación**:
- `rhel9-app01` con la Etapa 2 aplicada (sirve cualquier `app01`; `dns01` y `ansible01` no tienen `vg_data`).
- Snapshot de práctica con la VM apagada, en el **host**:
  ```bash
  scripts/lab.sh down rhel9-app01            # espera a que esté apagada: virsh domstate rhel9-app01
  virsh -c qemu:///system snapshot-create-as rhel9-app01 rhel9-pre-caso10 --description "Antes del caso etapa2/10"
  scripts/lab.sh up rhel9-app01
  ```
- Unos 5 GB libres en el pool `lab-images` del host (el disco nuevo es *thin*: ocupa solo lo que se escribe).

## Cómo provocar

Dentro de `rhel9-app01`, como root:

```bash
vgs vg_data                                        # VFree ≈ 2 GiB (lo que deja 02-lvm.sh)
lvextend -r -l +100%FREE /dev/vg_data/lv_backup    # gasta TODO el espacio libre del VG en /backup
avail=$(df --output=avail -BM /backup | tail -1 | tr -dc '0-9')
fallocate -l $((avail - 100))M /backup/relleno-caso10.img   # deja /backup casi lleno (~100 MB libres)
```

## Síntoma

```bash
df -hT /backup                       # Use% 98-99 %
dd if=/dev/zero of=/backup/prueba bs=1M count=200    # "No space left on device"
lvextend -r -L +1G /dev/vg_data/lv_backup            # "Insufficient free space: 256 extents needed, but only 0 available"
```

El servicio que escribe en `/backup` (en producción: copias de seguridad, ficheros de una interfaz, logs)
empieza a fallar. Es una **incidencia**: primero se restaura el servicio y después se analiza la causa.

## Hipótesis

1. Un proceso está escribiendo sin control (log, copia, fichero temporal) → ¿se puede liberar espacio?
2. Hay ficheros borrados que un proceso mantiene abiertos → `df` dice lleno pero `du` no lo encuentra.
3. El volumen se quedó pequeño de verdad para el uso real → hay que **ampliar**.
4. Se acabaron los inodos, no los bloques → `df -i`.

## Diagnóstico

```bash
df -hT /backup ; df -i /backup                     # ¿bloques o inodos?
du -xh --max-depth=1 /backup | sort -h | tail      # qué ocupa (-x: no cruza a otros sistemas de ficheros)
find /backup -xdev -type f -size +500M -exec ls -lh {} +   # ficheros grandes
lsof +L1 2>/dev/null | grep /backup                # borrados pero abiertos (hipótesis 2)
vgs vg_data                                        # VFree = 0 → no se puede ampliar desde el VG
pvs ; lvs vg_data                                  # en qué PV está cada LV
```

En este escenario, `relleno-caso10.img` hace de "datos legítimos que no se pueden borrar". Se descartan
las hipótesis 1, 2 y 4: el volumen se ha quedado pequeño y el VG no tiene espacio → **hace falta un disco nuevo**.

## Causa raíz

El LV ha crecido hasta ocupar todo el VG y el uso real de `/backup` supera su capacidad. En LVM, un LV solo
puede crecer con extensiones libres de **su** VG; si el VG está a 0, hay que darle más espacio físico.

## Solución

**1. En el host: crear un disco de 5 GB y conectarlo en caliente** (el equivalente a que el equipo de
virtualización o de almacenamiento te asigne una LUN o un disco nuevo):

```bash
virsh -c qemu:///system vol-create-as lab-images rhel9-app01-data2.qcow2 5G --format qcow2
DISK=$(virsh -c qemu:///system vol-path rhel9-app01-data2.qcow2 --pool lab-images)
virsh -c qemu:///system attach-disk rhel9-app01 "$DISK" vdc \
      --driver qemu --subdriver qcow2 --targetbus virtio --persistent
virsh -c qemu:///system domblklist rhel9-app01      # aparece vdc
```

`--persistent` lo conecta en caliente **y** lo guarda en la definición de la VM (sobrevive al reinicio).

**2. En la VM: identificar el disco nuevo sin equivocarse**

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT          # el disco de 5G sin particiones ni FSTYPE
wipefs -n /dev/vdc                                  # sin salida = vacío (comprobación de seguridad)
```

El nombre que ve la VM (`vdc`) **no está garantizado**: confírmalo por tamaño y por estar vacío. En
producción, este es el paso donde se formatea el disco equivocado.

**3. LVM: PV nuevo → VG más grande → LV más grande**

```bash
pvcreate /dev/vdc                                   # el disco pasa a ser un volumen físico
vgextend vg_data /dev/vdc                           # se añade al grupo: VFree ≈ 5 GiB
vgs vg_data ; pvs
lvextend -r -L +3G /dev/vg_data/lv_backup           # amplía el LV Y el XFS (-r), montado y en uso
df -hT /backup                                      # ~3 GiB más, sin desmontar
```

Se amplía **lo necesario** (+3G), no todo: los ~2 GiB que quedan libres en el VG son margen para la
siguiente vez (y es lo que comprueba `test_storage.sh`).

**4. Restaurar el servicio**: `dd if=/dev/zero of=/backup/prueba bs=1M count=200` ya funciona;
`rm -f /backup/prueba`.

## Validación

```bash
df -hT /backup                                      # Use% bajo
vgs vg_data                                         # #PV = 2, VFree ≥ 1 GiB
pvs -o pv_name,vg_name,pv_size,pv_free
lvs -o lv_name,lv_size,devices vg_data              # lv_backup ocupa extensiones de vdb y vdc
grep /backup /etc/fstab                             # mismo UUID: no hay que tocar fstab
```

Y desde el host: `scripts/lab.sh test test_storage.sh rhel9-app01` → 0 FAIL.

**Prueba de reinicio**: `reboot` y comprobar que `/backup` monta y `vgs vg_data` sigue mostrando 2 PV.

## Volver al estado inicial

En el host:

```bash
scripts/lab.sh down rhel9-app01                    # espera a "shut off"
virsh -c qemu:///system snapshot-revert rhel9-app01 rhel9-pre-caso10
virsh -c qemu:///system domblklist rhel9-app01     # vdc ya no debe aparecer
# Si apareciera: virsh -c qemu:///system detach-disk rhel9-app01 vdc --config
virsh -c qemu:///system vol-delete rhel9-app01-data2.qcow2 --pool lab-images
virsh -c qemu:///system snapshot-delete rhel9-app01 rhel9-pre-caso10
scripts/lab.sh up rhel9-app01
```

El `vol-delete` es necesario: el snapshot devuelve la VM a su estado anterior, pero el fichero qcow2 del
disco nuevo se queda en el pool. Vuelve al estado inicial **antes** de crear el siguiente snapshot de etapa,
para que no arrastre el disco de práctica.

## Prevención

- Monitorizar el uso de los sistemas de ficheros con umbrales de aviso (80 %) y crítico (90 %), y la
  tendencia de crecimiento, no solo el valor actual.
- Dejar siempre espacio libre en el VG en lugar de asignarlo todo a los LV: ampliar es inmediato, reducir un
  XFS es imposible.
- Ampliar con `lvextend -r` (o `xfs_growfs <punto de montaje>` justo después): un LV ampliado sin ampliar el
  sistema de ficheros no da espacio a nadie.
- Documentar el cambio (disco añadido, tamaño, LV ampliado) y actualizar el inventario.

## Diferencias RHEL 7 / 8 / 9 / 10

- **RHEL 9 y 10**: LVM usa por defecto el fichero de dispositivos (`/etc/lvm/devices/system.devices`).
  `pvcreate` y `vgextend` añaden el disco nuevo automáticamente; compruébalo con `lvmdevices` ◦. Si un disco
  se añade por otra vía (por ejemplo, un PV que ya existía en otro sistema), LVM **no lo ve** hasta
  `lvmdevices --adddev /dev/vdX` o `vgimportdevices` ◦.
- **RHEL 7 y 8**: no hay fichero de dispositivos activo por defecto; LVM busca en todos los discos ◦.
- `lvextend -r` funciona en las cuatro versiones (llama a `xfs_growfs` por debajo) ◦.

## Lo que se pregunta en una entrevista

*"El /data de un servidor está al 98 % y el VG no tiene espacio libre. ¿Qué haces?"* → Restaurar primero
(¿hay algo que se pueda liberar o rotar?), y si no, pedir un disco nuevo y: `lsblk` → `pvcreate` →
`vgextend` → `lvextend -r` → `df -h`, todo en caliente. Después, analizar por qué creció y ajustar la
monitorización.
