#!/usr/bin/env bash
# Etapa 7 — Ansible: nodo de control operativo y nodos gestionados en el estado
# aplicado por el playbook 'site'. Las comprobaciones difieren según el host,
# igual que hace lab-healthcheck.sh (Etapa 6) con el array SERVICES por rol.
# shellcheck disable=SC2034  # TEST_NAME lo usa summary() de lib.sh
# shellcheck disable=SC2016  # comillas simples a propósito: se expande DENTRO del 'bash -c'
TEST_NAME=test_ansible; source "$(dirname "$0")/lib.sh"; need_root

HOST="$(hostname -s)"

# lab_stage es una FUNCIÓN de lib.sh: no existe dentro de un 'bash -c' (proceso
# nuevo, no hereda funciones), así que 'bash -c "(( $(lab_stage) >= 7 ))"' fallaba
# SIEMPRE aunque /etc/lab-release dijera LAB_STAGE=7 (troubleshooting/etapa7/06).
# check() ejecuta "$@" en esta misma shell, así que una función propia sí la ve.
etapa7_marcada() { (( $(lab_stage) >= 7 )); }

if [[ "$HOST" == ansible01 ]]; then
  ADMIN_HOME=/home/adminlab
  LAB="$ADMIN_HOME/ansible-lab"
  check "ansible-core instalado" command -v ansible
  check "ansible-playbook instalado" command -v ansible-playbook
  check "inventario del lab presente" test -f "$LAB/inventory/hosts.ini"
  check "ansible.cfg del lab presente" test -f "$LAB/ansible.cfg"
  check "playbook site.yml presente" test -f "$LAB/playbooks/site.yml"
  check "clave SSH del controlador generada" test -f "$ADMIN_HOME/.ssh/id_ed25519"
  check "clave privada con permisos 600" bash -c "[[ \"\$(stat -c %a $ADMIN_HOME/.ssh/id_ed25519)\" == 600 ]]"
  check "contraseña de Ansible Vault presente y con permisos 600" bash -c "[[ \"\$(stat -c %a $ADMIN_HOME/.vault_pass.txt)\" == 600 ]]"
  # group_vars vive JUNTO al inventario (inventory/group_vars), no en la raíz del
  # proyecto: ver troubleshooting/etapa7/03.
  check "inventory/group_vars/all/vault.yml está cifrado (no en texto plano)" bash -c "head -1 '$LAB/inventory/group_vars/all/vault.yml' | grep -q '^\$ANSIBLE_VAULT'"
  # stage7-setup sincroniza con rsync --delete: no deben quedar restos de
  # ejercicios ni copias de seguridad en el nodo de control (troubleshooting/etapa7/04).
  check "proyecto sin restos (*.lab-bak.*, *.swp, host_vars/)" bash -c "! find '$LAB' \( -name '*.lab-bak.*' -o -name '*.swp' -o -path '$LAB/inventory/host_vars' \) | grep -q ."
  check "etapa 7 marcada en el nodo de control (set_stage)" etapa7_marcada
else
  check "marcador de gestión Ansible presente" test -f /etc/ansible-lab-managed.txt
  # Se lee el enlace /etc/localtime, igual que el rol 'common': 'timedatectl show -p'
  # no existe en el systemd 219 de RHEL 7 (troubleshooting/etapa7/01).
  check "huso horario Europe/Madrid aplicado" bash -c '[[ "$(readlink /etc/localtime)" == */zoneinfo/Europe/Madrid ]]'
  check "paquete tree instalado por el rol common" rpm -q tree
  check "usuario ansible.demo1 creado" id ansible.demo1
  check "usuario ansible.demo2 creado" id ansible.demo2
  check "ansible.demo1 tiene la contraseña bloqueada (solo entra por clave)" bash -c "passwd -S ansible.demo1 | awk '{print \$2}' | grep -qE '^(L|LK)$'"
  check "etapa 7 marcada (set_stage)" etapa7_marcada
fi
summary
