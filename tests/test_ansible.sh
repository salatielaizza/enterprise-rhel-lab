#!/usr/bin/env bash
# Etapa 7 — Ansible: nodo de control operativo y nodos gestionados en el estado
# aplicado por el playbook 'site'. Las comprobaciones difieren según el host,
# igual que hace lab-healthcheck.sh (Etapa 6) con el array SERVICES por rol.
# shellcheck disable=SC2034  # TEST_NAME lo usa summary() de lib.sh
TEST_NAME=test_ansible; source "$(dirname "$0")/lib.sh"; need_root

HOST="$(hostname -s)"

if [[ "$HOST" == ansible01 ]]; then
  ADMIN_HOME=/home/adminlab
  check "ansible-core instalado" command -v ansible
  check "ansible-playbook instalado" command -v ansible-playbook
  check "inventario del lab presente" test -f "$ADMIN_HOME/ansible-lab/inventory/hosts.ini"
  check "ansible.cfg del lab presente" test -f "$ADMIN_HOME/ansible-lab/ansible.cfg"
  check "playbook site.yml presente" test -f "$ADMIN_HOME/ansible-lab/playbooks/site.yml"
  check "clave SSH del controlador generada" test -f "$ADMIN_HOME/.ssh/id_ed25519"
  check "clave privada con permisos 600" bash -c "[[ \"\$(stat -c %a $ADMIN_HOME/.ssh/id_ed25519)\" == 600 ]]"
  check "contraseña de Ansible Vault presente y con permisos 600" bash -c "[[ \"\$(stat -c %a $ADMIN_HOME/.vault_pass.txt)\" == 600 ]]"
  check "group_vars/all/vault.yml está cifrado (no en texto plano)" bash -c "head -1 '$ADMIN_HOME/ansible-lab/group_vars/all/vault.yml' | grep -q '^\$ANSIBLE_VAULT'"
else
  check "marcador de gestión Ansible presente" test -f /etc/ansible-lab-managed.txt
  check "huso horario Europe/Madrid aplicado" bash -c '[[ "$(timedatectl show -p Timezone --value)" == "Europe/Madrid" ]]'
  check "paquete tree instalado por el rol common" rpm -q tree
  check "usuario ansible.demo1 creado" id ansible.demo1
  check "usuario ansible.demo2 creado" id ansible.demo2
  check "ansible.demo1 tiene la contraseña bloqueada (solo entra por clave)" bash -c "passwd -S ansible.demo1 | awk '{print \$2}' | grep -qE '^(L|LK)$'"
  check "etapa 7 marcada (set_stage)" bash -c '(( $(lab_stage) >= 7 ))'
fi
summary
