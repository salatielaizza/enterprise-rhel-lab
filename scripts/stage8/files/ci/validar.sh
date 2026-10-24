#!/usr/bin/env bash
# =============================================================================
# validar.sh — "CI" de la Etapa 8: lo que un pipeline comprobaría antes de aceptar un cambio
# en scripts/stage8/files/ (subetapa 8.11). No necesita clúster ni toca nada: solo lee.
#
#   scripts/stage8/files/ci/validar.sh            # desde la raíz del repo (o desde cualquier sitio)
#
# Comprueba, con la herramienta que haya instalada (si falta, la salta y lo dice):
#   1. yamllint     sintaxis y estilo de todos los YAML
#   2. kubeconform  manifiestos válidos para la API de Kubernetes (los CRD se omiten)
#   3. promtool     reglas de Prometheus correctas, copia para tests al día y tests unitarios
#   4. terraform    formato (fmt) y, si hay red para descargar providers, validate
# Sale con 1 si algo FALLA; lo OMITIDO no hace fallar (se informa al final).
# =============================================================================
set -uo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"          # scripts/stage8/files
cd "$BASE" || exit 2
fallos=0; omitidos=()
ok()      { printf '  OK      %s\n' "$*"; }
fallo()   { printf '  FALLO   %s\n' "$*"; fallos=$((fallos + 1)); }
omitir()  { printf '  OMITIDO %s\n' "$*"; omitidos+=("$1"); }
titulo()  { printf '\n== %s\n' "$*"; }
tiene()   { command -v "$1" >/dev/null 2>&1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

mapfile -t YAMLS < <(find . -path ./terraform -prune -o \( -name '*.yaml' -o -name '*.yml' \) -print | sort)
# Manifiestos de Kubernetes (no los ficheros de valores de Helm ni los de promtool)
mapfile -t MANIFIESTOS < <(printf '%s\n' "${YAMLS[@]}" | grep -Ev 'values\.yaml$|/tests/')

titulo "1. yamllint (${#YAMLS[@]} ficheros)"
if tiene yamllint; then
  if yamllint -d '{extends: relaxed, rules: {line-length: {max: 140}}}' "${YAMLS[@]}"; then ok "YAML correcto"
  else fallo "yamllint encontró errores"; fi
else omitir yamllint "(dnf install yamllint, o pip install --user yamllint)"; fi

titulo "2. kubeconform (${#MANIFIESTOS[@]} manifiestos)"
if tiene kubeconform; then
  if kubeconform -strict -summary -ignore-missing-schemas -kubernetes-version 1.36.5 "${MANIFIESTOS[@]}"; then
    ok "manifiestos válidos (objetos de CRD como ServiceMonitor o IPAddressPool: omitidos)"
  else fallo "kubeconform encontró manifiestos inválidos"; fi
else omitir kubeconform "(binario de https://github.com/yannh/kubeconform/releases)"; fi

titulo "3. promtool"
if tiene promtool && tiene python3; then
  for r in monitoring/rules/*.yaml; do
    # Un PrometheusRule es un objeto de Kubernetes: promtool solo entiende su .spec (groups)
    python3 -c 'import sys, yaml; d = yaml.safe_load(open(sys.argv[1])); yaml.safe_dump({"groups": d["spec"]["groups"]}, open(sys.argv[2], "w"), allow_unicode=True, sort_keys=False)' \
      "$r" "$tmp/$(basename "$r")" || { fallo "$r no es un PrometheusRule legible"; continue; }
    if promtool check rules "$tmp/$(basename "$r")" >/dev/null; then ok "reglas de $r"
    else promtool check rules "$tmp/$(basename "$r")"; fallo "reglas de $r"; fi
  done
  # La copia de tests/ debe coincidir con la regla real (si no, los tests prueban una versión vieja)
  if diff -q <(grep -v '^#' monitoring/tests/podinfo-slo.rules.yaml) "$tmp/podinfo-slo.yaml" >/dev/null; then
    ok "tests/podinfo-slo.rules.yaml al día con rules/podinfo-slo.yaml"
  else fallo "tests/podinfo-slo.rules.yaml desfasado: regenéralo (comando en su cabecera)"; fi
  if (cd monitoring/tests && promtool test rules podinfo-slo.test.yaml >/dev/null); then ok "tests unitarios de alertas"
  else (cd monitoring/tests && promtool test rules podinfo-slo.test.yaml); fallo "tests unitarios de alertas"; fi
else omitir promtool "(está en el tarball de Prometheus: https://github.com/prometheus/prometheus/releases)"; fi

titulo "4. terraform"
TF=""; tiene terraform && TF=terraform; [[ -z "$TF" ]] && tiene tofu && TF=tofu
if [[ -n "$TF" ]]; then
  if "$TF" fmt -check -recursive terraform >/dev/null; then ok "$TF fmt"
  else "$TF" fmt -check -recursive -diff terraform; fallo "$TF fmt: ejecuta '$TF fmt -recursive terraform'"; fi
  for d in terraform/10-plataforma terraform/20-config; do
    # -backend=false: valida sin tocar el estado del clúster. Necesita descargar los providers.
    # TF_DATA_DIR temporal: no deja .terraform/ dentro del repo
    export TF_DATA_DIR="$tmp/tf-${d##*/}"
    if (cd "$d" && "$TF" init -backend=false -input=false >/dev/null 2>&1); then
      if (cd "$d" && "$TF" validate -no-color >/dev/null); then ok "$TF validate $d"
      else (cd "$d" && "$TF" validate -no-color); fallo "$TF validate $d"; fi
    else omitir "validate-$d" "($TF init no pudo descargar los providers: ¿sin red?)"; fi
  done
else omitir terraform "(dnf install terraform desde rpm.releases.hashicorp.com)"; fi

printf '\n'
[[ ${#omitidos[@]} -gt 0 ]] && printf 'Omitido (no cuenta como fallo): %s\n' "${omitidos[*]}"
if [[ $fallos -eq 0 ]]; then printf 'RESULTADO: OK\n'; exit 0; fi
printf 'RESULTADO: %d FALLO(S)\n' "$fallos"; exit 1
