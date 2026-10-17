# 01 — `test_siem.sh` da 20 FAIL en `siem01` antes de desplegar el SIEM 🔎

## Objetivo
Comprobar que `siem01` tiene la base del lab (Etapas 2-5) en 0 FAIL antes de empezar la Etapa N2
(bloque 0 de la guía: `scripts/lab.sh test all siem01`).

## Preparación
`siem01` recién creada e integrada con `stage2`, `stage3`, `stage4-clients` y `stage5`. Todavía **no** se había
lanzado `siem-docker`, `siem-stack` ni `siem-inputs`.

## Síntoma
```text
### test_siem.sh
FAIL  /var/lib/docker es un LV propio
FAIL  docker activo y habilitado
...
PASS  imágenes con versión fijada (ninguna :latest)
...
PASS  ningún puerto del SIEM publicado en 0.0.0.0
--- test_siem en siem01: 4 PASS, 20 FAIL
RESULTADO del host siem01: HAY FALLOS (151 PASS, 20 FAIL, 12s)
```

## Hipótesis (descartadas)
- *La base del lab está mal*: descartada. Los otros tests (usuarios, red, DNS, hora, SSH, SELinux, auditd,
  hardening) suman 147 PASS y 0 FAIL; los 20 FAIL son todos de `test_siem.sh`.
- *Algo del SIEM se instaló a medias*: descartada. No se había ejecutado ningún comando `siem-*`.

## Diagnóstico
- `tests/run_all.sh` añade `test_siem.sh` en `siem01` **por el nombre del host**, no por lo desplegado.
- `test_siem.sh` comprobaba en `siem01` todo el servidor (Docker, contenedores, API, entradas, ingesta) sin
  mirar si ya se había desplegado.
- Los 4 PASS eran **vacíos**: sin Docker ni contenedores, "ninguna imagen `:latest`", "MongoDB no publicado",
  "nada en 0.0.0.0" y "sin la contraseña `admin`" se cumplen porque no hay nada que mirar.

## Causa raíz
Defecto de diseño del test: no distinguía "mal configurado" de "todavía no desplegado", y eso contradice la
propia guía, que pide 0 FAIL en `test all siem01` **antes** de empezar.

## Solución aplicada
`test_siem.sh` comprueba el servidor **por fases**, según lo que ya existe:

| Fase | Se detecta por | Comprobaciones | Si falta |
|---|---|---|---|
| 1 | `rpm -q docker-ce` | LV, etiqueta SELinux, Docker, `daemon.json`, `vm.max_map_count` | INFO: pendiente `lab.sh siem-docker` |
| 2 | `/opt/siem/docker-compose.yml` | Contenedores, secretos, exposición, API, OpenSearch, puertos | INFO: pendiente `lab.sh siem-stack` |
| 3 | Entradas `lab-*` en la API de Graylog | Entradas RUNNING, prueba de extremo a extremo, Kubernetes | INFO: pendiente `lab.sh siem-inputs` |

Lo pendiente sale como **INFO**, no como FAIL ni como PASS vacío.

## Validación
```bash
scripts/lab.sh test all siem01
#   INFO  SIEM no desplegado todavía: pendiente 'lab.sh siem-docker' ...
#   --- test_siem en siem01: 0 PASS, 0 FAIL      -> RESULTADO: OK
```
Tras cada `lab.sh siem-*`, el mismo test pasa a comprobar la fase siguiente.

## Prevención
- Un test que solo "aplica" en una fase debe detectar esa fase y no suponerla por el nombre del host.
- Desconfiar de los PASS de comprobaciones negativas ("no hay X"): sin el servicio desplegado, siempre pasan.
