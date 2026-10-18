# 02 — El preflight dice que `siem01.lab.local` no resuelve, y la zona DNS está bien 🔎

## Objetivo
Pasar `scripts/lab.sh siem-preflight` en `siem01` con 0 FAIL antes de `siem-docker` (bloque 1 de la guía).

## Preparación
`siem01` integrada en el lab (Etapas 2-5) y zona `lab.local` regenerada con `lab.sh stage4-dns`, con el registro A
y el PTR de `siem01` (10.10.10.55).

## Síntoma
```text
$ scripts/lab.sh siem-preflight
...
FAIL  DNS: siem01.lab.local no resuelve a 10.10.10.55 (lab.sh stage4-dns con las plantillas nuevas)
PASS  DNS inverso de 10.10.10.55
...
--- preflight: 18 PASS, 0 WARN, 1 FAIL
```

El **inverso** pasa y el **directo** falla con la misma zona y el mismo servidor.

## Hipótesis (descartadas)
- *Falta el registro A en la zona*: descartada. `dns01` lo publica:
  ```text
  $ dig +short @10.10.10.20 siem01.lab.local A
  10.10.10.55
  ```
- *Zona editada pero no recargada (serial sin subir)*: descartada por lo mismo: `dns01` ya responde con el A.
- *El resolvedor del sistema no usa `dns01`*: descartada. `getent ahostsv4 siem01.lab.local` devuelve
  `10.10.10.55`, y el PTR (que sí pregunta a `dns01`) pasa.

## Diagnóstico
La comprobación (línea 60 de `00-preflight.sh`) se quedaba con **la primera dirección** de `getent hosts`:

```bash
if [[ "$(getent hosts "$SIEM_NAME.lab.local" | awk '{print $1}')" == "$SIEM_IP" ]]; then
```

- `getent hosts` **pregunta primero por IPv6** y solo después por IPv4.
- La zona no tiene registro AAAA, así que la consulta IPv6 sigue por `nsswitch.conf`
  (`hosts: files dns myhostname`) hasta **`nss-myhostname`**.
- `nss-myhostname` responde por el **nombre del propio host** con sus direcciones locales, incluida la IPv6 de
  enlace local (`fe80::…`). Por eso, **dentro de `siem01`**, `getent hosts siem01.lab.local` devuelve la `fe80::`
  y no la `10.10.10.55`. La comparación de texto con la IPv4 falla aunque el DNS esté perfecto.
- En cualquier **otro** host (o en el PC con Linux Mint) la misma orden devuelve la IPv4, porque
  `nss-myhostname` solo responde por el nombre propio. Por eso el fallo solo se ve ejecutándolo en `siem01`.

Comprobación en `siem01`:
```bash
getent hosts siem01.lab.local       # fe80::…  siem01.lab.local siem01   (IPv6 de nss-myhostname)
getent ahostsv4 siem01.lab.local    # 10.10.10.55  STREAM siem01.lab.local ...
dig +short @10.10.10.20 siem01.lab.local A    # 10.10.10.55
```

## Causa raíz
Defecto del propio preflight: usaba `getent hosts` (que puede devolver IPv6 primero) para comparar con una IPv4,
y además mezclaba en una sola prueba dos cosas distintas: lo que **publica la zona** y lo que **resuelve el
sistema**.

## Solución aplicada
`00-preflight.sh` separa las dos comprobaciones:

| Comprobación | Orden | Qué demuestra |
|---|---|---|
| DNS (dns01) | `dig +short siem01.lab.local A @10.10.10.20` | La zona `lab.local` publica el A, sin cachés ni `/etc/hosts` |
| DNS (sistema) | `getent ahostsv4 siem01.lab.local` | El sistema (NSS) resuelve el nombre a la IPv4, como lo hará Docker o Graylog |

Las dos comparan con `grep -Fxq` (línea exacta) sobre **todas** las direcciones devueltas, no solo la primera.
Si falla una y la otra no, el mensaje dice dónde mirar: zona en `dns01` o resolución local
(`/etc/resolv.conf`, `/etc/hosts`).

## Validación
```bash
grep -n -E 'getent|dig ' scripts/stageN2/00-preflight.sh     # dig @10.10.10.20 y getent ahostsv4
scripts/lab.sh siem-preflight
#   PASS  DNS (dns01): siem01.lab.local -> 10.10.10.55
#   PASS  DNS (sistema): siem01.lab.local -> 10.10.10.55
#   PASS  DNS inverso de 10.10.10.55
#   --- preflight: 20 PASS, 0 WARN, 0 FAIL
```

## Prevención
- Para comparar con una IPv4, usar `getent ahostsv4` (o `dig … A`), nunca la primera línea de `getent hosts`.
- Una comprobación de DNS que se ejecuta **en el propio host** que se está resolviendo pasa por `nss-myhostname`:
  probarla siempre dentro de la VM, no solo desde el PC.
- Separar "lo publica el servidor" (`dig @servidor`) de "lo resuelve el sistema" (`getent`): son dos averías
  distintas con soluciones distintas (ver Etapa 3, `README_troubleshooting_etapa3.md`, *por qué `getent` y no `dig`*).
