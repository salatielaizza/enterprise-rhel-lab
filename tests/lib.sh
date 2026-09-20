#!/usr/bin/env bash
# lib.sh — mini framework de tests (PASS/FAIL). Los tests son de SOLO LECTURA:
# nunca modifican configuración ni destruyen datos (a lo sumo crean y borran un
# fichero temporal para probar permisos).

PASS_N=0; FAIL_N=0
HOSTS_CONF="${HOSTS_CONF:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hosts.conf}"
[[ -f "$HOSTS_CONF" ]] || HOSTS_CONF="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd)/hosts.conf"

pass() { printf 'PASS  %s\n' "$1"; PASS_N=$((PASS_N + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAIL_N=$((FAIL_N + 1)); }
# check "descripción" comando [args...]   -> PASS si el comando devuelve 0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
summary() {
  printf -- '--- %s en %s: %d PASS, %d FAIL\n' "${TEST_NAME:-test}" "$(hostname -s)" "$PASS_N" "$FAIL_N"
  [[ $FAIL_N -eq 0 ]]
}
lab_stage() { local s; s="$(awk -F= '$1=="LAB_STAGE"{print $2}' /etc/lab-release 2>/dev/null)"; echo "${s:-1}"; }
my_field() {  # my_field N -> campo N de mi fila en hosts.conf
  awk -v n="$(hostname -s)" '$1==n {print $'"$1"'}' "$HOSTS_CONF"
}
all_hosts() { awk '$1 !~ /^#/ && NF>=7 {print $1" "$3}' "$HOSTS_CONF"; }
need_root() { [[ $EUID -eq 0 ]] || { echo "Ejecuta como root (sudo)"; exit 2; }; }
