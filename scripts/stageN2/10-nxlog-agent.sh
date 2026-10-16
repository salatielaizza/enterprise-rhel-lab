#!/usr/bin/env bash
# =============================================================================
# 10-nxlog-agent.sh — Agente NXLog Community Edition: auditd -> Graylog (GELF TCP 12201)
#
# Corre en la VM agente (por defecto rhel9-app01; vale cualquier RHEL 8/9 del lab).
#   1. Instala el RPM de NXLog CE que se le pasa (descargado de nxlog.co/downloads;
#      lab.sh siem-nxlog lo copia a la VM). Las dependencias salen de los repos de RHEL.
#   2. Da al usuario 'nxlog' acceso de LECTURA al log de auditd sin hacerlo root:
#      auditd.conf 'log_group = nxlog' (auditd crea sus ficheros 0640 con ese grupo) y
#      /var/log/audit 0750 root:nxlog. Copia de seguridad de auditd.conf.
#   3. Genera la configuración desde files/nxlog/nxlog.conf.tpl, la VALIDA con 'nxlog -v'
#      antes de activarla (si falla, restaura la anterior) y arranca el servicio.
#   4. Prueba: 'auditctl -m' escribe un evento con un marcador en audit.log.
#
# Uso: lab.sh siem-nxlog <host> <ruta-al-rpm>     (en la VM: 10-nxlog-agent.sh <rpm>)
# =============================================================================
set -euo pipefail
# shellcheck source=siem-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/siem-lib.sh"
require_root

RPM="${1:-}"
[[ "$(hostname -s)" != "$SIEM_NAME" ]] || fatal "El agente va en las VMs que ENVÍAN logs, no en $SIEM_NAME"

# --- 1) Paquete -------------------------------------------------------------------------------
if ! rpm -q nxlog-ce >/dev/null 2>&1; then
  [[ -n "$RPM" && -f "$RPM" ]] || fatal "Uso: 10-nxlog-agent.sh <nxlog-ce-*.rpm> (no existe: '${RPM:-<vacío>}')"
  case "$RPM" in *rhel"$(rpm -E %rhel)"*) ;; *) warnmsg "el RPM no parece de RHEL $(rpm -E %rhel): $(basename "$RPM")" ;; esac
  say "Instalando $(basename "$RPM") (dnf resuelve las dependencias)"
  if ! dnf install -y "$(realpath "$RPM")"; then
    fatal "dnf no pudo instalar NXLog. Si falta una dependencia (p. ej. libdbi), habilita CodeReady Builder:
  subscription-manager repos --enable codeready-builder-for-rhel-$(rpm -E %rhel)-x86_64-rpms
y repite. Anota el caso en troubleshooting/etapaN2/."
  fi
fi
id nxlog >/dev/null 2>&1 || fatal "El paquete no ha creado el usuario 'nxlog'"
NX_BIN="$(command -v nxlog || echo /usr/bin/nxlog)"
CONF=/etc/nxlog.conf
if [[ -f /etc/nxlog/nxlog.conf && ! -f /etc/nxlog.conf ]]; then CONF=/etc/nxlog/nxlog.conf; fi   # según la versión del RPM
install -d -m 0750 -o nxlog -g nxlog /var/log/nxlog

# --- 2) Acceso de lectura al log de auditd ----------------------------------------------------
AUDITD_CONF=/etc/audit/auditd.conf
if ! grep -Eq '^[[:space:]]*log_group[[:space:]]*=[[:space:]]*nxlog[[:space:]]*$' "$AUDITD_CONF"; then
  backup "$AUDITD_CONF"
  if grep -Eq '^[[:space:]]*log_group[[:space:]]*=' "$AUDITD_CONF"; then
    sed -i -E 's/^[[:space:]]*log_group[[:space:]]*=.*/log_group = nxlog/' "$AUDITD_CONF"
  else
    echo "log_group = nxlog" >> "$AUDITD_CONF"
  fi
  chgrp nxlog /var/log/audit && chmod 0750 /var/log/audit
  # auditd no se reinicia con systemctl (RefuseManualStop=yes): se usa 'service', como indica Red Hat
  service auditd restart >/dev/null
  say "auditd: log_group = nxlog (audit.log legible por el agente, sin darle root)"
fi
runuser -u nxlog -- test -r /var/log/audit/audit.log || fatal "nxlog sigue sin poder leer /var/log/audit/audit.log (ls -l /var/log/audit)"

# --- 3) Configuración, validada antes de activarla --------------------------------------------
NEW="$(mktemp)"; trap 'rm -f "$NEW"' EXIT
sed "s/@SIEM_IP@/$SIEM_IP/g" "$N2_FILES/nxlog/nxlog.conf.tpl" > "$NEW"
if ! cmp -s "$NEW" "$CONF"; then
  backup "$CONF"
  install -m 0640 -o root -g nxlog "$NEW" "$CONF"
  if ! "$NX_BIN" -v -c "$CONF"; then
    if [[ -f "$CONF.lab-bak.$STAMP" ]]; then cp -a "$CONF.lab-bak.$STAMP" "$CONF"; fi
    fatal "La configuración nueva no valida (nxlog -v): restaurada la anterior"
  fi
  say "Configuración validada e instalada en $CONF"
fi
systemctl enable nxlog >/dev/null 2>&1
systemctl restart nxlog
sleep 3
systemctl is-active --quiet nxlog || fatal "nxlog no arranca: journalctl -u nxlog -n 30; tail /var/log/nxlog/nxlog.log"
if grep -q ERROR /var/log/nxlog/nxlog.log 2>/dev/null; then
  warnmsg "hay errores en /var/log/nxlog/nxlog.log:"; grep ERROR /var/log/nxlog/nxlog.log | tail -n 3 >&2
fi

# --- 4) Evento de prueba ------------------------------------------------------------------------
marker="nxlog-$(hostname -s)-$(date +%s)"
auditctl -m "siem-test $marker"
if timeout 3 bash -c "</dev/tcp/$SIEM_IP/12201" 2>/dev/null; then
  say "Conexión con $SIEM_IP:12201/tcp OK. Busca en Graylog: \"$marker\"  (o en siem01: os_search.py search --query '\"$marker\"')"
else
  warnmsg "$SIEM_IP:12201/tcp no responde: el agente reintentará solo cuando vuelva (¿siem01 apagada?)"
fi
