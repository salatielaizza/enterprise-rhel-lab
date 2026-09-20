#!/usr/bin/env bash
# =============================================================================
# 04-sudo.sh — Perfiles sudo (sysadmins / developers / backup) en /etc/sudoers.d/
#
# Regla de oro: NUNCA se instala un fichero de sudoers sin validarlo antes con
# 'visudo -cf'. Un sudoers roto = perder sudo (y en esta VM, el acceso admin).
#   sysadmins  -> administración completa (sin contraseña SOLO por ser laboratorio)
#   developers -> solo gestionar/consultar el servicio lab-app
#   backup     -> solo ejecutar el script fijo /usr/local/sbin/lab-backup.sh
# Al final elimina el sudo de arranque del kickstart (90-adminlab-bootstrap).
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root
command -v visudo >/dev/null || fatal "visudo no está instalado"
id -nG adminlab | grep -qw sysadmins || fatal "adminlab no está en sysadmins (ejecuta 01-users-groups.sh): abortando para no quedarte sin sudo"

install_sudoers() {  # install_sudoers NOMBRE  (contenido por stdin)
  local name="$1" tmp; tmp="$(mktemp)"
  cat > "$tmp"
  if visudo -cf "$tmp" >/dev/null; then
    install -m 0440 -o root -g root "$tmp" "/etc/sudoers.d/$name"
    say "[+] /etc/sudoers.d/$name validado e instalado"
  else
    rm -f "$tmp"; fatal "sudoers inválido para $name: NO instalado"
  fi
  rm -f "$tmp"
}

install_sudoers 10-sysadmins <<'EOF'
# Administración completa. En producción: exigir contraseña/MFA y registrar sesiones.
%sysadmins ALL=(ALL) NOPASSWD: ALL
EOF

install_sudoers 20-developers <<'EOF'
# Los desarrolladores gestionan SOLO el servicio de la aplicación (comandos exactos, sin comodines).
Cmnd_Alias DEV_SERVICE = /usr/bin/systemctl status lab-app, \
                         /usr/bin/systemctl start lab-app, \
                         /usr/bin/systemctl stop lab-app, \
                         /usr/bin/systemctl restart lab-app
Cmnd_Alias DEV_LOGS = /usr/bin/journalctl -u lab-app, /usr/bin/journalctl -u lab-app -n 50
%developers ALL=(root) NOPASSWD: DEV_SERVICE, DEV_LOGS
EOF

# Script de backup fijo: sudo NO da rsync/tar libres (serían equivalentes a root).
cat > /usr/local/sbin/lab-backup.sh <<'EOF'
#!/usr/bin/env bash
# Copia de seguridad de /opt/application hacia /backup (solo operación permitida al grupo backup)
set -euo pipefail
dest="/backup/app-$(date +%F-%H%M%S).tar.gz"
tar -czf "$dest" -C /opt application
chown root:backup "$dest"; chmod 0640 "$dest"
echo "backup creado: $dest"
EOF
chown root:root /usr/local/sbin/lab-backup.sh; chmod 0750 /usr/local/sbin/lab-backup.sh
restorecon /usr/local/sbin/lab-backup.sh || true

install_sudoers 30-backup <<'EOF'
%backup ALL=(root) NOPASSWD: /usr/local/sbin/lab-backup.sh
EOF

visudo -c >/dev/null || fatal "La configuración global de sudoers es inválida"
if [[ -f /etc/sudoers.d/90-adminlab-bootstrap ]]; then
  rm -f /etc/sudoers.d/90-adminlab-bootstrap
  say "[-] sudo de arranque eliminado (adminlab sigue con sudo vía grupo sysadmins)"
fi
visudo -c
sudo -l -U adminlab | tail -n 3
set_stage 2
