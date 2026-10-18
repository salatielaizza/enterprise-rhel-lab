#!/usr/bin/env bash
# Etapa N2 — SIEM. Un solo test que se adapta al papel de cada VM:
#   siem01                      servidor: Docker, contenedores, API, exposición de puertos, ingesta
#   VMs con reenvío de rsyslog  agente syslog: configuración, SELinux, cola, conectividad
#   VMs con NXLog               agente NXLog: servicio, configuración, permisos de auditd
# En el resto no hace nada. Lanzarlo:  scripts/lab.sh test test_siem.sh siem01   (o <host>)
# Lo que depende de que OTRA VM esté encendida se informa como INFO, no como FAIL.
# En siem01 comprueba POR FASES (caso troubleshooting/etapaN2/01): solo lo ya desplegado. Lo que aún
# no se ha lanzado (siem-docker, siem-stack, siem-inputs) sale como INFO "pendiente", no como FAIL
# (y tampoco como PASS vacío: sin contenedores, "ninguna imagen :latest" no demuestra nada).
# shellcheck disable=SC2034  # TEST_NAME lo usa summary() de lib.sh
TEST_NAME=test_siem; source "$(dirname "$0")/lib.sh"; need_root

SIEM_IP="$(awk '$1=="siem01" {print $3}' "$HOSTS_CONF")"; SIEM_IP="${SIEM_IP:-10.10.10.55}"
TOOLS=/opt/siem/tools
info() { printf 'INFO  %s\n' "$*"; }
tcp_open() { timeout 3 bash -c "</dev/tcp/$1/$2" 2>/dev/null; }
roles=0; phase=0

# ---------------------------------------------------------------- servidor (siem01)
if [[ "$(hostname -s)" == siem01 ]]; then
  roles=1
  phase=0                                                     # 0 nada · 1 Docker · 2 stack · 3 entradas
  if rpm -q docker-ce >/dev/null 2>&1; then phase=1; fi
  if [[ $phase -ge 1 && -f /opt/siem/docker-compose.yml ]]; then phase=2; fi
  if [[ $phase -ge 2 && -f /root/.siem/graylog-admin.txt && -x $TOOLS/graylog_inputs.py ]] \
     && python3 "$TOOLS/graylog_inputs.py" --password-file /root/.siem/graylog-admin.txt --list 2>/dev/null | grep -q '^lab-'; then
    phase=3
  fi
  if [[ $phase -eq 0 ]]; then
    info "SIEM no desplegado todavía: pendiente 'lab.sh siem-docker' (se omiten las comprobaciones del servidor)"
  fi
fi
if [[ "$(hostname -s)" == siem01 && $phase -ge 1 ]]; then
  # Almacenamiento y host de contenedores
  check "/var/lib/docker es un LV propio" mountpoint -q /var/lib/docker
  ctx_docker() { [[ "$(stat -c %C /var/lib/docker)" == *container_var_lib_t* ]]; }
  check "/var/lib/docker con etiqueta SELinux container_var_lib_t" ctx_docker
  check "docker activo y habilitado" bash -c 'systemctl is-active --quiet docker && systemctl is-enabled --quiet docker'
  check "Docker con SELinux en los contenedores (selinux-enabled)" bash -c "docker info --format '{{.SecurityOptions}}' | grep -q selinux"
  check "rotación de logs de contenedores configurada (max-size)" grep -q '"max-size"' /etc/docker/daemon.json
  # Caso troubleshooting/etapaN2/03: con el "containerd image store" (Docker 29) las imágenes van a
  # /var/lib/containerd (en /var, 4 GB) y no a lv_docker. Driver overlay2 = todo en /var/lib/docker.
  check "storage driver overlay2 (imágenes en lv_docker, no en /var/lib/containerd)" bash -c "[[ \$(docker info --format '{{.Driver}}') == overlay2 ]]"
  max_map_ok() { [[ "$(sysctl -n vm.max_map_count)" -ge 262144 ]]; }
  check "vm.max_map_count >= 262144" max_map_ok
  if [[ $phase -eq 1 ]]; then info "stack pendiente: 'lab.sh siem-stack' (se omiten contenedores, API e ingesta)"; fi
fi
if [[ "$(hostname -s)" == siem01 && $phase -ge 2 ]]; then
  # Contenedores
  for c in siem-mongodb siem-opensearch siem-graylog; do
    check "contenedor $c en ejecución" bash -c "[[ \$(docker inspect -f '{{.State.Running}}' $c 2>/dev/null) == true ]]"
  done
  for c in siem-mongodb siem-opensearch; do
    check "contenedor $c healthy" bash -c "[[ \$(docker inspect -f '{{.State.Health.Status}}' $c 2>/dev/null) == healthy ]]"
  done
  check "imágenes con versión fijada (ninguna :latest)" bash -c "! docker ps --format '{{.Image}}' | grep -Eq ':latest$|^[^:]+$'"

  # Secretos y exposición (buenas prácticas)
  mode_is() { [[ "$(stat -c %a "$1" 2>/dev/null)" == "$2" ]]; }
  check ".env del SIEM con permisos 600" mode_is /opt/siem/.env 600
  check "contraseña de admin guardada con permisos 600" mode_is /root/.siem/graylog-admin.txt 600
  check "Graylog no usa la contraseña por defecto 'admin'" bash -c "! grep -q 8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918 /opt/siem/.env"
  check "OpenSearch solo en 127.0.0.1:9200 (no expuesto a la red)" bash -c "ss -ltn | grep -q '127.0.0.1:9200 ' && ! ss -ltn | grep -Eq '(0.0.0.0|\\*|$SIEM_IP):9200 '"
  check "MongoDB no publicado en el host" bash -c "! ss -ltn | grep -q ':27017 '"
  check "ningún puerto del SIEM publicado en 0.0.0.0" bash -c "! docker ps --format '{{.Ports}}' | grep -q '0.0.0.0:'"

  # Servicio
  check "API de Graylog: lbstatus ALIVE" bash -c "[[ \$(curl -s -m 5 http://127.0.0.1:9000/api/system/lbstatus) == ALIVE ]]"
  check "OpenSearch: clúster green o yellow" python3 "$TOOLS/os_search.py" health
  check "entradas escuchando: Syslog 5140/tcp y GELF 12201/tcp" bash -c "ss -ltn | grep -q '$SIEM_IP:5140 ' && ss -ltn | grep -q '$SIEM_IP:12201 '"
  check "entradas escuchando: Syslog 5140/udp y GELF 12201/udp" bash -c "ss -lun | grep -q '$SIEM_IP:5140 ' && ss -lun | grep -q '$SIEM_IP:12201 '"
  if [[ $phase -eq 2 ]]; then info "entradas pendientes: 'lab.sh siem-inputs' (se omiten entradas, ingesta y Kubernetes)"; fi
fi
if [[ "$(hostname -s)" == siem01 && $phase -ge 3 ]]; then
  check "4 entradas del lab en RUNNING" bash -c "[[ \$(python3 $TOOLS/graylog_inputs.py --password-file /root/.siem/graylog-admin.txt --list | grep -c '^lab-.*RUNNING') -eq 4 ]]"

  # Ingesta de extremo a extremo (mensaje nuevo con marcador -> índice)
  marker="test-$(date +%s)"
  e2e() {
    python3 "$TOOLS/gelf_send.py" --host "$SIEM_IP" --proto tcp --marker "$marker" >/dev/null || return 1
    local i
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
      [[ "$(python3 "$TOOLS/os_search.py" count --query "lab_marker:$marker" --minutes 5 2>/dev/null)" -ge 1 ]] && return 0
      sleep 5
    done
    return 1
  }
  check "GELF TCP de prueba indexado en OpenSearch (<60 s)" e2e
  n="$(python3 "$TOOLS/os_search.py" top --field source --minutes 60 --size 20 2>/dev/null | tail -n +2 | wc -l)"
  info "fuentes distintas en la última hora: ${n:-0}"
  python3 "$TOOLS/os_search.py" top --field source --minutes 60 --size 20 2>/dev/null | sed 's/^/INFO    /' || true

  # Kubernetes (si se instaló: lab.sh siem-k8s)
  if systemctl list-unit-files k3s.service >/dev/null 2>&1 && [[ -x /usr/local/bin/kubectl ]]; then
    check "k3s: nodo Ready" bash -c "/usr/local/bin/kubectl get nodes --no-headers | grep -qw Ready"
    ds_ready() {
      local ready desired
      ready="$(/usr/local/bin/kubectl -n logging get ds fluent-bit -o jsonpath='{.status.numberReady}')"
      desired="$(/usr/local/bin/kubectl -n logging get ds fluent-bit -o jsonpath='{.status.desiredNumberScheduled}')"
      [[ -n "$ready" && "$ready" -ge 1 && "$ready" == "$desired" ]]
    }
    check "Fluent Bit: DaemonSet con todos los pods listos" ds_ready
    check "logs de Kubernetes (namespace demo) en los últimos 15 min" \
      bash -c "[[ \$(python3 $TOOLS/os_search.py count --query 'k8s_namespace_name:demo' --minutes 15) -gt 0 ]]"
  else
    info "k3s no instalado: se omiten las comprobaciones de Kubernetes (lab.sh siem-k8s)"
  fi
fi

# ---------------------------------------------------------------- agente rsyslog
FWD=/etc/rsyslog.d/90-siem-forward.conf
if [[ -f "$FWD" ]]; then
  roles=1
  check "rsyslog activo" systemctl is-active --quiet rsyslog
  check "configuración de rsyslog válida (rsyslogd -N1)" rsyslogd -N1
  check "reenvío apunta a $SIEM_IP:5140/tcp" bash -c "grep -q 'target=\"$SIEM_IP\"' $FWD && grep -q 'port=\"5140\"' $FWD"
  check "reenvío con cola en disco (queue.filename)" grep -q 'queue.filename' "$FWD"
  if [[ "$(getenforce)" != Disabled ]]; then
    seport_ok() { semanage port -l | awk '$1=="syslogd_port_t" && $2=="tcp" { for (i = 3; i <= NF; i++) { gsub(",", "", $i); if ($i == "5140") f = 1 } } END { exit !f }'; }
    check "SELinux: tcp/5140 etiquetado como syslogd_port_t" seport_ok
  fi
  if tcp_open "$SIEM_IP" 5140; then pass "conexión TCP con el SIEM ($SIEM_IP:5140)"
  else info "el SIEM no responde en $SIEM_IP:5140 (¿siem01 apagada?): los mensajes esperan en la cola de disco"; fi
fi

# ---------------------------------------------------------------- agente NXLog
if rpm -q nxlog-ce >/dev/null 2>&1; then
  roles=1
  CONF=/etc/nxlog.conf; [[ -f "$CONF" ]] || CONF=/etc/nxlog/nxlog.conf
  check "nxlog activo y habilitado" bash -c 'systemctl is-active --quiet nxlog && systemctl is-enabled --quiet nxlog'
  check "configuración de NXLog válida (nxlog -v)" nxlog -v -c "$CONF"
  check "NXLog envía a $SIEM_IP:12201 en GELF_TCP" bash -c "grep -q 'Host *$SIEM_IP' $CONF && grep -q 'OutputType *GELF_TCP' $CONF"
  check "NXLog NO corre como root (User nxlog)" bash -c "grep -Eq '^User +nxlog' $CONF && [[ \$(ps -o user= -C nxlog | sort -u | head -n1) == nxlog ]]"
  check "auditd: log_group = nxlog" grep -Eq '^[[:space:]]*log_group[[:space:]]*=[[:space:]]*nxlog' /etc/audit/auditd.conf
  check "el usuario nxlog puede leer audit.log" runuser -u nxlog -- test -r /var/log/audit/audit.log
  if tcp_open "$SIEM_IP" 12201; then pass "conexión TCP con el SIEM ($SIEM_IP:12201)"
  else info "el SIEM no responde en $SIEM_IP:12201 (¿siem01 apagada?)"; fi
fi

if [[ $roles -eq 0 ]]; then echo "test_siem: $(hostname -s) no es siem01 ni tiene agentes del SIEM (no aplica)"; fi
summary
