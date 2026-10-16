#!/usr/bin/env python3
"""os_search.py — Consulta OpenSearch / Elasticsearch por su API REST (la misma API en los dos).

Graylog guarda cada mensaje como un documento JSON en índices graylog_0, graylog_1...
(alias graylog_deflector = índice activo). Consultar el almacén directamente sirve para
entender qué hay debajo de Graylog y para automatizar comprobaciones.

Uso (en siem01; OpenSearch solo escucha en 127.0.0.1):
  os_search.py health                                   # salud del clúster y versión
  os_search.py indices                                  # índices, documentos y tamaño
  os_search.py search --query 'lab_marker:lab-1234' --minutes 15
  os_search.py search --query 'source:rhel9-app01 AND level:<=4' --fields source,message
  os_search.py count  --query '*' --minutes 60
  os_search.py top    --field source --minutes 60       # quién envía más (agregación terms)
  # Elasticsearch del perfil opcional (puerto 9201, usuario elastic):
  os_search.py --url http://127.0.0.1:9201 --user elastic --password-file <fich> ingest-demo --count 50
  os_search.py --url http://127.0.0.1:9201 --user elastic --password-file <fich> search --index lab-demo --query 'level:ERROR'

Solo biblioteca estándar.
"""
import argparse
import base64
import json
import random
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone


class Search:
    def __init__(self, url="http://127.0.0.1:9200", user=None, password=None, timeout=15):
        self.url = url.rstrip("/")
        self.headers = {"Content-Type": "application/json", "Accept": "application/json"}
        if user:
            token = base64.b64encode(f"{user}:{password or ''}".encode()).decode()
            self.headers["Authorization"] = f"Basic {token}"
        self.timeout = timeout

    def call(self, method, path, body=None, raw_body=None):
        data = raw_body if raw_body is not None else (json.dumps(body).encode() if body is not None else None)
        headers = dict(self.headers)
        if raw_body is not None:
            headers["Content-Type"] = "application/x-ndjson"    # formato de _bulk: una línea JSON por acción
        req = urllib.request.Request(self.url + path, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                return json.loads(resp.read() or b"{}")
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode(errors="replace")[:500]
            raise SystemExit(f"ERROR {method} {path}: HTTP {exc.code} {detail}") from None
        except urllib.error.URLError as exc:
            raise SystemExit(f"ERROR {method} {self.url}{path}: {exc.reason}") from None

    # --- consultas -------------------------------------------------------------------
    def info(self):
        root = self.call("GET", "/")
        ver = root.get("version", {})
        return ver.get("distribution", "elasticsearch"), ver.get("number", "?")

    def query(self, query, minutes, time_field="timestamp"):
        """query_string (sintaxis Lucene, la misma que la barra de búsqueda de Graylog) + rango de tiempo."""
        must = [{"query_string": {"query": query or "*", "default_field": "message", "analyze_wildcard": True}}]
        if minutes:
            must.append({"range": {time_field: {"gte": f"now-{minutes}m"}}})
        return {"bool": {"must": must}}

    def search(self, index, query, minutes, size=10, time_field="timestamp"):
        body = {"size": size, "sort": [{time_field: {"order": "desc", "unmapped_type": "date"}}],
                "query": self.query(query, minutes, time_field), "track_total_hits": True}
        return self.call("POST", f"/{index}/_search", body)

    def count(self, index, query, minutes, time_field="timestamp"):
        return self.call("POST", f"/{index}/_count", {"query": self.query(query, minutes, time_field)})["count"]

    def top(self, index, field, query, minutes, size=10, time_field="timestamp"):
        body = {"size": 0, "query": self.query(query, minutes, time_field),
                "aggs": {"top": {"terms": {"field": field, "size": size}}}}
        return self.call("POST", f"/{index}/_search", body)["aggregations"]["top"]["buckets"]


def total_hits(res):
    total = res.get("hits", {}).get("total", 0)
    return total.get("value", 0) if isinstance(total, dict) else total


def cmd_health(s, _args):
    dist, ver = s.info()
    h = s.call("GET", "/_cluster/health")
    print(f"{dist} {ver} · clúster {h['cluster_name']} · estado {h['status']} · nodos {h['number_of_nodes']} · "
          f"shards activos {h['active_shards']} · sin asignar {h['unassigned_shards']}")
    # Un solo nodo: las réplicas no se pueden asignar -> "yellow" en índices con réplicas (normal en el lab)
    return 0 if h["status"] in ("green", "yellow") else 1


def cmd_indices(s, _args):
    rows = s.call("GET", "/_cat/indices?format=json&bytes=mb&s=index")
    print(f"{'ÍNDICE':32} {'SALUD':7} {'DOCS':>10} {'MB':>8}")
    for r in rows:
        if r["index"].startswith("."):
            continue     # índices internos
        print(f"{r['index']:32} {r['health']:7} {r['docs.count'] or 0:>10} {r['store.size'] or 0:>8}")
    return 0


def cmd_search(s, args):
    res = s.search(args.index, args.query, args.minutes, args.size, args.time_field)
    fields = args.fields.split(",")
    print(f"# {total_hits(res)} coincidencia(s) para «{args.query}» en los últimos {args.minutes} min (máx. {args.size} mostradas)")
    for hit in res["hits"]["hits"]:
        src = hit["_source"]
        print(" | ".join(str(src.get(f, "-")) for f in fields))
    return 0 if total_hits(res) > 0 else 1


def cmd_count(s, args):
    n = s.count(args.index, args.query, args.minutes, args.time_field)
    print(n)
    return 0 if n > 0 else 1


def cmd_top(s, args):
    buckets = s.top(args.index, args.field, args.query, args.minutes, args.size, args.time_field)
    print(f"{args.field:30} MENSAJES")
    for b in buckets:
        print(f"{str(b['key']):30} {b['doc_count']}")
    return 0 if buckets else 1


def cmd_ingest_demo(s, args):
    """Crea un índice con mapeo explícito y le mete eventos de ejemplo con _bulk (práctica de la API)."""
    exists = True
    try:
        s.call("HEAD", f"/{args.index}")
    except SystemExit:
        exists = False
    if not exists:
        s.call("PUT", f"/{args.index}", {
            "settings": {"number_of_shards": 1, "number_of_replicas": 0},    # un nodo: 0 réplicas -> green
            "mappings": {"properties": {
                "timestamp": {"type": "date"}, "host": {"type": "keyword"}, "level": {"type": "keyword"},
                "app": {"type": "keyword"}, "src_ip": {"type": "ip"}, "message": {"type": "text"}}},
        })
        print(f"índice {args.index} creado (1 shard, 0 réplicas)")
    hosts = ["rhel7-app01", "rhel8-app01", "rhel9-app01", "rhel10-app01", "dns01"]
    lines = []
    for i in range(args.count):
        level = random.choices(["INFO", "WARN", "ERROR"], weights=[80, 15, 5])[0]
        doc = {"timestamp": datetime.now(timezone.utc).isoformat(), "host": random.choice(hosts), "level": level,
               "app": "pagos-demo", "src_ip": f"10.10.10.{random.choice([11, 12, 13, 14, 20])}",
               "message": f"operación {i} procesada con resultado {level}"}
        lines.append(json.dumps({"index": {"_index": args.index}}))
        lines.append(json.dumps(doc))
    res = s.call("POST", "/_bulk?refresh=wait_for", raw_body=("\n".join(lines) + "\n").encode())
    print(f"_bulk: {len(res.get('items', []))} documento(s), errores={res.get('errors')}")
    return 1 if res.get("errors") else 0


def build_parser():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--url", default="http://127.0.0.1:9200")
    ap.add_argument("--user")
    ap.add_argument("--password-file")
    ap.add_argument("--index", default="graylog_*")
    ap.add_argument("--time-field", default="timestamp")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("health")
    sub.add_parser("indices")
    for name in ("search", "count", "top"):
        p = sub.add_parser(name)
        p.add_argument("--query", default="*")
        p.add_argument("--minutes", type=int, default=60)
        p.add_argument("--size", type=int, default=10)
        p.add_argument("--index", default=argparse.SUPPRESS)
        if name == "search":
            p.add_argument("--fields", default="timestamp,source,message")
        if name == "top":
            p.add_argument("--field", default="source")
    p = sub.add_parser("ingest-demo")
    p.add_argument("--count", type=int, default=50)
    p.add_argument("--index", default=argparse.SUPPRESS)
    return ap


def main(argv=None):
    args = build_parser().parse_args(argv)
    if args.cmd == "ingest-demo" and args.index == "graylog_*":
        args.index = "lab-demo"     # nunca escribir en los índices que gestiona Graylog
    password = None
    if args.password_file:
        with open(args.password_file, encoding="utf-8") as fh:
            password = fh.read().strip()
    s = Search(args.url, args.user, password)
    handlers = {"health": cmd_health, "indices": cmd_indices, "search": cmd_search, "count": cmd_count,
                "top": cmd_top, "ingest-demo": cmd_ingest_demo}
    return handlers[args.cmd](s, args)


if __name__ == "__main__":
    sys.exit(main())
