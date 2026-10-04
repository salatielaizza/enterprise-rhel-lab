#!/usr/bin/env bash
# Etapa 8 — Datastore NFS compartido de los ESXi. Se ejecuta en dns01 (en los demás no hace nada):
#   scripts/lab.sh test test_nfs_datastore.sh dns01
# shellcheck disable=SC2034  # TEST_NAME lo usa summary() de lib.sh
TEST_NAME=test_nfs_datastore; source "$(dirname "$0")/lib.sh"; need_root

if [[ "$(hostname -s)" != dns01 ]]; then
  echo "test_nfs_datastore: solo aplica en dns01"
  summary; exit $?
fi

MP=/srv/nfs/vmware
check "disco SCSI 'labnfs' presente (no es /dev/vdb: no choca con la Etapa 2)" bash -c 'compgen -G "/dev/disk/by-id/*labnfs" >/dev/null'
check "LV vg_nfs/lv_vmware existe" lvs vg_nfs/lv_vmware
check "$MP montado desde lv_vmware" bash -c "findmnt -no SOURCE $MP | grep -q lv_vmware"
check "$MP es XFS" bash -c "[[ \"\$(findmnt -no FSTYPE $MP)\" == xfs ]]"
check "fstab usa UUID para $MP" bash -c "grep -Eq '^UUID=[0-9a-f-]+[[:space:]]+${MP}[[:space:]]+xfs' /etc/fstab"
check "nfs-server activo y habilitado" bash -c 'systemctl is-active --quiet nfs-server && systemctl is-enabled --quiet nfs-server'
# Opciones de UN cliente concreto (sin que el patrón salte a las de otro cliente)
export_opts() { exportfs -v | tr -d '\n\t ' | grep -o "$MP$1([^)]*)"; }
export_ok()   { local o; o="$(export_opts "$1")" && grep -qE '[(,]rw[,)]' <<<"$o" && grep -q 'no_root_squash' <<<"$o"; }
for ip in 10.10.10.60 10.10.10.61 10.10.10.62; do
  check "export a $ip con rw y no_root_squash" export_ok "$ip"
done
for s in nfs rpc-bind mountd; do
  check "firewalld permite $s" bash -c "firewall-cmd --list-services | grep -qw $s"
done
check "SELinux: nfs_export_all_rw = on" bash -c 'getsebool nfs_export_all_rw | grep -q "on$"'
check "showmount publica $MP" bash -c "showmount -e localhost | grep -q '^$MP '"
summary
