#!/usr/bin/env bash
# Etapa 2 — Permisos: propietarios, modos, setgid/sticky, ACL y acceso funcional
# shellcheck disable=SC2034  # TEST_NAME lo usa summary() de lib.sh
TEST_NAME=test_permissions; source "$(dirname "$0")/lib.sh"; need_root
dirs=( "/opt/application:appuser:application:2750" "/opt/application/config:root:application:2750"
       "/opt/application/data:appuser:application:2770" "/backup:root:backup:3770"
       "/var/log/lab-app:appuser:application:2770" )
for d in "${dirs[@]}"; do
  IFS=: read -r path owner group mode <<<"$d"
  check "$path = $owner:$group modo $mode" bash -c "[[ \"\$(stat -c %U:%G:%a $path)\" == $owner:$group:$mode ]]"
done
check "setgid activo en /opt/application/data" test -g /opt/application/data
check "sticky bit activo en /backup" test -k /backup
check "ACL: developers r-x en config" bash -c "getfacl -p /opt/application/config | grep -q '^group:developers:r-x'"
check "ACL por defecto: developers r-x en config (herencia)" bash -c "getfacl -p /opt/application/config | grep -q '^default:group:developers:r-x'"
check "lab-app.env es 0640 root:application" bash -c '[[ "$(stat -c %U:%G:%a /opt/application/config/lab-app.env)" == root:application:640 ]]'
check "developers PUEDEN leer lab-app.env (ACL)" su -s /bin/bash -c 'test -r /opt/application/config/lab-app.env' devuser
check "developers NO pueden escribir en config" bash -c "! su -s /bin/bash -c 'test -w /opt/application/config' devuser"
check "appuser PUEDE escribir en data" su -s /bin/bash -c 'f=/opt/application/data/.t.$$; touch "$f" && rm -f "$f"' appuser
check "backupuser PUEDE escribir en /backup" su -s /bin/bash -c 'f=/backup/.t.$$; touch "$f" && rm -f "$f"' backupuser
check "un usuario ajeno (nobody) NO entra en /opt/application" bash -c "! su -s /bin/bash -c 'ls /opt/application' nobody"
check "contexto SELinux de lab-app.sh = bin_t" bash -c "stat -c %C /opt/application/bin/lab-app.sh | grep -q ':bin_t:'"
check "contexto SELinux de /backup sin 'unlabeled_t'" bash -c "! stat -c %C /backup | grep -q unlabeled_t"
summary
