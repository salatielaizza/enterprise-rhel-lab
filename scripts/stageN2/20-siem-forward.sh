#!/usr/bin/env bash
# =============================================================================
# 20-siem-forward.sh — (ansible01) rsyslog de las VMs del lab -> Graylog, con Ansible
#
# Copia files/siem-lab a ~adminlab/siem-lab (proyecto aparte: 'stage7-setup' no lo pisa)
# y lanza playbooks/siem-forwarding.yml como adminlab, con el inventario, las group_vars,
# la clave SSH y la contraseña de Vault de la Etapa 7.
#
# Uso: lab.sh siem-forward [args de ansible-playbook]
#   lab.sh siem-forward --check --diff
#   lab.sh siem-forward --limit rhel9-app01
#   lab.sh siem-forward -e siem_state=absent        # rollback
# =============================================================================
set -euo pipefail
# shellcheck source=siem-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/siem-lib.sh"
require_root
require_host ansible01

ADMIN_USER=adminlab
PROJ="/home/$ADMIN_USER/siem-lab"
[[ -f "/home/$ADMIN_USER/ansible-lab/inventory/hosts.ini" ]] || fatal "Falta el proyecto de la Etapa 7: ejecuta antes 'lab.sh stage7-setup'"
command -v ansible-playbook >/dev/null || fatal "ansible-core no está instalado (lab.sh stage7-setup)"

# La fuente de verdad es scripts/stageN2/files/siem-lab en git (lección del caso etapa7/03):
# se recopia en cada ejecución; un arreglo hecho solo en ansible01 se perdería.
install -d -m 0750 -o "$ADMIN_USER" -g "$ADMIN_USER" "$PROJ"
cp -a "$N2_FILES/siem-lab/." "$PROJ/"
chown -R "$ADMIN_USER:$ADMIN_USER" "$PROJ"

EXTRA=""
if [[ $# -gt 0 ]]; then EXTRA="$(printf '%q ' "$@")"; fi   # sin args, nada (printf %q '' daría un argumento vacío)
say "ansible-playbook playbooks/siem-forwarding.yml $*"
runuser -l "$ADMIN_USER" -c "cd '$PROJ' && ansible-playbook playbooks/siem-forwarding.yml $EXTRA"
