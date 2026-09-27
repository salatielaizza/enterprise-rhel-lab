#!/usr/bin/env bash
# =============================================================================
# 01-selinux-hardening.sh — SELinux en modo enforcing + saneamiento de contextos
#
# No crea módulos SELinux a medida (eso es un ejercicio manual, ver
# security/selinux.md): este script solo deja el sistema en un estado base
# seguro y repetible:
#   1. Enforcing en caliente (setenforce) y persistente (/etc/selinux/config).
#   2. Booleans documentados EXPLÍCITAMENTE (nunca "a ciegas").
#   3. Contextos de ficheros/directorios propios del lab re-aplicados
#      (defensivo: por si alguna operación manual los rompió).
#   4. Una foto de las denegaciones AVC recientes, para comparar en el
#      ejercicio de troubleshooting (no es un fallo si no hay ninguna).
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root

command -v getenforce >/dev/null || fatal "SELinux no está instalado en este host; abortando"

CONF=/etc/selinux/config
STAMP="$(date +%Y%m%d%H%M%S)"

case "$(getenforce)" in
  Disabled)
    fatal "SELinux está Disabled a nivel de kernel: no se puede activar en caliente. Cambia SELINUX=enforcing en $CONF y REINICIA la VM antes de repetir esta etapa." ;;
  Permissive)
    say "SELinux está en Permissive: pasando a Enforcing en caliente"
    setenforce 1 ;;
  Enforcing)
    say "SELinux ya está Enforcing" ;;
esac

cp -a "$CONF" "$CONF.lab-bak.$STAMP"
if grep -Eq '^SELINUX=enforcing' "$CONF"; then
  say "$CONF ya tiene SELINUX=enforcing"
else
  sed -i -E 's/^SELINUX=.*/SELINUX=enforcing/' "$CONF"
  say "$CONF actualizado a SELINUX=enforcing (persistente tras reiniciar)"
fi

# --- Booleans documentados explícitamente (añade aquí solo los que uses de verdad) ---
declare -A LAB_BOOLEANS=(
  [ssh_chroot_rw_homedirs]=on   # Etapa 4: sftpdemo necesita escribir dentro de su jaula
)
for b in "${!LAB_BOOLEANS[@]}"; do
  want="${LAB_BOOLEANS[$b]}"
  cur="$(getsebool "$b" 2>/dev/null | awk '{print $3}')"
  if [[ "$cur" == "$want" ]]; then
    say "boolean $b ya está $want"
  else
    setsebool -P "$b" "$want"
    say "boolean $b -> $want (persistente)"
  fi
done

# --- Contextos propios del lab (defensivo/idempotente) --------------------------
if command -v semanage >/dev/null; then
  semanage fcontext -a -t user_home_t '/srv/sftp/[^/]+/upload(/.*)?' 2>/dev/null \
    || semanage fcontext -m -t user_home_t '/srv/sftp/[^/]+/upload(/.*)?' || true
  restorecon -R /srv/sftp 2>/dev/null || true
fi
[[ -d /opt/application ]] && restorecon -R /opt/application 2>/dev/null || true
[[ -d /var/log/lab-app ]] && restorecon -R /var/log/lab-app 2>/dev/null || true

# --- Foto de denegaciones AVC recientes (solo informativo, nunca falla) ---------
# 'ausearch' puede colgarse sin responder (ver troubleshooting/20-ausearch-colgado-timeout.md):
# SIEMPRE con 'timeout', nunca a pelo.
BASELINE=/var/log/lab-selinux-baseline.log
if command -v ausearch >/dev/null; then
  timeout 15 ausearch -m avc,user_avc -ts today > "$BASELINE" 2>/dev/null || : > "$BASELINE"
  say "Denegaciones AVC de hoy volcadas en $BASELINE ($(wc -l < "$BASELINE") líneas)"
else
  : > "$BASELINE"
  say "ausearch no disponible; $BASELINE queda vacío"
fi
