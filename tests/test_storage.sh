#!/usr/bin/env bash
# Etapa 2 — Almacenamiento: LVM, XFS, fstab por UUID y montajes
# shellcheck disable=SC2034  # TEST_NAME lo usa summary() de lib.sh
TEST_NAME=test_storage; source "$(dirname "$0")/lib.sh"; need_root
if [[ "$(my_field 7)" -eq 0 ]]; then
  echo "Este host no tiene disco de datos: solo se comprueba el almacenamiento del sistema"
else
  check "VG vg_data existe" vgs vg_data
  for lv in lv_application lv_logs lv_backup; do check "LV $lv existe" lvs "vg_data/$lv"; done
  check "VG con >= 1 GiB libre (ejercicios de ampliación)" bash -c "vgs --noheadings --units g --nosuffix -o vg_free vg_data | awk '{exit !(\$1 >= 1.0)}'"
  for spec in lv_application:/opt/application/data lv_logs:/var/log/lab-app lv_backup:/backup; do
    lv="${spec%%:*}"; mp="${spec##*:}"
    check "$mp montado desde $lv" bash -c "findmnt -no SOURCE $mp | grep -q $lv"
    check "$mp es XFS" bash -c "[[ \"\$(findmnt -no FSTYPE $mp)\" == xfs ]]"
    check "fstab usa UUID para $mp" bash -c "grep -Eq '^UUID=[0-9a-f-]+[[:space:]]+${mp}[[:space:]]+xfs' /etc/fstab"
    check "fstab NO usa /dev/... para $mp" bash -c "! grep -Eq '^/dev/.*[[:space:]]+${mp}[[:space:]]' /etc/fstab"
  done
  check "copia de fstab original (/etc/fstab.lab-bak)" test -f /etc/fstab.lab-bak
fi
check "vg_system: lv_root, lv_swap, lv_var" bash -c 'for l in lv_root lv_swap lv_var; do lvs vg_system/$l || exit 1; done'
check "/ y /var montados como XFS" bash -c '[[ "$(findmnt -no FSTYPE /)" == xfs && "$(findmnt -no FSTYPE /var)" == xfs ]]'
if findmnt --help 2>&1 | grep -q -- '--verify'; then check "findmnt --verify sin errores" findmnt --verify; fi
check "swap activa" bash -c '[[ $(wc -l < /proc/swaps) -ge 2 ]]'
check "ninguna unidad .mount en estado failed" bash -c '! systemctl list-units --type=mount --state=failed --no-legend | grep -q .'
summary
