#!/usr/bin/env bash
# =============================================================================
# 03-graylog-inputs.sh — (siem01) Entradas de Graylog por API + prueba de extremo a extremo
#
#   1. graylog_inputs.py: crea (si faltan) y arranca Syslog TCP/UDP 5140 y GELF TCP/UDP 12201.
#   2. Comprueba que los puertos escuchan en la IP del lab (docker-proxy / DNAT).
#   3. Envía un GELF por TCP y otro por UDP con un marcador único y los busca
#      directamente en OpenSearch: si aparecen, la cadena entrada -> proceso -> índice funciona.
#
# Idempotente. Uso: lab.sh siem-inputs
# =============================================================================
set -euo pipefail
# shellcheck source=siem-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/siem-lib.sh"
require_root
require_host "$SIEM_NAME"

TOOLS="$SIEM_DIR/tools"
PWF="$SIEM_SECRETS/graylog-admin.txt"
[[ -x "$TOOLS/graylog_inputs.py" && -f "$PWF" ]] || fatal "Falta el SIEM desplegado: ejecuta antes 'lab.sh siem-stack'"
install -m 0750 "$N2_FILES"/python/*.py "$TOOLS/"     # por si las herramientas han cambiado en el repo

say "Entradas de Graylog (API REST)"
python3 "$TOOLS/graylog_inputs.py" --password-file "$PWF"

say "Puertos publicados en el host"
for p in 5140 12201; do
  if ss -ltn | grep -q "$SIEM_IP:$p "; then say "  $SIEM_IP:$p/tcp escucha"; else fatal "$SIEM_IP:$p/tcp no escucha (docker compose ps; docker port siem-graylog)"; fi
done

say "Prueba de extremo a extremo: GELF TCP y UDP -> Graylog -> OpenSearch"
marker="e2e-$(date +%s)"
python3 "$TOOLS/gelf_send.py" --host "$SIEM_IP" --proto tcp --marker "$marker" --message "prueba e2e TCP" --field via=tcp >/dev/null
python3 "$TOOLS/gelf_send.py" --host "$SIEM_IP" --proto udp --marker "$marker" --message "prueba e2e UDP" --field via=udp >/dev/null
both_indexed() { [[ "$(python3 "$TOOLS/os_search.py" count --query "lab_marker:$marker" --minutes 10 2>/dev/null)" -ge 2 ]]; }
if wait_for 60 "mensajes de prueba en OpenSearch" both_indexed; then
  python3 "$TOOLS/os_search.py" search --query "lab_marker:$marker" --minutes 10 --fields timestamp,source,via,message
  say "OK: los dos mensajes están indexados (busca en la web: lab_marker:$marker)"
else
  python3 "$TOOLS/os_search.py" search --query "lab_marker:$marker" --minutes 10 --fields timestamp,via,message || true
  fatal "No llegaron los 2 mensajes en 60 s. Mira: System > Inputs (¿RUNNING?), docker compose logs graylog, tcpdump -ni any port 12201"
fi
say "Siguiente: lab.sh siem-forward (rsyslog de las VMs) y lab.sh siem-nxlog rhel9-app01 <rpm>"
