#!/usr/bin/env bash
# =============================================================================
# 03-ssh-hardening.sh — Endurecimiento de sshd + SFTP enjaulado de demostración
#
# Procedimiento SEGURO (así se hace también a mano):
#   1. Mantener una sesión abierta. 2. Copia de seguridad de sshd_config.
#   3. Cambiar + validar con 'sshd -t' (si falla, se restaura y se aborta).
#   4. 'systemctl reload sshd' (las sesiones abiertas sobreviven).
#   5. Probar UNA SESIÓN NUEVA antes de cerrar la primera (lo hace lab.sh).
#
#  - RHEL 9/10 (sshd_config con 'Include'): ajustes globales en un drop-in
#    00-lab-hardening.conf (gana al 50-redhat.conf y a 01-permitrootlogin.conf,
#    porque sshd usa el PRIMER valor que encuentra).
#  - RHEL 7/8 (sin Include): se comentan las directivas activas y se añade un
#    bloque marcado '# BEGIN/END lab-ssh' al final.
#  - El bloque 'Match Group sftponly' va SIEMPRE al final de sshd_config.
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root
CONF=/etc/ssh/sshd_config
DROPIN=/etc/ssh/sshd_config.d/00-lab-hardening.conf
STAMP="$(date +%Y%m%d%H%M%S)"

id -nG adminlab | grep -qw sysadmins || fatal "adminlab no está en sysadmins (Etapa 2): abortando para no bloquear el acceso"
[[ -s /home/adminlab/.ssh/authorized_keys ]] || fatal "adminlab no tiene authorized_keys: abortando (PasswordAuthentication se desactivará)"

cp -a "$CONF" "$CONF.lab-bak.$STAMP"
say "Copia de seguridad: $CONF.lab-bak.$STAMP"

# --- Usuario SFTP de demostración (chroot) ---------------------------------------
getent group sftponly >/dev/null || groupadd -g 2005 sftponly
id sftpdemo >/dev/null 2>&1 || useradd -M -u 1005 -g sftponly -d /upload -s /sbin/nologin -c "Lab SFTP demo" sftpdemo
install -d -m 0755 -o root -g root /srv/sftp /srv/sftp/sftpdemo      # la jaula debe ser de root y no escribible
install -d -m 0770 -o sftpdemo -g sftponly /srv/sftp/sftpdemo/upload
install -d -m 0755 -o root -g root /etc/ssh/lab-keys
install -m 0644 -o root -g root /home/adminlab/.ssh/authorized_keys /etc/ssh/lab-keys/sftpdemo
if command -v semanage >/dev/null; then
  semanage fcontext -a -t user_home_t '/srv/sftp/[^/]+/upload(/.*)?' 2>/dev/null \
    || semanage fcontext -m -t user_home_t '/srv/sftp/[^/]+/upload(/.*)?' || true
  restorecon -R /srv/sftp || true
  setsebool -P ssh_chroot_rw_homedirs on 2>/dev/null || true
fi

GLOBAL='PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
AllowGroups sysadmins developers application backup sftponly'

MATCH='Match Group sftponly
    ChrootDirectory /srv/sftp/%u
    ForceCommand internal-sftp
    AuthorizedKeysFile /etc/ssh/lab-keys/%u
    PasswordAuthentication no
    AllowTcpForwarding no
    X11Forwarding no'

sed -i '/^# BEGIN lab-ssh/,/^# END lab-ssh/d' "$CONF"
rm -f "$DROPIN"
if grep -Eq '^[[:space:]]*Include[[:space:]]' "$CONF"; then
  install -d -m 0755 /etc/ssh/sshd_config.d
  printf '# Gestionado por enterprise-rhel-lab (stage4/03-ssh-hardening.sh)\n%s\n' "$GLOBAL" > "$DROPIN"
  chmod 0600 "$DROPIN"
  printf '# BEGIN lab-ssh\n%s\n# END lab-ssh\n' "$MATCH" >> "$CONF"
  say "Modo drop-in (Include soportado): $DROPIN"
else
  sed -i -E 's/^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|PermitEmptyPasswords|MaxAuthTries|LoginGraceTime|X11Forwarding|ClientAliveInterval|ClientAliveCountMax|AllowGroups)[[:space:]]+/#lab-disabled# \1 /' "$CONF"
  printf '# BEGIN lab-ssh\n%s\n\n%s\n# END lab-ssh\n' "$GLOBAL" "$MATCH" >> "$CONF"
  say "Modo bloque en $CONF (sin Include)"
fi

if ! sshd -t; then
  say "sshd -t FALLÓ: restaurando configuración anterior"
  cp -a "$CONF.lab-bak.$STAMP" "$CONF"; rm -f "$DROPIN"
  fatal "Configuración inválida; no se ha recargado sshd"
fi
systemctl reload sshd
say "sshd recargado. Ajustes efectivos:"
sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication|pubkeyauthentication|maxauthtries|x11forwarding|allowgroups) '
set_stage 4
