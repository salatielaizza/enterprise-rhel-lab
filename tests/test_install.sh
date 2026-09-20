#!/usr/bin/env bash
# Etapa 1 — Instalación base (kickstart): versión, discos, SELinux, firewall, SSH
# shellcheck disable=SC2034  # TEST_NAME lo usa summary() de lib.sh
TEST_NAME=test_install; source "$(dirname "$0")/lib.sh"; need_root
H="$(hostname -s)"; VER="$(my_field 2)"

check "hostname estático = $H.lab.local" bash -c "[[ \"\$(hostnamectl --static)\" == \"$H.lab.local\" ]]"
check "versión mayor del SO = RHEL $VER" bash -c ". /etc/os-release; [[ \${VERSION_ID%%.*} == $VER ]]"
check "SELinux en modo Enforcing" bash -c '[[ "$(getenforce)" == Enforcing ]]'
check "firewalld activo" systemctl is-active --quiet firewalld
check "firewalld permite ssh" bash -c 'firewall-cmd --list-services | grep -qw ssh'
check "sshd activo y habilitado" bash -c 'systemctl is-active --quiet sshd && systemctl is-enabled --quiet sshd'
check "chronyd activo" systemctl is-active --quiet chronyd
check "qemu-guest-agent activo" systemctl is-active --quiet qemu-guest-agent
check "LVM del sistema: vg_system con lv_root, lv_swap y lv_var" bash -c 'for l in lv_root lv_swap lv_var; do lvs vg_system/$l >/dev/null || exit 1; done'
check "/ es XFS" bash -c '[[ "$(findmnt -no FSTYPE /)" == xfs ]]'
check "/var es un volumen lógico aparte" bash -c 'findmnt -no SOURCE /var | grep -q lv_var'
check "swap activa" bash -c '[[ $(wc -l < /proc/swaps) -ge 2 ]]'
check "usuario adminlab (UID 1001) en wheel" bash -c '[[ "$(id -u adminlab)" == 1001 ]] && id -nG adminlab | grep -qw wheel'
check "adminlab tiene authorized_keys (acceso por clave)" test -s /home/adminlab/.ssh/authorized_keys
check "/etc/lab-release existe" test -f /etc/lab-release
if [[ "$(my_field 7)" -gt 0 ]]; then check "disco de datos /dev/vdb presente (lo usa la Etapa 2)" test -b /dev/vdb; fi
summary
