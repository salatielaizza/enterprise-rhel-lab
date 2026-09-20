#!/usr/bin/env bash
# =============================================================================
# collect-facts.sh — Recoge DATOS REALES de la VM en formato CLAVE=valor
# (solo lectura; no modifica nada). Alimenta comparison/matrix.generated.md.
# Uso (root): lab.sh facts <host|all>
# =============================================================================
set -u
first() { "$@" 2>/dev/null | head -n1; }
kv() { printf '%s=%s\n' "$1" "$2"; }

. /etc/os-release
kv HOSTNAME "$(hostname -s)"
kv OS_PRETTY "$PRETTY_NAME"
kv OS_VERSION "$VERSION_ID"
kv KERNEL "$(uname -r)"
kv ARCH "$(uname -m)"
kv INIT "$(first systemctl --version)"
kv GLIBC "$(first ldd --version)"
if command -v dnf >/dev/null; then kv PKGMGR "$(first dnf --version) [dnf]"; else kv PKGMGR "$(first yum --version) [yum]"; fi
kv RPM "$(first rpm --version)"
kv PYTHON_DEFAULT "$( (python --version 2>&1 || echo 'no hay /usr/bin/python') | head -n1)"
kv PYTHON3 "$( (python3 --version 2>&1 || echo 'no hay python3') | head -n1)"
kv PLATFORM_PYTHON "$(/usr/libexec/platform-python --version 2>&1 | head -n1 || true)"
kv NETWORKMANAGER "$(first NetworkManager --version)"
if [[ -d /etc/sysconfig/network-scripts ]] && ls /etc/sysconfig/network-scripts/ifcfg-* >/dev/null 2>&1; then
  kv NM_PROFILE_FORMAT "ifcfg (/etc/sysconfig/network-scripts)"
elif ls /etc/NetworkManager/system-connections/*.nmconnection >/dev/null 2>&1; then
  kv NM_PROFILE_FORMAT "keyfile (/etc/NetworkManager/system-connections)"
else
  kv NM_PROFILE_FORMAT "desconocido"
fi
kv NETWORK_SERVICE "$(systemctl is-enabled network 2>&1 | head -n1)"
kv NETTOOLS "$(command -v ifconfig >/dev/null && echo 'ifconfig presente' || echo 'ifconfig ausente')"
kv FIREWALLD "$(first firewall-cmd --version)"
kv FIREWALL_BACKEND "$(grep -h '^FirewallBackend' /etc/firewalld/firewalld.conf 2>/dev/null | head -n1 || true)"
kv SELINUX "$(getenforce 2>/dev/null)"
kv SSH "$(ssh -V 2>&1 | head -n1)"
kv TIMESYNC "$(first chronyd --version)"
kv NTPD_INSTALLED "$(rpm -q ntp 2>&1 | head -n1)"
kv ROOT_FS "$(findmnt -no FSTYPE /)"
kv LVM "$(lvm version 2>/dev/null | awk '/LVM version/{print $3}')"
kv XFSPROGS "$(rpm -q xfsprogs 2>&1 | head -n1)"
kv LOG_DAEMON "$(rpm -q rsyslog 2>&1 | head -n1)"
kv JOURNAL_PERSISTENT "$([[ -d /var/log/journal ]] && echo si || echo 'no (volatil)')"
kv BOOT_MODE "$([[ -d /sys/firmware/efi ]] && echo UEFI || echo BIOS)"
kv BOOTLOADER "$(rpm -q grub2-pc 2>&1 | head -n1)"
kv CGROUP "$(stat -fc %T /sys/fs/cgroup 2>/dev/null)"
kv CRYPTO_POLICY "$(update-crypto-policies --show 2>/dev/null || echo 'no aplica')"
kv CPU_FLAGS_V3 "$(grep -qw avx2 /proc/cpuinfo && echo 'avx2 presente' || echo 'sin avx2')"
kv SUBSCRIPTION "$(subscription-manager status 2>/dev/null | awk -F': ' '/Overall Status/{print $2}')"
kv REPOS "$( (dnf repolist 2>/dev/null || yum repolist 2>/dev/null) | awk 'NR>1 && NF{print $1}' | grep -v -E '^(repo|Loaded|Loading|Repo|This|Last)' | tr '\n' ' ')"
