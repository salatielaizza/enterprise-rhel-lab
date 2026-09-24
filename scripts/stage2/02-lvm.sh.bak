#!/usr/bin/env bash
# =============================================================================
# 02-lvm.sh — LVM + XFS sobre el disco de datos (/dev/vdb, 10 GB)
#
#   vg_data
#    ├── lv_application (3G) -> /opt/application/data
#    ├── lv_logs        (2G) -> /var/log/lab-app
#    └── lv_backup      (3G) -> /backup
#   (~2 GB libres en el VG para ejercicios de ampliación y snapshots)
#
# Seguridad: aborta si el disco está montado o tiene firmas. NO destruye datos.
# Persistencia: /etc/fstab por UUID (con copia previa en /etc/fstab.lab-bak).
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root

DISK="${LAB_DATA_DISK:-/dev/vdb}"
if [[ ! -b "$DISK" ]]; then say "Sin disco de datos ($DISK): se omite LVM en este host"; exit 0; fi

if vgs vg_data >/dev/null 2>&1; then
  say "[=] vg_data ya existe: no se crea nada nuevo"
else
  [[ -z "$(lsblk -no MOUNTPOINT "$DISK" | tr -d '[:space:]')" ]] || fatal "$DISK tiene algo montado"
  [[ -z "$(wipefs -n "$DISK")" ]] || fatal "$DISK tiene firmas previas (revisa: wipefs -n $DISK). Limpia manualmente solo si es seguro."
  pvcreate -y "$DISK"
  vgcreate vg_data "$DISK"
  lvcreate -y -n lv_application -L 3G vg_data
  lvcreate -y -n lv_logs        -L 2G vg_data
  lvcreate -y -n lv_backup      -L 3G vg_data
  for lv in lv_application lv_logs lv_backup; do mkfs.xfs -q "/dev/vg_data/$lv"; done
  say "[+] PV/VG/LV y sistemas de ficheros XFS creados"
fi

[[ -f /etc/fstab.lab-bak ]] || cp -a /etc/fstab /etc/fstab.lab-bak
mkdir -p /opt/application/data /var/log/lab-app /backup

add_mount() {  # add_mount LV PUNTO
  local dev="/dev/vg_data/$1" mp="$2" uuid
  uuid="$(blkid -s UUID -o value "$dev")"
  if ! grep -qE "^UUID=${uuid}[[:space:]]" /etc/fstab; then
    printf 'UUID=%s %s xfs defaults 0 0\n' "$uuid" "$mp" >> /etc/fstab
    say "[+] fstab: UUID=$uuid -> $mp"
  fi
}
add_mount lv_application /opt/application/data
add_mount lv_logs        /var/log/lab-app
add_mount lv_backup      /backup
systemctl daemon-reload            # regenera las unidades .mount desde fstab
mount -a
restorecon -RF /opt/application/data /var/log/lab-app /backup || true
say "Montajes:"; findmnt -no TARGET,SOURCE,FSTYPE /opt/application/data /var/log/lab-app /backup
vgs vg_data
