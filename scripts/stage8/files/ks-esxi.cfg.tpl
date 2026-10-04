# =============================================================================
# Kickstart de ESXi 8 — enterprise-rhel-lab, Etapa 8
# Lo renderiza scripts/stage8/01-esxi-iso.sh (envsubst, SOLO las variables ${ESX_*}
# y ${LAB_*} listadas en el script) y lo mete en el ISO como /KS.CFG.
# El hash de root y la clave pública se sustituyen al construir el ISO: NUNCA van
# al repositorio. El ISO resultante sí los contiene: no lo compartas.
#
# Cada línea equivale a una pantalla del instalador interactivo de ESXi (ver
# virtualization/esxi.md cuando exista). Validar primero a mano (fase 2) y después
# con este fichero (fase 5).
# =============================================================================
vmaccepteula

# Disco 1 (SATA, ${ESX_BOOT_GB} GB) = sistema. --novmfsondisk: NO crea datastore en el disco
# de arranque; el datastore local va en el disco 2 (ver %firstboot), si el host lo tiene.
install --firstdisk --overwritevmfs --novmfsondisk

network --bootproto=static --device=vmnic0 --ip=${ESX_IP} --netmask=255.255.255.0 --gateway=${LAB_GW} --nameserver=${LAB_DNS_SERVER} --hostname=${ESX_FQDN} --addvmportgroup=1

rootpw --iscrypted ${ESX_ROOT_HASH}
keyboard 'Spanish'
reboot

%firstboot --interpreter=busybox
# Se ejecuta UNA vez, en el primer arranque tras instalar. Registro en /var/log/lab-firstboot.log
exec >/var/log/lab-firstboot.log 2>&1
set -x

# 1) Identidad, DNS y hora (vCenter exige DNS directo/inverso y hora coherente con dns01)
esxcli system hostname set --fqdn=${ESX_FQDN}
esxcli network ip dns search add --domain=${LAB_DOMAIN}
esxcli system ntp set --server=${LAB_DNS_SERVER} --enabled=true

# 2) SSH y shell de ESXi (SOLO laboratorio: en producción se dejan desactivados)
vim-cmd hostsvc/enable_ssh
vim-cmd hostsvc/start_ssh
vim-cmd hostsvc/enable_esx_shell
vim-cmd hostsvc/start_esx_shell
esxcli system settings advanced set -o /UserVars/SuppressShellWarning -i 1

# 3) Clave pública del host del lab para root (RSA: el sshd de ESXi 8 va en modo FIPS)
cat > /etc/ssh/keys-root/authorized_keys <<'KEYEOF'
${ESX_SSH_PUBKEY}
KEYEOF
chmod 600 /etc/ssh/keys-root/authorized_keys

# 4) ESXi ANIDADO: sin esto las VMs de dentro no tienen red (sus MAC no son las de la NIC de KVM)
esxcli network vswitch standard policy security set --vswitch-name=vSwitch0 \
  --allow-promiscuous=true --allow-forged-transmits=true --allow-mac-change=true

# 5) vMotion por vmnic1 en su propia pila TCP/IP 'vmotion' (solo hosts con 2 NICs)
if [ "${ESX_NICS}" -ge 2 ] && [ "${ESX_VMOTION_IP}" != "-" ]; then
  esxcli network vswitch standard add --vswitch-name=vSwitch1
  esxcli network vswitch standard uplink add --uplink-name=vmnic1 --vswitch-name=vSwitch1
  esxcli network vswitch standard policy security set --vswitch-name=vSwitch1 \
    --allow-promiscuous=true --allow-forged-transmits=true --allow-mac-change=true
  esxcli network vswitch standard portgroup add --portgroup-name=vMotion --vswitch-name=vSwitch1
  esxcli network ip netstack add --netstack=vmotion
  esxcli network ip interface add --interface-name=vmk1 --portgroup-name=vMotion --netstack=vmotion
  esxcli network ip interface ipv4 set --interface-name=vmk1 --type=static \
    --ipv4=${ESX_VMOTION_IP} --netmask=255.255.255.0
fi

# 6) Datastore local VMFS6 en el disco 2 (solo si el host tiene disco de datos).
#    Se elige el ÚNICO disco sin particiones; si hay dudas, no se toca nada.
if [ "${ESX_DATA_GB}" -gt 0 ]; then
  DISK=""
  for d in $(ls /vmfs/devices/disks/ | grep -v ':' | grep -v '^vml'); do
    nparts=$(partedUtil getptbl "/vmfs/devices/disks/$d" 2>/dev/null | tail -n +3 | wc -l)
    if [ "$nparts" -eq 0 ]; then
      if [ -n "$DISK" ]; then echo "Más de un disco vacío: no se crea el datastore"; DISK=""; break; fi
      DISK="$d"
    fi
  done
  if [ -n "$DISK" ]; then
    partedUtil mklabel "/vmfs/devices/disks/$DISK" gpt
    END=$(partedUtil getUsableSectors "/vmfs/devices/disks/$DISK" | awk '{print $2}')
    partedUtil setptbl "/vmfs/devices/disks/$DISK" gpt "1 2048 $END AA31E02A400F11DB9590000C2911D1B8 0"
    vmkfstools -C vmfs6 -S datastore-${ESX_SHORT} "/vmfs/devices/disks/$DISK:1"
  fi
fi

echo "lab-firstboot: terminado"
