#!/usr/bin/env bash
# =============================================================================
# 03-os-hardening.sh — Política de contraseñas, caducidad, sysctl y banner
#
# Último script de la Etapa 5: aplica cada bloque de forma idempotente (con
# copia de seguridad con timestamp de cada fichero tocado) y marca la etapa.
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root
STAMP="$(date +%Y%m%d%H%M%S)"

# --- 1) Calidad de contraseña (pwquality) ---------------------------------------
PWQ=/etc/security/pwquality.conf
cp -a "$PWQ" "$PWQ.lab-bak.$STAMP"
for kv in "minlen = 12" "dcredit = -1" "ucredit = -1" "lcredit = -1" "ocredit = -1"; do
  key="${kv%% =*}"
  if grep -Eq "^${key}[[:space:]]*=" "$PWQ"; then
    sed -i -E "s/^${key}[[:space:]]*=.*/${kv}/" "$PWQ"
  else
    echo "$kv" >> "$PWQ"
  fi
done
say "pwquality.conf: minlen=12, mayúscula+minúscula+dígito+símbolo obligatorios"

# --- 2) Caducidad de contraseñas para altas nuevas (login.defs) -----------------
DEFS=/etc/login.defs
cp -a "$DEFS" "$DEFS.lab-bak.$STAMP"
sed -i -E 's/^(PASS_MAX_DAYS[[:space:]]+).*/\190/' "$DEFS"
sed -i -E 's/^(PASS_MIN_DAYS[[:space:]]+).*/\11/' "$DEFS"
sed -i -E 's/^(PASS_WARN_AGE[[:space:]]+).*/\17/' "$DEFS"
say "login.defs: PASS_MAX_DAYS=90, PASS_MIN_DAYS=1, PASS_WARN_AGE=7 (solo afecta a altas nuevas)"

# --- 3) sysctl de red -------------------------------------------------------------
SYSCTL_D=/etc/sysctl.d/98-lab-hardening.conf
cat > "$SYSCTL_D" <<'EOF'
# Gestionado por enterprise-rhel-lab (stage5/03-os-hardening.sh)
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
kernel.randomize_va_space = 2
EOF
sysctl --system >/dev/null
say "sysctl aplicado desde $SYSCTL_D"

# --- 4) Aviso legal de acceso ------------------------------------------------------
ISSUE=/etc/issue
[[ -f "$ISSUE" ]] && cp -a "$ISSUE" "$ISSUE.lab-bak.$STAMP"
if ! grep -q "enterprise-rhel-lab" "$ISSUE" 2>/dev/null; then
  cat > "$ISSUE" <<'EOF'
*** Acceso restringido — enterprise-rhel-lab ***
Este sistema es un laboratorio de pruebas. Todo acceso queda registrado (auditd).
EOF
fi
say "/etc/issue actualizado con el aviso de acceso del lab"

set_stage 5
