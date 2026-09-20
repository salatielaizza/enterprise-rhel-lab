#!/usr/bin/env bash
# =============================================================================
# download-isos.sh — Descarga y verifica las ISOs de RHEL 7/8/9/10 (API de Red Hat)
#
# Flujo (el que documenta Red Hat para descargar con curl):
#   1. offline token --(sso.redhat.com)--> access token (dura pocos minutos)
#   2. access token + SHA-256 de la ISO --(api.access.redhat.com)--> URL temporal
#   3. curl descarga la ISO (reanudable) y sha256sum la verifica
#
# Uso:
#   ./download-isos.sh --check     # valida token y checksums; NO descarga
#   ./download-isos.sh             # descarga las 4 ISOs (salta las ya válidas)
#   ./download-isos.sh --only 9    # solo RHEL 9 (también 7, 8 o 10)
#
# Es idempotente: si la ISO ya existe y su SHA-256 coincide, no se vuelve a bajar.
# El token NUNCA se pasa por línea de comandos ni se guarda en el repositorio Git:
# vive en ~/.config/rhel-lab/offline_token con permisos 600.
# =============================================================================
set -euo pipefail

CONF="${LAB_CONF:-$HOME/.config/rhel-lab/isos.conf}"
TOKEN_FILE="${RH_TOKEN_FILE:-$HOME/.config/rhel-lab/offline_token}"
SSO_URL="https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token"
API_URL="https://api.access.redhat.com/management/v1/images"

CHECK_ONLY=0
ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_ONLY=1 ;;
    --only)  ONLY="${2:-}"; shift || true ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; exit 2 ;;
  esac
  shift || true
done
if [[ -n "$ONLY" && ! "$ONLY" =~ ^(7|8|9|10)$ ]]; then
  echo "--only admite 7, 8, 9 o 10" >&2; exit 2
fi

# --- Requisitos --------------------------------------------------------------
for cmd in curl jq sha256sum; do
  command -v "$cmd" >/dev/null || { echo "Falta '$cmd' (sudo apt install $cmd)" >&2; exit 1; }
done
[[ -f "$CONF" ]] || { echo "No existe $CONF (copia isos.conf.example y rellénalo)" >&2; exit 1; }
[[ -f "$TOKEN_FILE" ]] || { echo "No existe $TOKEN_FILE (ver instrucciones de token)" >&2; exit 1; }
if [[ "$(stat -c %a "$TOKEN_FILE")" != "600" ]]; then
  echo "Permisos inseguros en $TOKEN_FILE. Ejecuta: chmod 600 $TOKEN_FILE" >&2; exit 1
fi

# --- Lectura de configuración (sin ejecutar el fichero) ----------------------
conf_get() {   # conf_get CLAVE -> valor sin comillas ni espacios finales, o vacío
  sed -nE "s/^[[:space:]]*$1=[\"']?([^\"'#]*)[\"']?.*$/\1/p" "$CONF" \
    | tail -n1 | sed -E "s|^~|$HOME|; s|\\\$HOME|$HOME|; s/[[:space:]]+\$//"
}
ISO_DIR="$(conf_get ISO_DIR)"
ISO_DIR="${ISO_DIR:-$HOME/rhel-lab/isos}"
mkdir -p "$ISO_DIR"

# --- Token -------------------------------------------------------------------
get_access_token() {
  local tok
  tok="$(tr -d '[:space:]' < "$TOKEN_FILE")"
  # El token va por stdin (printf es un builtin): no aparece en 'ps'.
  printf 'grant_type=refresh_token&client_id=rhsm-api&refresh_token=%s' "$tok" \
    | curl -fsS --data @- "$SSO_URL" | jq -er .access_token
}

# --- Bucle principal ---------------------------------------------------------
FAIL=0
SUMMARY=()
for v in 7 8 9 10; do
  [[ -n "$ONLY" && "$ONLY" != "$v" ]] && continue

  sha="$(conf_get "RHEL${v}_SHA256" | tr 'A-F' 'a-f')"
  if [[ -z "$sha" ]]; then
    echo "RHEL $v: sin RHEL${v}_SHA256 en $CONF -> omitida"
    SUMMARY+=("RHEL $v: OMITIDA (sin checksum)"); continue
  fi
  if [[ ! "$sha" =~ ^[0-9a-f]{64}$ ]]; then
    echo "RHEL $v: el valor no parece un SHA-256 (64 hex)" >&2
    SUMMARY+=("RHEL $v: ERROR (checksum inválido)"); FAIL=1; continue
  fi

  echo "== RHEL $v =="
  if ! access="$(get_access_token)"; then
    echo "  No se pudo obtener el access token (¿offline token caducado?)" >&2
    SUMMARY+=("RHEL $v: ERROR (token)"); FAIL=1; continue
  fi
  if ! meta="$(curl -fsS -H "Authorization: Bearer $access" "$API_URL/$sha/download")"; then
    echo "  La API no reconoce ese checksum o no tienes acceso a esa imagen" >&2
    SUMMARY+=("RHEL $v: ERROR (API)"); FAIL=1; continue
  fi
  filename="$(jq -er .body.filename <<<"$meta")"
  href="$(jq -er .body.href <<<"$meta")"
  if [[ "$filename" == */* || "$filename" == .* ]]; then
    echo "  Nombre de fichero sospechoso: $filename" >&2
    SUMMARY+=("RHEL $v: ERROR (nombre)"); FAIL=1; continue
  fi
  echo "  Imagen: $filename"

  if [[ $CHECK_ONLY -eq 1 ]]; then
    SUMMARY+=("RHEL $v: OK (checksum reconocido) $filename"); continue
  fi

  dest="$ISO_DIR/$filename"
  if [[ -f "$dest" ]] && echo "$sha  $dest" | sha256sum -c --status -; then
    echo "  Ya descargada y verificada"
    SUMMARY+=("RHEL $v: YA ESTABA $dest"); continue
  fi

  echo "  Descargando a $dest (reanudable)..."
  if ! curl -fL -C - --retry 3 --progress-bar -o "$dest.part" "$href"; then
    echo "  Descarga interrumpida; vuelve a ejecutar el script para reanudar" >&2
    SUMMARY+=("RHEL $v: ERROR (descarga)"); FAIL=1; continue
  fi
  echo "  Verificando SHA-256..."
  if echo "$sha  $dest.part" | sha256sum -c --status -; then
    mv "$dest.part" "$dest"
    SUMMARY+=("RHEL $v: DESCARGADA Y VERIFICADA $dest")
  else
    rm -f "$dest.part"
    echo "  El SHA-256 NO coincide: fichero descartado" >&2
    SUMMARY+=("RHEL $v: ERROR (SHA-256 no coincide)"); FAIL=1
  fi
done

echo
echo "===== RESUMEN ====="
printf '%s\n' "${SUMMARY[@]}"
exit "$FAIL"
