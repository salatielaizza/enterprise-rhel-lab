#!/usr/bin/env bash
# Etapa 8 — VMware vSphere. Se ejecuta en ansible01 (en los demás hosts no hace nada):
#   scripts/lab.sh test test_vmware.sh ansible01
#
# 1) Herramientas: venv propio de la Etapa 8, colecciones, pyVmomi, vault cifrado, PowerCLI.
# 2) DNS directo e inverso de esxi01-03, vcsa01 y rhel9-vm01 en dns01.
# 3) vSphere, con playbooks/90-verify.yml (solo lectura), UNA etiqueta por check:
#    cada objetivo se comprueba solo si está encendido (fase A: esxi01; fase B: vCenter),
#    y se informa con INFO lo que se omite. Al menos un ESXi o vCenter debe responder.
# shellcheck disable=SC2034  # TEST_NAME lo usa summary() de lib.sh
TEST_NAME=test_vmware; source "$(dirname "$0")/lib.sh"; need_root

if [[ "$(hostname -s)" != ansible01 ]]; then
  echo "test_vmware: solo aplica en ansible01"
  summary; exit $?
fi

ADMIN=adminlab
AH=/home/$ADMIN
VENV=$AH/.venvs/vmware
PROJ=$AH/vmware-lab
DNS=10.10.10.20
info() { printf 'INFO  %s\n' "$*"; }
tcp_open() { timeout 3 bash -c "</dev/tcp/$1/$2" 2>/dev/null; }
as_admin() { runuser -l "$ADMIN" -c "$1"; }
verify() { as_admin "cd '$PROJ' && ANSIBLE_DEPRECATION_WARNINGS=False '$VENV/bin/ansible-playbook' playbooks/90-verify.yml --tags $1"; }

# --- 1) Herramientas ----------------------------------------------------------------
check "venv de la Etapa 8 con ansible-playbook" test -x "$VENV/bin/ansible-playbook"
check "ansible-core del venv >= 2.19" bash -c "'$VENV/bin/python' -c 'import ansible.release as r, sys; v=tuple(map(int, r.__version__.split(\".\")[:2])); sys.exit(0 if v >= (2, 19) else 1)'"
check "pyVmomi importable en el venv" "$VENV/bin/python" -c 'import pyVmomi'
coll_ok() { as_admin "'$VENV/bin/ansible-galaxy' collection list -p '$AH/.ansible/collections' 2>/dev/null" | grep -q "^$1 "; }
check "colección community.vmware instalada" coll_ok community.vmware
check "colección vmware.vmware instalada" coll_ok vmware.vmware
check "proyecto ~/vmware-lab presente" test -f "$PROJ/ansible.cfg"
check "vault.yml de la Etapa 8 cifrado" bash -c "head -1 '$PROJ/inventory/group_vars/all/vault.yml' | grep -q '^\$ANSIBLE_VAULT'"
vault_real() { ! as_admin "cd '$PROJ' && '$VENV/bin/ansible-vault' view inventory/group_vars/all/vault.yml" | grep -q CAMBIAR; }
check "vault.yml sin marcadores 'CAMBIAR' (contraseñas reales puestas)" vault_real
if command -v pwsh >/dev/null; then
  check "PowerCLI instalado para adminlab" bash -c "runuser -l $ADMIN -c \"pwsh -NoLogo -NoProfile -Command 'if (Get-Module -ListAvailable -Name VCF.PowerCLI, VMware.PowerCLI) { exit 0 } else { exit 1 }'\""
else
  info "PowerShell no instalado (stage8-setup --no-powercli): se omite PowerCLI"
fi

# --- 2) DNS ---------------------------------------------------------------------------
for spec in esxi01:10.10.10.60 esxi02:10.10.10.61 esxi03:10.10.10.62 vcsa01:10.10.10.63 rhel9-vm01:10.10.10.64; do
  n="${spec%%:*}"; ip="${spec##*:}"
  check "DNS A   $n.lab.local -> $ip" bash -c "[[ \"\$(dig +short +time=2 +tries=1 @$DNS $n.lab.local | head -1)\" == $ip ]]"
  check "DNS PTR $ip -> $n.lab.local." bash -c "[[ \"\$(dig +short +time=2 +tries=1 @$DNS -x $ip | head -1)\" == $n.lab.local. ]]"
done

# --- 3) vSphere -------------------------------------------------------------------------
any=0
if tcp_open 10.10.10.60 443; then
  any=1; check "esxi01 (gratuito): ESXi 8, fuera de mantenimiento y con datastore local" verify esxi01
else
  info "esxi01 no responde en 443 (normal en la fase B): se omite"
fi
if tcp_open 10.10.10.63 443; then
  any=1
  check "vCenter: existe el clúster lab-cluster" verify vcenter
  check "clúster: esxi02 y esxi03 conectados y fuera de mantenimiento" verify cluster
  check "datastore NFS nfs-vmware accesible y compartido" verify datastore
  check "cada host del clúster tiene VMkernel de vMotion" verify vmotion
  if tcp_open 10.10.10.64 22; then
    check "rhel9-vm01 encendida en un host del clúster" verify guest
    guest_ping() { as_admin "cd '$PROJ' && '$VENV/bin/ansible' vmware_guests -m ping" >/dev/null; }
    check "rhel9-vm01 gestionada por Ansible (ping)" guest_ping
  else
    info "rhel9-vm01 no responde por SSH: se omiten sus checks"
  fi
else
  info "vCenter (10.10.10.63) no responde en 443 (normal en la fase A): se omiten los checks de clúster"
fi
check "al menos un ESXi o vCenter accesible" test "$any" -eq 1
summary
