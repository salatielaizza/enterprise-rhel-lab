#!/usr/bin/env bash
# =============================================================================
# 02-audit-rules.sh — auditd instalado, activo y vigilando ficheros críticos
#
# Reglas mínimas y con clave (-k) para poder buscar después con 'ausearch -k'.
# Usa augenrules (rules.d/), NUNCA edita /etc/audit/audit.rules a mano: ese
# fichero se regenera y cualquier cambio manual se perdería.
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root

command -v auditctl >/dev/null || {
  say "Instalando el paquete audit..."
  dnf install -y audit 2>/dev/null || yum install -y audit
}

systemctl enable --now auditd

RULES=/etc/audit/rules.d/lab-hardening.rules
STAMP="$(date +%Y%m%d%H%M%S)"
[[ -f "$RULES" ]] && cp -a "$RULES" "$RULES.lab-bak.$STAMP"

cat > "$RULES" <<'EOF'
# Gestionado por enterprise-rhel-lab (stage5/02-audit-rules.sh)
-w /etc/passwd -p wa -k lab-identity
-w /etc/shadow -p wa -k lab-identity
-w /etc/group -p wa -k lab-identity
-w /etc/ssh/sshd_config -p wa -k lab-ssh
-w /etc/sudoers -p wa -k lab-sudo
-w /etc/sudoers.d/ -p wa -k lab-sudo
EOF

augenrules --load
say "Reglas de auditoría cargadas:"
auditctl -l | grep -E 'lab-identity|lab-ssh|lab-sudo' || fatal "Las reglas no aparecen en auditctl -l tras augenrules --load"
