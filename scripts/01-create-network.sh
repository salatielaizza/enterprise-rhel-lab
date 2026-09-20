#!/usr/bin/env bash
# =============================================================================
# 01-create-network.sh — Crea la red virtual lab-net (10.10.10.0/24, NAT)
#
#  - Modo NAT: el host hace de router y sale a Internet por tu Wi-Fi
#    (un bridge sobre Wi-Fi no funciona bien).
#  - Sin DHCP: todas las VMs usan IP estática (ver scripts/hosts.conf).
#  - dnsmasq de libvirt escucha en 10.10.10.1:53 y se usa SOLO como forwarder
#    de arranque; el DNS del laboratorio es dns01 (10.10.10.20).
# =============================================================================
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need virsh

if virsh net-info "$LAB_NET" >/dev/null 2>&1; then
  info "La red $LAB_NET ya existe"
else
  if ip route | grep -q '^10\.10\.10\.'; then
    die "Ya hay una ruta 10.10.10.0/24 en este host (¿VPN u otra red?). Revisa 'ip route' antes de continuar."
  fi
  XML="$(mktemp)"; trap 'rm -f "$XML"' EXIT
  cat > "$XML" <<EOF_XML
<network>
  <name>$LAB_NET</name>
  <forward mode='nat'/>
  <bridge name='$LAB_BRIDGE' stp='on' delay='0'/>
  <ip address='$LAB_GW' netmask='255.255.255.0'/>
</network>
EOF_XML
  virsh net-define "$XML" >/dev/null
  ok "Red $LAB_NET definida"
fi

virsh net-autostart "$LAB_NET" >/dev/null
virsh net-info "$LAB_NET" | grep -Eq 'Active:[[:space:]]+yes' || virsh net-start "$LAB_NET" >/dev/null

echo
info "Verificación (el gateway debe ser $LAB_GW; NO se inventa: se lee de la red real)"
gw_real="$(virsh net-dumpxml "$LAB_NET" | sed -nE "s/.*<ip address='([^']+)'.*/\1/p")"
echo "  gateway según libvirt : $gw_real"
ip -br addr show "$LAB_BRIDGE" 2>/dev/null | sed 's/^/  /' || warn "El bridge $LAB_BRIDGE aún no aparece"
[[ "$gw_real" == "$LAB_GW" ]] || warn "El gateway real ($gw_real) difiere de lib.sh ($LAB_GW): corrige lib.sh y los kickstarts"
ok "Red lista. Si usas ufw: 'sudo ufw allow in on $LAB_BRIDGE' y 'sudo ufw route allow in on $LAB_BRIDGE'"
