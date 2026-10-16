#!/usr/bin/env python3
"""gelf_send.py — Envía mensajes GELF 1.1 a Graylog por UDP (con compresión y troceado) o por TCP.

GELF (Graylog Extended Log Format) es JSON con campos fijos (version, host, short_message,
timestamp, level) y campos propios que empiezan por "_" (en Graylog aparecen sin el "_").

Uso:
  gelf_send.py --host 10.10.10.55 --proto udp --message "prueba"            # 1 mensaje
  gelf_send.py --host 10.10.10.55 --proto tcp --count 20 --field app=pagos  # 20 mensajes TCP
  gelf_send.py --host 10.10.10.55 --level 3 --field alert_rule=demo         # level 3 = error (syslog)

Imprime el marcador (lab_marker) para buscarlo después:  lab_marker:<marcador>
Solo biblioteca estándar.
"""
import argparse
import json
import os
import socket
import sys
import time
import uuid
import zlib

GELF_MAGIC = b"\x1e\x0f"     # cabecera de un trozo GELF por UDP
CHUNK_SIZE = 1420            # cabe en una trama Ethernet (MTU 1500) sin fragmentar
MAX_CHUNKS = 128             # límite del protocolo


def build(host, message, level, fields, marker, seq):
    msg = {
        "version": "1.1",
        "host": host,
        "short_message": message,
        "timestamp": round(time.time(), 3),
        "level": level,
        "_lab_marker": marker,
        "_seq": seq,
        "_app": "gelf_send",
    }
    for key, value in fields.items():
        if key in ("id", "_id"):
            raise SystemExit("ERROR: el campo 'id' está reservado en GELF")
        msg["_" + key.lstrip("_")] = value
    return json.dumps(msg, separators=(",", ":")).encode()


def udp_datagrams(payload, compress):
    """Un mensaje UDP -> uno o varios datagramas (troceado GELF si no cabe en uno)."""
    data = zlib.compress(payload) if compress else payload
    if len(data) <= CHUNK_SIZE:
        return [data]
    parts = [data[i:i + CHUNK_SIZE] for i in range(0, len(data), CHUNK_SIZE)]
    if len(parts) > MAX_CHUNKS:
        raise SystemExit(f"ERROR: mensaje demasiado grande ({len(data)} bytes, más de {MAX_CHUNKS} trozos)")
    msg_id = os.urandom(8)    # mismo id en todos los trozos: así Graylog los reensambla
    return [GELF_MAGIC + msg_id + bytes([n, len(parts)]) + part for n, part in enumerate(parts)]


def parse_fields(pairs):
    out = {}
    for pair in pairs:
        if "=" not in pair:
            raise SystemExit(f"ERROR: --field espera clave=valor (recibido: {pair})")
        key, value = pair.split("=", 1)
        out[key] = value
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--host", default="10.10.10.55", help="IP o nombre de Graylog")
    ap.add_argument("--port", type=int, default=12201)
    ap.add_argument("--proto", choices=("udp", "tcp"), default="udp")
    ap.add_argument("--count", type=int, default=1)
    ap.add_argument("--message", default="mensaje de prueba GELF del lab")
    ap.add_argument("--level", type=int, default=6, choices=range(0, 8), help="0=emerg ... 3=err 4=warning 6=info 7=debug")
    ap.add_argument("--field", action="append", default=[], help="campo propio clave=valor (repetible)")
    ap.add_argument("--marker", default=None, help="marcador fijo (por defecto, uno aleatorio)")
    ap.add_argument("--source", default=socket.gethostname().split(".")[0], help="valor del campo host")
    ap.add_argument("--no-compress", action="store_true", help="UDP sin zlib (para verlo con tcpdump -A)")
    ap.add_argument("--big", type=int, default=0, help="añade N bytes de relleno para forzar el troceado UDP")
    args = ap.parse_args()

    marker = args.marker or "lab-" + uuid.uuid4().hex[:12]
    fields = parse_fields(args.field)
    if args.big:
        fields["padding"] = os.urandom(args.big // 2).hex()

    if args.proto == "udp":
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sent = 0
        for seq in range(1, args.count + 1):
            for dgram in udp_datagrams(build(args.source, args.message, args.level, fields, marker, seq), not args.no_compress):
                sock.sendto(dgram, (args.host, args.port))
                sent += 1
        sock.close()
        print(f"UDP {args.host}:{args.port}: {args.count} mensaje(s) en {sent} datagrama(s)")
    else:
        try:
            sock = socket.create_connection((args.host, args.port), timeout=5)
        except OSError as exc:
            print(f"ERROR: no conecta con {args.host}:{args.port}/tcp: {exc}", file=sys.stderr)
            return 1
        with sock:
            for seq in range(1, args.count + 1):
                # GELF TCP: sin compresión, cada mensaje termina en un byte nulo
                sock.sendall(build(args.source, args.message, args.level, fields, marker, seq) + b"\x00")
        print(f"TCP {args.host}:{args.port}: {args.count} mensaje(s)")
    print(f"lab_marker:{marker}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
