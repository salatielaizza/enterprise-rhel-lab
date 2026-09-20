#!/usr/bin/env bash
# =============================================================================
# 05-systemd-app.sh — Aplicación de prueba y unidad systemd (lab-app.service)
# La app escribe un "latido" en el journal (y en /var/log/lab-app/app.log).
# Parámetros en /opt/application/config/lab-app.env:
#   LAB_APP_INTERVAL=5        segundos entre latidos
#   LAB_APP_CRASH_AFTER=0     >0: la app falla tras N latidos (prueba de Restart=)
# Nota SELinux: /opt/application/bin/ recibe el tipo bin_t con restorecon; si el
# script se copia con 'mv' desde /tmp conserva su etiqueta y systemd no puede
# ejecutarlo (ver troubleshooting/06-selinux-denial.md).
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root
id appuser >/dev/null 2>&1 || fatal "Falta appuser (01-users-groups.sh)"
[[ -d /opt/application/bin ]] || fatal "Falta /opt/application/bin (03-permissions.sh)"

cat > /opt/application/bin/lab-app.sh <<'EOF'
#!/usr/bin/env bash
# Aplicación de prueba del laboratorio: latido periódico.
interval="${LAB_APP_INTERVAL:-5}"
crash_after="${LAB_APP_CRASH_AFTER:-0}"
logdir=/var/log/lab-app
log() { if [[ -w "$logdir" ]]; then echo "$*" | tee -a "$logdir/app.log"; else echo "$*"; fi; }
trap 'log "lab-app: SIGTERM recibido, salida limpia"; exit 0' TERM
log "lab-app iniciada (pid $$) intervalo=${interval}s crash_after=${crash_after}"
n=0
while true; do
  n=$((n + 1))
  log "heartbeat $n $(date -Is) host=$(hostname -s)"
  if [[ "$crash_after" -gt 0 && "$n" -ge "$crash_after" ]]; then
    echo "lab-app: fallo simulado tras $n latidos" >&2
    exit 3
  fi
  sleep "$interval" & wait $!
done
EOF
chown root:application /opt/application/bin/lab-app.sh
chmod 0755 /opt/application/bin/lab-app.sh
restorecon -R /opt/application/bin || true

cat > /etc/systemd/system/lab-app.service <<'EOF'
[Unit]
Description=Aplicacion de prueba del laboratorio (lab-app)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=appuser
Group=application
WorkingDirectory=/opt/application
EnvironmentFile=-/opt/application/config/lab-app.env
ExecStart=/opt/application/bin/lab-app.sh
Restart=on-failure
RestartSec=5
SyslogIdentifier=lab-app
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 /etc/systemd/system/lab-app.service
restorecon /etc/systemd/system/lab-app.service || true

systemctl daemon-reload
systemctl enable lab-app >/dev/null 2>&1
systemctl restart lab-app
sleep 2
systemctl --no-pager --lines=5 status lab-app || true
systemctl is-active --quiet lab-app || fatal "lab-app no arrancó: revisa 'journalctl -u lab-app' y 'ausearch -m avc -ts recent'"
set_stage 2
