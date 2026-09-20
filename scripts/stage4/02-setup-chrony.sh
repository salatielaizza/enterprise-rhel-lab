#!/usr/bin/env bash
# =============================================================================
# 02-setup-chrony.sh — Sincronización horaria jerárquica
#   --role server  (dns01)  sincroniza con el pool público y sirve a 10.10.10.0/24
#   --role client  (resto)  sincroniza SOLO con dns01 (10.10.10.20)
# Los cambios van entre marcas '# BEGIN/END lab-chrony' (idempotente) y las
# líneas pool/server originales se comentan con '#lab-disabled#' (reversible).
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root
[[ "${1:-}" == "--role" && ( "${2:-}" == server || "${2:-}" == client ) ]] || fatal "Uso: $0 --role server|client"
ROLE="$2"; CONF=/etc/chrony.conf

if ! command -v chronyd >/dev/null; then
  { command -v dnf >/dev/null && dnf -y install chrony; } || yum -y install chrony || fatal "No se pudo instalar chrony"
fi
[[ -f "$CONF.lab-orig" ]] || cp -a "$CONF" "$CONF.lab-orig"
sed -i '/^# BEGIN lab-chrony/,/^# END lab-chrony/d' "$CONF"

if [[ "$ROLE" == client ]]; then
  sed -i -E 's/^(pool|server)[[:space:]]+/#lab-disabled# \1 /' "$CONF"
  printf '# BEGIN lab-chrony\nserver 10.10.10.20 iburst\n# END lab-chrony\n' >> "$CONF"
else
  sed -i -E 's/^#lab-disabled# (pool|server)[[:space:]]+/\1 /' "$CONF"
  printf '# BEGIN lab-chrony\nallow 10.10.10.0/24\nlocal stratum 10\n# END lab-chrony\n' >> "$CONF"
  if systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-service=ntp >/dev/null
    firewall-cmd --reload >/dev/null
    say "[+] firewalld: servicio ntp (123/udp) permitido"
  fi
fi

systemctl enable chronyd >/dev/null 2>&1
systemctl restart chronyd
sleep 3
chronyc -a makestep >/dev/null 2>&1 || true
for _ in $(seq 10); do
  chronyc tracking 2>/dev/null | grep -Eq 'Leap status[[:space:]]*: Normal' && break
  sleep 3
done
say "chronyc sources:"; chronyc sources
chronyc tracking | grep -E 'Reference ID|Stratum|Leap status' || true
timedatectl | grep -Ei 'synchronized|NTP' || true
set_stage 4
