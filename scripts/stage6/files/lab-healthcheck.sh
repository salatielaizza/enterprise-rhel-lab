#!/usr/bin/env bash
# lab-healthcheck.sh — comprobación de salud básica de la máquina (Etapa 6)
#
# Pensado como EJEMPLO de bash "de producción" para el lab:
#   - set -euo pipefail + trap ERR para no fallar en silencio.
#   - getopts para flags (-v verbose, -t umbral de disco).
#   - arrays para los servicios a comprobar según el host.
#   - aritmética con (( )) para comparar umbrales.
#   - logging con timestamp a fichero Y a stdout (útil también bajo systemd).
#
# Salida: 0 si todo OK, 1 si algo falla.
# Uso manual: sudo /usr/local/sbin/lab-healthcheck.sh -v [-t 80]
set -euo pipefail

LOG=/var/log/lab-healthcheck.log
VERBOSE=0
DISK_THRESHOLD=80   # % de uso a partir del cual se avisa

usage() { echo "Uso: $0 [-v] [-t umbral_disco_%]"; exit 2; }
while getopts ":vt:" opt; do
  case "$opt" in
    v) VERBOSE=1 ;;
    t) DISK_THRESHOLD="$OPTARG" ;;
    *) usage ;;
  esac
done

FAILED=0
log() {  # log NIVEL mensaje...
  local level="$1"; shift
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$LOG"
  # OJO: nunca "cond && comando" como frase suelta bajo 'set -e' — si la
  # condición es falsa, bash considera que TODA la línea ha fallado y aborta
  # el script (caso 28 de este proyecto). Por eso aquí un 'if' explícito.
  if [[ $VERBOSE -eq 1 ]]; then
    printf '[%s] %s\n' "$level" "$*"
  fi
}
trap 'log ERROR "healthcheck abortado inesperadamente (línea $LINENO)"' ERR

# --- Servicios a comprobar según el rol del host (hostname corto) --------------
HOST="$(hostname -s)"
declare -a SERVICES=(sshd chronyd)
if [[ "$HOST" == dns01 ]]; then
  SERVICES+=(named)
fi

for svc in "${SERVICES[@]}"; do
  if systemctl is-active --quiet "$svc"; then
    log OK "servicio $svc activo"
  else
    log FAIL "servicio $svc NO está activo"
    FAILED=1
  fi
done

# --- Disco: / y /var ------------------------------------------------------------
for mnt in / /var; do
  [[ -d "$mnt" ]] || continue
  use="$(df -P "$mnt" | awk 'NR==2{gsub("%","",$5); print $5}')"
  if (( use >= DISK_THRESHOLD )); then
    log FAIL "uso de disco en $mnt: ${use}% (umbral ${DISK_THRESHOLD}%)"
    FAILED=1
  else
    log OK "uso de disco en $mnt: ${use}%"
  fi
done

# --- Carga media (1 min) frente a nº de CPUs, solo informativo -------------------
cpus="$(nproc)"
load1="$(awk '{print $1}' /proc/loadavg)"
log OK "carga media 1 min: $load1 (CPUs: $cpus)"

if [[ $FAILED -eq 0 ]]; then
  log OK "healthcheck: todo correcto"
else
  log FAIL "healthcheck: se han encontrado problemas (ver arriba)"
fi
exit $FAILED
