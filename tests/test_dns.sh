#!/usr/bin/env bash
# Etapa 4 — DNS: registros A/PTR contra dns01 y, en dns01, estado de BIND
# shellcheck disable=SC2034  # TEST_NAME lo usa summary() de lib.sh
TEST_NAME=test_dns; source "$(dirname "$0")/lib.sh"; need_root
SERVER=10.10.10.20
if [[ "$(hostname -s)" == dns01 ]]; then
  check "named activo y habilitado" bash -c 'systemctl is-active --quiet named && systemctl is-enabled --quiet named'
  check "named-checkconf -z sin errores" named-checkconf -z /etc/named.conf
  check "escucha en 53/udp y 53/tcp" bash -c "ss -lun | grep -q ':53 ' && ss -ltn | grep -q ':53 '"
  check "firewalld permite dns" bash -c 'firewall-cmd --list-services | grep -qw dns'
fi
while read -r n ip; do
  check "A   $n.lab.local -> $ip" bash -c "[[ \"\$(dig +short +time=2 +tries=1 @$SERVER $n.lab.local | head -n1)\" == $ip ]]"
  rev="$(dig +short +time=2 +tries=1 @$SERVER -x "$ip" | head -n1)"
  check "PTR $ip -> $n.lab.local." bash -c "[[ \"$rev\" == $n.lab.local. ]]"
done < <(all_hosts)
check "kvm-host.lab.local -> 10.10.10.1" bash -c "[[ \"\$(dig +short @$SERVER kvm-host.lab.local)\" == 10.10.10.1 ]]"
check "resolución externa mediante el forwarder (redhat.com)" bash -c "[[ -n \"\$(dig +short +time=3 +tries=1 @$SERVER redhat.com | head -n1)\" ]]"
check "el resolvedor del sistema usa dns01 (getent hosts dns01)" bash -c 'getent hosts dns01 | grep -q 10.10.10.20'
summary
