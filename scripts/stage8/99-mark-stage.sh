#!/usr/bin/env bash
# =============================================================================
# 99-mark-stage.sh — Marca la Etapa 8 como alcanzada (dns01 y ansible01)
#
# Solo se ejecuta al CERRAR la Etapa 8 ('lab.sh stage8-close'), y se niega si la
# Etapa 7 no está cerrada en este host: run_all.sh añade los tests según
# LAB_STAGE, y con LAB_STAGE=8 lanzaría test_ansible.sh aunque la Etapa 7 siguiera
# a medias.
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root

cur="$(awk -F= '$1=="LAB_STAGE"{print $2}' /etc/lab-release 2>/dev/null)"
(( ${cur:-0} >= 7 )) || fatal "LAB_STAGE=${cur:-0} en $(hostname -s): cierra antes la Etapa 7 (lab.sh stage7 site)"
case "$(hostname -s)" in
  dns01)     exportfs -v | grep -q /srv/nfs/vmware || fatal "dns01 no exporta /srv/nfs/vmware (lab.sh stage8-nfs)" ;;
  ansible01) [[ -d /home/adminlab/vmware-lab ]] || fatal "ansible01 sin ~/vmware-lab (lab.sh stage8-setup)" ;;
  *)         fatal "La Etapa 8 solo se marca en dns01 y ansible01" ;;
esac
set_stage 8
say "Etapa 8 marcada como alcanzada en $(hostname -s)"
