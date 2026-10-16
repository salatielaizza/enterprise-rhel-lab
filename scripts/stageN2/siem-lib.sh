#!/usr/bin/env bash
# =============================================================================
# siem-lib.sh — Funciones comunes de los scripts de la Etapa N2 que corren DENTRO
# de las VMs (como root, vía 'lab.sh' -> push + run_remote). Carga ../common.sh.
#
# Variables que exporta:
#   SIEM_NAME  siem01            SIEM_IP   IP de siem01 leída de ../hosts.conf
#   SIEM_DIR   /opt/siem         (proyecto de Docker Compose: compose + .env)
#   SIEM_SECRETS /root/.siem     (contraseñas generadas; 0700, nunca al repo)
#   STAMP      fecha para las copias de seguridad (*.lab-bak.<STAMP>)
# =============================================================================
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
# shellcheck disable=SC2034  # las variables las usan los scripts que cargan este fichero
{
  N2_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  N2_FILES="$N2_DIR/files"
  SIEM_NAME=siem01
  SIEM_IP="$(awk -v n="$SIEM_NAME" '$1==n {print $3}' "$N2_DIR/../hosts.conf" 2>/dev/null)"
  SIEM_IP="${SIEM_IP:-10.10.10.55}"
  SIEM_DIR=/opt/siem
  SIEM_SECRETS=/root/.siem
  STAMP="$(date +%Y%m%d-%H%M%S)"
}

warnmsg() { printf '[%s] AVISO: %s\n' "$(hostname -s)" "$*" >&2; }

# backup FICHERO -> copia FICHERO.lab-bak.<STAMP> si existe (regla del lab: nunca tocar sin copia)
backup() { if [[ -e "$1" ]]; then cp -a "$1" "$1.lab-bak.$STAMP"; say "copia de seguridad: $1.lab-bak.$STAMP"; fi; }

# require_host NOMBRE -> aborta si no estamos en esa VM (evita lanzar un script en la VM equivocada)
require_host() { [[ "$(hostname -s)" == "$1" ]] || fatal "Este script solo se ejecuta en $1 (estás en $(hostname -s))"; }

# randpw N -> contraseña aleatoria de N caracteres alfanuméricos (sin símbolos: evita problemas de comillas en .env)
randpw() {
  local n="${1:-24}" out=""
  while [[ ${#out} -lt $n ]]; do
    out+="$(head -c 512 /dev/urandom | tr -dc 'A-Za-z0-9')"
  done
  printf '%s' "${out:0:$n}"
}

# fw_rich PUERTO/PROTO -> regla rica permanente: solo la red del lab puede llegar a ese puerto
fw_rich() {
  local port="${1%/*}" proto="${1#*/}"
  local rule="rule family=\"ipv4\" source address=\"10.10.10.0/24\" port port=\"$port\" protocol=\"$proto\" accept"
  if ! firewall-cmd --permanent --query-rich-rule="$rule" >/dev/null 2>&1; then
    firewall-cmd --permanent --add-rich-rule="$rule" >/dev/null
    say "firewalld: $port/$proto permitido solo desde 10.10.10.0/24"
  fi
}

# wait_for SEGUNDOS DESCRIPCIÓN COMANDO... -> reintenta cada 5 s hasta que el comando devuelva 0
wait_for() {
  local max="$1" desc="$2"; shift 2
  local t=0
  until "$@" >/dev/null 2>&1; do
    (( t >= max )) && return 1
    sleep 5; t=$((t + 5))
    if (( t % 30 == 0 )); then say "esperando: $desc (${t}s/${max}s)"; fi
  done
}
