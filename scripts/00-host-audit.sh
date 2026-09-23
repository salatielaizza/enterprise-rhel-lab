#!/usr/bin/env bash
# =============================================================================
# 00-host-audit.sh — FASE 0: AUDITORÍA DEL HOST (SOLO LECTURA)
# Enterprise RHEL Infrastructure Lab
#
# GARANTÍAS DE SEGURIDAD
#   - No usa sudo. No instala paquetes. No arranca/para servicios.
#   - virsh se usa SIEMPRE con conexión de solo lectura (-r).
#   - No toca discos, red, firewall ni /etc.
#   - Lo ÚNICO que escribe es el informe dentro del proyecto:
#       evidence/host/host-audit-<fecha>.txt
#
# USO
#   ./scripts/00-host-audit.sh                 # informe completo
#   ./scripts/00-host-audit.sh --with-checksums  # además calcula SHA-256 de ISOs (lento)
# =============================================================================
set -uo pipefail   # sin -e a propósito: un comando que falle no debe cortar la auditoría

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO_DIR="${ISO_DIR:-$PROJECT_ROOT/isos}"
ISO_CONF="$PROJECT_ROOT/config/isos.conf"
LAB_NET_CIDR_PREFIX="10.10.10."
WITH_CHECKSUMS=0
[[ "${1:-}" == "--with-checksums" ]] && WITH_CHECKSUMS=1

REPORT_DIR="$PROJECT_ROOT/evidence/host"
REPORT="$REPORT_DIR/host-audit-$(date +%Y%m%d-%H%M%S).txt"
mkdir -p "$REPORT_DIR"

RISKS=()
risk() { RISKS+=("$1"); }
have() { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n==================== %s ====================\n' "$1"; }
run() { printf '\n$ %s\n' "$*"; "$@" 2>&1 || printf '(comando devolvió código %s)\n' "$?"; }

VIRSH=(virsh -r -c qemu:///system)   # -r = read-only

audit() {
  echo "HOST AUDIT — Enterprise RHEL Infrastructure Lab"
  echo "Fecha: $(date -Is)"
  echo "Usuario: $(id -un)  Grupos: $(id -Gn)"
  echo "Proyecto: $PROJECT_ROOT"

  # ---------------------------------------------------------------- SO / CPU / RAM
  section "OS / KERNEL"
  run cat /etc/os-release
  run uname -a

  section "CPU"
  run lscpu
  local vmx; vmx=$(grep -cE '\b(vmx|svm)\b' /proc/cpuinfo)
  echo "Hilos con vmx/svm: $vmx"
  [[ "$vmx" -eq 0 ]] && risk "CRÍTICO: la CPU no expone vmx/svm (¿VT-x desactivado en BIOS?). KVM no funcionará."

  echo; echo "--- Nivel de microarquitectura x86-64 (RHEL 9 exige v2, RHEL 10 exige v3)"
  local ld=/lib64/ld-linux-x86-64.so.2
  if [[ -x "$ld" ]]; then
    "$ld" --help 2>/dev/null | grep -E 'x86-64-v[234]' || echo "(ld.so no informa niveles)"
    if ! "$ld" --help 2>/dev/null | grep -q 'x86-64-v3 (supported'; then
      risk "ALTO: el host no parece soportar x86-64-v3 → RHEL 10 no arrancará."
    fi
  fi
  for f in avx avx2 bmi1 bmi2 fma movbe f16c; do
    if grep -qw "$f" /proc/cpuinfo; then echo "  flag $f: sí"; else echo "  flag $f: NO"; risk "ALTO: falta el flag $f (x86-64-v3)"; fi
  done

  section "MEMORIA"
  run free -h
  local avail_gb; avail_gb=$(awk '/MemAvailable/ {printf "%d", $2/1024/1024}' /proc/meminfo)
  echo "RAM disponible ahora: ${avail_gb} GB"
  [[ "$avail_gb" -lt 12 ]] && risk "MEDIO: menos de 12 GB libres; no arranques todas las VMs a la vez."

  # ---------------------------------------------------------------- STORAGE
  section "STORAGE — HOST DISKS / FILESYSTEMS (no se toca nada)"
  run lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL
  run findmnt --real
  run df -hT -x tmpfs -x devtmpfs -x squashfs -x overlay
  local free_proj_gb; free_proj_gb=$(df -BG --output=avail "$PROJECT_ROOT" | tail -1 | tr -dc '0-9')
  echo "Espacio libre en el FS del proyecto: ${free_proj_gb} GB"
  [[ "$free_proj_gb" -lt 120 ]] && risk "MEDIO: <120 GB libres donde está el proyecto (4 ISOs ≈ 35-45 GB + discos qcow2)."
  if [[ -d /var/lib/libvirt/images ]]; then
    echo; echo "--- /var/lib/libvirt/images (LIBVIRT STORAGE por defecto)"
    run ls -la /var/lib/libvirt/images
    run df -hT /var/lib/libvirt/images
  fi

  # ---------------------------------------------------------------- VIRTUALIZACIÓN
  section "VIRTUALIZACIÓN / KVM"
  run ls -l /dev/kvm
  run lsmod | grep -E '^kvm' || true
  for b in virsh virt-install qemu-system-x86_64 qemu-img virt-manager osinfo-query jq curl sha256sum; do
    printf '  %-20s %s\n' "$b" "$(command -v "$b" || echo 'NO INSTALADO')"
  done
  echo; echo "--- Paquetes dpkg relevantes (consulta, no instala)"
  dpkg -l 2>/dev/null | awk '$1=="ii" && $2 ~ /^(qemu-system-x86|qemu-kvm|libvirt-daemon-system|libvirt-clients|virtinst|virt-manager|osinfo-db|jq|ovmf)$/ {print "  "$2, $3}'
  echo; echo "--- Estado de servicios libvirt (consulta)"
  for s in libvirtd virtqemud; do printf '  %-12s active=%s enabled=%s\n' "$s" "$(systemctl is-active "$s" 2>/dev/null)" "$(systemctl is-enabled "$s" 2>/dev/null)"; done
  id -nG | grep -qw libvirt || risk "INFO: el usuario no está en el grupo 'libvirt' (virsh sin sudo no verá qemu:///system)."

  section "LIBVIRT — VMs / REDES / POOLS (conexión read-only)"
  if have virsh; then
    run "${VIRSH[@]}" uri
    run "${VIRSH[@]}" list --all
    run "${VIRSH[@]}" net-list --all
    run "${VIRSH[@]}" pool-list --all
    for vm in rhel7-app01 rhel8-app01 rhel9-app01 rhel10-app01 dns01 ansible01; do
      "${VIRSH[@]}" dominfo "$vm" >/dev/null 2>&1 && risk "INFO: ya existe una VM llamada $vm (no se tocará; revisar antes de crear)."
    done
    local nets; nets=$("${VIRSH[@]}" net-list --all --name 2>/dev/null)
    for n in $nets; do
      "${VIRSH[@]}" net-dumpxml "$n" 2>/dev/null | grep -q "$LAB_NET_CIDR_PREFIX" \
        && risk "ALTO: la red libvirt existente '$n' ya usa ${LAB_NET_CIDR_PREFIX}0/24."
    done
    if osinfo-query os >/dev/null 2>&1; then
      echo; echo "--- os-variants RHEL conocidos por osinfo-db"
      osinfo-query os 2>/dev/null | grep -E '^\s*rhel(7\.9|8|9|10)' | awk '{print "  "$1}' | sort -V | tail -20
      osinfo-query os 2>/dev/null | grep -qE '^\s*rhel10' || risk "INFO: osinfo-db no conoce rhel10.x (se usará un os-variant alternativo al crear rhel10-app01)."
    fi
  else
    echo "virsh no instalado → no hay infraestructura libvirt que auditar."
  fi

  # ---------------------------------------------------------------- RED
  section "RED DEL HOST (solo lectura)"
  run ip -br addr
  run ip route
  run ip -br link
  if have nmcli; then run nmcli connection show; run nmcli device status; fi
  if ip route | grep -q "$LAB_NET_CIDR_PREFIX"; then
    risk "ALTO: el host ya tiene rutas hacia ${LAB_NET_CIDR_PREFIX}0/24 → conflicto con lab-net."
  fi
  if ip -br link | awk '{print $1}' | grep -q '^wl'; then
    risk "INFO: el host sale por Wi-Fi. Un bridge físico sobre Wi-Fi no es viable: lab-net debe ser NAT/aislada (es lo previsto)."
  fi

  # ---------------------------------------------------------------- ISOs
  section "ISOs"
  echo "ISO_DIR = $ISO_DIR"
  if [[ -d "$ISO_DIR" ]]; then run ls -la "$ISO_DIR"; else echo "ISO_DIR no existe todavía."; fi
  local found; found=$(find "$ISO_DIR" /var/lib/libvirt/images -maxdepth 2 -name 'rhel-*.iso' 2>/dev/null)
  [[ -z "$found" ]] && risk "INFO: no hay ISOs RHEL descargadas (esperado: usar scripts/download-isos.sh)."
  if [[ "$WITH_CHECKSUMS" -eq 1 && -n "$found" ]]; then
    echo "--- SHA-256 (puede tardar varios minutos)"
    while IFS= read -r f; do sha256sum "$f"; done <<<"$found"
  fi
  [[ -f "$ISO_CONF" ]] && { echo "--- config/isos.conf"; grep -vE '^\s*(#|$)' "$ISO_CONF"; }

  echo; echo "--- Permisos de acceso para el usuario de QEMU (libvirt-qemu)"
  local p="$ISO_DIR"
  while [[ "$p" != "/" && -n "$p" ]]; do [[ -e "$p" ]] && stat -c '  %A %U:%G %n' "$p"; p=$(dirname "$p"); done
  local home_mode; home_mode=$(stat -c '%a' "$HOME")
  (( ${home_mode: -1} % 2 == 0 )) && [[ "$ISO_DIR" == "$HOME"* ]] && \
    risk "MEDIO: $HOME tiene permisos $home_mode; libvirt-qemu no podrá leer ISOs dentro de tu home. Opciones (requieren tu confirmación): mover/copiar ISOs a /var/lib/libvirt/images/iso o dar ACL +x."

  # ---------------------------------------------------------------- PROYECTO
  section "PROYECTO / GIT"
  run ls -la "$PROJECT_ROOT"
  if [[ -d "$PROJECT_ROOT/.git" ]]; then
    run git -C "$PROJECT_ROOT" status --short --branch
    run git -C "$PROJECT_ROOT" log --oneline -n 15
  else
    risk "INFO: el proyecto no es todavía un repositorio Git."
  fi

  # ---------------------------------------------------------------- RESUMEN
  section "RESUMEN DE RIESGOS"
  if [[ ${#RISKS[@]} -eq 0 ]]; then echo "Sin riesgos detectados automáticamente."; else printf ' - %s\n' "${RISKS[@]}"; fi
  echo; echo "Auditoría terminada. No se ha modificado nada fuera de: $REPORT"
}

audit | tee "$REPORT"
