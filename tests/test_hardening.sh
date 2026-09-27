#!/usr/bin/env bash
# Etapa 5 — Hardening general: políticas de contraseña, caducidad, sysctl y banner
# shellcheck disable=SC2034  # TEST_NAME lo usa summary() de lib.sh
TEST_NAME=test_hardening; source "$(dirname "$0")/lib.sh"; need_root

pwq_minlen_ok()  { local v; v="$(awk -F= '/^[[:space:]]*minlen/{gsub(/[[:space:]]/,"",$2); print $2}' /etc/security/pwquality.conf)"; [[ -n "$v" && "$v" -ge 12 ]]; }
login_defs_ok()  { local v; v="$(awk '$1=="PASS_MAX_DAYS"{print $2}' /etc/login.defs)"; [[ -n "$v" && "$v" -le 90 ]]; }
sysctl_ok()      { [[ "$(sysctl -n "$1" 2>/dev/null)" == "$2" ]]; }
issue_has_lab()  { grep -q "enterprise-rhel-lab" /etc/issue 2>/dev/null; }

check "pwquality: minlen >= 12" pwq_minlen_ok
check "login.defs: PASS_MAX_DAYS <= 90" login_defs_ok
check "sysctl: net.ipv4.conf.all.accept_source_route = 0" sysctl_ok net.ipv4.conf.all.accept_source_route 0
check "sysctl: net.ipv4.conf.all.accept_redirects = 0" sysctl_ok net.ipv4.conf.all.accept_redirects 0
check "sysctl: kernel.randomize_va_space = 2" sysctl_ok kernel.randomize_va_space 2
check "/etc/sysctl.d/98-lab-hardening.conf presente" test -f /etc/sysctl.d/98-lab-hardening.conf
check "/etc/issue tiene el aviso del lab" issue_has_lab
summary
