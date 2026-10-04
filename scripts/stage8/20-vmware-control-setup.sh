#!/usr/bin/env bash
# =============================================================================
# 20-vmware-control-setup.sh — (ansible01) Prepara la automatización de VMware
#
# SOLO en ansible01 y DESPUÉS de 'lab.sh stage7-setup' (reutiliza la clave SSH y
# la contraseña de Ansible Vault de la Etapa 7). Idempotente.
#
#   1. Entorno virtual de Python PROPIO de la Etapa 8 (~adminlab/.venvs/vmware) con
#      ansible-core >= 2.19 + pyVmomi. Motivo: community.vmware 6.x exige
#      ansible-core >= 2.19, que no está en RHEL 9; y NO se toca el ansible-core del
#      sistema que usa la Etapa 7 (sigue en curso).
#   2. Colecciones community.vmware y vmware.vmware (requirements.yml).
#   3. Proyecto ~/vmware-lab (aparte de ~/ansible-lab: 'stage7-setup' recopia
#      ansible-lab con 'cp -a' y pisaría lo que no esté en scripts/stage7/files).
#   4. vault.yml con contraseñas de MARCADOR, cifrado con la misma contraseña de
#      Vault de la Etapa 7. El usuario pone las reales con 'ansible-vault edit'.
#   5. PowerShell + PowerCLI (opcional: --no-powercli para omitirlo).
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root
[[ "$(hostname -s)" == ansible01 ]] || fatal "Este script es solo para ansible01"

WITH_PWSH=1; [[ "${1:-}" == --no-powercli ]] && WITH_PWSH=0
ADMIN_USER=adminlab
ADMIN_HOME="/home/$ADMIN_USER"
VENV="$ADMIN_HOME/.venvs/vmware"
PROJ="$ADMIN_HOME/vmware-lab"
VAULT_PASS_FILE="$ADMIN_HOME/.vault_pass.txt"
VAULT_FILE="$PROJ/inventory/group_vars/all/vault.yml"
SRC="$(dirname "${BASH_SOURCE[0]}")/files/vmware-lab"
as_admin() { runuser -l "$ADMIN_USER" -c "$1"; }

[[ -f "$VAULT_PASS_FILE" ]] || fatal "No existe $VAULT_PASS_FILE: ejecuta antes 'lab.sh stage7-setup'"
[[ -f "$ADMIN_HOME/.ssh/id_ed25519" ]] || fatal "No existe la clave SSH de adminlab: ejecuta antes 'lab.sh stage7-setup'"

# --- 1) Python >= 3.11 + venv ------------------------------------------------------------
PY=""
for c in python3.12 python3.11; do command -v "$c" >/dev/null && { PY="$(command -v "$c")"; break; }; done
if [[ -z "$PY" ]]; then
  say "Instalando python3.11 (AppStream de RHEL 9): ansible-core 2.19 necesita Python >= 3.11"
  dnf -y install python3.11 python3.11-pip
  PY="$(command -v python3.11)" || fatal "No se pudo instalar python3.11"
fi
say "Python para la Etapa 8: $PY ($("$PY" --version 2>&1))"
if [[ ! -x "$VENV/bin/python" ]]; then
  as_admin "mkdir -p '$(dirname "$VENV")' && '$PY' -m venv '$VENV'"
  say "[+] entorno virtual creado en $VENV"
fi
as_admin "'$VENV/bin/python' -m pip install -q --upgrade pip"
as_admin "'$VENV/bin/python' -m pip install -q 'ansible-core>=2.19,<2.21' 'pyvmomi>=8.0.3' requests"
say "ansible-core del venv: $(as_admin "'$VENV/bin/ansible' --version" | head -1)"

# --- 2) Proyecto ~/vmware-lab (conservando vault.yml si ya está cifrado) --------------------
KEEP_VAULT=""
# shellcheck disable=SC2016  # '^\$ANSIBLE_VAULT' es una expresión regular, no una variable
if [[ -f "$VAULT_FILE" ]] && head -1 "$VAULT_FILE" | grep -q '^\$ANSIBLE_VAULT'; then
  KEEP_VAULT="$(mktemp)"; cp -a "$VAULT_FILE" "$KEEP_VAULT"
fi
mkdir -p "$PROJ"
cp -a "$SRC"/. "$PROJ"/
if [[ -n "$KEEP_VAULT" ]]; then cp -a "$KEEP_VAULT" "$VAULT_FILE"; rm -f "$KEEP_VAULT"; say "[=] vault.yml existente conservado"; fi
mkdir -p "$PROJ/reports"
chown -R "$ADMIN_USER:$ADMIN_USER" "$PROJ" "$ADMIN_HOME/.venvs"
say "Proyecto copiado a $PROJ"

# --- 3) Colecciones --------------------------------------------------------------------------
as_admin "cd '$PROJ' && '$VENV/bin/ansible-galaxy' collection install -r requirements.yml -p '$ADMIN_HOME/.ansible/collections'" \
  || fatal "No se pudieron instalar las colecciones (¿ansible01 tiene salida a Internet por el NAT del lab?)"
as_admin "'$VENV/bin/ansible-galaxy' collection list -p '$ADMIN_HOME/.ansible/collections' 2>/dev/null | grep -E 'community.vmware|vmware.vmware'" || true

# --- 4) Vault ----------------------------------------------------------------------------------
# shellcheck disable=SC2016
if ! head -1 "$VAULT_FILE" 2>/dev/null | grep -q '^\$ANSIBLE_VAULT'; then
  cp -a "$PROJ/inventory/group_vars/all/vault.yml.example" "$VAULT_FILE"
  chown "$ADMIN_USER:$ADMIN_USER" "$VAULT_FILE"; chmod 600 "$VAULT_FILE"
  as_admin "cd '$PROJ' && '$VENV/bin/ansible-vault' encrypt inventory/group_vars/all/vault.yml"
  say "[+] vault.yml cifrado con marcadores 'CAMBIAR'. Pon las contraseñas reales con:"
  say "    ssh ansible01 → cd ~/vmware-lab && ~/.venvs/vmware/bin/ansible-vault edit inventory/group_vars/all/vault.yml"
fi

# --- 5) PowerShell + PowerCLI ----------------------------------------------------------------------
if [[ $WITH_PWSH -eq 1 ]]; then
  if ! command -v pwsh >/dev/null; then
    say "Instalando PowerShell desde el repositorio de Microsoft para RHEL 9"
    rpm -q packages-microsoft-prod >/dev/null 2>&1 \
      || dnf -y install https://packages.microsoft.com/config/rhel/9/packages-microsoft-prod.rpm
    dnf -y install powershell
  fi
  # Desde 2025 el módulo se llama VCF.PowerCLI; si la galería no lo ofrece, se usa VMware.PowerCLI.
  as_admin "pwsh -NoLogo -NoProfile -Command '
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    if (-not (Get-Module -ListAvailable -Name VCF.PowerCLI, VMware.PowerCLI)) {
      try { Install-Module VCF.PowerCLI -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop }
      catch { Install-Module VMware.PowerCLI -Scope CurrentUser -Force -AllowClobber }
    }
    Set-PowerCLIConfiguration -Scope User -InvalidCertificateAction Ignore -ParticipateInCEIP \$false -Confirm:\$false | Out-Null
    Get-Module -ListAvailable -Name VCF.PowerCLI, VMware.PowerCLI | Select-Object -First 1 Name, Version | Format-Table -HideTableHeaders
  '" || say "AVISO: PowerCLI no se pudo instalar (no bloquea Ansible). Reintenta más tarde."
fi

say "ansible01 listo para la Etapa 8. Playbooks: lab.sh stage8 <info|cluster|esxi-config|guest|vmotion|snapshot|guest-baseline|verify>"
