#!/usr/bin/env bash
# =============================================================================
# 00-preflight.sh — Auditoría de SOLO LECTURA del host antes de la Etapa 8
#
# No cambia nada: ni el host, ni libvirt, ni las VMs. Comprueba lo que necesita
# ESXi anidado en KVM y vCenter, y dice qué falta. Salida PASS / WARN / FAIL;
# devuelve 1 si hay algún FAIL (bloqueante).
#
# Uso: 00-preflight.sh [A|B]     A = solo ESXi gratuito (por defecto)
#                                B = clúster con vCenter en evaluación
# =============================================================================
set -uo pipefail
# shellcheck source=vmware-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/vmware-lib.sh"

PHASE="${1:-A}"
[[ "$PHASE" == A || "$PHASE" == B ]] || die "Uso: $0 [A|B]"
P=0; W=0; F=0
pass() { printf '\033[1;32mPASS\033[0m  %s\n' "$*"; P=$((P + 1)); }
wrn()  { printf '\033[1;33mWARN\033[0m  %s\n' "$*"; W=$((W + 1)); }
bad()  { printf '\033[1;31mFAIL\033[0m  %s\n' "$*"; F=$((F + 1)); }

info "=== Preflight de la Etapa 8 (fase $PHASE) — solo lectura ==="

# --- CPU y KVM -------------------------------------------------------------------
if grep -Eq '(vmx|svm)' /proc/cpuinfo; then pass "CPU con virtualización por hardware (vmx/svm)"; else bad "La CPU no expone vmx/svm"; fi
nested="$(cat /sys/module/kvm_intel/parameters/nested 2>/dev/null || cat /sys/module/kvm_amd/parameters/nested 2>/dev/null || echo '?')"
if [[ "$nested" == Y || "$nested" == 1 ]]; then pass "virtualización anidada activa (nested=$nested)"
else bad "virtualización anidada desactivada (nested=$nested): ESXi no podrá ejecutar VMs"; fi
msrs="$(cat /sys/module/kvm/parameters/ignore_msrs 2>/dev/null || echo '?')"
if [[ "$msrs" == Y || "$msrs" == 1 ]]; then pass "kvm.ignore_msrs=$msrs"
else wrn "kvm.ignore_msrs=$msrs: si ESXi da una pantalla morada (PSOD) al arrancar, es lo primero a probar.
      Cambio EN CALIENTE y NO persistente (pide confirmación antes):  echo 1 | sudo tee /sys/module/kvm/parameters/ignore_msrs"; fi
if grep -q 'model name' /proc/cpuinfo; then pass "CPU: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')"; fi

# --- Herramientas -----------------------------------------------------------------
for t in virsh virt-install xorriso envsubst openssl ssh-keygen; do
  if command -v "$t" >/dev/null; then pass "comando $t disponible"; else bad "falta el comando $t"; fi
done
if command -v dig >/dev/null; then pass "comando dig disponible"; else wrn "falta dig (paquete bind9-dnsutils): se usa para comprobar el DNS del lab"; fi
if [[ "$PHASE" == B ]]; then
  for t in jq udisksctl; do
    if command -v "$t" >/dev/null; then pass "comando $t disponible (despliegue de VCSA)"; else bad "falta $t (lo usa vcsa-deploy)"; fi
  done
fi
# NO usar 'comando | grep -q' con pipefail: grep -q sale al primer acierto, el comando
# recibe SIGPIPE (141) y pipefail convierte el acierto en fallo -> falso FAIL
# (caso troubleshooting/etapa8/01). Se captura la salida y se busca sobre la variable.
qemu_devs="$(qemu-system-x86_64 -device help 2>/dev/null || true)"
if grep -q '"vmxnet3"' <<<"$qemu_devs"; then pass "QEMU ofrece la NIC vmxnet3"
else bad "QEMU no ofrece vmxnet3 (ESXi no reconoce virtio-net)"; fi

# --- libvirt ---------------------------------------------------------------------
net_info="$(virsh net-info "$LAB_NET" 2>/dev/null || true)"   # sin tubería: ver nota de vmxnet3
if grep -Eq 'Active:[[:space:]]+yes' <<<"$net_info"; then pass "red $LAB_NET activa"; else bad "red $LAB_NET no activa (lab.sh network)"; fi
if virsh pool-info lab-images >/dev/null 2>&1; then pass "pool lab-images definido"; else bad "falta el pool lab-images (lab.sh host-setup)"; fi

# --- RAM ---------------------------------------------------------------------------
total_mb="$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo)"
avail_mb="$(mem_avail_mb)"
info "RAM total ${total_mb} MB, disponible ahora ${avail_mb} MB"
if [[ "$PHASE" == A ]]; then
  need=$(( $(vmw_field esxi01 5) + 2048 ))
  if (( avail_mb >= need )); then pass "RAM disponible >= ${need} MB (esxi01 + margen)"
  else wrn "RAM disponible < ${need} MB: apaga alguna app01 antes de 'lab.sh esxi-create esxi01'"; fi
else
  need=$(( $(vmw_field esxi02 5) + $(vmw_field esxi03 5) + 3072 ))
  if (( avail_mb >= need )); then pass "RAM disponible >= ${need} MB (esxi02 + esxi03 + margen)"
  else wrn "RAM disponible < ${need} MB: apaga las 4 app01 y esxi01 (lab.sh down rhel7-app01 ...; lab.sh esxi-down esxi01)"; fi
  for h in rhel7-app01 rhel8-app01 rhel9-app01 rhel10-app01; do
    if [[ "$(vmw_state "$h")" == running ]]; then wrn "$h está encendida: en la fase B debería estar apagada"; fi
  done
fi

# --- Disco -------------------------------------------------------------------------
free_gb="$(df -BG --output=avail "$LAB_STORE" 2>/dev/null | tail -1 | tr -dc '0-9')"
free_gb="${free_gb:-0}"
need_gb=$([[ "$PHASE" == A ]] && echo 70 || echo 130)
info "Disco libre en $LAB_STORE: ${free_gb} GB (regla del lab: no bajar de 50 GB libres)"
if (( free_gb >= need_gb )); then pass "disco libre >= ${need_gb} GB (uso real estimado de la fase + 50 GB de margen)"
else wrn "disco libre < ${need_gb} GB: revisa ISOs duplicadas o snapshots antiguos ANTES de seguir (sin borrar nada a ciegas)"; fi

# --- ISOs ---------------------------------------------------------------------------
check_iso() {  # check_iso CLAVE descripción obligatorio(1/0)
  local p
  if ! p="$(iso_path "$1")"; then
    if [[ "$3" == 1 ]]; then bad "$1 no definido en $LAB_CONF ($2)"; else wrn "$1 no definido en $LAB_CONF ($2)"; fi
    return 0
  fi
  if [[ -f "$p" ]]; then pass "$2: $(basename "$p")"
  elif [[ "$3" == 1 ]]; then bad "$2 no encontrado: $p"
  else wrn "$2 no encontrado: $p"; fi
}
check_iso ESXI_FREE_ISO "ISO de ESXi gratuito (8.0U3e)" 1
if [[ "$PHASE" == B ]]; then
  check_iso ESXI_EVAL_ISO "ISO estándar de ESXi 8 (evaluación)" 1
  check_iso VCSA_ISO "ISO de vCenter Server Appliance 8" 1
fi

# --- Clave SSH para root@ESXi --------------------------------------------------------
if [[ -f "$LAB_ESXI_KEY" ]]; then pass "clave SSH de ESXi presente ($LAB_ESXI_KEY)"
else wrn "no existe $LAB_ESXI_KEY: la crea 'lab.sh esxi-iso' (RSA: el sshd de ESXi 8 va en modo FIPS)"; fi

# --- DNS del lab (vCenter EXIGE A y PTR correctos) ------------------------------------
if command -v dig >/dev/null && tcp_open "$LAB_DNS_SERVER" 53; then
  names=(esxi01:10.10.10.60)
  [[ "$PHASE" == B ]] && names+=(esxi02:10.10.10.61 esxi03:10.10.10.62 "$VCSA_NAME:$VCSA_IP")
  names+=("$GUEST_NAME:$GUEST_IP")
  for spec in "${names[@]}"; do
    n="${spec%%:*}"; ip="${spec##*:}"
    a="$(dig +short +time=2 +tries=1 @"$LAB_DNS_SERVER" "$n.$LAB_DOMAIN" A | head -1)"
    r="$(dig +short +time=2 +tries=1 @"$LAB_DNS_SERVER" -x "$ip" | head -1)"
    if [[ "$a" == "$ip" ]]; then pass "DNS A   $n.$LAB_DOMAIN -> $ip"
    else bad "DNS A   $n.$LAB_DOMAIN devuelve '${a:-nada}' (esperado $ip): lab.sh stage4-dns"; fi
    if [[ "$r" == "$n.$LAB_DOMAIN." ]]; then pass "DNS PTR $ip -> $n.$LAB_DOMAIN."
    else bad "DNS PTR $ip devuelve '${r:-nada}': lab.sh stage4-dns"; fi
  done
else
  wrn "dns01 ($LAB_DNS_SERVER:53) no responde o falta dig: no se puede comprobar el DNS (vCenter lo exige)"
fi

# --- Firmware para snapshots internos -------------------------------------------------
info "Los ESXi se crean con firmware BIOS para conservar los snapshots internos de libvirt (como el resto del lab)."

# --- VMs de la Etapa 8 ya existentes --------------------------------------------------
for h in $(vmw_all); do
  st="$(vmw_state "$h")"; [[ -n "$st" ]] && info "$h ya existe en libvirt (estado: $st)"
done

echo
printf -- '--- preflight fase %s: %d PASS, %d WARN, %d FAIL\n' "$PHASE" "$P" "$W" "$F"
(( F == 0 ))
