#!/usr/bin/env bash
# =============================================================================
# 04-esxi-status.sh — Estado de los ESXi del lab (SOLO LECTURA)
#
# Uso:  04-esxi-status.sh [esxi01|esxi02|esxi03|all]     (por defecto: all)
#
# Por host: estado en libvirt, HTTPS, SSH, versión, licencia (gratuita o evaluación
# y su CADUCIDAD), modo mantenimiento, NTP, datastores, VMs internas y snapshots.
# Al final: RAM y disco libres del host y si vCenter (vcsa01) responde.
# =============================================================================
set -uo pipefail
# shellcheck source=vmware-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/vmware-lib.sh"

for h in $(vmw_targets "${1:-all}"); do
  ip="$(vmw_ip "$h")"; st="$(vmw_state "$h")"
  echo; info "=== $h ($(vmw_role "$h"), $ip) — libvirt: ${st:-no existe} ==="
  [[ "$st" == running ]] || { snaps="$(virsh snapshot-list "$h" --name 2>/dev/null | grep . | tr '\n' ' ')"; [[ -n "$snaps" ]] && echo "  snapshots: $snaps"; continue; }
  tcp_open "$ip" 443 && echo "  HTTPS 443 : OK  (https://$ip/ui/)" || echo "  HTTPS 443 : NO"
  if ! esxi_ssh "$h" true 2>/dev/null; then echo "  SSH       : NO (clave $LAB_ESXI_KEY)"; continue; fi
  echo "  SSH       : OK"
  # shellcheck disable=SC2016  # todo el bloque se evalúa en el ESXi, no en el host
  esxi_ssh "$h" '
    printf "  versión   : %s\n" "$(esxcli system version get | awk -F": " "/Version|Build/ {printf \"%s \", \$2}")"
    printf "  manten.   : %s\n" "$(esxcli system maintenanceMode get)"
    printf "  NTP       : %s\n" "$(esxcli system ntp get 2>/dev/null | awk -F": " "/Enabled|Server/ {printf \"%s=%s \", \$1, \$2}" | tr -s " ")"
    echo   "  licencia  :"; vim-cmd vimsvc/license --show 2>/dev/null | grep -iE "^ *(name|expirationDate|editionKey) " | sed "s/^ */              /"
    echo   "  datastores:"; esxcli storage filesystem list 2>/dev/null | awk "NR>2 && \$2!=\"\" {printf \"              %-22s %-6s libre %d GB\n\", \$2, \$5, \$7/1073741824}"
    echo   "  VMs       :"; vim-cmd vmsvc/getallvms 2>/dev/null | awk "NR>1 && \$1 ~ /^[0-9]+$/ {print \$1, \$2}" | while read -r id n; do
                             printf "              %-20s %s\n" "$n" "$(vim-cmd vmsvc/power.getstate "$id" | tail -1)"; done
  ' 2>/dev/null
  snaps="$(virsh snapshot-list "$h" --name 2>/dev/null | grep . | tr '\n' ' ')"; echo "  snapshots : ${snaps:-ninguno}"
done

echo
info "=== Host y vCenter ==="
printf '  RAM disponible : %s MB\n' "$(mem_avail_mb)"
printf '  Disco libre    : %s (%s)\n' "$(df -h --output=avail "$LAB_STORE" | tail -1 | tr -d ' ')" "$LAB_STORE"
tcp_open "$VCSA_IP" 443 && echo "  vCenter        : OK  https://$VCSA_NAME.$LAB_DOMAIN/ui/ ($VCSA_IP)" || echo "  vCenter        : no responde ($VCSA_IP:443)"
tcp_open "$GUEST_IP" 22 && echo "  $GUEST_NAME     : SSH OK ($GUEST_IP)" || echo "  $GUEST_NAME     : no responde ($GUEST_IP:22)"
exit 0
