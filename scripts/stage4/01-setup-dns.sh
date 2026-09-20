#!/usr/bin/env bash
# =============================================================================
# 01-setup-dns.sh — BIND en dns01: zonas lab.local + 10.10.10.in-addr.arpa
# Requiere que dns01 tenga repositorios (registro Red Hat o repo local desde la
# ISO: ver administration/packages.md). Solo se ejecuta en dns01.
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root
[[ "$(hostname -s)" == dns01 ]] || fatal "Este script es solo para dns01"
DIR="$(dirname "${BASH_SOURCE[0]}")/dns"

if ! rpm -q bind >/dev/null 2>&1; then
  say "Instalando bind y bind-utils"
  { command -v dnf >/dev/null && dnf -y install bind bind-utils; } \
    || fatal "No se pudo instalar bind. ¿Registraste dns01 (lab.sh register dns01 <usuario>) o montaste la ISO como repo?"
fi

[[ -f /etc/named.conf.lab-orig ]] || cp -a /etc/named.conf /etc/named.conf.lab-orig
SERIAL="$(date +%y%m%d%H%M)"
install -m 0640 -o root -g named "$DIR/named.conf" /etc/named.conf
sed "s/@@SERIAL@@/$SERIAL/" "$DIR/lab.local.zone.tpl" > /var/named/lab.local.zone
sed "s/@@SERIAL@@/$SERIAL/" "$DIR/10.10.10.rev.tpl"   > /var/named/10.10.10.rev
chown root:named /var/named/lab.local.zone /var/named/10.10.10.rev
chmod 0640 /var/named/lab.local.zone /var/named/10.10.10.rev
restorecon -R /etc/named.conf /var/named || true

say "Validando configuración y zonas (si falla, NO se arranca)"
named-checkconf -z /etc/named.conf
named-checkzone lab.local /var/named/lab.local.zone
named-checkzone 10.10.10.in-addr.arpa /var/named/10.10.10.rev

if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-service=dns >/dev/null
  firewall-cmd --reload >/dev/null
  say "[+] firewalld: servicio dns (53/tcp,udp) permitido"
fi
systemctl enable named >/dev/null 2>&1
systemctl restart named
sleep 1
systemctl is-active --quiet named || fatal "named no arrancó: journalctl -u named -n 50"

say "Comprobación local:"
dig +short @127.0.0.1 dns01.lab.local
dig +short @127.0.0.1 -x 10.10.10.13
set_stage 4
