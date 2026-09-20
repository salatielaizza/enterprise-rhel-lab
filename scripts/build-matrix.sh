#!/usr/bin/env bash
# =============================================================================
# build-matrix.sh — Genera comparison/matrix.generated.md con DATOS REALES
# leídos de results/facts/<host>.env (los crea 'lab.sh facts all').
# Nada de esta tabla se inventa: si falta un dato, aparece '—'.
# =============================================================================
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
F="$LAB_ROOT/results/facts"; OUT="$LAB_ROOT/comparison/matrix.generated.md"
hosts=(rhel7-app01 rhel8-app01 rhel9-app01 rhel10-app01)
for h in "${hosts[@]}"; do [[ -f "$F/$h.env" ]] || warn "Falta $F/$h.env (ejecuta: lab.sh facts $h)"; done

val() { local v; v="$(grep -m1 "^$2=" "$F/$1.env" 2>/dev/null | cut -d= -f2-)"; echo "${v:-—}"; }
row() {  # row "Etiqueta" CLAVE
  printf '| %s |' "$1"
  for h in "${hosts[@]}"; do printf ' %s |' "$(val "$h" "$2" | sed 's/|/\\|/g')"; done
  printf '\n'
}
{
  echo "# Matriz de comparación RHEL 7 / 8 / 9 / 10 (datos REALES de las VMs)"
  echo
  echo "Generada el $(date -Is) por \`scripts/build-matrix.sh\` desde \`results/facts/*.env\`."
  echo "No edites este fichero a mano: regenera con \`scripts/lab.sh facts all && scripts/lab.sh matrix\`."
  echo
  echo "| Característica | RHEL 7 | RHEL 8 | RHEL 9 | RHEL 10 |"
  echo "|---|---|---|---|---|"
  row "Versión (os-release)" OS_PRETTY
  row "Kernel" KERNEL
  row "Init / systemd" INIT
  row "glibc" GLIBC
  row "Gestor de paquetes" PKGMGR
  row "rpm" RPM
  row "Python (/usr/bin/python)" PYTHON_DEFAULT
  row "Python 3 (python3)" PYTHON3
  row "platform-python" PLATFORM_PYTHON
  row "NetworkManager" NETWORKMANAGER
  row "Formato de perfiles de red" NM_PROFILE_FORMAT
  row "Servicio 'network' (initscripts)" NETWORK_SERVICE
  row "net-tools (ifconfig)" NETTOOLS
  row "firewalld" FIREWALLD
  row "Backend de firewalld" FIREWALL_BACKEND
  row "SELinux" SELINUX
  row "OpenSSH" SSH
  row "Sincronización horaria" TIMESYNC
  row "Paquete ntp instalado" NTPD_INSTALLED
  row "Sistema de ficheros raíz" ROOT_FS
  row "LVM2" LVM
  row "xfsprogs" XFSPROGS
  row "Demonio de logs" LOG_DAEMON
  row "Journal persistente" JOURNAL_PERSISTENT
  row "Modo de arranque" BOOT_MODE
  row "cgroups (tipo de FS)" CGROUP
  row "Política criptográfica" CRYPTO_POLICY
  row "Suscripción" SUBSCRIPTION
  row "Repositorios activos" REPOS
} > "$OUT"
ok "Matriz escrita en $OUT"
