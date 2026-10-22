#!/usr/bin/env bash
# =============================================================================
# 03-mark-stage.sh — Marca la Etapa 7 como alcanzada (nodos gestionados y ansible01)
#
# La Etapa 7 la aplica Ansible desde ansible01, no un script local — pero el
# marcador de "hasta qué etapa ha llegado esta VM" (/etc/lab-release, leído por
# tests/lib.sh -> lab_stage) lo escribe siempre 'set_stage' de common.sh, igual
# que en el resto de etapas. set_stage NUNCA reduce la etapa: relanzarlo en un
# host que ya está en una etapa posterior no lo baja.
#
# lab.sh lo llama en dos sitios (ver troubleshooting/etapa7/06):
#   - 'lab.sh stage7 site': en cada NODO GESTIONADO (rhel7/8/9/10-app01, dns01),
#     solo si el playbook terminó sin errores. Requisito: el marcador que deja
#     el rol 'common' (/etc/ansible-lab-managed.txt).
#   - 'lab.sh stage7-setup': en ANSIBLE01 (el nodo de control), al final, tras
#     el ping + become en verde. Requisito: el proyecto Ansible y la contraseña
#     de Vault en la home de adminlab. Sin esta marca, ansible01 se quedaba en
#     la etapa 6 y run_all.sh nunca le ejecutaba test_ansible.sh.
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root

HOST="$(hostname -s)"

if [[ "$HOST" == ansible01 ]]; then
  test -f /home/adminlab/ansible-lab/ansible.cfg \
    || fatal "/home/adminlab/ansible-lab/ansible.cfg no existe: 'lab.sh stage7-setup' no se completó en ansible01"
  test -f /home/adminlab/.vault_pass.txt \
    || fatal "/home/adminlab/.vault_pass.txt no existe: falta la contraseña de Ansible Vault en ansible01"
else
  test -f /etc/ansible-lab-managed.txt \
    || fatal "/etc/ansible-lab-managed.txt no existe: el playbook 'site' no se aplicó a este host todavía"
fi

set_stage 7
say "Etapa 7 marcada como alcanzada en $HOST"
