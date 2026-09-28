#!/usr/bin/env bash
# =============================================================================
# 03-mark-stage.sh — Marca la Etapa 7 como alcanzada en un NODO GESTIONADO
#
# La Etapa 7 la aplica Ansible desde ansible01, no un script local — pero el
# marcador de "hasta qué etapa ha llegado esta VM" (/etc/lab-release, leído por
# tests/lib.sh -> lab_stage) lo escribe siempre 'set_stage' de common.sh, igual
# que en el resto de etapas. lab.sh llama a este script en cada nodo gestionado
# (rhel7/8/9/10-app01, dns01) SOLO si 'lab.sh stage7 site' terminó sin errores.
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root

test -f /etc/ansible-lab-managed.txt || fatal "/etc/ansible-lab-managed.txt no existe: el playbook 'site' no se aplicó a este host todavía"
set_stage 7
say "Etapa 7 marcada como alcanzada en $(hostname -s)"
