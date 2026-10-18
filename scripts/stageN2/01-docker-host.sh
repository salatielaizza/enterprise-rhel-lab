#!/usr/bin/env bash
# =============================================================================
# 01-docker-host.sh — (siem01) Prepara el host de contenedores del SIEM
#
#   1. LVs propios para /var/lib/docker (35 GB) y /var/lib/rancher (10 GB, k3s):
#      el kickstart del lab deja /var en 4 GB y un SIEM lo llenaría en horas.
#      Montaje por UUID en fstab + restorecon (SELinux etiqueta el FS nuevo).
#   2. Docker CE desde el repositorio oficial de Docker para RHEL (retira antes
#      podman/runc, que chocan con containerd.io).
#   3. /etc/docker/daemon.json: rotación de logs de contenedores, SELinux activo
#      en los contenedores, live-restore (reiniciar dockerd no tumba el SIEM) y
#      driver overlay2 en /var/lib/docker (sin containerd image store: caso etapaN2/03).
#   4. vm.max_map_count=262144 (requisito de OpenSearch/Elasticsearch).
#
# Idempotente: se puede relanzar. Copia de seguridad de fstab y daemon.json.
# Uso: lab.sh siem-docker
# =============================================================================
set -euo pipefail
# shellcheck source=siem-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/siem-lib.sh"
require_root
require_host "$SIEM_NAME"

VG=vg_system
ADMIN_USER=adminlab

# --- 1) Almacenamiento ------------------------------------------------------------------
# mk_lv NOMBRE TAMAÑO PUNTO_DE_MONTAJE
mk_lv() {
  local lv="$1" size="$2" mnt="$3" dev uuid
  dev="/dev/$VG/$lv"
  if ! lvs "$VG/$lv" >/dev/null 2>&1; then
    lvcreate -y -n "$lv" -L "$size" "$VG" >/dev/null
    mkfs.xfs -q "$dev"            # XFS con ftype=1 (por defecto en RHEL 9): lo exige overlay2
    say "LV $VG/$lv ($size) creado y formateado en XFS"
  fi
  uuid="$(blkid -s UUID -o value "$dev")"
  mkdir -p "$mnt"
  if ! grep -q "UUID=$uuid" /etc/fstab; then
    backup /etc/fstab
    printf 'UUID=%s %s xfs defaults 0 0\n' "$uuid" "$mnt" >> /etc/fstab
    systemctl daemon-reload       # systemd genera las unidades .mount desde fstab
    say "fstab: $mnt por UUID"
  fi
  if ! mountpoint -q "$mnt"; then mount "$mnt"; fi
  restorecon -R "$mnt"            # sin esto el FS nuevo queda con una etiqueta que Docker/k3s no pueden usar
}
mk_lv lv_docker 35G /var/lib/docker
mk_lv lv_rancher 10G /var/lib/rancher
say "Almacenamiento: $(df -h --output=target,size,avail /var/lib/docker /var/lib/rancher | tail -n +2 | tr -s ' ' | paste -sd ';')"

# --- 2) Docker CE -----------------------------------------------------------------------
if rpm -q podman runc >/dev/null 2>&1; then
  say "Retirando podman/runc (chocan con containerd.io)"
  dnf remove -y podman runc >/dev/null
fi
if ! rpm -q docker-ce >/dev/null 2>&1; then
  dnf install -y dnf-plugins-core >/dev/null
  if [[ ! -f /etc/yum.repos.d/docker-ce.repo ]]; then
    dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
  fi
  say "Instalando Docker CE (docker-ce, containerd.io, buildx, compose)"
  dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
fi
# container-selinux (dependencia de docker-ce) trae las reglas de etiquetado de /var/lib/docker:
# se vuelve a aplicar ahora que existen (la primera pasada, antes de instalar, deja var_lib_t)
restorecon -R /var/lib/docker
if [[ "$(stat -c %C /var/lib/docker)" != *container_var_lib_t* ]]; then
  warnmsg "/var/lib/docker sin container_var_lib_t: revisa 'ls -Zd /var/lib/docker'"
fi

# --- 3) daemon.json -----------------------------------------------------------------------
install -d -m 0755 /etc/docker
DAEMON_JSON=/etc/docker/daemon.json
NEW_JSON="$(mktemp)"
trap 'rm -f "$NEW_JSON"' EXIT
# containerd-snapshotter=false (caso troubleshooting etapaN2/03): desde Docker 29 las instalaciones
# nuevas usan el "containerd image store" y las capas de las imágenes van a /var/lib/containerd,
# que está en /var (4 GB) y NO en lv_docker -> "no space left on device" al descargar OpenSearch.
# Con false, Docker vuelve al driver clásico overlay2 y todo queda en /var/lib/docker (lv_docker).
cat > "$NEW_JSON" <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "selinux-enabled": true,
  "live-restore": true,
  "features": { "containerd-snapshotter": false }
}
EOF
python3 -m json.tool "$NEW_JSON" >/dev/null || fatal "daemon.json generado no es JSON válido"
if ! cmp -s "$NEW_JSON" "$DAEMON_JSON" 2>/dev/null; then
  backup "$DAEMON_JSON"
  install -m 0644 "$NEW_JSON" "$DAEMON_JSON"
  say "daemon.json actualizado (rotación de logs, SELinux, live-restore, overlay2 en /var/lib/docker)"
  systemctl restart docker 2>/dev/null || true
fi
systemctl enable --now docker >/dev/null
docker info --format '{{.ServerVersion}} {{.Driver}} {{.DockerRootDir}}' | { read -r v d r; say "Docker $v, storage driver $d, raíz $r"; }
drv="$(docker info --format '{{.Driver}}')"
if [[ "$drv" != overlay2 ]]; then
  warnmsg "storage driver '$drv' (se esperaba overlay2): las imágenes no irían a lv_docker sino a /var/lib/containerd"
fi
docker info --format '{{.SecurityOptions}}' | grep -q selinux || warnmsg "Docker no informa de SELinux en SecurityOptions"

# Grupo docker = equivalente a root en este host (puede montar / en un contenedor).
# En el lab se acepta para adminlab; en producción se limita y se audita (o se usa Podman rootless).
if ! id -nG "$ADMIN_USER" | grep -qw docker; then
  usermod -aG docker "$ADMIN_USER"
  say "$ADMIN_USER añadido al grupo docker (cierra la sesión y vuelve a entrar)"
fi

# --- 4) Kernel ------------------------------------------------------------------------------
SYSCTL=/etc/sysctl.d/90-siem.conf
if [[ "$(cat "$SYSCTL" 2>/dev/null)" != "vm.max_map_count = 262144" ]]; then
  backup "$SYSCTL"
  echo "vm.max_map_count = 262144" > "$SYSCTL"
  sysctl -q -p "$SYSCTL"
  say "vm.max_map_count = $(sysctl -n vm.max_map_count)"
fi

say "Host de contenedores listo. Siguiente: lab.sh siem-stack"
