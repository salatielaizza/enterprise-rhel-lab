#!/usr/bin/env bash
# =============================================================================
# 01-esxi-iso.sh — ISO de instalación DESATENDIDA de ESXi para un host del lab
#
# Uso:  01-esxi-iso.sh <esxi01|esxi02|esxi03> [--dry-run]
#
# Flujo (todo en el HOST, sin root, sin montar nada):
#   1. Elige el ISO base según el ROLE de vmware.conf (free -> ESXI_FREE_ISO,
#      eval -> ESXI_EVAL_ISO, definidos en ~/.config/rhel-lab/isos.conf).
#   2. Extrae el ISO con 'xorriso -osirrox' a un directorio temporal.
#   3. Renderiza files/ks-esxi.cfg.tpl con envsubst -> /KS.CFG (en MAYÚSCULAS:
#      el cargador de ESXi trabaja con nombres ISO 9660 en mayúsculas).
#   4. Cambia 'kernelopt=' en BOOT.CFG y EFI/BOOT/BOOT.CFG por 'ks=cdrom:/KS.CFG'.
#   5. Reconstruye el ISO arrancable (BIOS y UEFI) -> ISO_DIR/<host>-ks.iso
#
# La contraseña de root se pide una vez (o LAB_ESXI_PASSWORD) y solo se guarda
# su hash SHA-512 dentro del ISO generado. ESXi 8 exige contraseñas complejas
# (mínimo 7 caracteres con 3 tipos distintos: mayúsculas, minúsculas, dígitos, símbolos).
# =============================================================================
set -euo pipefail
umask 077
# shellcheck source=vmware-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/vmware-lib.sh"

NAME="" DRY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -*) die "Opción desconocida: $a" ;;
    *) NAME="$a" ;;
  esac
done
[[ -n "$NAME" ]] || die "Uso: $0 <esxi01|esxi02|esxi03> [--dry-run]"
row="$(vmw_row "$NAME")" || die "Host '$NAME' no está en $VMW_CONF"
read -r _ ROLE IP _ _ BOOT DATA NICS VMOTION_IP <<<"$row"
need envsubst; need openssl
[[ $DRY -eq 1 ]] || need xorriso

BASE="$(base_iso_for "$NAME")" || die "Define ESXI_$( [[ $ROLE == free ]] && echo FREE || echo EVAL )_ISO en $LAB_CONF (ver scripts/isos.conf.example)"
OUT="$(ks_iso_for "$NAME")"
if [[ $DRY -eq 0 ]]; then
  [[ -f "$BASE" ]] || die "No existe el ISO base: $BASE"
  [[ ! -e "$OUT" ]] || { warn "Ya existe $OUT: se sustituye (es un artefacto generado)"; }
fi
info "$NAME ($ROLE): ISO base $(basename "$BASE") -> $(basename "$OUT")"

# --- Clave y contraseña ---------------------------------------------------------
if [[ $DRY -eq 1 ]]; then
  # shellcheck disable=SC2016
  ESX_ROOT_HASH='$6$dryrun$notARealHash'
  ESX_SSH_PUBKEY="ssh-rsa AAAA-DRYRUN dry-run"
else
  ensure_esxi_key
  ESX_SSH_PUBKEY="$(<"$LAB_ESXI_KEY.pub")"
  if [[ -z "${LAB_ESXI_PASSWORD:-}" ]]; then
    read -rsp "Contraseña de root para los ESXi (solo laboratorio): " p1; echo
    read -rsp "Repite la contraseña: " p2; echo
    [[ -n "$p1" && "$p1" == "$p2" ]] || die "Las contraseñas no coinciden o están vacías"
    LAB_ESXI_PASSWORD="$p1"
  fi
  (( ${#LAB_ESXI_PASSWORD} >= 7 )) || die "ESXi 8 exige al menos 7 caracteres (y 3 tipos de carácter)"
  ESX_ROOT_HASH="$(openssl passwd -6 -stdin <<<"$LAB_ESXI_PASSWORD")"
fi

# --- Kickstart ------------------------------------------------------------------
export ESX_FQDN="$NAME.$LAB_DOMAIN" ESX_SHORT="$NAME" ESX_IP="$IP" ESX_NICS="$NICS"
export ESX_VMOTION_IP="$VMOTION_IP" ESX_DATA_GB="$DATA" ESX_BOOT_GB="$BOOT"
export ESX_ROOT_HASH ESX_SSH_PUBKEY LAB_GW LAB_DNS_SERVER LAB_DOMAIN
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
# shellcheck disable=SC2016
envsubst '${ESX_FQDN} ${ESX_SHORT} ${ESX_IP} ${ESX_NICS} ${ESX_VMOTION_IP} ${ESX_DATA_GB} ${ESX_BOOT_GB} ${ESX_ROOT_HASH} ${ESX_SSH_PUBKEY} ${LAB_GW} ${LAB_DNS_SERVER} ${LAB_DOMAIN}' \
  < "$STAGE8_DIR/files/ks-esxi.cfg.tpl" > "$WORK/KS.CFG"

if [[ $DRY -eq 1 ]]; then
  cp "$WORK/KS.CFG" "/tmp/$NAME.dryrun.KS.CFG"
  info "dry-run: kickstart renderizado en /tmp/$NAME.dryrun.KS.CFG (hash y clave ficticios)"
  echo "xorriso -osirrox on -indev '$BASE' -extract / <tmp>/iso"
  echo "sed -i 's|^kernelopt=.*|kernelopt=ks=cdrom:/KS.CFG|' <tmp>/iso/BOOT.CFG <tmp>/iso/EFI/BOOT/BOOT.CFG"
  echo "xorriso -as mkisofs -relaxed-filenames -J -R -o '$OUT' -b ISOLINUX.BIN -c BOOT.CAT -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e EFIBOOT.IMG -no-emul-boot <tmp>/iso"
  exit 0
fi

# --- Extraer, modificar y reconstruir ---------------------------------------------
info "Extrayendo $(basename "$BASE") (sin montar, con xorriso)..."
xorriso -osirrox on -indev "$BASE" -extract / "$WORK/iso" >/dev/null 2>&1 || die "No se pudo extraer $BASE"
chmod -R u+w "$WORK/iso"
cp "$WORK/KS.CFG" "$WORK/iso/KS.CFG"

changed=0
for cfg in "$WORK/iso/BOOT.CFG" "$WORK/iso/EFI/BOOT/BOOT.CFG"; do
  [[ -f "$cfg" ]] || continue
  grep -q '^kernelopt=' "$cfg" || die "$cfg no tiene línea kernelopt= (¿ISO de ESXi?)"
  sed -i 's|^kernelopt=.*|kernelopt=ks=cdrom:/KS.CFG|' "$cfg"
  changed=$((changed + 1))
done
(( changed > 0 )) || die "No se encontró BOOT.CFG en el ISO: ¿es un ISO de instalación de ESXi?"
[[ -f "$WORK/iso/ISOLINUX.BIN" ]] || die "Falta ISOLINUX.BIN en el ISO extraído"

EFI_ARGS=()
[[ -f "$WORK/iso/EFIBOOT.IMG" ]] && EFI_ARGS=(-eltorito-alt-boot -e EFIBOOT.IMG -no-emul-boot)
info "Construyendo $(basename "$OUT")..."
xorriso -as mkisofs -relaxed-filenames -J -R -o "$OUT.part" \
  -b ISOLINUX.BIN -c BOOT.CAT -no-emul-boot -boot-load-size 4 -boot-info-table \
  "${EFI_ARGS[@]}" "$WORK/iso" >/dev/null 2>&1 || die "xorriso no pudo crear el ISO"
mv -f "$OUT.part" "$OUT"
chmod 0640 "$OUT"
ok "ISO desatendido listo: $OUT  (contiene el hash de root: no lo compartas)"
info "Siguiente: scripts/lab.sh esxi-create $NAME"
