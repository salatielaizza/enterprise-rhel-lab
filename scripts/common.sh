#!/usr/bin/env bash
# common.sh — helpers de los scripts que corren DENTRO de las VMs (como root).
# Se copia a ~/lab-scripts/common.sh con 'lab.sh push' y lo cargan stage2/3/4.

require_root() { [[ $EUID -eq 0 ]] || { echo "Ejecuta como root (sudo)"; exit 1; }; }
say()  { printf '[%s] %s\n' "$(hostname -s)" "$*"; }
fatal() { printf '[%s] ERROR: %s\n' "$(hostname -s)" "$*" >&2; exit 1; }

# set_stage N — registra la etapa alcanzada en /etc/lab-release (nunca la reduce)
set_stage() {
  local n="$1" cur
  cur="$(awk -F= '$1=="LAB_STAGE"{print $2}' /etc/lab-release 2>/dev/null)"
  cur="${cur:-0}"
  if (( cur < n )); then
    if grep -q '^LAB_STAGE=' /etc/lab-release 2>/dev/null; then
      sed -i "s/^LAB_STAGE=.*/LAB_STAGE=$n/" /etc/lab-release
    else
      echo "LAB_STAGE=$n" >> /etc/lab-release
    fi
  fi
}
