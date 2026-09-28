#!/usr/bin/env bash
# =============================================================================
# 01-ansible-control-setup.sh — Convierte ansible01 en nodo de control (Etapa 7)
#
# SOLO se ejecuta en ansible01 (lab.sh lo llama explícitamente, no como parte
# de un bucle "all"). Deja el nodo de control listo para gestionar el resto del
# lab:
#   1. Instala ansible-core (EPEL en RHEL 7, AppStream en RHEL 8/9/10).
#   2. Copia el inventario/playbooks/roles (ya subidos por 'push') a la home de
#      adminlab, con los permisos correctos.
#   3. Genera un par de claves SSH propio de adminlab@ansible01 (si no existe
#      ya) — es la clave con la que ansible01 entrará por SSH en el resto de
#      VMs; lab.sh se encarga de distribuir la pública usando el acceso que el
#      EQUIPO HOST ya tiene desde la Etapa 1 (no hace falta ninguna contraseña
#      nueva).
#   4. Genera una contraseña aleatoria de Ansible Vault (si no existe ya) y, la
#      primera vez, cifra group_vars/all/vault.yml con ella. La contraseña
#      NUNCA se copia al repositorio (vive solo en ~adminlab/.vault_pass.txt,
#      0600), igual que el offline token de Red Hat en el equipo host.
#   5. Imprime la clave pública entre marcadores para que lab.sh la capture.
# =============================================================================
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
require_root

ADMIN_USER=adminlab
ADMIN_HOME="/home/$ADMIN_USER"
ANSIBLE_DIR="$ADMIN_HOME/ansible-lab"
KEY="$ADMIN_HOME/.ssh/id_ed25519"
VAULT_PASS_FILE="$ADMIN_HOME/.vault_pass.txt"

# --- 1) ansible-core -------------------------------------------------------------
if ! command -v ansible-playbook >/dev/null; then
  say "Instalando ansible-core..."
  if ! dnf install -y ansible-core 2>/dev/null; then
    say "ansible-core no está en los repos activos: probando con EPEL (típico en RHEL 7)"
    dnf install -y epel-release 2>/dev/null || yum install -y epel-release
    dnf install -y ansible-core 2>/dev/null || dnf install -y ansible || yum install -y ansible
  fi
else
  say "ansible-core ya está instalado ($(ansible --version | head -1))"
fi
command -v ansible-playbook >/dev/null || fatal "ansible-playbook sigue sin estar disponible tras el intento de instalación"

# --- 2) Contenido del lab (ya copiado por 'push' a ~/lab-scripts/stage7/files) ----
SRC="$(dirname "${BASH_SOURCE[0]}")/files"
mkdir -p "$ANSIBLE_DIR"
cp -a "$SRC"/. "$ANSIBLE_DIR"/
chown -R "$ADMIN_USER:$ADMIN_USER" "$ANSIBLE_DIR"
say "Inventario/playbooks/roles copiados a $ANSIBLE_DIR"

# --- 3) Clave SSH del controlador (idempotente) -----------------------------------
if [[ ! -f "$KEY" ]]; then
  sudo -u "$ADMIN_USER" ssh-keygen -t ed25519 -N '' -f "$KEY" -C "$ADMIN_USER@ansible01-lab-controller" >/dev/null
  say "Clave SSH generada para $ADMIN_USER en ansible01"
else
  say "La clave SSH de $ADMIN_USER ya existía; no se regenera"
fi
chmod 700 "$ADMIN_HOME/.ssh"
chmod 600 "$KEY"

# --- 4) Ansible Vault: contraseña local + cifrado del demo (solo la 1ª vez) -------
if [[ ! -f "$VAULT_PASS_FILE" ]]; then
  openssl rand -base64 24 > "$VAULT_PASS_FILE"
  chown "$ADMIN_USER:$ADMIN_USER" "$VAULT_PASS_FILE"
  chmod 600 "$VAULT_PASS_FILE"
  say "Contraseña de Ansible Vault generada en $VAULT_PASS_FILE (NUNCA se guarda en git)"
else
  say "Ya existía una contraseña de Ansible Vault; se reutiliza"
fi

VAULT_FILE="$ANSIBLE_DIR/group_vars/all/vault.yml"
# OJO: ansible.cfg YA define 'vault_password_file'. Pasar además '--vault-password-file'
# en la línea de comandos crea DOS vault-id "default" y ansible-vault lo rechaza
# ("Specify the vault-id to encrypt with --encrypt-vault-id"). Por eso aquí NUNCA
# se repite el flag: basta con ANSIBLE_CONFIG apuntando a $ANSIBLE_DIR/ansible.cfg.
if ! sudo -u "$ADMIN_USER" env ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg" ansible-vault view "$VAULT_FILE" >/dev/null 2>&1; then
  say "Cifrando $VAULT_FILE con Ansible Vault (primera vez)"
  cat > "$VAULT_FILE" <<'EOF'
---
vault_demo_api_token: "lab-demo-token-CHANGE-ME-0123456789"
EOF
  chown "$ADMIN_USER:$ADMIN_USER" "$VAULT_FILE"
  sudo -u "$ADMIN_USER" env ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg" ansible-vault encrypt "$VAULT_FILE"
  say "vault.yml cifrado correctamente"
else
  say "vault.yml ya estaba cifrado y se descifra correctamente con la contraseña local"
fi

# --- 5) Publicar la clave pública para que lab.sh la distribuya -------------------
echo "##ANSIBLE_PUBKEY_START##"
cat "$KEY.pub"
echo "##ANSIBLE_PUBKEY_END##"
