#!/usr/bin/env bash
# =============================================================================
# download-isos.sh — Descarga automatizada de ISOs RHEL (7, 8, 9, 10)
# Enterprise RHEL Infrastructure Lab
#
# Método oficial documentado por Red Hat:
#   1) offline token (https://access.redhat.com/management/api)
#   2) offline token  → access token  (SSO, client_id=rhsm-api, dura minutos)
#   3) GET /management/v1/images/<sha256>/download → {filename, href}
#   4) descarga del href + verificación SHA-256
#
# SEGURIDAD
#   - El token NUNCA se escribe en Git, en logs ni en la línea de comandos
#     (se pasa a curl por stdin, así no aparece en `ps`).
#   - Solo escribe dentro de ISO_DIR (por defecto <proyecto>/isos, ignorado por Git).
#   - No sobrescribe una ISO existente con checksum distinto: se detiene.
#   - No instala paquetes: si falta jq/curl, lo dice y sale.
#   - No usa sudo.
#
# USO
#   ./scripts/download-isos.sh --dry-run            # comprueba todo, no descarga
#   ./scripts/download-isos.sh                      # descarga las claves con checksum
#   ./scripts/download-isos.sh --only rhel9,rhel10  # solo algunas
#   ./scripts/download-isos.sh --list 10.1         # lista ISOs de una versión (experimental)
#   ./scripts/download-isos.sh --verify             # solo verifica las ya descargadas
#
# TOKEN (por orden de preferencia)
#   1. variable RH_OFFLINE_TOKEN (solo para esta sesión)
#   2. fichero ~/.config/enterprise-rhel-lab/offline_token  (permisos 600, fuera del repo)
#   3. se pide de forma interactiva (no se muestra al escribir)
# =============================================================================
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO_DIR="${ISO_DIR:-$PROJECT_ROOT/isos}"
ISO_CONF="${ISO_CONF:-$PROJECT_ROOT/config/isos.conf}"
TOKEN_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/enterprise-rhel-lab/offline_token"
SSO_URL="https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token"
API_URL="https://api.access.redhat.com/management/v1"
ARCH="x86_64"
MIN_FREE_GB=15          # margen mínimo por ISO pendiente

DRY_RUN=0; VERIFY_ONLY=0; LIST_VERSION=""; ONLY=""

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()   { printf '  PASS  %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,33p' "$0"; exit 0; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --verify)  VERIFY_ONLY=1 ;;
    --only)    ONLY="${2:?--only necesita lista, ej. rhel9,rhel10}"; shift ;;
    --list)    LIST_VERSION="${2:?--list necesita versión, ej. 9.6}"; shift ;;
    -h|--help) usage ;;
    *) die "opción desconocida: $1 (usa --help)" ;;
  esac
  shift
done

# ------------------------------------------------------------------ dependencias
for b in curl jq sha256sum df; do
  command -v "$b" >/dev/null || die "falta '$b'. Instálalo tú (p.ej. 'sudo apt install jq') y reintenta. Este script no instala nada."
done

# ------------------------------------------------------------------ config
declare -A SUM=()
[[ -f "$ISO_CONF" ]] || die "no existe $ISO_CONF"
while read -r key sum _; do
  [[ -z "${key:-}" || "$key" == \#* ]] && continue
  [[ "$key" =~ ^rhel(7|8|9|10)$ ]] || die "clave no válida en isos.conf: $key"
  if [[ -n "${sum:-}" ]]; then
    [[ "$sum" =~ ^[a-f0-9]{64}$ ]] || die "checksum mal formado para $key (deben ser 64 hex en minúscula)"
    SUM[$key]="$sum"
  fi
done < "$ISO_CONF"

selected() {
  [[ -z "$ONLY" ]] && return 0
  [[ ",$ONLY," == *",$1,"* ]]
}

# ------------------------------------------------------------------ token
get_offline_token() {
  if [[ -n "${RH_OFFLINE_TOKEN:-}" ]]; then printf '%s' "$RH_OFFLINE_TOKEN"; return; fi
  if [[ -f "$TOKEN_FILE" ]]; then
    local mode; mode=$(stat -c '%a' "$TOKEN_FILE")
    [[ "$mode" == "600" || "$mode" == "400" ]] || die "$TOKEN_FILE tiene permisos $mode; ejecuta: chmod 600 $TOKEN_FILE"
    tr -d '[:space:]' < "$TOKEN_FILE"; return
  fi
  local t; read -rsp "Offline token de Red Hat (no se mostrará): " t </dev/tty; echo >&2
  [[ -n "$t" ]] || die "token vacío"
  printf '%s' "$t"
}

OFFLINE_TOKEN=""
ensure_offline_token() {   # se llama en el shell principal (no en subshell) → se pide una sola vez
  [[ -n "$OFFLINE_TOKEN" ]] || OFFLINE_TOKEN="$(get_offline_token)"
}
get_access_token() {        # cada llamada obtiene un access token nuevo (caducan en minutos)
  local resp
  resp=$(printf '%s' "$OFFLINE_TOKEN" | curl -sS --fail-with-body "$SSO_URL" \
           -d grant_type=refresh_token -d client_id=rhsm-api \
           --data-urlencode "refresh_token@-") \
    || die "el SSO de Red Hat rechazó el token (¿caducado? genera otro en https://access.redhat.com/management/api)"
  jq -er '.access_token' <<<"$resp" || die "respuesta SSO sin access_token"
}

api_get() {   # api_get <ruta>  → cuerpo JSON (cabecera Authorization por stdin, no visible en ps)
  local at; at="$(get_access_token)"
  printf 'Authorization: Bearer %s' "$at" | curl -sS --fail-with-body -H @- "$API_URL/$1"
}
# ------------------------------------------------------------------ --list
if [[ -n "$LIST_VERSION" ]]; then
  [[ "$LIST_VERSION" =~ ^[0-9]+\.[0-9]+$ ]] || die "versión no válida: $LIST_VERSION (formato 9.6)"
  log "[EXPERIMENTAL] Listando imágenes RHEL $LIST_VERSION $ARCH"
  ensure_offline_token
  api_get "images/rhel/$LIST_VERSION/$ARCH" \
    | jq -r '.body[]? | [.filename, .checksum] | @tsv' \
    || die "la API no devolvió lista. Copia el checksum desde el portal web."
  exit 0
fi

# ------------------------------------------------------------------ verificación
verify_file() {  # verify_file <fichero> <sha256>
  local actual; actual=$(sha256sum "$1" | awk '{print $1}')
  [[ "$actual" == "$2" ]]
}

find_existing() {  # ISO ya descargada con ese checksum (registro local)
  local rec="$ISO_DIR/.downloaded"
  [[ -f "$rec" ]] || return 0
  awk -v s="$1" '$1==s {print $2}' "$rec" | tail -1
}

mkdir -p "$ISO_DIR"
[[ -f "$ISO_DIR/.gitignore" ]] || printf '*\n!.gitignore\n' > "$ISO_DIR/.gitignore"

log "Proyecto : $PROJECT_ROOT"
log "ISO_DIR  : $ISO_DIR"
MODE=DESCARGA; [[ $VERIFY_ONLY -eq 1 ]] && MODE=VERIFY; [[ $DRY_RUN -eq 1 ]] && MODE=DRY-RUN
log "Modo     : $MODE"

PENDING=(); FAILS=0
for key in rhel7 rhel8 rhel9 rhel10; do
  selected "$key" || continue
  if [[ -z "${SUM[$key]:-}" ]]; then log "$key: sin checksum en isos.conf → se omite"; continue; fi
  existing="$(find_existing "${SUM[$key]}")"
  if [[ -n "$existing" && -f "$ISO_DIR/$existing" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then ok "$key: ya presente ($existing) — verificación completa con --verify"
    elif verify_file "$ISO_DIR/$existing" "${SUM[$key]}"; then ok "$key: $existing (SHA-256 correcto)"
    else bad "$key: $existing NO coincide con el checksum → no se toca; revisa manualmente"; FAILS=$((FAILS+1)); fi
  else
    [[ $VERIFY_ONLY -eq 1 ]] && { bad "$key: no descargada"; FAILS=$((FAILS+1)); continue; }
    PENDING+=("$key")
  fi
done

[[ $VERIFY_ONLY -eq 1 ]] && { [[ $FAILS -eq 0 ]] && exit 0 || exit 1; }

free_gb=$(df -BG --output=avail "$ISO_DIR" | tail -1 | tr -dc '0-9')
need_gb=$(( ${#PENDING[@]} * MIN_FREE_GB ))
log "Pendientes: ${PENDING[*]:-ninguna}   Libre: ${free_gb} GB   Necesario aprox.: ${need_gb} GB"
(( free_gb >= need_gb )) || die "espacio insuficiente en $(df --output=target "$ISO_DIR" | tail -1)"

if [[ $DRY_RUN -eq 1 ]]; then
  for key in "${PENDING[@]}"; do log "DRY-RUN: se descargaría $key (sha256 ${SUM[$key]:0:16}…)"; done
  log "DRY-RUN terminado. No se ha contactado con Red Hat ni descargado nada."
  exit 0
fi

[[ ${#PENDING[@]} -gt 0 ]] && ensure_offline_token
for key in "${PENDING[@]}"; do
  sum="${SUM[$key]}"
  log "$key: solicitando enlace de descarga…"
  meta=$(api_get "images/$sum/download") || { bad "$key: la API no encuentra ese checksum (¿ISO no incluida en tu suscripción?)"; FAILS=$((FAILS+1)); continue; }
  filename=$(jq -er '.body.filename' <<<"$meta")
  href=$(jq -er '.body.href' <<<"$meta")
  # Defensa: el nombre viene de la red → solo un nombre de fichero simple
  [[ "$filename" =~ ^[A-Za-z0-9._-]+\.iso$ ]] || { bad "$key: nombre de fichero sospechoso '$filename'"; FAILS=$((FAILS+1)); continue; }
  dest="$ISO_DIR/$filename"
  if [[ -e "$dest" ]]; then
    if verify_file "$dest" "$sum"; then
      printf '%s %s %s\n' "$sum" "$filename" "$key" >> "$ISO_DIR/.downloaded"
      ok "$key: $filename ya existía y es correcta"; continue
    fi
    bad "$key: ya existe $dest con otro contenido → NO se sobrescribe"; FAILS=$((FAILS+1)); continue
  fi
  log "$key: descargando $filename (reanudable)…"
  curl -fL --retry 5 --retry-delay 10 -C - --progress-bar -o "$dest.part" "$href" \
    || { bad "$key: descarga interrumpida (vuelve a ejecutar: se reanuda)"; FAILS=$((FAILS+1)); continue; }
  log "$key: verificando SHA-256…"
  if verify_file "$dest.part" "$sum"; then
    mv -n "$dest.part" "$dest"
    printf '%s %s %s\n' "$sum" "$filename" "$key" >> "$ISO_DIR/.downloaded"
    ok "$key: $filename"
  else
    bad "$key: checksum incorrecto; se conserva $dest.part para análisis"; FAILS=$((FAILS+1))
  fi
done

log "Resumen: $([[ $FAILS -eq 0 ]] && echo 'PASS' || echo "FAIL ($FAILS)")"
[[ $FAILS -eq 0 ]]
