# 10 — Gateway incorrecto

**Objetivo**: reconocer "la LAN funciona pero no hay salida".
**Preparación**: snapshot de rhel9-app01.

## Cómo provocar
`sudo nmcli con mod lab0 ipv4.gateway 10.10.10.2 && sudo nmcli con up lab0`.

## Síntoma
`ping 10.10.10.20` OK; `ping 1.1.1.1` → `Destination Host Unreachable` desde la propia IP (ARP sin respuesta para .2); `dnf`/`getent hosts redhat.com` fallan.

## Hipótesis
Sin Internet en el host KVM, DNS, ruta por defecto errónea.

## Diagnóstico
```bash
ip r                                    # default via 10.10.10.2
ip route get 1.1.1.1                    # via 10.10.10.2 dev ens3
ip neigh show 10.10.10.2                # FAILED / INCOMPLETE
ping -c2 10.10.10.1                     # el gateway real responde
```

## Causa raíz
La ruta por defecto apunta a una IP inexistente.

## Solución
`sudo nmcli con mod lab0 ipv4.gateway 10.10.10.1 && sudo nmcli con up lab0`.

## Validación
`ping -c2 1.1.1.1`; `test_network.sh`.

## Prevención
Gateway definido en un único lugar (`lib.sh`/`stage3`), comprobación `ip route show default` en los tests.
