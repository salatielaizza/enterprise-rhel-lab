#!/usr/bin/env bash
# =============================================================================
# 06-dns01-nfs-disk.sh — (HOST) Añade a dns01 el disco del datastore NFS compartido
#
# Uso:  06-dns01-nfs-disk.sh [--dry-run]
#
# Crea el volumen dns01-nfs.qcow2 (60 GB, thin) en el pool lab-images y lo conecta
# a dns01 en caliente Y de forma persistente.
#
# Por qué virtio-SCSI y no virtio-blk: un segundo disco virtio aparecería en dns01
# como /dev/vdb, y scripts/stage2/02-lvm.sh trata /dev/vdb como "el disco de datos
# de la Etapa 2". Con virtio-SCSI aparece como /dev/sdX y se localiza por su serie
# (/dev/disk/by-id/*labnfs*), sin chocar con nada de etapas anteriores.
# Idempotente: si el volumen o el disco ya están, no hace nada.
# =============================================================================
set -euo pipefail
# shellcheck source=vmware-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/vmware-lib.sh"
need virsh

DRY=0; [[ "${1:-}" == --dry-run ]] && DRY=1
DOM=dns01; VOL=dns01-nfs.qcow2; SIZE=60G; SERIAL=labnfs; TARGET=sda
run() { if [[ $DRY -eq 1 ]]; then echo "+ $*"; else "$@"; fi; }

virsh dominfo "$DOM" >/dev/null 2>&1 || die "$DOM no existe"
state="$(virsh domstate "$DOM" | tr -d '[:space:]')"
live=(--config); [[ "$state" == running ]] && live=(--config --live)

# 1) Controlador virtio-SCSI
if virsh dumpxml "$DOM" | grep -q "model='virtio-scsi'"; then
  info "$DOM ya tiene controlador virtio-scsi"
else
  ctl="$(mktemp)"; trap 'rm -f "$ctl"' EXIT
  printf "<controller type='scsi' model='virtio-scsi'/>\n" > "$ctl"
  run virsh attach-device "$DOM" "$ctl" "${live[@]}"
  info "Controlador virtio-scsi añadido a $DOM"
fi

# 2) Volumen
if virsh vol-info --pool lab-images "$VOL" >/dev/null 2>&1; then
  info "El volumen $VOL ya existe"
else
  run virsh vol-create-as lab-images "$VOL" "$SIZE" --format qcow2
  info "Volumen $VOL ($SIZE, thin) creado"
fi
path="$(virsh vol-path --pool lab-images "$VOL" 2>/dev/null || echo "<ruta-de-$VOL>")"

# 3) Disco conectado
if virsh domblklist "$DOM" --details | awk '{print $4}' | grep -qx "$path"; then
  info "$VOL ya está conectado a $DOM"
else
  run virsh attach-disk "$DOM" "$path" "$TARGET" --driver qemu --subdriver qcow2 \
      --targetbus scsi --serial "$SERIAL" "${live[@]}"
  ok "$VOL conectado a $DOM como disco SCSI (serie '$SERIAL')"
fi
info "Siguiente: el script de dns01 lo formatea y exporta (lab.sh stage8-nfs lo encadena)"
