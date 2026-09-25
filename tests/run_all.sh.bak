#!/usr/bin/env bash
# run_all.sh — ejecuta todos los tests aplicables a ESTA VM según la etapa alcanzada
# (/etc/lab-release: LAB_STAGE). Devuelve 1 si algún test falla.
cd "$(dirname "$0")" || exit 2
source ./lib.sh
[[ $EUID -eq 0 ]] || { echo "Ejecuta como root (sudo)"; exit 2; }
stage="$(lab_stage)"; rc=0
echo "== $(hostname -s): etapa alcanzada = $stage =="
tests=(test_install.sh)
[[ $stage -ge 2 ]] && tests+=(test_users.sh test_permissions.sh test_storage.sh test_services.sh)
[[ $stage -ge 3 ]] && tests+=(test_network.sh)
[[ $stage -ge 4 ]] && tests+=(test_dns.sh test_time.sh test_ssh.sh)
for t in "${tests[@]}"; do
  echo; echo "### $t"
  bash "./$t" || rc=1
done
echo; [[ $rc -eq 0 ]] && echo "RESULTADO GLOBAL: OK" || echo "RESULTADO GLOBAL: HAY FALLOS"
exit $rc
