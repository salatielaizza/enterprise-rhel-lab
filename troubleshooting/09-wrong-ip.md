# 09 — Dirección IP incorrecta

**Objetivo**: detectar que un host "existe" pero en otra IP.
**Preparación**: snapshot de rhel9-app01; **hazlo desde `virsh console`** (perderás SSH).

## Cómo provocar
`sudo nmcli con mod lab0 ipv4.addresses 10.10.10.113/24 && sudo nmcli con up lab0`.

## Síntoma
Desde otras VMs: `ping 10.10.10.13` falla; `ssh rhel9-app01` (alias por IP) se cuelga; `dig rhel9-app01.lab.local` sigue devolviendo .13 (el DNS no cambió).

## Hipótesis
Host apagado, red, IP cambiada, firewall, DNS obsoleto.

## Diagnóstico
```bash
# consola de rhel9-app01
ip -br a                                   # 10.10.10.113/24
nmcli -f ipv4.addresses,ipv4.gateway con show lab0
# otro host
ping -c2 10.10.10.13 ; ping -c2 10.10.10.113 ; ip neigh | grep 10.10.10
```

## Causa raíz
La IP configurada no coincide con `hosts.conf`/DNS.

## Solución
`sudo nmcli con mod lab0 ipv4.addresses 10.10.10.13/24 && sudo nmcli con up lab0` (o `lab.sh stage3 rhel9-app01`).

## Validación
`scripts/lab.sh test test_network.sh rhel9-app01`.

## Prevención
Inventario único (`hosts.conf`), IPs reservadas, comprobación periódica con `test_network.sh`, cambios siempre con acceso por consola.
