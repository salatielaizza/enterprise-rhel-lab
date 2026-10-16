#!/usr/bin/env bash
# =============================================================================
# 04-k3s-fluentbit.sh — (siem01) Kubernetes de un nodo (k3s) que envía sus logs al SIEM
#
#   1. k3s (canal stable) con SELinux activo (--selinux; el instalador añade k3s-selinux)
#      y sin Traefik (no hace falta ingress aquí y ahorra RAM). El instalador se descarga,
#      se guarda y se registra su SHA-256 antes de ejecutarlo: nada de 'curl | sh' a ciegas.
#   2. firewalld: redes de pods (10.42.0.0/16) y servicios (10.43.0.0/16) en la zona trusted.
#   3. kubeconfig para adminlab (~/.kube/config, 0600).
#   4. Fluent Bit (DaemonSet) -> Graylog GELF TCP y la app de ejemplo pagos-demo.
#   5. Comprueba que los logs del pod llegan a OpenSearch con sus metadatos de Kubernetes.
#
# Idempotente. Uso: lab.sh siem-k8s
# =============================================================================
set -euo pipefail
# shellcheck source=siem-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/siem-lib.sh"
require_root
require_host "$SIEM_NAME"

ADMIN_USER=adminlab
KUBECTL=/usr/local/bin/kubectl
mountpoint -q /var/lib/rancher || fatal "/var/lib/rancher no es un LV propio: ejecuta antes 'lab.sh siem-docker'"
[[ -x "$SIEM_DIR/tools/os_search.py" ]] || fatal "Falta el SIEM: ejecuta antes 'lab.sh siem-stack' y 'lab.sh siem-inputs'"

# --- 1) k3s -------------------------------------------------------------------------------
if ! systemctl is-active --quiet k3s; then
  installer="$SIEM_SECRETS/k3s-install.sh"
  install -d -m 0700 "$SIEM_SECRETS"
  curl -sfL https://get.k3s.io -o "$installer" || fatal "No se pudo descargar el instalador de k3s"
  say "Instalador de k3s descargado: sha256 $(sha256sum "$installer" | cut -c1-16)… (guardado en $installer)"
  INSTALL_K3S_CHANNEL=stable \
  INSTALL_K3S_EXEC="server --selinux --disable traefik --write-kubeconfig-mode 0600" \
    sh "$installer"
fi
restorecon -R /var/lib/rancher      # k3s-selinux trae las etiquetas de /var/lib/rancher (LV propio)
wait_for 180 "nodo de Kubernetes Ready" bash -c "$KUBECTL get nodes --no-headers 2>/dev/null | grep -qw Ready" \
  || fatal "El nodo no pasa a Ready (journalctl -u k3s -n 50)"
say "k3s: $($KUBECTL version 2>/dev/null | awk -F': ' '/Server Version/ {print $2}') · $($KUBECTL get nodes --no-headers | awk '{print $1, $2}')"

# --- 2) firewalld -------------------------------------------------------------------------
if systemctl is-active --quiet firewalld; then
  changed=0
  for net in 10.42.0.0/16 10.43.0.0/16; do
    if ! firewall-cmd --permanent --zone=trusted --query-source="$net" >/dev/null 2>&1; then
      firewall-cmd --permanent --zone=trusted --add-source="$net" >/dev/null; changed=1
    fi
  done
  if [[ $changed -eq 1 ]]; then firewall-cmd --reload >/dev/null; say "firewalld: redes de pods y servicios en la zona trusted"; fi
fi

# --- 3) kubeconfig para adminlab ------------------------------------------------------------
install -d -m 0700 -o "$ADMIN_USER" -g "$ADMIN_USER" "/home/$ADMIN_USER/.kube"
install -m 0600 -o "$ADMIN_USER" -g "$ADMIN_USER" /etc/rancher/k3s/k3s.yaml "/home/$ADMIN_USER/.kube/config"

# --- 4) Fluent Bit + app de ejemplo -----------------------------------------------------------
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
sed "s/__SIEM_IP__/$SIEM_IP/g" "$N2_FILES/k8s/10-fluent-bit.yaml" > "$tmp/10-fluent-bit.yaml"
cp "$N2_FILES/k8s/20-demo-app.yaml" "$tmp/"
$KUBECTL apply -f "$tmp/10-fluent-bit.yaml" -f "$tmp/20-demo-app.yaml"
# Un cambio en el ConfigMap no reinicia los pods: se fuerza para que lean la configuración nueva
$KUBECTL -n logging rollout restart daemonset/fluent-bit >/dev/null
$KUBECTL -n logging rollout status daemonset/fluent-bit --timeout=180s
$KUBECTL -n demo rollout status deployment/pagos-demo --timeout=180s

# --- 5) ¿Llegan los logs? ---------------------------------------------------------------------
k8s_logs() { [[ "$(python3 "$SIEM_DIR/tools/os_search.py" count --query 'k8s_namespace_name:demo' --minutes 10 2>/dev/null)" -gt 0 ]]; }
if wait_for 120 "logs de pagos-demo en OpenSearch" k8s_logs; then
  python3 "$SIEM_DIR/tools/os_search.py" search --query 'k8s_namespace_name:demo' --minutes 10 --size 3 \
    --fields timestamp,source,k8s_pod_name,message
  say "OK: los logs de Kubernetes llegan a Graylog (búsqueda: k8s_namespace_name:demo AND \"level=ERROR\")"
else
  fatal "No llegan logs de demo. Mira: kubectl -n logging logs ds/fluent-bit | tail; timeout 20 ausearch -m AVC -ts recent"
fi
