# =============================================================================
# Kickstart RHEL 8.10 — enterprise-rhel-lab
# Renderizado por scripts/02-create-vm.sh (envsubst). Las variables ${LAB_*} se
# sustituyen al crear la VM; las contraseñas NUNCA se guardan en el repositorio.
# Cada línea equivale a una pantalla de Anaconda (ver rhel8/installation.md).
# =============================================================================
cdrom
text
lang en_US.UTF-8
keyboard --vckeymap=es --xlayouts='es'
timezone ${LAB_TZ} --utc
rootpw --iscrypted ${LAB_ROOT_HASH}
user --name=adminlab --uid=1001 --gecos="Lab administrator" --groups=wheel --iscrypted --password=${LAB_ADMIN_HASH}
selinux --enforcing
firewall --enabled --service=ssh
network --bootproto=static --device=link --ip=${LAB_IP} --netmask=255.255.255.0 --gateway=${LAB_GW} --nameserver=${LAB_DNS} --hostname=${LAB_HOSTNAME} --onboot=yes --activate
firstboot --disable
eula --agreed
skipx
services --enabled=sshd,chronyd,qemu-guest-agent

# --- Disco: vda = sistema (LVM+XFS); vdb (datos) NO se toca: lo usa la Etapa 2 ---
ignoredisk --only-use=vda
zerombr
clearpart --all --initlabel --drives=vda
bootloader --location=mbr --boot-drive=vda --append="console=tty0 console=ttyS0,115200n8"
part /boot --fstype=xfs --size=1024 --ondisk=vda
part pv.01 --size=1 --grow --ondisk=vda
volgroup vg_system pv.01
logvol /     --vgname=vg_system --name=lv_root --fstype=xfs  --size=8192
logvol swap  --vgname=vg_system --name=lv_swap --fstype=swap --size=2048
logvol /var  --vgname=vg_system --name=lv_var  --fstype=xfs  --size=4096
poweroff

%packages --ignoremissing
@^minimal-environment
chrony
firewalld
NetworkManager-tui
net-tools
bind-utils
tcpdump
traceroute
lsof
psmisc
rsync
tar
wget
curl
nmap-ncat
sysstat
acl
lvm2
xfsprogs
e2fsprogs
qemu-guest-agent
policycoreutils-python-utils
yum-utils
bash-completion
vim-enhanced
tree
strace
less
man-pages
%end

%post --log=/root/ks-post.log
set -x
install -d -m 0700 -o adminlab -g adminlab /home/adminlab/.ssh
cat > /home/adminlab/.ssh/authorized_keys <<'KEYEOF'
${LAB_SSH_PUBKEY}
KEYEOF
chown adminlab:adminlab /home/adminlab/.ssh/authorized_keys
chmod 0600 /home/adminlab/.ssh/authorized_keys
restorecon -R /home/adminlab/.ssh || true

# sudo de ARRANQUE: lo sustituye la Etapa 2 (scripts/stage2/04-sudo.sh)
cat > /etc/sudoers.d/90-adminlab-bootstrap <<'SUDOEOF'
adminlab ALL=(ALL) NOPASSWD: ALL
SUDOEOF
chmod 0440 /etc/sudoers.d/90-adminlab-bootstrap

cat > /etc/lab-release <<'LABEOF'
LAB_HOSTNAME=${LAB_HOSTNAME}
LAB_STAGE=1
LABEOF
%end
