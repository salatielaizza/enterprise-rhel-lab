#!/usr/bin/env bash
# =============================================================================
# 01-bash-tools.sh — Instala las herramientas de ejemplo de la Etapa 6
# (lab-healthcheck.sh, lab-logscan.sh) y un temporizador systemd que ejecuta
# el healthcheck cada 5 minutos. El objetivo no es el resultado (dos scripts
# pequeños), sino practicar patrones de bash "de producción": set -euo pipefail,
# trap, getopts, arrays, y una unidad systemd .service+.timer en vez de cron.
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root

SRC="$(dirname "${BASH_SOURCE[0]}")/files"
install -d -m 0755 /usr/local/sbin
install -m 0750 -o root -g root "$SRC/lab-healthcheck.sh" /usr/local/sbin/lab-healthcheck.sh
install -m 0750 -o root -g root "$SRC/lab-logscan.sh"     /usr/local/sbin/lab-logscan.sh
bash -n /usr/local/sbin/lab-healthcheck.sh
bash -n /usr/local/sbin/lab-logscan.sh
say "Herramientas instaladas en /usr/local/sbin/"

touch /var/log/lab-healthcheck.log
chmod 0644 /var/log/lab-healthcheck.log

cat > /etc/systemd/system/lab-healthcheck.service <<'EOF'
[Unit]
Description=Lab healthcheck (Etapa 6 - bash avanzado)

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/lab-healthcheck.sh
EOF

cat > /etc/systemd/system/lab-healthcheck.timer <<'EOF'
[Unit]
Description=Ejecuta lab-healthcheck.sh cada 5 minutos

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Unit=lab-healthcheck.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now lab-healthcheck.timer
say "lab-healthcheck.timer habilitado y arrancado (cada 5 min)"

# Primera ejecución inmediata, para no depender de esperar 5 min al testear
systemctl start lab-healthcheck.service || true

set_stage 6
