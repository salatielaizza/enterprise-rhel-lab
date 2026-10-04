#!/usr/bin/env bash
# =============================================================================
# 05-esxi-snapshot.sh — Snapshots de los ESXi (VMs de KVM) con nombre estable
#
# Uso:  05-esxi-snapshot.sh <create|list|revert|delete> <esxi0N> [etapa]
#       Nombre: <host>-stage<etapa>-complete   (etapa por defecto: 8)
#
# Diferencia con scripts/03-snapshot.sh (RHEL): aquí NUNCA se apaga el ESXi a la
# fuerza. 'create' y 'revert' exigen el host APAGADO (lab.sh esxi-down <host>),
# porque un ESXi con vCenter o VMs dentro no se debe congelar en caliente.
#
# Evaluación de 60 días: el snapshot conserva el TRABAJO, pero no está garantizado
# que reinicie la cuenta atrás de la licencia de evaluación. Lo fiable para
# "renovarla" es reconstruir con la automatización (esxi-iso, esxi-create, vcsa-deploy, stage8).
# =============================================================================
set -euo pipefail
# shellcheck source=vmware-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/vmware-lib.sh"
need virsh

action="${1:-}"; vm="${2:-}"; stage="${3:-8}"
[[ -n "$action" && -n "$vm" ]] || die "Uso: $0 <create|list|revert|delete> <esxi0N> [etapa]"
vmw_row "$vm" >/dev/null || die "ESXi desconocido: $vm"
[[ "$stage" =~ ^[0-9]+$ ]] || die "Etapa no válida: $stage"
s="$vm-stage$stage-complete"
must_be_off() { [[ "$(vmw_state "$vm")" == shutoff ]] || die "$vm debe estar APAGADO (scripts/lab.sh esxi-down $vm)"; }

case "$action" in
  list)   virsh snapshot-list "$vm" ;;
  create)
    must_be_off
    virsh snapshot-info "$vm" "$s" >/dev/null 2>&1 && die "Ya existe $s (bórralo antes con: delete)"
    virsh snapshot-create-as "$vm" --name "$s" --description "Etapa $stage ($(date -Is))" >/dev/null
    ok "Snapshot $s creado" ;;
  revert)
    must_be_off
    virsh snapshot-revert "$vm" "$s"
    ok "$vm revertido a $s (arráncalo con: lab.sh esxi-up $vm)" ;;
  delete)
    virsh snapshot-delete "$vm" "$s" >/dev/null
    ok "Snapshot $s eliminado" ;;
  *) die "Acción desconocida: $action" ;;
esac
