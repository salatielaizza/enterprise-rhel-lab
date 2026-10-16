#!/usr/bin/env bash
# =============================================================================
# 02-graylog-stack.sh — (siem01) Despliega el SIEM con Docker Compose en /opt/siem
#
#   1. Copia docker-compose.yml a /opt/siem (root, 0750) con copia del anterior.
#   2. Genera /opt/siem/.env (0600) SOLO si no existe: secretos aleatorios y el
#      SHA-256 de una contraseña de admin aleatoria, que se guarda en
#      /root/.siem/graylog-admin.txt (0600). Nunca hay contraseñas por defecto.
#   3. 'docker compose config' (valida) -> pull -> up -d; espera a que la API de
#      Graylog responda ALIVE.
#   4. firewalld: los puertos del SIEM, solo desde 10.10.10.0/24 (documenta la
#      intención; ojo: los puertos que publica Docker NO pasan por las zonas de
#      firewalld — por eso el compose los liga a IPs concretas).
#
# Uso: lab.sh siem-stack [--with-elastic]
#   --with-elastic  arranca también Elasticsearch (perfil "elastic", +1,5 GB de RAM)
# =============================================================================
set -euo pipefail
# shellcheck source=siem-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/siem-lib.sh"
require_root
require_host "$SIEM_NAME"

WITH_ELASTIC=0
for a in "$@"; do
  case "$a" in
    --with-elastic) WITH_ELASTIC=1 ;;
    *) fatal "Opción desconocida: $a (uso: 02-graylog-stack.sh [--with-elastic])" ;;
  esac
done

command -v docker >/dev/null || fatal "Docker no está instalado: ejecuta antes 'lab.sh siem-docker'"
docker compose version >/dev/null 2>&1 || fatal "Falta el plugin docker compose (docker-compose-plugin)"
[[ "$(sysctl -n vm.max_map_count)" -ge 262144 ]] || fatal "vm.max_map_count < 262144: ejecuta 'lab.sh siem-docker'"

# --- 1) Proyecto Compose ------------------------------------------------------------------
install -d -m 0750 -o root -g root "$SIEM_DIR" "$SIEM_DIR/tools"
install -d -m 0700 -o root -g root "$SIEM_SECRETS"
if ! cmp -s "$N2_FILES/graylog/docker-compose.yml" "$SIEM_DIR/docker-compose.yml" 2>/dev/null; then
  backup "$SIEM_DIR/docker-compose.yml"
  install -m 0640 "$N2_FILES/graylog/docker-compose.yml" "$SIEM_DIR/docker-compose.yml"
  say "docker-compose.yml instalado en $SIEM_DIR"
fi
# Herramientas en Python (solo biblioteca estándar) que usan este script, el siguiente y los tests
install -m 0750 "$N2_FILES"/python/*.py "$SIEM_DIR/tools/"

# --- 2) Secretos -----------------------------------------------------------------------------
ENV_FILE="$SIEM_DIR/.env"
ADMIN_PW_FILE="$SIEM_SECRETS/graylog-admin.txt"
ELASTIC_PW_FILE="$SIEM_SECRETS/elastic.txt"
if [[ ! -f "$ENV_FILE" ]]; then
  umask 077
  admin_pw="$(randpw 20)"; elastic_pw="$(randpw 24)"
  printf '%s\n' "$admin_pw" > "$ADMIN_PW_FILE"
  printf '%s\n' "$elastic_pw" > "$ELASTIC_PW_FILE"
  {
    echo "# Generado por 02-graylog-stack.sh el $(date -Iseconds). NO va al repositorio."
    echo "SIEM_IP=$SIEM_IP"
    echo "SIEM_TZ=$(timedatectl show -p Timezone --value 2>/dev/null || echo Europe/Madrid)"
    echo "GRAYLOG_PASSWORD_SECRET=$(randpw 96)"
    echo "GRAYLOG_ROOT_PASSWORD_SHA2=$(printf '%s' "$admin_pw" | sha256sum | cut -d' ' -f1)"
    echo "OPENSEARCH_INITIAL_ADMIN_PASSWORD=$(randpw 24)Aa1"
    echo "ELASTIC_PASSWORD=$elastic_pw"
    echo "OS_HEAP=1g"
    echo "ES_HEAP=1g"
  } > "$ENV_FILE"
  chmod 0600 "$ENV_FILE" "$ADMIN_PW_FILE" "$ELASTIC_PW_FILE"
  umask 022
  unset admin_pw elastic_pw
  say "Secretos generados: $ENV_FILE y $ADMIN_PW_FILE (0600)"
else
  say "$ENV_FILE ya existe: se conserva (regenerar GRAYLOG_PASSWORD_SECRET rompería los datos cifrados)"
fi
[[ -f "$ADMIN_PW_FILE" ]] || fatal "Falta $ADMIN_PW_FILE (¿.env creado a mano?). Guarda ahí la contraseña de admin."
# Defensa: nunca la contraseña "admin" (su SHA-256 es el ejemplo de la documentación oficial)
if grep -q '^GRAYLOG_ROOT_PASSWORD_SHA2=8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918$' "$ENV_FILE"; then
  fatal "El .env usa la contraseña 'admin': genera otra (sha256sum) antes de seguir"
fi

# --- 3) Despliegue ---------------------------------------------------------------------------
cd "$SIEM_DIR"
PROFILE_ARGS=()
if [[ $WITH_ELASTIC -eq 1 ]]; then PROFILE_ARGS=(--profile elastic); fi
docker compose "${PROFILE_ARGS[@]}" config --quiet || fatal "docker compose config: el compose o el .env tienen errores"
say "Descargando imágenes (la primera vez tarda: ~2 GB)"
docker compose "${PROFILE_ARGS[@]}" pull --quiet
docker compose "${PROFILE_ARGS[@]}" up -d
docker compose "${PROFILE_ARGS[@]}" ps --format 'table {{.Name}}\t{{.Image}}\t{{.Status}}'

graylog_alive() { [[ "$(curl -s -m 5 http://127.0.0.1:9000/api/system/lbstatus)" == ALIVE ]]; }
say "Esperando a la API de Graylog (hasta 5 min: la primera vez crea índices en OpenSearch)"
if ! wait_for 300 "API de Graylog" graylog_alive; then
  docker compose logs --tail 40 graylog >&2 || true
  fatal "Graylog no responde ALIVE en 127.0.0.1:9000 (mira: docker compose -f $SIEM_DIR/docker-compose.yml logs graylog)"
fi
say "Graylog responde: $(curl -s -m 5 -u "admin:$(cat "$ADMIN_PW_FILE")" -H 'Accept: application/json' \
  http://127.0.0.1:9000/api/system | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("version","?"), d.get("lifecycle","?"))' 2>/dev/null || echo '?')"

# --- 4) firewalld ------------------------------------------------------------------------------
if systemctl is-active --quiet firewalld; then
  for p in 9000/tcp 5140/tcp 5140/udp 12201/tcp 12201/udp; do fw_rich "$p"; done
  firewall-cmd --reload >/dev/null
fi

cat <<EOF

  Web de Graylog:  http://$SIEM_IP:9000   (o http://graylog.lab.local:9000)
  Usuario:         admin
  Contraseña:      sudo cat $ADMIN_PW_FILE     (en siem01)
  OpenSearch:      curl -s 127.0.0.1:9200/_cluster/health?pretty   (solo desde siem01)
EOF
if [[ $WITH_ELASTIC -eq 1 ]]; then
  echo "  Elasticsearch:   sudo $SIEM_DIR/tools/os_search.py --url http://127.0.0.1:9201 --user elastic --password-file $ELASTIC_PW_FILE health"
fi
say "Siguiente: lab.sh siem-inputs"
