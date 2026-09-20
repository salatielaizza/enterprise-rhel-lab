#!/usr/bin/env bash
# =============================================================================
# 01-users-groups.sh — Grupos y usuarios del laboratorio (idempotente)
# UID/GID FIJOS y iguales en todos los hosts: imprescindible más adelante para
# NFS (Etapa 12), LDAP (13) y Ansible. adminlab (UID 1001) lo crea el kickstart.
# Las cuentas nuevas quedan BLOQUEADAS: define su contraseña con 'passwd <usuario>'.
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root

declare -A GROUP_IDS=( [sysadmins]=2001 [developers]=2002 [application]=2003 [backup]=2004 )
for g in sysadmins developers application backup; do
  if getent group "$g" >/dev/null; then say "[=] grupo $g ya existe"
  else groupadd -g "${GROUP_IDS[$g]}" "$g"; say "[+] grupo $g (GID ${GROUP_IDS[$g]})"; fi
done

ensure_user() {  # ensure_user NOMBRE UID GRUPO_PRIMARIO
  local u="$1" uid="$2" pg="$3"
  if id "$u" >/dev/null 2>&1; then
    say "[=] usuario $u ya existe"
  else
    useradd -m -u "$uid" -g "$pg" -s /bin/bash -c "Lab $u" "$u"
    usermod -L "$u"
    say "[+] usuario $u (UID $uid, grupo primario $pg, cuenta bloqueada)"
  fi
}

id adminlab >/dev/null 2>&1 || fatal "adminlab no existe (lo crea el kickstart)"
usermod -aG sysadmins adminlab        # -a IMPRESCINDIBLE: sin -a se sustituyen los grupos
ensure_user devuser    1002 developers
ensure_user appuser    1003 application
ensure_user backupuser 1004 backup

# Política de contraseñas de ejemplo para devuser (ejercicio con chage)
chage -M 90 -m 1 -W 7 devuser

say "Resumen:"
for u in adminlab devuser appuser backupuser; do id "$u"; done
set_stage 2
