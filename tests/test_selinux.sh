#!/usr/bin/env bash
# Etapa 5 — SELinux: enforcing, booleans documentados y contextos propios del lab
# shellcheck disable=SC2034  # TEST_NAME lo usa summary() de lib.sh
TEST_NAME=test_selinux; source "$(dirname "$0")/lib.sh"; need_root

enforcing()        { [[ "$(getenforce)" == Enforcing ]]; }
config_enforcing() { grep -Eq '^SELINUX=enforcing' /etc/selinux/config; }
sebool_is()        { [[ "$(getsebool "$1" 2>/dev/null | awk '{print $3}')" == "$2" ]]; }
sftp_context_ok()  { ls -Zd /srv/sftp/*/upload 2>/dev/null | grep -q user_home_t; }

check "SELinux está instalado (getenforce disponible)" command -v getenforce
check "SELinux en modo Enforcing" enforcing
check "/etc/selinux/config tiene SELINUX=enforcing" config_enforcing
check "boolean ssh_chroot_rw_homedirs=on" sebool_is ssh_chroot_rw_homedirs on
check "contexto de /srv/sftp/*/upload es user_home_t" sftp_context_ok
check "existe la foto de denegaciones AVC (/var/log/lab-selinux-baseline.log)" test -f /var/log/lab-selinux-baseline.log
summary
