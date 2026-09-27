#!/usr/bin/env bash
# lab-logscan.sh — cuenta intentos de login SSH fallidos por IP en los últimos N
# minutos (Etapa 6). Ejemplo de bash avanzado:
#   - array asociativo como "diccionario" (IP -> nº de intentos).
#   - process substitution ('< <(...)') en vez de 'cmd | while read', para que
#     el array sobreviva al bucle (un pipe a while corre en un subshell).
#   - nunca se parsea 'ls': la fuente es journalctl (fiable en RHEL 7-10, con
#     o sin rsyslog persistente).
set -euo pipefail

MINUTES=60
usage() { echo "Uso: $0 [-m minutos]"; exit 2; }
while getopts ":m:" opt; do
  case "$opt" in
    m) MINUTES="$OPTARG" ;;
    *) usage ;;
  esac
done

declare -A COUNT=()
SINCE="$(date -d "-${MINUTES} minutes" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')"

while IFS= read -r ip; do
  [[ -n "$ip" ]] && COUNT["$ip"]=$(( ${COUNT["$ip"]:-0} + 1 ))
done < <(journalctl -u sshd --since "$SINCE" 2>/dev/null \
           | grep -E 'Failed (password|publickey)' \
           | grep -Eo 'from [0-9.]+' | awk '{print $2}')

if [[ ${#COUNT[@]} -eq 0 ]]; then
  echo "Sin intentos fallidos de SSH en los últimos $MINUTES minutos."
  exit 0
fi

echo "Intentos fallidos de SSH en los últimos $MINUTES minutos:"
for ip in "${!COUNT[@]}"; do
  printf '%s %s\n' "${COUNT[$ip]}" "$ip"
done | sort -rn | while read -r n ip; do
  printf '  %-15s %d intento(s)\n' "$ip" "$n"
done
