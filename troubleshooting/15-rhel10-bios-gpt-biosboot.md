# 15 — RHEL 10 + BIOS: falta partición biosboot (GPT por defecto)

**Objetivo**: reconocer y corregir un fallo de instalación **desatendida** de RHEL 10 en un host BIOS (SeaBIOS/no UEFI), causado por un cambio real de comportamiento de Anaconda respecto a RHEL 7/8/9.

**Preparación**: host con firmware BIOS (el diseño del laboratorio usa SeaBIOS, ver `architecture/architecture.md`), VM `rhel10-app01` sin instalar o recién creada.

## Cómo se manifestó (caso real, verificado en hardware)

`scripts/lab.sh vm-create rhel10-app01` se quedó colgado sin avanzar ni dar error visible en el log de `virt-install`. Tras el límite de `--wait 60` (60 min), `virt-install`/libvirt mataron la VM con `SIGTERM`. El disco quedó completamente vacío: sin firma de arranque MBR (`55 aa`) y sin particiones reconocibles por `virt-filesystems`.

Al conectar por consola serie durante un nuevo intento (`virsh console rhel10-app01 --force`) y forzar el modo interactivo de Anaconda, apareció el mensaje real:

```
Installation Destination
[!] Installation Destination     (Kickstart insufficient)
...
Your BIOS-based system needs a special partition to boot from a GPT disk label.
To continue, please create a 1MiB 'biosboot' type partition on the vda disk.
```

## Hipótesis descartadas antes de dar con la causa

1. `os-variant` incorrecto (osinfo-db sin `rhel10.x`) — descartado: no cambia el esquema de particionado de Anaconda.
2. VM "colgada"/CPU en bucle — descartado: `virsh qemu-monitor-command --hmp "info registers"` mostraba `HLT=1` con `EIP` estable tras un `virsh reset`, compatible con SeaBIOS en "No bootable device" (esperando en el punto exacto donde antes Anaconda se había quedado sin poder continuar), no con un cuelgue real del kernel.
3. Kickstart de RHEL 10 distinto al de RHEL 9 en las líneas de particionado — descartado: son idénticas línea a línea (mismo `ignoredisk`, `clearpart`, `bootloader`, `part /boot`, `part pv.01`).

## Diagnóstico que sí lo confirmó

```bash
# Disco vacío tras el intento fallido (solo lectura, VM apagada):
sudo virt-filesystems --long --all -a /var/lib/libvirt/lab/images/rhel10-app01.qcow2
sudo guestfish --ro -a /var/lib/libvirt/lab/images/rhel10-app01.qcow2 run : \
  pread-device /dev/sda 512 0 | xxd | tail -3     # sin "55 aa" al final: sin firma de arranque

# Confirmación definitiva: repetir la instalación con la consola abierta desde el
# principio (virsh console rhel10-app01 --force en una segunda terminal) y
# completar los pasos interactivos de Anaconda cuando avisa de "Kickstart
# insufficient" en Installation Destination -> aparece el mensaje de biosboot.
```

## Causa raíz

**El Anaconda de RHEL 10 etiqueta el disco como GPT por defecto, incluso en un sistema con firmware BIOS.** RHEL 7/8/9 usaban MBR (msdos) automáticamente en estas condiciones y el mismo kickstart les bastaba. Con BIOS + GPT, GRUB2 necesita una partición de 1 MiB de tipo `biosboot` (equivalente a la partición EF02 de gdisk) donde alojar su código de segunda etapa; sin ella, Anaconda no puede completar el particionado y --en modo desatendido-- se queda esperando una decisión que el kickstart no le da, hasta que `virt-install --wait` la corta.

## Solución

Añadir la partición `biosboot` **antes** de `/boot` en el kickstart de RHEL 10 (solo RHEL 10; no hace falta en 7/8/9):

```diff
+part biosboot --fstype=biosboot --size=1 --ondisk=vda
 part /boot --fstype=xfs --size=1024 --ondisk=vda
 part pv.01 --size=1 --grow --ondisk=vda
```

Aplicado en `scripts/kickstart/rhel10.ks.tpl`. Validado con `ksvalidator -v RHEL10` antes de usarlo, y confirmado con una instalación real completa y desatendida en hardware (sin intervención manual en Anaconda).

## Validación

```bash
bash scripts/lab.sh vm-create rhel10-app01 --force
# con virsh console rhel10-app01 --force abierta en paralelo: Anaconda ya NO
# pregunta por Installation Destination; termina y se apaga sola como 7/8/9.
scripts/lab.sh test test_install.sh rhel10-app01
```

## Prevención

- Cualquier plantilla de kickstart nueva para una versión mayor de RHEL debe probarse con la consola (`virsh console ... --force`) abierta desde el primer segundo del primer intento, no solo confiar en el código de salida de `virt-install`: un `--wait` que expira no distingue "instalación lenta" de "Anaconda esperando una respuesta que nunca llegará".
- Diferencia a tener en cuenta al escribir o adaptar kickstarts para versiones futuras de RHEL en firmware BIOS: **no asumas MBR automático**; sé explícito con la partición `biosboot` si el host no es UEFI.
