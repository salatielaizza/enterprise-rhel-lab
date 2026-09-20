# 11 — Servidor DNS del cliente incorrecto

**Objetivo**: separar "sin red" de "sin DNS".
**Preparación**: snapshot de rhel9-app01 (Etapa 4 aplicada).

## Cómo provocar
`sudo nmcli con mod lab0 ipv4.dns 10.10.10.99 && sudo nmcli con up lab0`.

## Síntoma
`ping 1.1.1.1` OK; `ping redhat.com` → `Temporary failure in name resolution` tras varios segundos; `dnf` falla; `ssh` por IP funciona.

## Hipótesis
Internet caído, DNS caído, cliente apunta al DNS equivocado.

## Diagnóstico
```bash
cat /etc/resolv.conf                       # nameserver 10.10.10.99
getent hosts redhat.com                    # falla (lento)
dig @10.10.10.20 redhat.com +short         # FUNCIONA → el servidor está bien; el fallo es del cliente
sudo tcpdump -ni any port 53               # consultas a .99 sin respuesta
```

## Causa raíz
`ipv4.dns` del perfil `lab0` apunta a un servidor inexistente.

## Solución
`sudo nmcli con mod lab0 ipv4.dns 10.10.10.20 && sudo nmcli con up lab0` (no edites `resolv.conf`: NM lo reescribe).

## Validación
`getent hosts dns01`; `test_dns.sh` y `test_network.sh`.

## Prevención
DNS gestionado por NM/scripts, no a mano; `test_network.sh` comprueba el primer nameserver según la etapa.
