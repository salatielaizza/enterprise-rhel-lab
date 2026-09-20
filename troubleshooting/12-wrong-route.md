# 12 — Ruta estática incorrecta

**Objetivo**: diagnosticar que **un destino concreto** falla mientras el resto funciona.
**Preparación**: snapshot de rhel9-app01.

## Cómo provocar
`sudo ip route add 10.10.10.20/32 via 10.10.10.99` (runtime). Variante persistente: `sudo nmcli con mod lab0 +ipv4.routes "10.10.10.20/32 10.10.10.99"` + `con up`.

## Síntoma
Solo dns01 (10.10.10.20) es inalcanzable; gateway y demás hosts responden; la resolución DNS falla porque el servidor está "roto" para este cliente.

## Hipótesis
dns01 caído (no: otros clientes lo alcanzan), firewall, ruta específica.

## Diagnóstico
```bash
ip route get 10.10.10.20                  # via 10.10.10.99  ← ruta /32 más específica que la conectada
ip r                                      # aparece 10.10.10.20 via 10.10.10.99
ping -c2 10.10.10.13 ; ping -c2 10.10.10.1     # el resto OK
```
La ruta **más específica** (longest prefix match) gana a la de la subred.

## Causa raíz
Una ruta /32 errónea desvía el tráfico hacia un next-hop inexistente.

## Solución
`sudo ip route del 10.10.10.20/32` (runtime) o `sudo nmcli con mod lab0 -ipv4.routes "10.10.10.20/32 10.10.10.99" && sudo nmcli con up lab0`.

## Validación
`ip route get 10.10.10.20` → `dev ens3` directo; `test_network.sh`.

## Prevención
Rutas estáticas documentadas y en NM (no a mano); revisar `ip r` en cada diagnóstico.
