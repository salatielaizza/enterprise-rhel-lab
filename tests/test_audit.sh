#!/usr/bin/env bash
# Etapa 5 — auditd: servicio activo y reglas de vigilancia sobre ficheros críticos
# shellcheck disable=SC2034  # TEST_NAME lo usa summary() de lib.sh
TEST_NAME=test_audit; source "$(dirname "$0")/lib.sh"; need_root

rule_present() { auditctl -l 2>/dev/null | grep -q -- "$1"; }

check "paquete audit instalado (auditctl disponible)" command -v auditctl
check "servicio auditd activo" systemctl is-active --quiet auditd
check "servicio auditd habilitado al arranque" systemctl is-enabled --quiet auditd
check "regla de vigilancia sobre /etc/passwd" rule_present "-w /etc/passwd"
check "regla de vigilancia sobre /etc/shadow" rule_present "-w /etc/shadow"
check "regla de vigilancia sobre /etc/ssh/sshd_config" rule_present "-w /etc/ssh/sshd_config"
check "regla de vigilancia sobre /etc/sudoers" rule_present "-w /etc/sudoers"
check "fichero de reglas del lab presente" test -f /etc/audit/rules.d/lab-hardening.rules
summary
