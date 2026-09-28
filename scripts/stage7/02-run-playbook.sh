#!/usr/bin/env bash
# =============================================================================
# 02-run-playbook.sh — Ejecuta un playbook desde ansible01 (Etapa 7)
#
# SOLO se ejecuta en ansible01. Se invoca como root (vía run_remote, igual que
# el resto de scripts de etapa), pero el propio ansible-playbook se lanza como
# 'adminlab' (con 'runuser'), porque la clave SSH, el ansible.cfg y el
# ~/.vault_pass.txt viven en su home, no en la de root.
#
# Uso: 02-run-playbook.sh <site|facts|ping|advanced|dynamic_inventory_demo> [--limit <grupo_o_host>]
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root

ADMIN_USER=adminlab
ANSIBLE_DIR="/home/$ADMIN_USER/ansible-lab"
PLAYBOOK="${1:?Uso: 02-run-playbook.sh <site|facts|ping|advanced|dynamic_inventory_demo> [--limit <grupo_o_host>]}"; shift || true

[[ -d "$ANSIBLE_DIR" ]] || fatal "$ANSIBLE_DIR no existe: ejecuta antes 'lab.sh stage7-setup'"

case "$PLAYBOOK" in
  ping)
    # Ad-hoc, no playbook: la forma más rápida de comprobar conectividad+sudo
    say "ansible lab -m ping (+ comprobación de 'become')"
    runuser -l "$ADMIN_USER" -c "cd '$ANSIBLE_DIR' && ansible lab -m ping" || fatal "Fallo el ping a algún host del inventario"
    runuser -l "$ADMIN_USER" -c "cd '$ANSIBLE_DIR' && ansible lab -b -m command -a whoami" \
      || fatal "El 'become' (sudo) desde ansible01 no funciona en algún host"
    ;;
  site|facts|advanced)
    PB="playbooks/$PLAYBOOK.yml"
    say "ansible-playbook $PB $*"
    runuser -l "$ADMIN_USER" -c "cd '$ANSIBLE_DIR' && ansible-playbook '$PB' $(printf '%q ' "$@")"
    ;;
  dynamic_inventory_demo)
    # Este SÍ necesita un inventario distinto (el script dinámico, no hosts.ini):
    # requiere que ansible01 tenga salida a Internet (NAT del lab) para llegar
    # a la API pública de demostración.
    PB="playbooks/dynamic_inventory_demo.yml"
    say "ansible-playbook -i inventory/dynamic_inventory_demo.py $PB $*"
    runuser -l "$ADMIN_USER" -c \
      "cd '$ANSIBLE_DIR' && ansible-playbook -i inventory/dynamic_inventory_demo.py '$PB' $(printf '%q ' "$@")"
    ;;
  *)
    fatal "Playbook desconocido: $PLAYBOOK (usa site, facts, ping, advanced o dynamic_inventory_demo)"
    ;;
esac
