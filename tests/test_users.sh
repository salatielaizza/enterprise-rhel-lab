#!/usr/bin/env bash
# Etapa 2 — Usuarios, grupos (UID/GID fijos), política de contraseñas y sudo
# shellcheck disable=SC2034  # TEST_NAME lo usa summary() de lib.sh
TEST_NAME=test_users; source "$(dirname "$0")/lib.sh"; need_root

for spec in sysadmins:2001 developers:2002 application:2003 backup:2004; do
  g="${spec%%:*}"; gid="${spec##*:}"
  check "grupo $g con GID $gid" bash -c "[[ \"\$(getent group $g | cut -d: -f3)\" == $gid ]]"
done
for spec in adminlab:1001 devuser:1002 appuser:1003 backupuser:1004; do
  u="${spec%%:*}"; uid="${spec##*:}"
  check "usuario $u con UID $uid" bash -c "[[ \"\$(id -u $u)\" == $uid ]]"
done
check "adminlab pertenece a sysadmins Y a wheel" bash -c 'id -nG adminlab | tr " " "\n" | grep -qx sysadmins && id -nG adminlab | tr " " "\n" | grep -qx wheel'
check "devuser: grupo primario developers" bash -c '[[ "$(id -gn devuser)" == developers ]]'
check "appuser: grupo primario application" bash -c '[[ "$(id -gn appuser)" == application ]]'
check "backupuser: grupo primario backup" bash -c '[[ "$(id -gn backupuser)" == backup ]]'
check "devuser: caducidad de contraseña 90 días (chage)" bash -c "chage -l devuser | grep -Eq 'Maximum number of days between password change[[:space:]]*: 90'"
check "/etc/shadow sin permisos para otros (modo 000 o 0640 root:root/shadow)" bash -c '[[ "$(stat -c %a /etc/shadow)" =~ ^(0|640|600)$ ]]'
check "pwck sin errores en /etc/passwd y /etc/shadow" bash -c 'pwck -r >/dev/null'
check "grpck sin errores" bash -c 'grpck -r >/dev/null'

check "sudoers global válido (visudo -c)" visudo -c
check "existe /etc/sudoers.d/10-sysadmins" test -f /etc/sudoers.d/10-sysadmins
check "existe /etc/sudoers.d/20-developers" test -f /etc/sudoers.d/20-developers
check "existe /etc/sudoers.d/30-backup" test -f /etc/sudoers.d/30-backup
check "sudo de arranque (90-adminlab-bootstrap) eliminado" bash -c '[[ ! -e /etc/sudoers.d/90-adminlab-bootstrap ]]'
check "adminlab puede ejecutar cualquier comando con sudo" bash -c 'sudo -l -U adminlab | grep -q "(ALL) NOPASSWD: ALL"'
check "developers: solo systemctl/journalctl de lab-app" bash -c 'sudo -l -U devuser | grep -q "systemctl restart lab-app" && ! sudo -l -U devuser | grep -q "NOPASSWD: ALL"'
check "backup: solo lab-backup.sh" bash -c 'sudo -l -U backupuser | grep -q "/usr/local/sbin/lab-backup.sh" && ! sudo -l -U backupuser | grep -q "NOPASSWD: ALL"'
check "lab-backup.sh es de root y no escribible por otros" bash -c '[[ "$(stat -c %U:%a /usr/local/sbin/lab-backup.sh)" == root:750 ]]'
summary
