# 13 — Registro DNS incorrecto

**Objetivo**: detectar y corregir un A/PTR erróneo en la zona.
**Preparación**: Etapa 4; snapshot de dns01.

## Cómo provocar
En dns01: `sudo sed -i 's/^rhel9-app01 .*/rhel9-app01    IN  A   10.10.10.131/' /var/named/lab.local.zone` y `sudo rndc reload`.

## Síntoma
`dig @10.10.10.20 rhel9-app01.lab.local +short` → 10.10.10.131; conexiones por nombre van a una IP sin dueño (*timeout*); el PTR de .13 sigue diciendo rhel9-app01 (directa e inversa **no coinciden**). `test_dns.sh` falla en A.

## Hipótesis
Cliente, caché, host apagado, registro erróneo.

## Diagnóstico
```bash
dig @10.10.10.20 rhel9-app01.lab.local +short ; dig @10.10.10.20 -x 10.10.10.13 +short
ssh rhel9-app01 'ip -br a'                # la IP real (por alias de IP) es .13
grep rhel9-app01 /var/named/lab.local.zone /var/named/10.10.10.rev
```

## Causa raíz
El dato de la zona directa no coincide con la realidad (typo).

## Solución
Corregir el A a 10.10.10.13, **subir el serial** (AAMMDDhhmm) y `sudo named-checkzone lab.local /var/named/lab.local.zone && sudo rndc reload`. (O reejecutar `lab.sh stage4-dns`, que regenera zonas desde la plantilla.)

## Validación
`scripts/lab.sh test test_dns.sh all`.

## Prevención
Zonas en Git (plantillas), `named-checkzone` en cada cambio, test A/PTR automatizado.
