#!/usr/bin/env python3
"""detect_bruteforce.py — Regla de correlación de ejemplo: intentos de SSH fallidos por IP de origen.

Es lo que hace un SIEM por dentro: buscar eventos en una ventana de tiempo, agruparlos y comparar con
un umbral. Mira dos fuentes que llegan a Graylog por caminos distintos:
  - Syslog (rsyslog -> Syslog TCP 5140): líneas de sshd ("Invalid user x from IP", "Failed password ...").
  - auditd (NXLog -> GELF TCP 12201): registros con audit_res=failed y audit_addr=<IP>.

Con --notify, cada alerta se reenvía a Graylog como mensaje GELF (level 2 = crítico, alert_rule=ssh-bruteforce)
para que la vean un stream, un dashboard o una Event Definition.

Uso (en siem01):
  detect_bruteforce.py --minutes 15 --threshold 5
  detect_bruteforce.py --minutes 15 --threshold 5 --notify
Sale con 2 si hay alguna alerta (útil en un temporizador systemd o en un pipeline), 0 si no.
Solo biblioteca estándar.
"""
import argparse
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from os_search import Search  # noqa: E402  (mismo directorio)

SSHD_PATTERNS = [
    re.compile(r"Invalid user (?P<user>\S+) from (?P<ip>\d+\.\d+\.\d+\.\d+)"),
    re.compile(r"Failed (?:password|publickey) for (?:invalid user )?(?P<user>\S+) from (?P<ip>\d+\.\d+\.\d+\.\d+)"),
    re.compile(r"Connection closed by (?:authenticating|invalid) user (?P<user>\S+) (?P<ip>\d+\.\d+\.\d+\.\d+)"),
]
SYSLOG_QUERY = '"Invalid user" OR "Failed password" OR "Failed publickey" OR "Connection closed by invalid user"'
AUDIT_QUERY = "audit_res:failed AND _exists_:audit_addr"


def syslog_failures(search, minutes, size):
    """IP -> nº de fallos y IP -> usuarios probados, a partir del texto de sshd."""
    res = search.search("graylog_*", SYSLOG_QUERY, minutes, size)
    per_ip, users = Counter(), {}
    seen = set()
    for hit in res["hits"]["hits"]:
        msg = hit["_source"].get("message", "")
        for pat in SSHD_PATTERNS:
            m = pat.search(msg)
            if m:
                # una misma conexión deja varias líneas: se cuenta una vez por (host, pid, ip, usuario)
                key = (hit["_source"].get("source"), hit["_source"].get("process_id"), m["ip"], m["user"])
                if key not in seen:
                    seen.add(key)
                    per_ip[m["ip"]] += 1
                    users.setdefault(m["ip"], set()).add(m["user"])
                break
    return per_ip, users


def audit_failures(search, minutes, size):
    buckets = search.top("graylog_*", "audit_addr", AUDIT_QUERY, minutes, size)
    return Counter({b["key"]: b["doc_count"] for b in buckets if b["key"] not in ("?", "")})


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--url", default="http://127.0.0.1:9200")
    ap.add_argument("--minutes", type=int, default=15)
    ap.add_argument("--threshold", type=int, default=5)
    ap.add_argument("--size", type=int, default=500)
    ap.add_argument("--notify", action="store_true", help="reenviar las alertas a Graylog por GELF")
    ap.add_argument("--siem", default="10.10.10.55", help="destino GELF de --notify (Docker publica 12201 en la IP del lab)")
    args = ap.parse_args()

    search = Search(args.url)
    sys_ip, sys_users = syslog_failures(search, args.minutes, args.size)
    aud_ip = audit_failures(search, args.minutes, args.size)

    print(f"Ventana: {args.minutes} min · umbral: {args.threshold} fallos por IP")
    print(f"{'IP ORIGEN':16} {'SYSLOG':>7} {'AUDITD':>7}  USUARIOS PROBADOS")
    alerts = []
    for ip in sorted(set(sys_ip) | set(aud_ip)):
        n_sys, n_aud = sys_ip.get(ip, 0), aud_ip.get(ip, 0)
        tried = ",".join(sorted(sys_users.get(ip, [])))[:60]
        flag = "  <-- ALERTA" if max(n_sys, n_aud) >= args.threshold else ""
        print(f"{ip:16} {n_sys:>7} {n_aud:>7}  {tried}{flag}")
        if flag:
            alerts.append((ip, n_sys, n_aud, tried))
    if not sys_ip and not aud_ip:
        print("(sin intentos fallidos en la ventana)")

    if alerts and args.notify:
        sender = Path(__file__).resolve().parent / "gelf_send.py"
        for ip, n_sys, n_aud, tried in alerts:
            subprocess.run([sys.executable, str(sender), "--host", args.siem, "--proto", "tcp", "--level", "2",
                            "--message", f"ALERTA ssh-bruteforce desde {ip}: {max(n_sys, n_aud)} fallos en {args.minutes} min",
                            "--field", "alert_rule=ssh-bruteforce", "--field", f"src_ip={ip}",
                            "--field", f"users_tried={tried}", "--field", f"window_min={args.minutes}"],
                           check=False, stdout=subprocess.DEVNULL)
        print(f"{len(alerts)} alerta(s) reenviada(s) a Graylog (busca: alert_rule:ssh-bruteforce)")
    return 2 if alerts else 0


if __name__ == "__main__":
    sys.exit(main())
