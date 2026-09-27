#!/usr/bin/env bash
# Etapa 4 — SSH: configuración válida, endurecimiento, claves y SFTP enjaulado
# shellcheck disable=SC2034  # TEST_NAME lo usa summary() de lib.sh
TEST_NAME=test_ssh; source "$(dirname "$0")/lib.sh"; need_root
STAGE="$(lab_stage)"
check "sshd -t (configuración válida)" sshd -t
check "sshd escucha en 22/tcp" bash -c "ss -ltn | grep -q ':22 '"
check "clave de host ed25519 presente" test -f /etc/ssh/ssh_host_ed25519_key
check "~adminlab/.ssh es 700 y authorized_keys 600" bash -c '[[ "$(stat -c %a /home/adminlab/.ssh)" == 700 && "$(stat -c %a /home/adminlab/.ssh/authorized_keys)" == 600 ]]'
check "authorized_keys con contexto SELinux ssh_home_t" bash -c "stat -c %C /home/adminlab/.ssh/authorized_keys | grep -q ':ssh_home_t:'"
if [[ $STAGE -ge 4 ]]; then
  eff() { sshd -T | awk -v k="$1" '$1==k{ $1=""; sub(/^ /,""); print; exit }'; }
  check "PermitRootLogin no" bash -c "[[ \"$(eff permitrootlogin)\" == no ]]"
  check "PasswordAuthentication no" bash -c "[[ \"$(eff passwordauthentication)\" == no ]]"
  check "PubkeyAuthentication yes" bash -c "[[ \"$(eff pubkeyauthentication)\" == yes ]]"
  check "MaxAuthTries 3" bash -c "[[ \"$(eff maxauthtries)\" == 3 ]]"
  check "X11Forwarding no" bash -c "[[ \"$(eff x11forwarding)\" == no ]]"
  check "AllowGroups incluye sysadmins" bash -c "sshd -T | grep -i '^allowgroups' | grep -qw sysadmins"
  check "usuario sftpdemo existe (UID 1005, grupo sftponly)" bash -c '[[ "$(id -u sftpdemo)" == 1005 && "$(id -gn sftpdemo)" == sftponly ]]'
  check "SFTP: jaula /srv/sftp/sftpdemo es de root y modo 755" bash -c '[[ "$(stat -c %U:%a /srv/sftp/sftpdemo)" == root:755 ]]'
  check "SFTP: ChrootDirectory + ForceCommand internal-sftp para sftpdemo" bash -c "sshd -T -C user=sftpdemo,host=lab,addr=10.10.10.1 | grep -Eiq '^forcecommand internal-sftp' && sshd -T -C user=sftpdemo,host=lab,addr=10.10.10.1 | grep -Eiq '^chrootdirectory /srv/sftp/sftpdemo'"
fi
summary
