#!/usr/bin/env bash
# Etapa N3 — validación ESTÁTICA del proyecto de referencia de la práctica de Ansible.
# Corre en el equipo host (o en ansible01) y NO toca ninguna VM: trabaja sobre una copia temporal.
#   scripts/stageN3/validar.sh            # PASS/FAIL/SKIP por comprobación; código de salida = nº de FAIL
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/files/practica-ansible"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0; skip=0
ok()   { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
ko()   { printf 'FAIL  %s\n' "$1"; fail=$((fail + 1)); }
salta(){ printf 'SKIP  %s\n' "$1"; skip=$((skip + 1)); }

command -v ansible-playbook >/dev/null || { echo "ansible-playbook no está instalado"; exit 1; }
[[ -d "$DIR" ]] || { echo "No existe $DIR"; exit 1; }

# Copia de trabajo: el vault de ejemplo (sin cifrar) hace de vault.yml, así no hace falta contraseña
cp -a "$DIR/." "$TMP/"
cp "$TMP/inventory/group_vars/all/vault.yml.example" "$TMP/inventory/group_vars/all/vault.yml"
cd "$TMP"

# 1. Los ficheros que Ansible carga solos deben llamarse main.yml (casos etapaN3/03 y 07)
malos="$(find roles -mindepth 3 -maxdepth 3 -type f \( -path '*/defaults/*' -o -path '*/tasks/*' -o -path '*/handlers/*' \) \
          ! -name 'main.yml')"
if [[ -z "$malos" ]]; then ok "roles: defaults/tasks/handlers solo contienen main.yml"; else ko "roles: ficheros que Ansible no carga: $malos"; fi

# 2. Ningún directorio de rol suelto dentro de roles/ (caso etapaN3/03: roles/tasks, roles/defaults)
sueltos="$(find roles -mindepth 1 -maxdepth 1 -type d \( -name tasks -o -name defaults -o -name handlers -o -name templates -o -name vars -o -name meta \))"
if [[ -z "$sueltos" ]]; then ok "roles/: sin carpetas de rol sueltas"; else ko "roles/: carpetas sueltas: $sueltos"; fi

# 3. El vault real nunca dentro del árbol del repositorio sin cifrar
# shellcheck disable=SC2016  # '$ANSIBLE_VAULT' es texto literal, no una variable
if [[ -f "$DIR/inventory/group_vars/all/vault.yml" ]] && ! head -1 "$DIR/inventory/group_vars/all/vault.yml" | grep -qF '$ANSIBLE_VAULT'; then
  ko "vault.yml existe en el repositorio y NO está cifrado"
else
  ok "vault.yml: ausente o cifrado (en .gitignore)"
fi

# 4. Inventario: grupos esperados
grafo="$(ansible-inventory --graph 2>/dev/null)"
for g in app legacy modernos servicios; do
  if grep -q "@$g:" <<<"$grafo"; then ok "inventario: grupo $g"; else ko "inventario: falta el grupo $g"; fi
done

# 5. Sintaxis de cada playbook (los que usan ansible.posix necesitan la colección instalada)
# ansible-doc y 'collection list' devuelven 0 aunque no la encuentren: se mira la salida
posix=0
# Sin '| grep -q' directo: con pipefail, grep cierra la tubería antes y da SIGPIPE (caso etapa10/01)
colecciones="$(ansible-galaxy collection list 2>/dev/null || true)"
if grep -q '^ansible\.posix ' <<<"$colecciones"; then posix=1; fi
for p in p*.yml limpieza.yml; do
  if grep -q 'ansible\.posix\.' "$p" && (( posix == 0 )); then
    salta "--syntax-check $p (falta ansible.posix: ansible-galaxy collection install -r requirements.yml -p ./collections)"
    continue
  fi
  if ansible-playbook --syntax-check "$p" >/dev/null 2>&1; then ok "--syntax-check $p"; else ko "--syntax-check $p"; fi
done

# 6. Ninguna fecha dentro de las plantillas (caso etapa7/02: rompe la idempotencia)
if grep -rnE 'date_time|now\(' --include='*.j2' . >/dev/null; then ko "plantillas con fecha (rompen la idempotencia)"; else ok "plantillas sin fechas"; fi

# 7. Linters, si están instalados
if command -v yamllint >/dev/null; then
  if yamllint -d '{extends: relaxed, rules: {line-length: {max: 140}}}' . >/dev/null 2>&1; then ok "yamllint"
  else ko "yamllint (lánzalo a mano para ver los avisos)"; fi
else salta "yamllint no instalado"; fi
if command -v ansible-lint >/dev/null; then
  if ansible-lint --offline p*.yml >/dev/null 2>&1; then ok "ansible-lint"
  else salta "ansible-lint con avisos (P8 usa ignore_errors a propósito); revísalos a mano"; fi
else salta "ansible-lint no instalado"; fi

echo "----"
echo "PASS=$pass FAIL=$fail SKIP=$skip"
exit "$fail"
