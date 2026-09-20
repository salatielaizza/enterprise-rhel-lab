#!/usr/bin/env bash
# =============================================================================
# 02-create-vm.sh — Crea una VM RHEL con instalación desatendida (kickstart)
#
# Uso:  02-create-vm.sh <nombre> [--force] [--dry-run]
#   <nombre>   una fila de scripts/hosts.conf (rhel9-app01, dns01, ...)
#   --force    si la VM existe, la destruye y la borra (con sus discos)
#   --dry-run  renderiza el kickstart y muestra el comando virt-install, sin ejecutar
#
# Flujo: localiza la ISO -> renderiza scripts/kickstart/rhelN.ks.tpl con envsubst
# -> virt-install (--location ISO + --initrd-inject) -> expulsa la ISO ->
# arranca la VM -> espera al SSH.
# La contraseña (root y adminlab) se pide una vez (o LAB_PASSWORD) y NO se guarda.
# =============================================================================
set -euo pipefail
umask 077
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

NAME="" FORCE=0 DRY=0
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;; --dry-run) DRY=1 ;;
    -*) die "Opción desconocida: $a" ;;
    *) NAME="$a" ;;
  esac
done
[[ -n "$NAME" ]] || die "Uso: $0 <nombre> [--force] [--dry-run]"
row="$(host_row "$NAME")" || die "Host '$NAME' no está en $HOSTS_CONF"
read -r _ VER IP VCPUS MEM DISK DATA <<<"$row"

if [[ $DRY -eq 0 ]]; then
  need virt-install; need virsh; need openssl; need envsubst; need ssh
  [[ -f "$LAB_SSH_KEY.pub" ]] || die "Falta $LAB_SSH_KEY.pub (ejecuta: lab.sh host-setup)"
  virsh net-info "$LAB_NET" >/dev/null 2>&1 || die "Falta la red $LAB_NET (ejecuta: lab.sh network)"
  virsh pool-info lab-images >/dev/null 2>&1 || die "Falta el pool lab-images (ejecuta: lab.sh host-setup)"
else
  need envsubst
fi

# --- ISO ------------------------------------------------------------------------
ISO_DIR="$(iso_dir)"
shopt -s nullglob
if [[ "$VER" == 7 ]]; then pattern="rhel-server-7.*-x86_64-dvd.iso"; else pattern="rhel-$VER.*-x86_64-dvd.iso"; fi
# shellcheck disable=SC2206
isos=( "$ISO_DIR"/$pattern )
if ((${#isos[@]} == 0)); then
  [[ $DRY -eq 1 ]] || die "No hay ISO ($pattern) en $ISO_DIR. Ejecuta: lab.sh iso"
  ISO="$ISO_DIR/${pattern/\*/X}"; warn "dry-run: ISO no encontrada, se usa un nombre ficticio"
else
  ISO="${isos[${#isos[@]}-1]}"
fi
info "$NAME: RHEL $VER, ISO $(basename "$ISO"), ${VCPUS} vCPU, ${MEM} MB, disco ${DISK} GB + datos ${DATA} GB"

# --- ¿Ya existe? ------------------------------------------------------------------
if [[ $DRY -eq 0 ]] && virsh dominfo "$NAME" >/dev/null 2>&1; then
  [[ $FORCE -eq 1 ]] || die "La VM $NAME ya existe (usa --force para recrearla)"
  warn "Eliminando la VM existente $NAME"
  virsh destroy "$NAME" >/dev/null 2>&1 || true
  virsh undefine "$NAME" --remove-all-storage --snapshots-metadata >/dev/null
  ssh-keygen -R "$IP" -f "$LAB_KNOWN_HOSTS" >/dev/null 2>&1 || true
fi

# --- Contraseñas (solo laboratorio) -----------------------------------------------
if [[ $DRY -eq 1 ]]; then
  # shellcheck disable=SC2016
  ROOT_HASH='$6$dryrun$notARealHash'
  # shellcheck disable=SC2016
  ADMIN_HASH='$6$dryrun$notARealHash'
else
  if [[ -z "${LAB_PASSWORD:-}" ]]; then
    read -rsp "Contraseña de root y adminlab para las VMs (solo laboratorio): " p1; echo
    read -rsp "Repite la contraseña: " p2; echo
    [[ -n "$p1" && "$p1" == "$p2" ]] || die "Las contraseñas no coinciden o están vacías"
    LAB_PASSWORD="$p1"
  fi
  ROOT_HASH="$(openssl passwd -6 -stdin <<<"$LAB_PASSWORD")"
  ADMIN_HASH="$(openssl passwd -6 -stdin <<<"$LAB_PASSWORD")"
fi

# --- Kickstart --------------------------------------------------------------------
TPL="$SCRIPTS_DIR/kickstart/rhel${VER}.ks.tpl"
[[ -f "$TPL" ]] || die "No existe la plantilla $TPL"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export LAB_HOSTNAME="$NAME.$LAB_DOMAIN" LAB_IP="$IP" LAB_GW LAB_DNS="$LAB_GW" LAB_TZ
export LAB_ROOT_HASH="$ROOT_HASH" LAB_ADMIN_HASH="$ADMIN_HASH"
if [[ -f "$LAB_SSH_KEY.pub" ]]; then LAB_SSH_PUBKEY="$(<"$LAB_SSH_KEY.pub")"; else LAB_SSH_PUBKEY="ssh-ed25519 AAAA-DRYRUN dry-run"; fi
export LAB_SSH_PUBKEY
# shellcheck disable=SC2016
envsubst '${LAB_HOSTNAME} ${LAB_IP} ${LAB_GW} ${LAB_DNS} ${LAB_TZ} ${LAB_ROOT_HASH} ${LAB_ADMIN_HASH} ${LAB_SSH_PUBKEY}' \
  < "$TPL" > "$WORK/ks.cfg"

# --- os-variant (osinfo-db de Ubuntu 24.04 puede no conocer RHEL más recientes) ------
pick_variant() {
  command -v osinfo-query >/dev/null 2>&1 || { echo generic; return; }
  local known c; known="$(osinfo-query -f short-id os 2>/dev/null | tr -d ' ')"
  for c in "$@"; do grep -qx "$c" <<<"$known" && { echo "$c"; return; }; done
  echo generic
}
case "$VER" in
  7)  VARIANT="$(pick_variant rhel7.9 rhel7.8 rhel7-unknown)" ;;
  8)  VARIANT="$(pick_variant rhel8.10 rhel8.9 rhel8.8 rhel8-unknown)" ;;
  9)  VARIANT="$(pick_variant rhel9.8 rhel9.7 rhel9.6 rhel9.5 rhel9.4 rhel9.3 rhel9.2 rhel9.1 rhel9.0 rhel9-unknown)" ;;
  10) VARIANT="$(pick_variant rhel10.2 rhel10.1 rhel10.0 rhel10-unknown rhel9-unknown)" ;;
  *)  die "Versión no soportada: $VER" ;;
esac
info "os-variant: $VARIANT"

args=(
  --connect "$LIBVIRT_URI" --name "$NAME" --memory "$MEM" --vcpus "$VCPUS"
  --cpu host-passthrough --os-variant "$VARIANT"
  --disk "pool=lab-images,size=$DISK,format=qcow2,bus=virtio"
  --network "network=$LAB_NET,model=virtio"
  --graphics none --noautoconsole --wait 60
  --location "$ISO" --initrd-inject "$WORK/ks.cfg"
  --extra-args "inst.ks=file:/ks.cfg inst.text console=ttyS0,115200n8"
  --channel "unix,target_type=virtio,name=org.qemu.guest_agent.0"
)
if [[ "$DATA" -gt 0 ]]; then args+=( --disk "pool=lab-images,size=$DATA,format=qcow2,bus=virtio" ); fi

if [[ $DRY -eq 1 ]]; then
  cp "$WORK/ks.cfg" "/tmp/$NAME.dryrun.ks"
  info "dry-run: kickstart renderizado en /tmp/$NAME.dryrun.ks (con hashes ficticios)"
  echo "virt-install ${args[*]}"
  exit 0
fi

info "Instalando $NAME (10-25 min). Para verlo en directo, en otra terminal: virsh console $NAME   (salir: Ctrl+])"
virt-install "${args[@]}" || die "virt-install falló. Revisa: virsh console $NAME / journalctl -u libvirtd"

state="$(virsh domstate "$NAME" | tr -d '[:space:]')"
cd_target="$(virsh domblklist "$NAME" --details | awk '$2=="cdrom"{print $3; exit}')"
if [[ -n "$cd_target" ]]; then
  virsh change-media "$NAME" "$cd_target" --eject --config --force >/dev/null 2>&1 \
    || warn "No se pudo expulsar la ISO de $NAME (la VM no arrancará si borras la ISO)"
fi
[[ "$state" == running ]] || virsh start "$NAME" >/dev/null
info "Esperando al SSH de $NAME ($IP)..."
if wait_ssh "$NAME" 60; then
  ok "$NAME instalada y accesible: ssh $NAME"
else
  warn "SSH no responde tras 5 min. Mira: virsh console $NAME  y  /root/ks-post.log dentro de la VM"
  exit 1
fi
