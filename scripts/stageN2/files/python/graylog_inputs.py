#!/usr/bin/env python3
"""graylog_inputs.py — Crea (si faltan) y arranca las entradas del SIEM del lab por la API REST de Graylog.

Idempotente: busca cada entrada por su título; si existe no la duplica, y si está parada la arranca.
Solo usa la biblioteca estándar (urllib), así funciona en cualquier RHEL sin pip.

Uso:
  graylog_inputs.py --password-file /root/.siem/graylog-admin.txt            # asegurar entradas
  graylog_inputs.py --password-file /root/.siem/graylog-admin.txt --list     # solo listar
  graylog_inputs.py --password-file ... --dry-run                            # qué haría, sin cambiar nada

Detalles de la API que conviene saber:
  - Autenticación básica (usuario:contraseña o token:"token").
  - Toda petición que cambia algo exige la cabecera X-Requested-By (protección CSRF).
  - POST /api/system/inputs crea; PUT /api/system/inputstates/<id> arranca en este nodo.
"""
import argparse
import base64
import json
import sys
import urllib.error
import urllib.request

# Entradas del lab. Puertos > 1024: el proceso de Graylog no corre como root dentro del contenedor.
INPUTS = [
    {"title": "lab-syslog-tcp-5140", "type": "org.graylog2.inputs.syslog.tcp.SyslogTCPInput", "port": 5140, "proto": "tcp", "kind": "syslog"},
    {"title": "lab-syslog-udp-5140", "type": "org.graylog2.inputs.syslog.udp.SyslogUDPInput", "port": 5140, "proto": "udp", "kind": "syslog"},
    {"title": "lab-gelf-tcp-12201", "type": "org.graylog2.inputs.gelf.tcp.GELFTCPInput", "port": 12201, "proto": "tcp", "kind": "gelf"},
    {"title": "lab-gelf-udp-12201", "type": "org.graylog2.inputs.gelf.udp.GELFUDPInput", "port": 12201, "proto": "udp", "kind": "gelf"},
]


def input_configuration(spec):
    """Configuración de cada tipo de entrada (los nombres de campo son los de la API de Graylog)."""
    cfg = {
        "bind_address": "0.0.0.0",       # dentro del contenedor; el compose decide en qué IP del host se publica
        "port": spec["port"],
        "recv_buffer_size": 1048576 if spec["proto"] == "tcp" else 262144,
        "number_worker_threads": 2,
    }
    if spec["proto"] == "tcp":
        cfg.update({
            "tls_enable": False,             # TLS del transporte: ampliación (puerto 6514 / certificados)
            "tcp_keepalive": False,
            "max_message_size": 2097152,
            # GELF por TCP separa mensajes con un byte nulo; Syslog por TCP, con salto de línea
            "use_null_delimiter": spec["kind"] == "gelf",
        })
    if spec["kind"] == "syslog":
        cfg.update({
            "allow_override_date": True,
            "store_full_message": True,      # guarda la línea original en full_message (útil en auditoría)
            "expand_structured_data": False,
            "force_rdns": False,
        })
    if spec["kind"] == "gelf" and spec["proto"] == "udp":
        cfg["decompress_size_limit"] = 8388608
    return cfg


class Graylog:
    def __init__(self, url, user, password, timeout=15):
        self.url = url.rstrip("/")
        token = base64.b64encode(f"{user}:{password}".encode()).decode()
        self.headers = {
            "Authorization": f"Basic {token}",
            "Accept": "application/json",
            "Content-Type": "application/json",
            "X-Requested-By": "lab-graylog-inputs",
        }
        self.timeout = timeout

    def call(self, method, path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.url + path, data=data, method=method, headers=self.headers)
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode(errors="replace")[:400]
            raise SystemExit(f"ERROR {method} {path}: HTTP {exc.code} {detail}") from None
        except urllib.error.URLError as exc:
            raise SystemExit(f"ERROR {method} {path}: {exc.reason} (¿Graylog arrancado? 'lab.sh siem-stack')") from None


def states_by_id(api):
    """id de entrada -> estado (RUNNING, FAILED, STARTING...) en este nodo."""
    data = api.call("GET", "/api/system/inputstates")
    return {s["id"]: s.get("state", "?") for s in data.get("states", [])}


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--url", default="http://127.0.0.1:9000")
    ap.add_argument("--user", default="admin")
    ap.add_argument("--password-file", required=True)
    ap.add_argument("--list", action="store_true", help="solo listar las entradas y su estado")
    ap.add_argument("--dry-run", action="store_true", help="mostrar qué se haría, sin cambiar nada")
    args = ap.parse_args()

    with open(args.password_file, encoding="utf-8") as fh:
        password = fh.read().strip()
    api = Graylog(args.url, args.user, password)

    existing = {i["title"]: i for i in api.call("GET", "/api/system/inputs").get("inputs", [])}
    states = states_by_id(api)

    if args.list:
        print(f"{'TÍTULO':28} {'TIPO':48} {'PUERTO':7} ESTADO")
        for title, inp in sorted(existing.items()):
            port = inp.get("attributes", {}).get("port", "?")
            print(f"{title:28} {inp['type']:48} {str(port):7} {states.get(inp['id'], 'NO INICIADA')}")
        return 0

    rc = 0
    for spec in INPUTS:
        title = spec["title"]
        if title in existing:
            input_id = existing[title]["id"]
            action = "existe"
        elif args.dry_run:
            print(f"[dry-run] crearía {title} ({spec['proto']}/{spec['port']})")
            continue
        else:
            body = {"title": title, "type": spec["type"], "global": True, "configuration": input_configuration(spec)}
            input_id = api.call("POST", "/api/system/inputs", body)["id"]
            action = "creada"
        state = states_by_id(api).get(input_id, "NO INICIADA")
        if state != "RUNNING":
            if args.dry_run:
                print(f"[dry-run] arrancaría {title} (estado {state})")
                continue
            api.call("PUT", f"/api/system/inputstates/{input_id}")
            state = states_by_id(api).get(input_id, "?")
            action += ", arrancada"
        print(f"{title:28} {spec['proto']}/{spec['port']:<6} {action:22} {state}")
        if state not in ("RUNNING", "STARTING"):
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
