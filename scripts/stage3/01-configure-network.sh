#!/usr/bin/env bash
# =============================================================================
# 01-configure-network.sh — IP estática, gateway, DNS y hostname con nmcli
#
# Uso (lo invoca 'lab.sh stage3'):
#   01-configure-network.sh --ip 10.10.10.13 --gw 10.10.10.1 --dns 10.10.10.1 \
#                           --hostname rhel9-app01.lab.local [--domain lab.local]
#
# DNS de arranque (10.10.10.1 = dnsmasq de libvirt) mientras dns01 no existe.
# En la Etapa 4 se vuelve a ejecutar con --dns 10.10.10.20 (DNS del laboratorio).
# La conexión resultante se llama SIEMPRE 'lab0' (mismo nombre en RHEL 7/8/9/10).
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root

IP="" GW="" DNS="" HOST="" DOMAIN="lab.local"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ip) IP="$2"; shift ;; --gw) GW="$2"; shift ;; --dns) DNS="$2"; shift ;;
    --hostname) HOST="$2"; shift ;; --domain) DOMAIN="$2"; shift ;;
    *) fatal "Opción desconocida: $1" ;;
  esac
  shift
done
[[ -n "$IP" && -n "$GW" && -n "$DNS" && -n "$HOST" ]] || fatal "Faltan --ip --gw --dns --hostname"
command -v nmcli >/dev/null || fatal "nmcli no está instalado"
systemctl is-active --quiet NetworkManager || fatal "NetworkManager no está activo"

dev="$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="ethernet"{print $1; exit}')"
[[ -n "$dev" ]] || fatal "No hay interfaz ethernet"
con="$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v d="$dev" '$2==d{print $1; exit}')"

if [[ -z "$con" ]]; then
  nmcli connection add type ethernet ifname "$dev" con-name lab0 >/dev/null
  say "[+] conexión lab0 creada sobre $dev"
elif [[ "$con" != lab0 ]]; then
  nmcli connection modify "$con" connection.id lab0
  say "[~] conexión '$con' renombrada a lab0"
fi

nmcli connection modify lab0 \
  connection.interface-name "$dev" connection.autoconnect yes \
  ipv4.method manual ipv4.addresses "$IP/24" ipv4.gateway "$GW" \
  ipv4.dns "$DNS" ipv4.dns-search "$DOMAIN" ipv4.ignore-auto-dns yes \
  ipv6.method ignore

# Aplicar sin cortar la sesión SSH (la IP no cambia): reapply y, si no se puede, 'up'
nmcli device reapply "$dev" >/dev/null 2>&1 || nmcli connection up lab0 >/dev/null
hostnamectl set-hostname "$HOST"

say "Resultado:"
ip -br -4 addr show dev "$dev"
ip route show default
grep -E '^(search|nameserver)' /etc/resolv.conf || true
hostnamectl --static
say "Fichero de perfil: $(nmcli -t -f NAME,FILENAME connection show 2>/dev/null | awk -F: '$1=="lab0"{print $2}')"
set_stage 3
