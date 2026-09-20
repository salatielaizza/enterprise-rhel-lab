#!/usr/bin/env bash
# =============================================================================
# 00-host-setup.sh — Prepara el HOST (Linux Mint / Ubuntu / Debian) para el lab
#
# Qué hace (idempotente, puedes repetirlo):
#   1. Comprueba virtualización por hardware (vmx/svm) y x86-64-v3 (RHEL 10)
#   2. Instala KVM/libvirt/virt-install/virt-manager y utilidades
#   3. Añade tu usuario a los grupos libvirt y kvm
#   4. Crea /var/lib/libvirt/lab/{isos,images} y los pools lab-isos / lab-images
#   5. Mueve las ISOs ya descargadas y actualiza ISO_DIR en isos.conf
#   6. Crea la clave SSH del laboratorio (~/.ssh/lab_ed25519) y ~/.ssh/lab_config
#
# Por qué los pools NO están en tu $HOME: en Ubuntu/Mint el usuario de QEMU
# (libvirt-qemu) no puede entrar en $HOME (permisos 750) y AppArmor lo agrava.
# =============================================================================
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $EUID -ne 0 ]] || die "Ejecútalo como tu usuario normal (usa sudo internamente)"
command -v apt-get >/dev/null || die "Este script asume un host con apt (Debian/Ubuntu/Mint)"

info "1/6 Comprobando virtualización por hardware"
grep -Eq '(vmx|svm)' /proc/cpuinfo || die "La CPU no expone vmx/svm: activa VT-x/AMD-V en la BIOS/UEFI"
ok "vmx/svm presente"
if /lib64/ld-linux-x86-64.so.2 --help 2>/dev/null | grep -q 'x86-64-v3 (supported'; then
  ok "x86-64-v3 soportado (RHEL 10 podrá arrancar con --cpu host-passthrough)"
else
  warn "El host NO declara x86-64-v3: RHEL 10 no arrancará. Excluye rhel10-app01 del lab."
fi

info "2/6 Instalando paquetes (sudo)"
sudo apt-get update -qq
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst virt-manager \
  libguestfs-tools cpu-checker libosinfo-bin gettext-base openssl jq curl acl openssh-client
sudo systemctl enable --now libvirtd
ok "KVM/libvirt instalados"

info "3/6 Grupos libvirt y kvm"
sudo usermod -aG libvirt,kvm "$USER"
ok "Usuario $USER añadido (cierra sesión y vuelve a entrar para que surta efecto)"

info "4/6 Directorios y pools de libvirt"
sudo install -d -m 2775 -o "$USER" -g libvirt "$LAB_STORE" "$LAB_STORE/isos" "$LAB_STORE/images"
for p in isos images; do
  if ! sudo virsh pool-info "lab-$p" >/dev/null 2>&1; then
    sudo virsh pool-define-as "lab-$p" dir --target "$LAB_STORE/$p" >/dev/null
    info "pool lab-$p definido"
  fi
  sudo virsh pool-autostart "lab-$p" >/dev/null
  sudo virsh pool-start "lab-$p" >/dev/null 2>&1 || true
done
ok "Pools lab-isos y lab-images listos en $LAB_STORE"

info "5/6 ISOs y configuración"
OLD="$HOME/rhel-lab/isos"
if compgen -G "$OLD/*.iso" >/dev/null; then
  mv -v "$OLD"/*.iso "$LAB_STORE/isos/"
fi
if [[ -f "$LAB_CONF" ]]; then
  if grep -Eq '^[[:space:]]*ISO_DIR=' "$LAB_CONF"; then
    sed -i -E "s|^[[:space:]]*ISO_DIR=.*|ISO_DIR=\"$LAB_STORE/isos\"|" "$LAB_CONF"
  else
    printf 'ISO_DIR="%s"\n' "$LAB_STORE/isos" >> "$LAB_CONF"
  fi
  ok "ISO_DIR=$LAB_STORE/isos en $LAB_CONF"
else
  warn "No existe $LAB_CONF: copia scripts/isos.conf.example antes de descargar ISOs"
fi

info "6/6 Clave SSH del laboratorio"
mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
if [[ ! -f "$LAB_SSH_KEY" ]]; then
  echo "Se creará $LAB_SSH_KEY. Te pedirá una passphrase (recomendado; usa ssh-agent)."
  ssh-keygen -t ed25519 -f "$LAB_SSH_KEY" -C "adminlab@$LAB_DOMAIN"
fi
{
  echo "# Generado por 00-host-setup.sh a partir de scripts/hosts.conf"
  while read -r name _ ip _; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    printf 'Host %s\n  HostName %s\n  User %s\n  IdentityFile %s\n  IdentitiesOnly yes\n  UserKnownHostsFile %s\n  StrictHostKeyChecking accept-new\n\n' \
      "$name" "$ip" "$LAB_ADMIN" "$LAB_SSH_KEY" "$LAB_KNOWN_HOSTS"
  done < "$HOSTS_CONF"
} > "$HOME/.ssh/lab_config"
chmod 600 "$HOME/.ssh/lab_config"
if ! grep -qs 'Include ~/.ssh/lab_config' "$HOME/.ssh/config"; then
  { printf 'Include ~/.ssh/lab_config\n\n'; cat "$HOME/.ssh/config" 2>/dev/null || true; } > "$HOME/.ssh/config.new"
  chmod 600 "$HOME/.ssh/config.new"; mv "$HOME/.ssh/config.new" "$HOME/.ssh/config"
fi
ok "Ahora puedes hacer: ssh rhel9-app01  (cuando exista la VM)"

echo
ok "Host preparado. Siguiente: cierra sesión/entra de nuevo y ejecuta: scripts/lab.sh network"
