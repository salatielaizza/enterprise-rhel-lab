#!/usr/bin/env bash
# vmware-lib.sh — funciones comunes de los scripts de la Etapa 8 que corren EN EL HOST.
# Uso:  source "$(dirname "${BASH_SOURCE[0]}")/vmware-lib.sh"   (carga también ../lib.sh)
# (No activa 'set -e': lo decide cada script que lo carga.)
# shellcheck disable=SC2034  # las variables las usan los scripts que hacen 'source'

# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

STAGE8_DIR="$SCRIPTS_DIR/stage8"
VMW_CONF="${VMW_CONF:-$SCRIPTS_DIR/vmware.conf}"

# Clave SSH SOLO para root@ESXi. Es RSA y no ed25519 a propósito: el sshd de ESXi 8
# funciona en modo FIPS por defecto y ed25519 no es un algoritmo aprobado por FIPS.
LAB_ESXI_KEY="${LAB_ESXI_KEY:-$HOME/.ssh/lab_esxi_rsa}"
ESXI_SSH_OPTS=(-i "$LAB_ESXI_KEY" -o BatchMode=yes -o ConnectTimeout=5 -o IdentitiesOnly=yes
               -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$LAB_KNOWN_HOSTS")

VCSA_NAME="vcsa01"; VCSA_IP="10.10.10.63"
GUEST_NAME="rhel9-vm01"; GUEST_IP="10.10.10.64"

# --- Inventario (vmware.conf) ---------------------------------------------------
vmw_row()   { awk -v n="$1" '$1==n {print; f=1} END{exit !f}' "$VMW_CONF"; }
vmw_field() { vmw_row "$1" | awk -v f="$2" '{print $f}'; }
vmw_all()   { awk '$1 !~ /^#/ && NF>=9 {print $1}' "$VMW_CONF"; }
vmw_ip()    { vmw_field "$1" 3; }
vmw_role()  { vmw_field "$1" 2; }
vmw_targets() {  # 'all' o un nombre de vmware.conf -> lista de nombres
  if [[ "$1" == all ]]; then vmw_all
  else vmw_row "$1" >/dev/null || die "ESXi desconocido: $1 (mira $VMW_CONF)"; echo "$1"; fi
}

# --- Estado ---------------------------------------------------------------------
vmw_state()  { virsh domstate "$1" 2>/dev/null | tr -d '[:space:]'; }
tcp_open()   { timeout 3 bash -c "</dev/tcp/$1/$2" 2>/dev/null; }      # tcp_open IP PUERTO
# shellcheck disable=SC2029  # los argumentos son el comando remoto: se pasan tal cual a ssh
esxi_ssh()   { local h="$1"; shift; ssh "${ESXI_SSH_OPTS[@]}" "root@$(vmw_ip "$h")" "$@"; }
mem_avail_mb() { awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo; }

wait_https() {  # wait_https IP [intentos]  (10 s entre intentos) — ESXi tarda en levantar hostd
  local ip="$1" tries="${2:-60}" i
  for ((i = 0; i < tries; i++)); do
    tcp_open "$ip" 443 && return 0
    sleep 10
  done
  return 1
}

# ISO configurados en ~/.config/rhel-lab/isos.conf (ESXI_FREE_ISO, ESXI_EVAL_ISO, VCSA_ISO):
# nombre de fichero dentro de ISO_DIR, o ruta absoluta.
iso_path() {
  local v; v="$(conf_get "$1")"
  [[ -n "$v" ]] || return 1
  [[ "$v" == /* ]] && echo "$v" || echo "$(iso_dir)/$v"
}
base_iso_for() {  # base_iso_for HOST -> ISO original según su ROLE
  case "$(vmw_role "$1")" in
    free) iso_path ESXI_FREE_ISO ;;
    eval) iso_path ESXI_EVAL_ISO ;;
    *) return 1 ;;
  esac
}
ks_iso_for() { echo "$(iso_dir)/$1-ks.iso"; }   # ISO personalizado con kickstart

ensure_esxi_key() {
  if [[ ! -f "$LAB_ESXI_KEY" ]]; then
    info "Creando la clave SSH del lab para root@ESXi: $LAB_ESXI_KEY (RSA 4096, sin passphrase)"
    ssh-keygen -q -t rsa -b 4096 -N '' -f "$LAB_ESXI_KEY" -C "root-esxi@$LAB_DOMAIN"
  fi
}
