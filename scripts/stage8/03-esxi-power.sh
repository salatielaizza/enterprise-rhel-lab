#!/usr/bin/env bash
# =============================================================================
# 03-esxi-power.sh — Encendido y apagado ORDENADO de los ESXi del lab
#
# Uso:  03-esxi-power.sh <up|down> <esxi01|esxi02|esxi03|all>
#
#   up    virsh start -> espera HTTPS -> sale del modo mantenimiento (si entró con 'down').
#   down  1) apaga de forma ordenada las VMs que corren DENTRO del ESXi (VMware Tools),
#         2) modo mantenimiento + 'esxcli system shutdown poweroff',
#         3) espera a que libvirt vea la VM apagada.
#         NUNCA hace 'virsh destroy': un apagado forzado de un ESXi puede dejar el VMFS
#         o el VCSA inconsistentes. Si algo no se apaga, avisa y para.
#
# Orden con 'all' en 'down': esxi03 -> esxi01 -> esxi02 (esxi02 aloja vCenter: el último).
# En 'up': esxi02 -> esxi03 -> esxi01 (vCenter primero, para que vea llegar al resto).
# =============================================================================
set -euo pipefail
# shellcheck source=vmware-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/vmware-lib.sh"

action="${1:-}"; target="${2:-}"
[[ ( "$action" == up || "$action" == down ) && -n "$target" ]] || die "Uso: $0 <up|down> <esxi0N|all>"

order() {  # ordena la lista según la acción
  local list; list="$(vmw_targets "$target")"
  local pref; [[ "$action" == down ]] && pref="esxi03 esxi01 esxi02" || pref="esxi02 esxi03 esxi01"
  local h; for h in $pref; do grep -qx "$h" <<<"$list" && echo "$h"; done
  return 0
}

guest_vms_running() {  # IDs de VMs encendidas dentro del ESXi
  # shellcheck disable=SC2016  # el bucle y sus $ se evalúan en el ESXi, no en el host
  esxi_ssh "$1" 'for id in $(vim-cmd vmsvc/getallvms 2>/dev/null | awk "NR>1 && \$1 ~ /^[0-9]+$/ {print \$1}"); do
                   vim-cmd vmsvc/power.getstate "$id" | grep -q "Powered on" && echo "$id"; done' 2>/dev/null || true
}

down_one() {
  local h="$1" ip; ip="$(vmw_ip "$h")"
  [[ "$(vmw_state "$h")" == running ]] || { info "$h ya está apagado"; return 0; }
  if ! esxi_ssh "$h" true 2>/dev/null; then
    warn "$h: no hay SSH con $LAB_ESXI_KEY. Apágalo desde Host Client (https://$ip/ui/) o la DCUI; no se fuerza nada."
    return 1
  fi
  local ids id i
  ids="$(guest_vms_running "$h")"
  if [[ -n "$ids" ]]; then
    info "$h: apagado ordenado de las VMs internas (IDs: $(tr '\n' ' ' <<<"$ids"))"
    for id in $ids; do esxi_ssh "$h" "vim-cmd vmsvc/power.shutdown $id" >/dev/null 2>&1 \
      || warn "$h: la VM $id no acepta apagado ordenado (¿sin VMware Tools / open-vm-tools?)"; done
    for ((i = 0; i < 60; i++)); do [[ -z "$(guest_vms_running "$h")" ]] && break; sleep 10; done
    if [[ -n "$(guest_vms_running "$h")" ]]; then
      warn "$h: siguen VMs encendidas tras 10 min. Apágalas a mano (Host Client / vCenter) y repite."
      return 1
    fi
  fi
  info "$h: modo mantenimiento + apagado"
  esxi_ssh "$h" "esxcli system maintenanceMode set --enable true --timeout 300" \
    || { warn "$h: no entra en modo mantenimiento"; return 1; }
  esxi_ssh "$h" "esxcli system shutdown poweroff --reason 'lab.sh esxi-down'" || true
  for ((i = 0; i < 36; i++)); do [[ "$(vmw_state "$h")" == shutoff ]] && break; sleep 5; done
  if [[ "$(vmw_state "$h")" == shutoff ]]; then ok "$h apagado"
  else warn "$h no se ha apagado en 3 min: revisa su consola (virt-viewer). No se fuerza."; return 1; fi
}

up_one() {
  local h="$1" ip; ip="$(vmw_ip "$h")"
  if [[ "$(vmw_state "$h")" != running ]]; then
    avail="$(mem_avail_mb)"; mem="$(vmw_field "$h" 5)"
    (( avail >= mem + 1024 )) || warn "$h: RAM disponible ${avail} MB para ${mem} MB asignados (vigila 'free -h')"
    virsh start "$h" >/dev/null && info "$h arrancando..."
  fi
  wait_https "$ip" 60 || { warn "$h no responde en $ip:443 tras 10 min"; return 1; }
  if esxi_ssh "$h" "esxcli system maintenanceMode get" 2>/dev/null | grep -q Enabled; then
    esxi_ssh "$h" "esxcli system maintenanceMode set --enable false" && info "$h: fuera de modo mantenimiento"
  fi
  ok "$h encendido (https://$ip/ui/)"
}

rc=0
for h in $(order); do
  if [[ "$action" == down ]]; then down_one "$h" || rc=1; else up_one "$h" || rc=1; fi
done
exit "$rc"
