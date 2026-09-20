#!/usr/bin/env bash
# lib.sh — constantes y funciones comunes de los scripts que corren EN EL HOST.
# Uso:  source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# (No activa 'set -e': lo decide cada script que lo carga.)
# shellcheck disable=SC2034  # las variables las usan los scripts que hacen 'source'

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$LAB_ROOT/scripts"
HOSTS_CONF="${HOSTS_CONF:-$SCRIPTS_DIR/hosts.conf}"

LIBVIRT_URI="qemu:///system"
export LIBVIRT_DEFAULT_URI="$LIBVIRT_URI"

LAB_CONF="${LAB_CONF:-$HOME/.config/rhel-lab/isos.conf}"
LAB_STORE="${LAB_STORE:-/var/lib/libvirt/lab}"
LAB_SSH_KEY="${LAB_SSH_KEY:-$HOME/.ssh/lab_ed25519}"
LAB_KNOWN_HOSTS="$HOME/.ssh/known_hosts_lab"
LAB_ADMIN="adminlab"
LAB_NET="lab-net"
LAB_BRIDGE="virbr-lab"
LAB_GW="10.10.10.1"
LAB_DNS_SERVER="10.10.10.20"
LAB_DOMAIN="lab.local"
LAB_TZ="${LAB_TZ:-Europe/Madrid}"

SSH_OPTS=(-i "$LAB_SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5
          -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$LAB_KNOWN_HOSTS")

info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Falta el comando '$1'"; }

# --- Inventario (hosts.conf) --------------------------------------------------
host_row()   { awk -v n="$1" '$1==n {print; f=1} END{exit !f}' "$HOSTS_CONF"; }
host_field() { host_row "$1" | awk -v f="$2" '{print $f}'; }
all_hosts()  { awk '$1 !~ /^#/ && NF>=7 {print $1}' "$HOSTS_CONF"; }
ip_of()      { host_field "$1" 3; }
ver_of()     { host_field "$1" 2; }
targets() {  # 'all' o un nombre válido -> lista de nombres
  if [[ "$1" == all ]]; then all_hosts
  else host_row "$1" >/dev/null || die "Host desconocido: $1 (mira $HOSTS_CONF)"; echo "$1"; fi
}

# --- Configuración de ISOs (isos.conf) ------------------------------------------
conf_get() {  # conf_get CLAVE -> valor sin comillas ni espacios finales
  [[ -f "$LAB_CONF" ]] || return 0
  sed -nE "s/^[[:space:]]*$1=[\"']?([^\"'#]*)[\"']?.*$/\1/p" "$LAB_CONF" \
    | tail -n1 | sed -E "s|^~|$HOME|; s|\\\$HOME|$HOME|; s/[[:space:]]+\$//"
}
iso_dir() { local d; d="$(conf_get ISO_DIR)"; echo "${d:-$LAB_STORE/isos}"; }

# --- SSH ------------------------------------------------------------------------
wait_ssh() {  # wait_ssh HOST [intentos]  (5 s entre intentos)
  local h="$1" tries="${2:-60}" i
  for ((i = 0; i < tries; i++)); do
    if ssh "${SSH_OPTS[@]}" "$LAB_ADMIN@$(ip_of "$h")" true 2>/dev/null; then return 0; fi
    sleep 5
  done
  return 1
}
