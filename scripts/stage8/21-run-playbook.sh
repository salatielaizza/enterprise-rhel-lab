#!/usr/bin/env bash
# =============================================================================
# 21-run-playbook.sh — (ansible01) Ejecuta un playbook de ~/vmware-lab
#
# Se invoca como root (run_remote), pero ansible-playbook corre como adminlab con
# el entorno virtual de la Etapa 8 (~/.venvs/vmware), igual que la Etapa 7 hace
# con el ansible-core del sistema.
#
# Uso: 21-run-playbook.sh <info|cluster|esxi-config|guest|vmotion|snapshot|guest-baseline|verify> [args de ansible-playbook]
#   ej.: 21-run-playbook.sh snapshot -e snap_state=present -e snap_name=antes-de-vmotion
#
# Los argumentos extra se pasan con 'printf %q' SOLO si los hay: con la lista vacía,
# 'printf %q' produce '' y ansible-playbook lo interpretaría como un segundo playbook
# vacío (el mismo bug detectado en stage7/02-run-playbook.sh).
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root

ADMIN_USER=adminlab
PROJ="/home/$ADMIN_USER/vmware-lab"
VENV="/home/$ADMIN_USER/.venvs/vmware"
NAME="${1:?Uso: 21-run-playbook.sh <info|cluster|esxi-config|guest|vmotion|snapshot|guest-baseline|verify> [args]}"; shift

[[ -x "$VENV/bin/ansible-playbook" ]] || fatal "Falta $VENV: ejecuta antes 'lab.sh stage8-setup'"
case "$NAME" in
  info)           PB=playbooks/00-info.yml ;;
  cluster)        PB=playbooks/10-cluster.yml ;;
  esxi-config)    PB=playbooks/20-esxi-config.yml ;;
  guest)          PB=playbooks/30-guest.yml ;;
  vmotion)        PB=playbooks/40-vmotion.yml ;;
  snapshot)       PB=playbooks/50-snapshot.yml ;;
  guest-baseline) PB=playbooks/60-guest-baseline.yml ;;
  verify)         PB=playbooks/90-verify.yml ;;
  *) fatal "Playbook desconocido: $NAME" ;;
esac

EXTRA=""
if [[ $# -gt 0 ]]; then EXTRA="$(printf '%q ' "$@")"; fi
say "ansible-playbook $PB $*"
runuser -l "$ADMIN_USER" -c "cd '$PROJ' && '$VENV/bin/ansible-playbook' '$PB' $EXTRA"
