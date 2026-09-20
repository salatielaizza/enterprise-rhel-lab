# 01 — Fallo del servidor DNS (dns01)

**Objetivo**: reconocer que la caída de dns01 rompe la resolución de todos y probar el diagnóstico por capas.
**Preparación**: Etapa 4 completa (`stage4-clients all`); snapshot de dns01 y de un cliente (rhel9-app01).

## Cómo provocar
En dns01: `sudo systemctl stop named`.

## Síntoma
En rhel9-app01: `ssh`/`curl`/`dnf` por nombre tardan y fallan; `ping 10.10.10.20` **sí** responde; `ping 1.1.1.1` **sí**.

## Hipótesis
(a) Red caída — descartada por los pings. (b) DNS del cliente mal — ver `resolv.conf`. (c) Servicio DNS parado. (d) Firewall.

## Diagnóstico
```bash
cat /etc/resolv.conf                       # nameserver 10.10.10.20 (correcto)
getent hosts rhel7-app01                   # tarda y no devuelve nada
dig @10.10.10.20 rhel7-app01.lab.local     # ";; communications error … connection refused" (o timeout)
nc -zvu 10.10.10.20 53                     # en dns01: ss -lun | grep :53  -> vacío
# En dns01:
systemctl status named ; journalctl -u named -n 30
```
Evidencia clave: ICMP OK + puerto 53 sin respuesta ⇒ el problema está en el **servicio**, no en la red.

## Causa raíz
`named` detenido (aquí a propósito; en la vida real: zona inválida tras una edición, disco lleno, OOM).

## Solución
`sudo named-checkconf -z /etc/named.conf && sudo systemctl start named`.

## Validación
`dig @10.10.10.20 rhel7-app01.lab.local +short` → 10.10.10.11; `scripts/lab.sh test test_dns.sh rhel9-app01`.

## Prevención
Validar siempre con `named-checkconf -z` y `named-checkzone` antes de recargar; segundo DNS (futuro); monitorización de 53/udp (Etapa 11).
