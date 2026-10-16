#!/usr/bin/env bash
# =============================================================================
# 30-vm-convert.sh — (HOST) Exportar, convertir e importar VMs entre KVM y VMware
#
# Nunca modifica la VM original: trabaja sobre una COPIA de su disco.
#
#   export <vm> [--format sparse|stream] [--no-prep]
#       1. Exige la VM apagada (un disco en uso copiado "en caliente" queda inconsistente).
#       2. qemu-img convert qcow2 -> copia de trabajo qcow2.
#       3. Preparación para VMware sobre la copia (virt-customize, sin arrancarla):
#          initramfs genérico (dracut --no-hostonly: incluye drivers de VMware, no solo virtio),
#          perfiles de NetworkManager no atados a un nombre de interfaz (virtio "enp1s0" pasa a
#          ser vmxnet3 "ens192"), y virt-sysprep (machine-id, claves SSH de host, MAC).
#       4. qemu-img convert -> VMDK:
#            sparse (monolithicSparse): para subir a un datastore y convertir con vmkfstools -i
#            stream (streamOptimized):  el formato de los OVA/OVF (compacto, para distribuir)
#       5. qemu-img check/info + SHA-256 (integridad al copiar entre sistemas).
#
#   import <fichero.vmdk|.ova|.qcow2> <nombre-nuevo> [--keep-network]
#       virt-v2v (-i disk / -i ova) -> VM nueva en libvirt (pool lab-images): convierte los drivers
#       del invitado a virtio. Queda DEFINIDA, APAGADA y SIN RED (la copia tiene la IP del original:
#       arrancarla en lab-net con el original encendido = IP duplicada). --keep-network la deja con red.
#
#   inspect <fichero>    qemu-img info + virt-inspector (SO, paquetes y discos de la imagen)
#
#   Opciones comunes: --dry-run (enseña los comandos sin ejecutarlos)
#   Salida: $LAB_EXPORT_DIR (por defecto ~/lab-export)
#
# Herramientas del host (Linux Mint): sudo apt install qemu-utils libguestfs-tools virt-v2v
# =============================================================================
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

EXPORT_DIR="${LAB_EXPORT_DIR:-$HOME/lab-export}"
DRY=0
run() { if [[ $DRY -eq 1 ]]; then printf '[dry-run] %s\n' "$*"; else "$@"; fi; }

usage() { sed -n '3,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

disk_of() {  # disk_of VM -> ruta del primer disco (vda)
  virsh domblklist "$1" --details | awk '$2=="disk" {print $4; exit}'
}

cmd_export() {
  local vm="" fmt=sparse prep=1 a
  while [[ $# -gt 0 ]]; do
    a="$1"; shift
    case "$a" in
      --format) fmt="${1:?--format sparse|stream}"; shift ;;
      --no-prep) prep=0 ;;
      --dry-run) DRY=1 ;;
      -*) die "Opción desconocida: $a" ;;
      *) vm="$a" ;;
    esac
  done
  [[ -n "$vm" ]] || die "Uso: 30-vm-convert.sh export <vm> [--format sparse|stream] [--no-prep] [--dry-run]"
  case "$fmt" in sparse) subfmt=monolithicSparse ;; stream) subfmt=streamOptimized ;; *) die "--format: sparse o stream" ;; esac
  need virsh; need qemu-img
  if [[ $prep -eq 1 ]]; then need virt-customize; need virt-sysprep; fi

  virsh dominfo "$vm" >/dev/null 2>&1 || die "No existe la VM $vm"
  local state; state="$(virsh domstate "$vm" | tr -d '[:space:]')"
  if [[ "$state" != "shutoff" ]]; then
    die "$vm está '$state': apágala antes (lab.sh down $vm). Copiar un disco en uso da una copia inconsistente."
  fi
  local src; src="$(disk_of "$vm")"
  [[ -n "$src" ]] || die "No se encontró el disco de $vm (virsh domblklist $vm --details)"

  local out="$EXPORT_DIR/$vm" work vmdk
  work="$out/$vm-work.qcow2"; vmdk="$out/$vm-$fmt.vmdk"
  run mkdir -p "$out"
  info "1/5 Copia de trabajo del disco ($src -> $work)"
  # El disco del pool es de root/libvirt-qemu: la lectura necesita sudo; el resultado se deja a tu usuario
  run sudo qemu-img convert -p -O qcow2 "$src" "$work"
  run sudo chown "$(id -u):$(id -g)" "$work"

  if [[ $prep -eq 1 ]]; then
    info "2/5 Preparación para VMware sobre la copia (virt-customize; tarda unos minutos)"
    # dracut --no-hostonly: initramfs con todos los drivers de almacenamiento (vmw_pvscsi, mptspi, ahci...)
    # sed: quita interface-name= de los perfiles de NetworkManager (keyfile) para que el perfil
    #      se aplique a la NIC nueva (vmxnet3 se llama distinto que virtio)
    run virt-customize -a "$work" \
      --run-command 'dracut -f --no-hostonly --regenerate-all' \
      --run-command 'sed -i "/^interface-name=/d" /etc/NetworkManager/system-connections/*.nmconnection 2>/dev/null || true' \
      --selinux-relabel
    info "3/5 virt-sysprep: machine-id, claves SSH de host, MAC y logs (identidad nueva)"
    run virt-sysprep -a "$work" --operations machine-id,ssh-hostkeys,net-hwaddr,udev-persistent-net,logfiles,tmp-files
  else
    info "2-3/5 Preparación omitida (--no-prep): en ESXi puede no arrancar (initramfs solo con virtio)"
  fi

  info "4/5 qcow2 -> VMDK ($subfmt)"
  run qemu-img convert -p -O vmdk -o "subformat=$subfmt,adapter_type=lsilogic" "$work" "$vmdk"
  info "5/5 Comprobación e integridad"
  run qemu-img info "$vmdk"
  if [[ $DRY -eq 0 ]]; then
    ( cd "$out" && sha256sum "$(basename "$vmdk")" > "$(basename "$vmdk").sha256" )
    ok "VMDK listo: $vmdk ($(du -h "$vmdk" | cut -f1) en disco; tamaño virtual $(qemu-img info --output=json "$vmdk" | python3 -c 'import json,sys; print(json.load(sys.stdin)["virtual-size"]//2**30, "GiB")'))"
    info "Copia de trabajo conservada para repetir la conversión: $work (bórrala cuando acabes)"
  fi
  echo
  if [[ "$fmt" == sparse ]]; then
    cat <<EOF
  Siguiente, por SSH a un ESXi (vale el gratuito esxi01; guía siem/etapaN2-siem.md, bloque 7):
    scp -i ~/.ssh/lab_esxi_rsa $vmdk root@esxi01:/vmfs/volumes/datastore1/
    ssh -i ~/.ssh/lab_esxi_rsa root@esxi01 "mkdir -p /vmfs/volumes/datastore1/$vm-conv && \\
      vmkfstools -i /vmfs/volumes/datastore1/$(basename "$vmdk") -d thin /vmfs/volumes/datastore1/$vm-conv/$vm-conv.vmdk"
  Después: Host Client > Crear VM > disco existente ($vm-conv.vmdk), controladora LSI Logic o PVSCSI, NIC VMXNET 3.
EOF
  else
    cat <<EOF
  Siguiente, por la API de vSphere (vCenter o ESXi en evaluación; el gratuito la tiene en solo lectura):
    govc import.vmdk -ds=<datastore> $vmdk $vm-conv
  streamOptimized es también el formato de disco de los paquetes OVA/OVF.
EOF
  fi
}

cmd_import() {
  local file="" name="" keepnet=0 a
  while [[ $# -gt 0 ]]; do
    a="$1"; shift
    case "$a" in
      --keep-network) keepnet=1 ;;
      --dry-run) DRY=1 ;;
      -*) die "Opción desconocida: $a" ;;
      *) if [[ -z "$file" ]]; then file="$a"; else name="$a"; fi ;;
    esac
  done
  [[ -n "$file" && -n "$name" ]] || die "Uso: 30-vm-convert.sh import <fichero.vmdk|.ova|.qcow2> <nombre-nuevo> [--keep-network] [--dry-run]"
  [[ -f "$file" ]] || die "No existe $file"
  need virt-v2v; need virsh
  if virsh dominfo "$name" >/dev/null 2>&1; then die "Ya existe una VM llamada $name"; fi
  if host_row "$name" >/dev/null 2>&1; then die "$name es un nombre del inventario del lab: usa otro (p. ej. ${name}-conv)"; fi
  if [[ -f "$file.sha256" && $DRY -eq 0 ]]; then
    ( cd "$(dirname "$file")" && sha256sum -c "$(basename "$file").sha256" ) || die "SHA-256 no coincide: fichero dañado en la copia"
  fi
  local input=disk
  case "$file" in *.ova) input=ova ;; esac
  info "virt-v2v -i $input -> libvirt ($name, pool lab-images)"
  run virt-v2v -i "$input" "$file" -o libvirt -oc "$LIBVIRT_URI" -os lab-images -on "$name"
  if [[ $keepnet -eq 0 ]]; then
    info "Quitando las NIC de $name (evita IP duplicada con el original)"
    run virt-xml "$name" --remove-device --network all
  else
    warn "$name conserva la red: NO la arranques con el original encendido (misma IP)"
  fi
  ok "Importada: $name (apagada). Arranque de prueba: virsh start $name && virsh console $name"
}

cmd_inspect() {
  local f="${1:?Uso: 30-vm-convert.sh inspect <fichero>}"
  need qemu-img
  qemu-img info "$f"
  if command -v virt-inspector >/dev/null; then
    virt-inspector -a "$f" 2>/dev/null | python3 -c '
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.stdin).getroot()
for os_ in r.findall("operatingsystem"):
    print("SO:", os_.findtext("product_name"), "| arquitectura:", os_.findtext("arch"), "| hostname:", os_.findtext("hostname"))
    print("Paquetes:", len(os_.findall("applications/application")))
' || warn "virt-inspector no pudo leer la imagen (¿/boot/vmlinuz-* legible? ver la guía)"
  fi
}

sub="${1:-}"; shift || true
case "$sub" in
  export)  cmd_export "$@" ;;
  import)  cmd_import "$@" ;;
  inspect) cmd_inspect "$@" ;;
  -h|--help|help|"") usage 0 ;;
  *) usage 1 ;;
esac
