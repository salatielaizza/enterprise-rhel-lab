#!/usr/bin/env bash
# Etapa 6 — Bash avanzado: herramientas propias instaladas, válidas y programadas
# shellcheck disable=SC2034  # TEST_NAME lo usa summary() de lib.sh
TEST_NAME=test_bash_tools; source "$(dirname "$0")/lib.sh"; need_root

check "lab-healthcheck.sh instalado y ejecutable" test -x /usr/local/sbin/lab-healthcheck.sh
check "lab-logscan.sh instalado y ejecutable" test -x /usr/local/sbin/lab-logscan.sh
check "lab-healthcheck.sh sin errores de sintaxis" bash -n /usr/local/sbin/lab-healthcheck.sh
check "lab-logscan.sh sin errores de sintaxis" bash -n /usr/local/sbin/lab-logscan.sh
check "lab-healthcheck.sh se ejecuta y devuelve 0 (sistema sano)" /usr/local/sbin/lab-healthcheck.sh
check "temporizador lab-healthcheck.timer activo" systemctl is-active --quiet lab-healthcheck.timer
check "temporizador lab-healthcheck.timer habilitado" systemctl is-enabled --quiet lab-healthcheck.timer
check "log de healthcheck se ha escrito al menos una vez" test -s /var/log/lab-healthcheck.log
summary
