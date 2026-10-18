#!/usr/bin/env bash
# =============================================================================
# 00-preflight.sh — (siem01) Auditoría de SOLO LECTURA antes de montar el SIEM
#
# No cambia nada. Comprueba lo que, si falta, hace fallar los pasos siguientes
# a mitad de camino: recursos, espacio libre en el VG, SELinux, hora (sin hora
# correcta no hay correlación de eventos), DNS, repositorios y salida a los
# registros de contenedores. Sale con 1 si hay algún FAIL (los WARN se leen).
#
# Uso: lab.sh siem-preflight      (o en siem01: sudo bash 00-preflight.sh)
# =============================================================================
set -uo pipefail          # sin -e: queremos ver TODAS las comprobaciones, no parar en la primera
# shellcheck source=siem-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/siem-lib.sh"
require_root

P=0 W=0 F=0
pass() { printf 'PASS  %s\n' "$*"; P=$((P + 1)); }
warn() { printf 'WARN  %s\n' "$*"; W=$((W + 1)); }
fail() { printf 'FAIL  %s\n' "$*"; F=$((F + 1)); }

echo "== Preflight de la Etapa N2 en $(hostname -f 2>/dev/null || hostname) =="

# --- Identidad y sistema --------------------------------------------------------------
if [[ "$(hostname -s)" == "$SIEM_NAME" ]]; then pass "hostname = $SIEM_NAME"; else fail "hostname = $(hostname -s) (se esperaba $SIEM_NAME)"; fi
if grep -q 'release 9' /etc/redhat-release 2>/dev/null; then pass "$(cat /etc/redhat-release)"; else fail "se esperaba RHEL 9 ($(cat /etc/redhat-release 2>/dev/null))"; fi
if ip -4 -o addr show | grep -q "inet $SIEM_IP/"; then pass "IP $SIEM_IP configurada"; else fail "IP $SIEM_IP no configurada"; fi

# --- Recursos -----------------------------------------------------------------------------
mem_mb=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 ))
if (( mem_mb >= 9000 )); then pass "RAM ${mem_mb} MB"
elif (( mem_mb >= 7500 )); then warn "RAM ${mem_mb} MB: suficiente sin Elasticsearch ni k3s a la vez (recomendado 10 GB)"
else fail "RAM ${mem_mb} MB (mínimo ~8 GB: OpenSearch + Graylog + MongoDB)"; fi
cpus=$(nproc)
if (( cpus >= 4 )); then pass "vCPU: $cpus"; else warn "vCPU: $cpus (recomendado 4)"; fi

# --- Disco: LVs para Docker y k3s (los crea 01-docker-host.sh) ---------------------------
# El kickstart del lab deja /var en 4 GB: Docker y k3s NO caben ahí. Hacen falta LVs propios.
vfree_g=$(vgs --noheadings --units g --nosuffix -o vg_free vg_system 2>/dev/null | awk '{printf "%d", $1}')
have_docker_lv=0; lvs vg_system/lv_docker >/dev/null 2>&1 && have_docker_lv=1
if (( have_docker_lv )); then
  pass "lv_docker ya existe ($(lvs --noheadings --units g -o lv_size vg_system/lv_docker | tr -d ' '))"
elif (( ${vfree_g:-0} >= 46 )); then pass "VG vg_system con ${vfree_g} GB libres (hacen falta 45: lv_docker 35 + lv_rancher 10)"
else fail "VG vg_system con ${vfree_g:-?} GB libres (hacen falta 45 GB; ¿disco de 80 GB en hosts.conf?)"; fi
var_use=$(df --output=pcent /var | tail -1 | tr -dc '0-9')
if (( var_use < 80 )); then pass "/var al ${var_use}%"; else warn "/var al ${var_use}% (los logs de contenedores de k3s van a /var/log/pods)"; fi

# --- Seguridad base y hora --------------------------------------------------------------
if [[ "$(getenforce)" == Enforcing ]]; then pass "SELinux Enforcing"; else warn "SELinux $(getenforce): el lab trabaja en Enforcing (Etapa 5)"; fi
if systemctl is-active --quiet firewalld; then pass "firewalld activo"; else warn "firewalld inactivo"; fi
if chronyc tracking 2>/dev/null | grep -q 'Leap status *: Normal'; then
  pass "chrony sincronizado ($(chronyc tracking | awk -F': ' '/Reference ID/ {print $2}'))"
else
  fail "chrony sin sincronizar: un SIEM con la hora mal ordena y correlaciona mal los eventos (lab.sh stage4-clients siem01)"
fi
tz="$(timedatectl show -p Timezone --value 2>/dev/null)"
pass "zona horaria: ${tz:-?} (Graylog guarda en UTC y muestra en la zona del usuario)"

# --- DNS --------------------------------------------------------------------------------
# Dos comprobaciones distintas (caso troubleshooting etapaN2/02):
#  1) dig @dns01: lo que publica la zona lab.local, sin cachés ni /etc/hosts.
#  2) getent ahostsv4: lo que resuelve el propio sistema (NSS), SOLO IPv4.
# No se usa 'getent hosts': devuelve primero la IPv6 si existe, y en el propio
# siem01 nss-myhostname responde con su fe80:: -> la comparación con la IPv4 fallaba.
fqdn="$SIEM_NAME.lab.local"
if dig +short "$fqdn" A @10.10.10.20 2>/dev/null | grep -Fxq "$SIEM_IP"; then pass "DNS (dns01): $fqdn -> $SIEM_IP"
else fail "DNS (dns01): $fqdn no resuelve a $SIEM_IP (lab.sh stage4-dns con las plantillas nuevas)"; fi
if getent ahostsv4 "$fqdn" 2>/dev/null | awk '{print $1}' | grep -Fxq "$SIEM_IP"; then pass "DNS (sistema): $fqdn -> $SIEM_IP"
else fail "DNS (sistema): $fqdn no resuelve a $SIEM_IP por NSS (revisar /etc/resolv.conf y /etc/hosts)"; fi
if [[ "$(dig +short -x "$SIEM_IP" @10.10.10.20 2>/dev/null)" == "$SIEM_NAME.lab.local." ]]; then pass "DNS inverso de $SIEM_IP"
else warn "falta el PTR de $SIEM_IP (los eventos mostrarían la IP en vez del nombre)"; fi

# --- Paquetes y salida a Internet ---------------------------------------------------------
if dnf -q repolist --enabled 2>/dev/null | grep -qi baseos; then pass "repositorio BaseOS habilitado"
else fail "sin repositorios de RHEL (lab.sh register siem01 <usuario>)"; fi
for url in https://download.docker.com/linux/rhel/docker-ce.repo https://registry-1.docker.io/v2/ https://get.k3s.io; do
  code="$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$url" 2>/dev/null)"
  if [[ "$code" =~ ^(200|301|302|401)$ ]]; then pass "salida a $url (HTTP $code)"; else fail "sin salida a $url (HTTP ${code:-000})"; fi
done

# --- Conflictos conocidos ---------------------------------------------------------------
if rpm -q podman runc >/dev/null 2>&1; then
  warn "podman/runc instalados: chocan con containerd.io (01-docker-host.sh los retira)"
else pass "sin podman/runc (no chocan con Docker CE)"; fi
if ss -ltnu | grep -Eq ':(9000|5140|12201) '; then warn "ya hay algo escuchando en 9000, 5140 o 12201 (ss -ltnup)"; else pass "puertos 9000/5140/12201 libres"; fi

echo "--- preflight: $P PASS, $W WARN, $F FAIL"
[[ $F -eq 0 ]]
