#!/usr/bin/env bash
# Etapa 4 — Hora: chronyd sincronizado con dns01 (o con el pool en dns01)
# shellcheck disable=SC2034  # TEST_NAME lo usa summary() de lib.sh
TEST_NAME=test_time; source "$(dirname "$0")/lib.sh"; need_root
check "chronyd activo y habilitado" bash -c 'systemctl is-active --quiet chronyd && systemctl is-enabled --quiet chronyd'
check "chronyc tracking: Leap status Normal" bash -c "chronyc tracking | grep -Eq 'Leap status[[:space:]]*: Normal'"
check "reloj sincronizado según timedatectl" bash -c "timedatectl | grep -Eiq '(NTP synchronized|System clock synchronized): yes'"
check "desfase del sistema < 1 s" bash -c "chronyc tracking | awk '/System time/{exit !(\$4 < 1.0)}'"
check "zona horaria configurada (timedatectl)" bash -c "timedatectl | grep -Eq 'Time zone: [A-Za-z]+/'"
if [[ "$(hostname -s)" == dns01 ]]; then
  check "servidor: allow 10.10.10.0/24 en chrony.conf" grep -q '^allow 10.10.10.0/24' /etc/chrony.conf
  check "servidor: firewalld permite ntp" bash -c 'firewall-cmd --list-services | grep -qw ntp'
else
  check "cliente: única fuente configurada = 10.10.10.20" bash -c "grep -Eq '^server 10.10.10.20( |\$)' /etc/chrony.conf && [[ \$(grep -Ec '^(pool|server)[[:space:]]' /etc/chrony.conf) -eq 1 ]]"
  check "cliente: fuente 10.10.10.20 seleccionada (^*)" bash -c "chronyc -n sources | grep -Eq '^\^\* +10.10.10.20'"
fi
summary
