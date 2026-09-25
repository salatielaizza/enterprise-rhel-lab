#!/usr/bin/env bash
# run_all.sh — ejecuta todos los tests aplicables a ESTA VM según la etapa alcanzada
# (/etc/lab-release: LAB_STAGE). Devuelve 1 si algún test falla.
#
# Imprime un resumen POR HOST ("RESULTADO del host <nombre>: ..."), no un resumen
# "global" (eso lo agrega scripts/lab.sh en tu equipo, que es el único sitio que
# conoce el resultado de TODAS las VMs a la vez). Mide el tiempo de cada sub-test
# y el tiempo total (segundos, con el builtin $SECONDS de bash), formateado como
# "Ns" (menos de 1 min) o "Mm SSs" (1 min o más).
#
# Además emite una línea de datos, sin formato humano, que scripts/lab.sh sabe leer
# para construir la tabla final de todas las VMs:
#   ##HOST_SUMMARY## <host> <PASS_total> <FAIL_total> <OK|FALLOS> <tiempo_total>
cd "$(dirname "$0")" || exit 2
source ./lib.sh
[[ $EUID -eq 0 ]] || { echo "Ejecuta como root (sudo)"; exit 2; }

fmt_time() {  # segundos -> "Ns" o "Mm SSs"
  local s=$1
  if (( s < 60 )); then printf '%ds' "$s"
  else printf '%dm%02ds' $((s / 60)) $((s % 60)); fi
}

stage="$(lab_stage)"; rc=0
HOST="$(hostname -s)"
HOST_PASS=0; HOST_FAIL=0
START=$SECONDS
echo "== $HOST: etapa alcanzada = $stage =="
tests=(test_install.sh)
[[ $stage -ge 2 ]] && tests+=(test_users.sh test_permissions.sh test_storage.sh test_services.sh)
[[ $stage -ge 3 ]] && tests+=(test_network.sh)
[[ $stage -ge 4 ]] && tests+=(test_dns.sh test_time.sh test_ssh.sh)
for t in "${tests[@]}"; do
  echo; echo "### $t"
  t0=$SECONDS
  out="$(bash "./$t" 2>&1)"; ec=$?
  dt=$((SECONDS - t0))
  printf '%s\n' "$out"
  printf '    (tiempo: %s)\n' "$(fmt_time "$dt")"
  [[ $ec -ne 0 ]] && rc=1
  line="$(printf '%s\n' "$out" | grep -E '^--- .* [0-9]+ PASS, [0-9]+ FAIL$' | tail -n1)"
  if [[ -n "$line" ]]; then
    p="$(sed -E 's/.*: ([0-9]+) PASS,.*/\1/' <<<"$line")"
    f="$(sed -E 's/.*, ([0-9]+) FAIL$/\1/' <<<"$line")"
    HOST_PASS=$((HOST_PASS + p)); HOST_FAIL=$((HOST_FAIL + f))
  fi
done
TOTAL_DT=$((SECONDS - START))
TOTAL_FMT="$(fmt_time "$TOTAL_DT")"
echo
if [[ $rc -eq 0 ]]; then
  echo "RESULTADO del host $HOST: OK ($HOST_PASS PASS, $HOST_FAIL FAIL, $TOTAL_FMT)"
  echo "##HOST_SUMMARY## $HOST $HOST_PASS $HOST_FAIL OK $TOTAL_FMT"
else
  echo "RESULTADO del host $HOST: HAY FALLOS ($HOST_PASS PASS, $HOST_FAIL FAIL, $TOTAL_FMT)"
  echo "##HOST_SUMMARY## $HOST $HOST_PASS $HOST_FAIL FALLOS $TOTAL_FMT"
fi
exit $rc
