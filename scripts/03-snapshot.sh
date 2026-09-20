#!/usr/bin/env bash
# =============================================================================
# 03-snapshot.sh — Snapshots por etapa con nombre estable: rhelN-stageM-complete
# Uso: 03-snapshot.sh <create|list|revert|delete> <host> [etapa 1-9]
#   create  apaga la VM (ACPI) para un snapshot limpio, lo crea y la vuelve a encender
#   revert  vuelve al snapshot de esa etapa
# Nombres: rhel7-stage1-complete, rhel10-stage3-complete, dns01-stage4-complete...
# =============================================================================
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need virsh
action="${1:-}"; vm="${2:-}"; stage="${3:-}"
[[ -n "$action" && -n "$vm" ]] || die "Uso: $0 <create|list|revert|delete> <host> [etapa]"
host_row "$vm" >/dev/null || die "Host desconocido: $vm"

snap_name() { echo "${vm%-app01}-stage${1}-complete"; }
domstate() { virsh domstate "$vm" | tr -d '[:space:]'; }
need_stage() { [[ "$stage" =~ ^[1-9]$ ]] || die "Indica la etapa (1-9)"; }

case "$action" in
  list) virsh snapshot-list "$vm" ;;
  create)
    need_stage; s="$(snap_name "$stage")"
    if virsh snapshot-info "$vm" "$s" >/dev/null 2>&1; then die "Ya existe $s (bórralo antes con: delete)"; fi
    was_running=0
    if [[ "$(domstate)" == running ]]; then
      was_running=1; info "Apagando $vm para un snapshot consistente..."
      virsh shutdown "$vm" >/dev/null
      for _ in $(seq 60); do [[ "$(domstate)" == shutoff ]] && break; sleep 2; done
      if [[ "$(domstate)" != shutoff ]]; then warn "No apagó por ACPI en 120 s: apagado forzado"; virsh destroy "$vm" >/dev/null; fi
    fi
    virsh snapshot-create-as "$vm" --name "$s" --description "Etapa $stage completa ($(date -Is))" >/dev/null
    ok "Snapshot $s creado"
    if [[ $was_running -eq 1 ]]; then virsh start "$vm" >/dev/null; info "$vm encendida de nuevo"; fi ;;
  revert)
    need_stage; s="$(snap_name "$stage")"
    virsh snapshot-revert "$vm" "$s"; ok "$vm revertida a $s (arráncala con: lab.sh up $vm)" ;;
  delete)
    need_stage; s="$(snap_name "$stage")"
    virsh snapshot-delete "$vm" "$s" >/dev/null; ok "Snapshot $s eliminado" ;;
  *) die "Acción desconocida: $action" ;;
esac
