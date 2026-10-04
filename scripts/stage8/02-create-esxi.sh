#!/usr/bin/env bash
# =============================================================================
# 02-create-esxi.sh — Crea un ESXi 8 como VM de KVM (virtualización anidada)
#
# Uso:  02-create-esxi.sh <esxi01|esxi02|esxi03> [--manual] [--force] [--dry-run]
#   --manual   arranca el ISO ORIGINAL (instalador interactivo; fase 2 "a mano").
#              Sin --manual usa ISO_DIR/<host>-ks.iso (desatendido, de 01-esxi-iso.sh).
#   --force    si la VM existe, la borra con sus discos (pide escribir el nombre).
#   --dry-run  muestra el comando virt-install sin ejecutar nada.
#
# Hardware virtual (decisiones de la Etapa 8, ver claude/etapas/etapa8-vmware.md):
#   - --cpu host-passthrough: ESXi necesita ver VT-x para ejecutar sus propias VMs.
#   - Máquina q35 + discos SATA: ESXi no tiene driver virtio-blk.
#   - NICs vmxnet3: ESXi no tiene driver virtio-net.
#   - Firmware BIOS: conserva los snapshots internos de libvirt (como el resto del lab).
#   - Gráficos VNC solo en 127.0.0.1: la consola DCUI se ve con virt-manager/virt-viewer.
# =============================================================================
set -euo pipefail
# shellcheck source=vmware-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/vmware-lib.sh"

NAME="" MANUAL=0 FORCE=0 DRY=0
for a in "$@"; do
  case "$a" in
    --manual) MANUAL=1 ;; --force) FORCE=1 ;; --dry-run) DRY=1 ;;
    -*) die "Opción desconocida: $a" ;;
    *) NAME="$a" ;;
  esac
done
[[ -n "$NAME" ]] || die "Uso: $0 <esxi01|esxi02|esxi03> [--manual] [--force] [--dry-run]"
row="$(vmw_row "$NAME")" || die "Host '$NAME' no está en $VMW_CONF"
read -r _ ROLE IP VCPUS MEM BOOT DATA NICS _ <<<"$row"

if [[ $MANUAL -eq 1 ]]; then ISO="$(base_iso_for "$NAME")" || die "ISO base de $NAME no definido en $LAB_CONF"
else ISO="$(ks_iso_for "$NAME")"; fi

if [[ $DRY -eq 0 ]]; then
  need virt-install; need virsh
  [[ -f "$ISO" ]] || die "No existe $ISO $( [[ $MANUAL -eq 0 ]] && echo "(ejecuta: lab.sh esxi-iso $NAME)" )"
  virsh net-info "$LAB_NET" >/dev/null 2>&1 || die "Falta la red $LAB_NET"
  virsh pool-info lab-images >/dev/null 2>&1 || die "Falta el pool lab-images"
fi
info "$NAME ($ROLE): ${VCPUS} vCPU, ${MEM} MB, disco ${BOOT} GB$( (( DATA > 0 )) && echo " + datastore ${DATA} GB"), ${NICS} NIC(s), ISO $(basename "$ISO")"

# --- ¿Ya existe? ------------------------------------------------------------------
if [[ $DRY -eq 0 ]] && virsh dominfo "$NAME" >/dev/null 2>&1; then
  [[ $FORCE -eq 1 ]] || die "La VM $NAME ya existe (usa --force para recrearla)"
  warn "Se va a BORRAR $NAME con sus discos (y su datastore local con todo lo que contenga)."
  read -rp "Escribe '$NAME' para confirmar: " confirm
  [[ "$confirm" == "$NAME" ]] || die "Cancelado"
  virsh destroy "$NAME" >/dev/null 2>&1 || true
  virsh undefine "$NAME" --remove-all-storage --snapshots-metadata >/dev/null
  ssh-keygen -R "$IP" -f "$LAB_KNOWN_HOSTS" >/dev/null 2>&1 || true
fi

# --- RAM: no arrancar si el host se quedaría sin margen ------------------------------
if [[ $DRY -eq 0 ]]; then
  avail="$(mem_avail_mb)"
  if (( avail < MEM + 2048 )); then
    warn "RAM disponible ${avail} MB < ${MEM} MB de $NAME + 2048 MB de margen para el host."
    read -rp "¿Continuar igualmente? (escribe 'si'): " r; [[ "$r" == si ]] || die "Cancelado: apaga VMs antes (lab.sh down <host>)"
  fi
fi

args=(
  --connect "$LIBVIRT_URI" --name "$NAME" --memory "$MEM" --vcpus "$VCPUS"
  --cpu host-passthrough --machine q35 --osinfo "detect=on,require=off"
  --disk "pool=lab-images,size=$BOOT,format=qcow2,bus=sata"
  --graphics "vnc,listen=127.0.0.1" --video vga
  --cdrom "$ISO" --noautoconsole --wait 60
)
if (( DATA > 0 )); then args+=( --disk "pool=lab-images,size=$DATA,format=qcow2,bus=sata" ); fi
for ((i = 0; i < NICS; i++)); do args+=( --network "network=$LAB_NET,model=vmxnet3" ); done

if [[ $DRY -eq 1 ]]; then
  echo "virt-install ${args[*]}"
  exit 0
fi

if [[ $MANUAL -eq 1 ]]; then
  info "Instalación INTERACTIVA: abre la consola con 'virt-manager' o 'virt-viewer -c $LIBVIRT_URI $NAME'"
  info "Datos a introducir: IP $IP/24, gateway $LAB_GW, DNS $LAB_DNS_SERVER, hostname $NAME.$LAB_DOMAIN"
else
  info "Instalación desatendida (10-20 min). Para verla: virt-viewer -c $LIBVIRT_URI $NAME"
fi
virt-install "${args[@]}" || die "virt-install falló. Mira la consola (virt-viewer) y 'journalctl -u libvirtd'"

# Igual que 02-create-vm.sh: al reiniciar el instalador la VM se para; se expulsa el ISO y se arranca
cd_target="$(virsh domblklist "$NAME" --details | awk '$2=="cdrom"{print $3; exit}')"
if [[ -n "$cd_target" ]]; then
  virsh change-media "$NAME" "$cd_target" --eject --config --force >/dev/null 2>&1 \
    || warn "No se pudo expulsar el ISO de $NAME"
fi
[[ "$(vmw_state "$NAME")" == running ]] || virsh start "$NAME" >/dev/null
info "Esperando a que ESXi publique HTTPS en $IP:443 (hasta 10 min)..."
if wait_https "$IP" 60; then
  ok "$NAME accesible: https://$IP/ui/  (Host Client)  ·  ssh root@$IP con $LAB_ESXI_KEY"
  info "Siguiente: scripts/lab.sh esxi-status $NAME"
else
  warn "ESXi no responde en 443 tras 10 min. Mira la consola DCUI (virt-viewer) — si ves PSOD, revisa kvm.ignore_msrs"
  exit 1
fi
