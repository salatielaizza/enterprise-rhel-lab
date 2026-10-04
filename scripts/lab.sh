#!/usr/bin/env bash
# =============================================================================
# lab.sh — Punto de entrada único de enterprise-rhel-lab (Etapas 1-8)
# Ejecuta 'scripts/lab.sh help' para ver los comandos.
# Los scripts son envoltorios de los MISMOS comandos que se documentan a mano en
# los .md: primero se practica a mano en una VM, después se repite con el script.
# =============================================================================
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  cat <<'EOF'
Uso: scripts/lab.sh <comando> [argumentos]

Etapa 1 - Instalación
  host-setup                      Instala KVM/libvirt, pools, clave SSH, ~/.ssh/lab_config
  network                         Crea la red virtual lab-net (10.10.10.0/24, NAT)
  iso [--check] [--only N]        Descarga y verifica las ISOs (download-isos.sh)
  vm-create <host|all> [--force] [--dry-run]
                                  Instala VMs con kickstart (pide una contraseña una vez)
  register <host> <usuario-RH>    Registra la VM en Red Hat (la contraseña se pide en la VM)
  snapshot <create|list|revert|delete> <host|all> [etapa]
                                  Snapshots rhelN-stageM-complete
  up|down <host|all>              Enciende / apaga (ACPI) las VMs
  status                          Estado de las VMs y del SSH

Etapa 2 - Administración Linux
  stage2 <host|all>               usuarios, LVM, permisos, sudo y servicio systemd

Etapa 3 - Networking
  stage3 <host|all> [--lab-dns]   IP/gateway/hostname con nmcli. DNS de arranque 10.10.10.1;
                                  con --lab-dns usa 10.10.10.20 (dns01)

Etapa 4 - Servicios enterprise
  stage4-dns                      BIND + chrony (servidor) en dns01
  stage4-clients <host|all>       DNS del lab + chrony + endurecimiento SSH (dns01 incluido)
  host-dns                        Enruta *.lab.local hacia dns01 en el host (resolvectl)

Etapa 5 - Seguridad
  stage5 <host|all>               SELinux enforcing, reglas de auditd, hardening del SO

Etapa 6 - Bash avanzado y scripting
  stage6 <host|all>               Instala lab-healthcheck.sh/lab-logscan.sh + temporizador systemd

Etapa 7 - Automatización con Ansible
  stage7-setup                    Instala Ansible en ansible01, genera su clave SSH,
                                   la distribuye a los nodos gestionados y sube el
                                   inventario/playbooks/roles (idempotente)
  stage7 <site|facts|ping|advanced|dynamic_inventory_demo> [--limit <grupo|host> | -e var=valor]
                                   Ejecuta un playbook desde ansible01. 'site'/'facts'
                                   van contra el inventario real (--limit los acota);
                                   'ping' es un chequeo ad-hoc; 'advanced' practica
                                   block/rescue/always + serial + módulo/filtro propios
                                   (-e lab_simulate_failure=true dispara el 'rescue');
                                   'dynamic_inventory_demo' explora un inventario
                                   dinámico real construido desde una API pública
                                   (requiere que ansible01 tenga salida a Internet)

Etapa 8 - VMware vSphere (ESXi anidado en KVM; inventario en scripts/vmware.conf)
  esxi-preflight [A|B]            Auditoría de SOLO LECTURA del host para la fase A (ESXi
                                   gratuito) o B (vCenter en evaluación): nested, RAM, disco, ISOs, DNS
  esxi-iso <esxi0N|all> [--dry-run]
                                  ISO desatendido de ESXi con kickstart (pide la contraseña de root)
  esxi-create <esxi0N> [--manual] [--force] [--dry-run]
                                  Crea el ESXi en KVM (SATA, vmxnet3, host-passthrough).
                                   --manual: instalador interactivo con el ISO original (fase 2)
  esxi-up|esxi-down <esxi0N|all>  Encendido / apagado ORDENADO (VMs internas -> mantenimiento -> host)
  esxi-status [esxi0N|all]        Estado, licencia y caducidad, NTP, datastores, VMs (solo lectura)
  esxi-snapshot <create|list|revert|delete> <esxi0N> [etapa]
                                  Snapshots <host>-stage8-complete (exige el ESXi apagado)
  stage8-nfs                      Disco SCSI extra en dns01 + export NFS del datastore compartido
  vcsa-deploy [--verify-only|--precheck-only]
                                  Despliega vCenter (VCSA tiny) en esxi02 con el instalador CLI
  stage8-setup [--no-powercli]    ansible01: venv con ansible-core >= 2.19, colecciones VMware,
                                   proyecto ~/vmware-lab, vault y PowerShell + PowerCLI
  stage8-guest-key                Copia la clave SSH de ansible01 a rhel9-vm01 (VM dentro de ESXi)
  stage8 <info|cluster|esxi-config|guest|vmotion|snapshot|guest-baseline|verify> [args]
                                  Playbooks de ~/vmware-lab desde ansible01 (args para ansible-playbook)
  stage8-close                    Marca LAB_STAGE=8 en dns01 y ansible01 (exige la Etapa 7 cerrada)

Verificación y documentación
  test <test_x.sh|all> <host|all> Ejecuta tests dentro de las VMs (p. ej. test_users.sh)
  facts <host|all>                Recoge datos reales -> results/facts/<host>.env
  matrix                          Genera comparison/matrix.generated.md desde esos datos
EOF
}

# --- utilidades remotas ---------------------------------------------------------
push() {  # copia los scripts y tests a ~/lab-scripts de la VM
  local h="$1" ip; ip="$(ip_of "$h")"
  ssh "${SSH_OPTS[@]}" "$LAB_ADMIN@$ip" 'rm -rf "$HOME/lab-scripts" && mkdir -p "$HOME/lab-scripts"'
  scp -O -q -r "${SSH_OPTS[@]}" \
    "$SCRIPTS_DIR/common.sh" "$SCRIPTS_DIR/collect-facts.sh" "$SCRIPTS_DIR/hosts.conf" \
    "$SCRIPTS_DIR/stage2" "$SCRIPTS_DIR/stage3" "$SCRIPTS_DIR/stage4" "$SCRIPTS_DIR/stage5" "$SCRIPTS_DIR/stage6" "$SCRIPTS_DIR/stage7" "$SCRIPTS_DIR/stage8" "$LAB_ROOT/tests" \
    "$LAB_ADMIN@$ip:lab-scripts/"
}
run_remote() {  # run_remote HOST ruta/relativa.sh [args...]  (como root, sin contraseña)
  local h="$1" rel="$2"; shift 2
  local cmd; cmd="$(printf '%q ' sudo -n bash "lab-scripts/$rel" "$@")"
  # shellcheck disable=SC2029  # $cmd se construye en el cliente con printf %q a propósito
  ssh "${SSH_OPTS[@]}" "$LAB_ADMIN@$(ip_of "$h")" "$cmd"
}
ensure_password() {
  if [[ -z "${LAB_PASSWORD:-}" ]]; then
    local p1 p2
    read -rsp "Contraseña de root y adminlab para las VMs (solo laboratorio): " p1; echo
    read -rsp "Repite la contraseña: " p2; echo
    [[ -n "$p1" && "$p1" == "$p2" ]] || die "Las contraseñas no coinciden o están vacías"
    export LAB_PASSWORD="$p1"
  fi
}
vm_state() { virsh domstate "$1" 2>/dev/null | tr -d '[:space:]'; }
fmt_time() {  # segundos -> "Ns" (menos de 1 min) o "Mm SSs" (1 min o más)
  local s=$1
  if (( s < 60 )); then printf '%ds' "$s"
  else printf '%dm%02ds' $((s / 60)) $((s % 60)); fi
}

# --- etapas ---------------------------------------------------------------------
stage2() {
  local h
  for h in $(targets "$1"); do
    info "=== Etapa 2 en $h ==="
    push "$h"
    local s
    for s in 01-users-groups 02-lvm 03-permissions 04-sudo 05-systemd-app; do
      info "$h: stage2/$s.sh"; run_remote "$h" "stage2/$s.sh"
    done
  done
}
stage3() {
  local t="$1" dns="$LAB_GW" h; shift || true
  [[ "${1:-}" == "--lab-dns" ]] && dns="$LAB_DNS_SERVER"
  for h in $(targets "$t"); do
    info "=== Etapa 3 en $h (DNS $dns) ==="
    push "$h"
    run_remote "$h" stage3/01-configure-network.sh --ip "$(ip_of "$h")" --gw "$LAB_GW" \
      --dns "$dns" --hostname "$h.$LAB_DOMAIN" --domain "$LAB_DOMAIN"
  done
}
stage4_dns() {
  info "=== Etapa 4: BIND + chrony servidor en dns01 ==="
  push dns01
  run_remote dns01 stage4/01-setup-dns.sh
  run_remote dns01 stage3/01-configure-network.sh --ip "$(ip_of dns01)" --gw "$LAB_GW" \
    --dns "$LAB_DNS_SERVER" --hostname "dns01.$LAB_DOMAIN" --domain "$LAB_DOMAIN"
  run_remote dns01 stage4/02-setup-chrony.sh --role server
}
stage4_clients() {
  local h role
  for h in $(targets "$1"); do
    info "=== Etapa 4 (DNS lab + chrony + SSH) en $h ==="
    push "$h"
    run_remote "$h" stage3/01-configure-network.sh --ip "$(ip_of "$h")" --gw "$LAB_GW" \
      --dns "$LAB_DNS_SERVER" --hostname "$h.$LAB_DOMAIN" --domain "$LAB_DOMAIN"
    role=client; [[ "$h" == dns01 ]] && role=server
    run_remote "$h" stage4/02-setup-chrony.sh --role "$role"
    run_remote "$h" stage4/03-ssh-hardening.sh
    # Segunda sesión NUEVA: comprueba que el acceso por clave sigue funcionando
    if ssh "${SSH_OPTS[@]}" "$LAB_ADMIN@$(ip_of "$h")" true; then ok "$h: nueva sesión SSH OK tras el endurecimiento"
    else warn "$h: NO entra por SSH. Entra por consola (virsh console $h) y restaura /etc/ssh/sshd_config.lab-bak.*"; fi
  done
}
stage5() {
  local h
  for h in $(targets "$1"); do
    info "=== Etapa 5 (seguridad) en $h ==="
    push "$h"
    run_remote "$h" stage5/01-selinux-hardening.sh
    run_remote "$h" stage5/02-audit-rules.sh
    run_remote "$h" stage5/03-os-hardening.sh
  done
}
stage6() {
  local h
  for h in $(targets "$1"); do
    info "=== Etapa 6 (bash avanzado) en $h ==="
    push "$h"
    run_remote "$h" stage6/01-bash-tools.sh
  done
}

# ansible01 es el nodo de control; estos son los nodos que GESTIONA (no se
# incluye a sí mismo). Lista explícita, igual que 'dns01' aparece literal en
# stage4_clients: los nombres/roles del lab son fijos desde la Etapa 1.
ANSIBLE_MANAGED_HOSTS=(rhel7-app01 rhel8-app01 rhel9-app01 rhel10-app01 dns01)

stage7_setup() {
  info "=== Etapa 7: preparando ansible01 como nodo de control ==="
  push ansible01
  local out pubkey h
  out="$(run_remote ansible01 stage7/01-ansible-control-setup.sh)"
  printf '%s\n' "$out" | grep -v -E '^##ANSIBLE_PUBKEY_(START|END)##$'
  pubkey="$(printf '%s\n' "$out" | sed -n '/##ANSIBLE_PUBKEY_START##/,/##ANSIBLE_PUBKEY_END##/p' | sed '1d;$d')"
  [[ -n "$pubkey" ]] || die "No se pudo capturar la clave pública de ansible01"

  for h in "${ANSIBLE_MANAGED_HOSTS[@]}"; do
    info "Distribuyendo la clave de ansible01 a $h (acceso ya confiado desde la Etapa 1, sin contraseña nueva)"
    ssh "${SSH_OPTS[@]}" "$LAB_ADMIN@$(ip_of "$h")" \
      "mkdir -p ~/.ssh && chmod 700 ~/.ssh && grep -qxF '$pubkey' ~/.ssh/authorized_keys 2>/dev/null || echo '$pubkey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
  done
  ok "Clave de ansible01 distribuida a ${#ANSIBLE_MANAGED_HOSTS[@]} nodo(s) gestionado(s)"

  info "Comprobando conectividad Ansible (ping + become)..."
  run_remote ansible01 stage7/02-run-playbook.sh ping
  ok "Etapa 7: ansible01 listo. Ejecuta 'lab.sh stage7 site' para aplicar la configuración."
}
stage7() {
  local playbook="$1"; shift || true
  run_remote ansible01 stage7/02-run-playbook.sh "$playbook" "$@"
  if [[ "$playbook" == site ]]; then
    local h
    for h in "${ANSIBLE_MANAGED_HOSTS[@]}"; do
      run_remote "$h" stage7/03-mark-stage.sh
    done
  fi
}

# Etapa 8: los ESXi NO están en hosts.conf (no son RHEL); sus scripts de host viven en
# scripts/stage8/ y leen scripts/vmware.conf. dns01 y ansible01 sí usan push/run_remote.
STAGE8="$SCRIPTS_DIR/stage8"
esxi_targets() {  # 'all' o un ESXi de vmware.conf -> lista de nombres
  local conf="$SCRIPTS_DIR/vmware.conf"
  if [[ "$1" == all ]]; then awk '$1 !~ /^#/ && NF>=9 {print $1}' "$conf"
  else awk -v n="$1" '$1==n {f=1} END{exit !f}' "$conf" || die "ESXi desconocido: $1 (mira $conf)"; echo "$1"; fi
}
stage8_nfs() {
  info "=== Etapa 8: datastore NFS compartido en dns01 ==="
  "$STAGE8/06-dns01-nfs-disk.sh"
  push dns01
  run_remote dns01 stage8/10-nfs-datastore.sh
  ok "Export NFS listo. Siguiente: lab.sh test test_nfs_datastore.sh dns01"
}
stage8_setup() {
  info "=== Etapa 8: automatización de VMware en ansible01 ==="
  push ansible01
  run_remote ansible01 stage8/20-vmware-control-setup.sh "$@"
  ok "ansible01 listo para VMware. Pon las contraseñas reales en el vault de ~/vmware-lab (ver la salida)."
}
stage8_guest_key() {
  local guest_ip=10.10.10.64 pubkey
  info "=== Etapa 8: clave SSH de ansible01 -> rhel9-vm01 ($guest_ip) ==="
  pubkey="$(ssh "${SSH_OPTS[@]}" "$LAB_ADMIN@$(ip_of ansible01)" 'cat ~/.ssh/id_ed25519.pub')" \
    || die "No se pudo leer la clave pública de ansible01 (¿lab.sh stage7-setup?)"
  # rhel9-vm01 se instala con el kickstart de RHEL 9 del lab: ya confía en la clave del HOST
  # shellcheck disable=SC2029  # $pubkey se expande en el cliente a propósito (igual que en stage7_setup)
  ssh "${SSH_OPTS[@]}" "$LAB_ADMIN@$guest_ip" \
    "mkdir -p ~/.ssh && chmod 700 ~/.ssh && grep -qxF '$pubkey' ~/.ssh/authorized_keys 2>/dev/null || echo '$pubkey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" \
    || die "No se pudo entrar en rhel9-vm01 con la clave del lab (¿instalada con el kickstart de RHEL 9?)"
  ok "rhel9-vm01 acepta la clave de ansible01. Siguiente: lab.sh stage8 guest-baseline"
}
stage8() {
  local playbook="$1"; shift || true
  run_remote ansible01 stage8/21-run-playbook.sh "$playbook" "$@"
}
stage8_close() {
  local h
  for h in dns01 ansible01; do push "$h"; run_remote "$h" stage8/99-mark-stage.sh; done
}

# --- despacho -------------------------------------------------------------------
cmd="${1:-help}"; if [[ $# -gt 0 ]]; then shift; fi
case "$cmd" in
  help|-h|--help) usage ;;
  host-setup) exec "$SCRIPTS_DIR/00-host-setup.sh" "$@" ;;
  network)    exec "$SCRIPTS_DIR/01-create-network.sh" "$@" ;;
  iso)        exec "$SCRIPTS_DIR/download-isos.sh" "$@" ;;
  vm-create)
    [[ $# -ge 1 ]] || die "Uso: lab.sh vm-create <host|all> [--force] [--dry-run]"
    t="$1"; shift
    list="$(targets "$t")"            # valida el nombre ANTES de pedir la contraseña
    [[ " $* " == *" --dry-run "* ]] || ensure_password
    for h in $list; do "$SCRIPTS_DIR/02-create-vm.sh" "$h" "$@"; done ;;
  register)
    [[ $# -eq 2 ]] || die "Uso: lab.sh register <host> <usuario-RH>"
    host_row "$1" >/dev/null || die "Host desconocido: $1"
    ssh -t "${SSH_OPTS[@]}" "$LAB_ADMIN@$(ip_of "$1")" "sudo subscription-manager register --username $(printf '%q' "$2")"
    ssh "${SSH_OPTS[@]}" "$LAB_ADMIN@$(ip_of "$1")" 'sudo subscription-manager status || true' ;;
  snapshot)
    [[ $# -ge 2 ]] || die "Uso: lab.sh snapshot <create|list|revert|delete> <host|all> [etapa]"
    for h in $(targets "$2"); do "$SCRIPTS_DIR/03-snapshot.sh" "$1" "$h" "${3:-}"; done ;;
  up)
    for h in $(targets "${1:?Uso: lab.sh up <host|all>}"); do
      [[ "$(vm_state "$h")" == running ]] && { info "$h ya está encendida"; continue; }
      virsh start "$h" >/dev/null && ok "$h encendida"
    done ;;
  down)
    for h in $(targets "${1:?Uso: lab.sh down <host|all>}"); do
      [[ "$(vm_state "$h")" == running ]] || { info "$h ya está apagada"; continue; }
      virsh shutdown "$h" >/dev/null && ok "$h: apagado ACPI solicitado"
    done ;;
  status)
    virsh list --all
    printf '\n%-14s %-13s %-8s %s\n' HOST IP SSH SNAPSHOTS
    for h in $(all_hosts); do
      ssh_ok="--"; ssh "${SSH_OPTS[@]}" -o ConnectTimeout=2 "$LAB_ADMIN@$(ip_of "$h")" true 2>/dev/null && ssh_ok="OK"
      snaps="$(virsh snapshot-list "$h" --name 2>/dev/null | grep . | tr '\n' ' ' || true)"
      printf '%-14s %-13s %-8s %s\n' "$h" "$(ip_of "$h")" "$ssh_ok" "$snaps"
    done ;;
  stage2) stage2 "${1:?Uso: lab.sh stage2 <host|all>}" ;;
  stage3) stage3 "${1:?Uso: lab.sh stage3 <host|all> [--lab-dns]}" "${@:2}" ;;
  stage4-dns) stage4_dns ;;
  stage4-clients) stage4_clients "${1:?Uso: lab.sh stage4-clients <host|all>}" ;;
  stage5) stage5 "${1:?Uso: lab.sh stage5 <host|all>}" ;;
  stage6) stage6 "${1:?Uso: lab.sh stage6 <host|all>}" ;;
  stage7-setup) stage7_setup ;;
  stage7) stage7 "${1:?Uso: lab.sh stage7 <site|facts|ping> [--limit <grupo|host>]}" "${@:2}" ;;
  esxi-preflight) exec "$STAGE8/00-preflight.sh" "$@" ;;
  esxi-iso)
    [[ $# -ge 1 ]] || die "Uso: lab.sh esxi-iso <esxi0N|all> [--dry-run]"
    t="$1"; shift
    list="$(esxi_targets "$t")"
    if [[ " $* " != *" --dry-run "* && -z "${LAB_ESXI_PASSWORD:-}" ]]; then   # una sola pregunta para 'all'
      read -rsp "Contraseña de root para los ESXi (solo laboratorio): " p1; echo
      read -rsp "Repite la contraseña: " p2; echo
      [[ -n "$p1" && "$p1" == "$p2" ]] || die "Las contraseñas no coinciden o están vacías"
      export LAB_ESXI_PASSWORD="$p1"
    fi
    for h in $list; do "$STAGE8/01-esxi-iso.sh" "$h" "$@"; done ;;
  esxi-create)   exec "$STAGE8/02-create-esxi.sh" "${1:?Uso: lab.sh esxi-create <esxi0N> [--manual] [--force] [--dry-run]}" "${@:2}" ;;
  esxi-up)       exec "$STAGE8/03-esxi-power.sh" up "${1:?Uso: lab.sh esxi-up <esxi0N|all>}" ;;
  esxi-down)     exec "$STAGE8/03-esxi-power.sh" down "${1:?Uso: lab.sh esxi-down <esxi0N|all>}" ;;
  esxi-status)   exec "$STAGE8/04-esxi-status.sh" "${1:-all}" ;;
  esxi-snapshot) exec "$STAGE8/05-esxi-snapshot.sh" "$@" ;;
  stage8-nfs)    stage8_nfs ;;
  vcsa-deploy)   exec "$STAGE8/07-vcsa-deploy.sh" "$@" ;;
  stage8-setup)  stage8_setup "$@" ;;
  stage8-guest-key) stage8_guest_key ;;
  stage8)        stage8 "${1:?Uso: lab.sh stage8 <info|cluster|esxi-config|guest|vmotion|snapshot|guest-baseline|verify> [args]}" "${@:2}" ;;
  stage8-close)  stage8_close ;;
  host-dns)
    need resolvectl
    sudo resolvectl dns "$LAB_BRIDGE" "$LAB_DNS_SERVER"
    sudo resolvectl domain "$LAB_BRIDGE" '~lab.local'
    sudo resolvectl mdns "$LAB_BRIDGE" no
    sudo resolvectl llmnr "$LAB_BRIDGE" no
    resolvectl query dns01.lab.local || warn "Sin respuesta: ¿dns01 encendida y con BIND?"
    info "Ajuste NO persistente. Nota: 'ssh x.lab.local' puede seguir fallando por nss-mdns (ver networking/dns.md); usa los alias de ~/.ssh/lab_config." ;;
  test)
    [[ $# -eq 2 ]] || die "Uso: lab.sh test <test_x.sh|all> <host|all>"
    script="$1"; [[ "$script" == all ]] && script=run_all.sh
    rc=0
    declare -A SUM_P SUM_F SUM_S SUM_T   # PASS/FAIL/estado/tiempo por host, para la tabla final
    HOSTS_RUN=()
    for h in $(targets "$2"); do
      info "=== $script en $h ==="; push "$h"
      t0=$SECONDS
      if out="$(run_remote "$h" "tests/$script" 2>&1)"; then
        ec=0
      else
        ec=$?
      fi
      dt=$((SECONDS - t0))
      printf '%s\n' "$out"
      [[ $ec -ne 0 ]] && rc=1
      HOSTS_RUN+=("$h")
      SUM_T[$h]="$(fmt_time "$dt")"
      line="$(printf '%s\n' "$out" | grep '^##HOST_SUMMARY##' | tail -n1)"
      if [[ -n "$line" ]]; then
        read -r _ _ p f st rt <<<"$line"
        SUM_P[$h]="$p"; SUM_F[$h]="$f"; SUM_S[$h]="$st"
        [[ -n "$rt" ]] && SUM_T[$h]="$rt"
      else
        line="$(printf '%s\n' "$out" | grep -E '^--- .* [0-9]+ PASS, [0-9]+ FAIL$' | tail -n1)"
        if [[ -n "$line" ]]; then
          SUM_P[$h]="$(sed -E 's/.*: ([0-9]+) PASS,.*/\1/' <<<"$line")"
          SUM_F[$h]="$(sed -E 's/.*, ([0-9]+) FAIL$/\1/' <<<"$line")"
          SUM_S[$h]=$([[ $ec -eq 0 ]] && echo OK || echo FALLOS)
        else
          SUM_P[$h]="-"; SUM_F[$h]="-"; SUM_S[$h]=$([[ $ec -eq 0 ]] && echo OK || echo FALLOS)
        fi
      fi
    done
    echo
    info "=== RESULTADO GLOBAL (${#HOSTS_RUN[@]} host(s)) ==="
    printf '%-16s %-8s %-8s %-8s %s\n' "HOST" "PASS" "FAIL" "TIEMPO" "ESTADO"
    for h in "${HOSTS_RUN[@]}"; do
      printf '%-16s %-8s %-8s %-8s %s\n' "$h" "${SUM_P[$h]}" "${SUM_F[$h]}" "${SUM_T[$h]}" "${SUM_S[$h]}"
    done
    echo
    if [[ $rc -eq 0 ]]; then ok "RESULTADO GLOBAL: OK — todas las VMs sin FAIL"
    else warn "RESULTADO GLOBAL: HAY FALLOS — revisa la tabla de arriba"; fi
    exit "$rc" ;;
  facts)
    mkdir -p "$LAB_ROOT/results/facts"
    for h in $(targets "${1:?Uso: lab.sh facts <host|all>}"); do
      push "$h"; run_remote "$h" collect-facts.sh > "$LAB_ROOT/results/facts/$h.env"
      ok "datos de $h -> results/facts/$h.env"
    done ;;
  matrix) exec "$SCRIPTS_DIR/build-matrix.sh" "$@" ;;
  *) usage; die "Comando desconocido: $cmd" ;;
esac
