#!/usr/bin/env bash
# =============================================================================
# 07-vcsa-deploy.sh — (HOST) Despliega vCenter Server Appliance en esxi02 por CLI
#
# Uso:  07-vcsa-deploy.sh [--verify-only | --precheck-only]
#   --verify-only    valida solo la plantilla JSON (no toca esxi02)
#   --precheck-only  comprueba requisitos contra esxi02 (DNS, red, datastore) sin desplegar
#   (sin opción)     despliegue real: 30-60 min
#
# Requisitos (los comprueba antes de empezar):
#   - VCSA_ISO en ~/.config/rhel-lab/isos.conf (requiere derecho de descarga en Broadcom)
#   - esxi02 encendido, con su datastore local 'datastore-esxi02'
#   - DNS A y PTR de vcsa01 y esxi02 en dns01 (sin esto el despliegue falla en la fase 2)
#   - jq, envsubst, udisksctl
#
# El ISO se monta SIN sudo con udisksctl (solo lectura) y se desmonta al salir.
# Las contraseñas (root de esxi02, root del appliance, administrator@vsphere.local)
# se piden aquí y se inyectan con jq en un JSON temporal 0600 que se borra al salir.
# Los logs del instalador van a ~/.local/state/rhel-lab/vcsa-deploy/ (fuera del repo).
# =============================================================================
set -euo pipefail
umask 077
# shellcheck source=vmware-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/vmware-lib.sh"

MODE=install
case "${1:-}" in
  "") ;; --verify-only) MODE=verify ;; --precheck-only) MODE=precheck ;;
  *) die "Uso: $0 [--verify-only|--precheck-only]" ;;
esac
need jq; need envsubst; need udisksctl
ESX=esxi02; ESX_IP="$(vmw_ip "$ESX")"; DS="datastore-$ESX"

ISO="$(iso_path VCSA_ISO)" || die "Define VCSA_ISO en $LAB_CONF (ver scripts/isos.conf.example)"
[[ -f "$ISO" ]] || die "No existe $ISO"

# --- Comprobaciones previas -----------------------------------------------------------
if command -v dig >/dev/null; then
  for spec in "$VCSA_NAME:$VCSA_IP" "$ESX:$ESX_IP"; do
    n="${spec%%:*}"; ip="${spec##*:}"
    [[ "$(dig +short +time=2 +tries=1 @"$LAB_DNS_SERVER" "$n.$LAB_DOMAIN" | head -1)" == "$ip" ]] \
      || die "DNS A de $n.$LAB_DOMAIN incorrecto o ausente (lab.sh stage4-dns)"
    [[ "$(dig +short +time=2 +tries=1 @"$LAB_DNS_SERVER" -x "$ip" | head -1)" == "$n.$LAB_DOMAIN." ]] \
      || die "DNS PTR de $ip incorrecto o ausente (lab.sh stage4-dns)"
  done
  ok "DNS directo e inverso correctos para $VCSA_NAME y $ESX"
fi
if [[ $MODE != verify ]]; then
  tcp_open "$ESX_IP" 443 || die "$ESX no responde en 443 (lab.sh esxi-up $ESX)"
  if esxi_ssh "$ESX" true 2>/dev/null; then
    esxi_ssh "$ESX" "esxcli storage filesystem list" | grep -qw "$DS" || die "$ESX no tiene el datastore $DS"
    ok "$ESX accesible y con datastore $DS"
  fi
  avail="$(mem_avail_mb)"
  (( avail >= 3072 )) || warn "Solo ${avail} MB libres en el host: el despliegue puede ir muy lento o fallar"
fi

# --- Montar el ISO (solo lectura, sin sudo) ----------------------------------------
LOOP="" MNT="" WORK="$(mktemp -d)"
cleanup() {
  [[ -n "$MNT" ]] && udisksctl unmount -b "$LOOP" >/dev/null 2>&1
  [[ -n "$LOOP" ]] && udisksctl loop-delete -b "$LOOP" >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT
LOOP="$(udisksctl loop-setup -r -f "$ISO" | sed -nE 's/.* as (\/dev\/loop[0-9]+)\.?$/\1/p')"
[[ -n "$LOOP" ]] || die "udisksctl no pudo asociar el ISO a un dispositivo loop"
sleep 2   # algunos escritorios auto-montan el loop
MNT="$(findmnt -no TARGET "$LOOP" 2>/dev/null || true)"
[[ -n "$MNT" ]] || MNT="$(udisksctl mount -b "$LOOP" -o ro | sed -nE 's/^Mounted .* at (.*)\.?$/\1/p' | sed 's/\.$//')"
[[ -d "$MNT/vcsa-cli-installer" ]] || die "No encuentro vcsa-cli-installer en $MNT (¿ISO de VCSA?)"
DEPLOY="$MNT/vcsa-cli-installer/lin64/vcsa-deploy"
TPL="$MNT/vcsa-cli-installer/templates/install/embedded_vCSA_on_ESXi.json"
[[ -x "$DEPLOY" ]] || die "No existe $DEPLOY"

# --- Renderizar la plantilla ----------------------------------------------------------
VCSA_TPL_VERSION="$(jq -r '.__version' "$TPL" 2>/dev/null || true)"
[[ -n "$VCSA_TPL_VERSION" && "$VCSA_TPL_VERSION" != null ]] || die "No se pudo leer __version de $TPL"
export VCSA_TPL_VERSION VCSA_ESXI_HOST="$ESX.$LAB_DOMAIN" VCSA_DATASTORE="$DS" LAB_GW LAB_DNS_SERVER LAB_DOMAIN
# shellcheck disable=SC2016
envsubst '${VCSA_TPL_VERSION} ${VCSA_ESXI_HOST} ${VCSA_DATASTORE} ${LAB_GW} ${LAB_DNS_SERVER} ${LAB_DOMAIN}' \
  < "$STAGE8_DIR/files/vcsa-deploy.json.tpl" > "$WORK/vcsa01.json"
jq empty "$WORK/vcsa01.json" || die "El JSON renderizado no es válido"
info "Plantilla del ISO: __version $VCSA_TPL_VERSION (se usa la misma en el JSON del lab)"

read_pw() {  # read_pw "texto" -> contraseña (no se muestra ni se guarda)
  local a b; read -rsp "$1: " a; echo >&2; read -rsp "Repite: " b; echo >&2
  [[ -n "$a" && "$a" == "$b" ]] || die "Las contraseñas no coinciden o están vacías"
  printf '%s' "$a"
}
if [[ $MODE != verify ]]; then
  P_ESX="${LAB_ESXI_PASSWORD:-$(read_pw "Contraseña de root de $ESX")}"
  P_OS="$(read_pw "Contraseña de root del appliance vcsa01")"
  P_SSO="$(read_pw "Contraseña de administrator@vsphere.local")"
  jq --arg e "$P_ESX" --arg o "$P_OS" --arg s "$P_SSO" \
     '.new_vcsa.esxi.password=$e | .new_vcsa.os.password=$o | .new_vcsa.sso.password=$s' \
     "$WORK/vcsa01.json" > "$WORK/vcsa01.secret.json"
  unset P_ESX P_OS P_SSO
  JSON="$WORK/vcsa01.secret.json"
else
  JSON="$WORK/vcsa01.json"
fi

LOGDIR="$HOME/.local/state/rhel-lab/vcsa-deploy/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$LOGDIR"
args=(install --accept-eula --no-ssl-certificate-verification --log-dir "$LOGDIR")
case "$MODE" in
  verify)   args+=(--verify-template-only) ;;
  precheck) args+=(--precheck-only) ;;
  install)  info "Despliegue REAL de vCenter en $ESX (30-60 min). Anota la FECHA DE HOY en checklists/etapa8.md (inicio de la evaluación)." ;;
esac
"$DEPLOY" "${args[@]}" "$JSON" || die "vcsa-deploy falló. Logs: $LOGDIR"
case "$MODE" in
  install) ok "vCenter desplegado: https://$VCSA_NAME.$LAB_DOMAIN/ui/  (administrator@vsphere.local)"
           info "Siguiente: lab.sh stage8 cluster && lab.sh stage8 esxi-config" ;;
  *)       ok "Comprobación '$MODE' superada. Logs: $LOGDIR" ;;
esac
