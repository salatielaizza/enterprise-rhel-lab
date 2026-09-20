#!/usr/bin/env bash
# =============================================================================
# 03-permissions.sh — Escenario de permisos (setgid, sticky, ACL)
#
#  /opt/application          appuser:application   2750  (setgid: hereda grupo)
#  /opt/application/config   root:application      2750  + ACL developers r-x (y por defecto)
#  /opt/application/data     appuser:application   2770  + ACL developers r-x (y por defecto)
#  /backup                   root:backup           3770  (setgid + sticky)
#  /var/log/lab-app          appuser:application   2770
# Ejecutar DESPUÉS de 02-lvm.sh: los permisos de un punto de montaje son los de
# la raíz del sistema de ficheros montado, no los del directorio original.
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root
for u in appuser devuser backupuser; do id "$u" >/dev/null 2>&1 || fatal "Falta $u (ejecuta 01-users-groups.sh)"; done

mkdir -p /opt/application/config /opt/application/data /opt/application/bin /backup /var/log/lab-app

chown appuser:application /opt/application;        chmod 2750 /opt/application
chown root:application    /opt/application/config; chmod 2750 /opt/application/config
chown appuser:application /opt/application/data;   chmod 2770 /opt/application/data
chown root:application    /opt/application/bin;    chmod 2755 /opt/application/bin
chown root:backup         /backup;                 chmod 3770 /backup
chown appuser:application /var/log/lab-app;        chmod 2770 /var/log/lab-app

# ACL: developers pueden LEER config y data (no escribir). 'd:' = ACL por defecto (heredable)
for d in /opt/application /opt/application/config /opt/application/data; do
  setfacl -m g:developers:rx "$d"
done
setfacl -m d:g:developers:rx /opt/application/config /opt/application/data

if [[ ! -f /opt/application/config/lab-app.env ]]; then
  printf 'LAB_APP_INTERVAL=5\nLAB_APP_CRASH_AFTER=0\n' > /opt/application/config/lab-app.env
fi
chown root:application /opt/application/config/lab-app.env
chmod 0640 /opt/application/config/lab-app.env
setfacl -m g:developers:r /opt/application/config/lab-app.env

restorecon -R /opt/application /backup /var/log/lab-app || true
say "Permisos aplicados:"
ls -ld /opt/application /opt/application/config /opt/application/data /backup /var/log/lab-app
getfacl -p /opt/application/config | sed 's/^/  /'
