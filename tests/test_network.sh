#!/usr/bin/env bash
# Etapa 3 — Red: IP, gateway, DNS, hostname, conectividad y exposición de puertos
# shellcheck disable=SC2034  # TEST_NAME lo usa summary() de lib.sh
TEST_NAME=test_network; source "$(dirname "$0")/lib.sh"; need_root
H="$(hostname -s)"; IP="$(my_field 3)"; STAGE="$(lab_stage)"
[[ -n "$IP" ]] || { echo "Host $H no está en hosts.conf"; exit 2; }
EXPECT_DNS=10.10.10.1; [[ $STAGE -ge 4 ]] && EXPECT_DNS=10.10.10.20

check "IP $IP/24 configurada" bash -c "ip -4 -o addr show | grep -q 'inet $IP/24'"
check "ruta por defecto vía 10.10.10.1" bash -c "ip route show default | grep -q 'via 10.10.10.1'"
check "conexión NetworkManager 'lab0' activa" bash -c "nmcli -t -f NAME connection show --active | grep -qx lab0"
check "primer nameserver = $EXPECT_DNS (etapa $STAGE)" bash -c "[[ \"\$(awk '/^nameserver/{print \$2; exit}' /etc/resolv.conf)\" == $EXPECT_DNS ]]"
check "search domain lab.local en resolv.conf" bash -c "grep -Eq '^search.*lab.local' /etc/resolv.conf"
check "hostname FQDN = $H.lab.local" bash -c "[[ \"\$(hostnamectl --static)\" == $H.lab.local ]]"
check "ping al gateway 10.10.10.1" ping -c1 -W2 10.10.10.1
check "salida a Internet por IP (1.1.1.1)" ping -c1 -W3 1.1.1.1
check "resolución de nombres externos (redhat.com)" getent hosts redhat.com
check "sshd escucha en 22/tcp" bash -c "ss -ltn | grep -q ':22 '"
check "IPv6 global no configurada (ipv6.method ignore)" bash -c "! ip -6 addr show scope global | grep -q inet6"
if [[ $STAGE -ge 4 ]]; then check "ping a dns01 (10.10.10.20)" ping -c1 -W2 10.10.10.20; fi
if [[ "${TEST_PEERS:-}" == all ]]; then
  while read -r n p; do [[ "$p" == "$IP" ]] || check "ping a $n ($p)" ping -c1 -W2 "$p"; done < <(all_hosts)
fi
summary
