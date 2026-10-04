#!/usr/bin/env bash
# =============================================================================
# 10-nfs-datastore.sh — (dns01) Export NFS para el datastore COMPARTIDO de ESXi
#
# Requisito: el disco SCSI con serie 'labnfs' (lo conecta 06-dns01-nfs-disk.sh
# desde el host; 'lab.sh stage8-nfs' encadena los dos pasos).
#
#   disco 'labnfs' -> PV -> vg_nfs -> lv_vmware (XFS) -> /srv/nfs/vmware
#   export a esxi01-03 (rw, sync, no_root_squash: ESXi escribe en NFS como root)
#
# Es un precursor mínimo de la Etapa 13 (NFS/CIFS), que lo tratará a fondo.
# Idempotente, con copia de seguridad de /etc/fstab. NO marca LAB_STAGE (la Etapa 7
# sigue en curso: ver 99-mark-stage.sh).
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root
[[ "$(hostname -s)" == dns01 ]] || fatal "Este script es solo para dns01"

MP=/srv/nfs/vmware
EXPORTS=/etc/exports.d/lab-vmware.exports
CLIENTS=(10.10.10.60 10.10.10.61 10.10.10.62)
STAMP="$(date +%Y%m%d%H%M%S)"

# --- 1) Disco ------------------------------------------------------------------------
shopt -s nullglob
ids=(/dev/disk/by-id/*labnfs)
(( ${#ids[@]} >= 1 )) || fatal "No aparece el disco con serie 'labnfs' (ejecuta desde el host: lab.sh stage8-nfs)"
DISK="$(readlink -f "${ids[0]}")"
say "Disco del datastore: ${ids[0]} -> $DISK"

if vgs vg_nfs >/dev/null 2>&1; then
  say "[=] vg_nfs ya existe"
else
  [[ -z "$(lsblk -no MOUNTPOINT "$DISK" | tr -d '[:space:]')" ]] || fatal "$DISK tiene algo montado"
  [[ -z "$(wipefs -n "$DISK")" ]] || fatal "$DISK tiene firmas previas (wipefs -n $DISK): no se toca"
  pvcreate -y "$DISK"
  vgcreate vg_nfs "$DISK"
  lvcreate -y -n lv_vmware -l 100%FREE vg_nfs
  mkfs.xfs -q /dev/vg_nfs/lv_vmware
  say "[+] vg_nfs/lv_vmware (XFS) creado"
fi

mkdir -p "$MP"
uuid="$(blkid -s UUID -o value /dev/vg_nfs/lv_vmware)"
if ! grep -qE "^UUID=${uuid}[[:space:]]" /etc/fstab; then
  cp -a /etc/fstab "/etc/fstab.lab-bak.$STAMP"
  printf 'UUID=%s %s xfs defaults 0 0\n' "$uuid" "$MP" >> /etc/fstab
  say "[+] fstab: UUID=$uuid -> $MP (copia: /etc/fstab.lab-bak.$STAMP)"
fi
systemctl daemon-reload
mount -a
findmnt -no SOURCE,FSTYPE "$MP" || fatal "$MP no está montado"
chown root:root "$MP"; chmod 0755 "$MP"
restorecon -R "$MP" || true

# --- 2) Servidor NFS -------------------------------------------------------------------
rpm -q nfs-utils >/dev/null 2>&1 || dnf -y install nfs-utils
mkdir -p /etc/exports.d
[[ -f "$EXPORTS" ]] && cp -a "$EXPORTS" "$EXPORTS.lab-bak.$STAMP"
{
  echo "# Gestionado por enterprise-rhel-lab (stage8/10-nfs-datastore.sh) — datastore NFS de los ESXi"
  printf '%s' "$MP"
  for c in "${CLIENTS[@]}"; do printf ' %s(rw,sync,no_root_squash,no_subtree_check)' "$c"; done
  echo
} > "$EXPORTS"
chmod 0644 "$EXPORTS"

# SELinux: con nfs_export_all_rw=on (valor por defecto) se puede exportar en lectura/escritura
if command -v getsebool >/dev/null && getsebool nfs_export_all_rw | grep -q off; then
  setsebool -P nfs_export_all_rw on; say "[+] boolean nfs_export_all_rw -> on"
fi

if systemctl is-active --quiet firewalld; then
  for s in nfs rpc-bind mountd; do firewall-cmd --permanent --add-service="$s" >/dev/null; done
  firewall-cmd --reload >/dev/null
  say "[+] firewalld: nfs, rpc-bind y mountd permitidos"
fi
systemctl enable --now nfs-server >/dev/null 2>&1
exportfs -ra
say "Exports activos:"
exportfs -v | sed 's/^/  /'
