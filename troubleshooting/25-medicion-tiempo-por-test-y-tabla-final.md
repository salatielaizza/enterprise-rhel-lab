# 25 — Medición de tiempo por sub-test y por VM en `lab.sh test` (con formato Ns/Mm SSs)

**Objetivo**: dejar registro de la mejora de instrumentación (tiempos automáticos en cada ejecución de
tests) y de un patrón de error recurrente con la edición manual en `vim` que costó varios intentos
resolver, con la disciplina de diagnóstico ya establecida en el proyecto.

**No es un fallo del laboratorio**: es una mejora de observabilidad solicitada explícitamente, más la
documentación de las dificultades de edición que surgieron al aplicarla.

## Qué se añadió

**`tests/run_all.sh`**: mide, con el builtin `$SECONDS` de bash, el tiempo de cada sub-test individual
(`t0=$SECONDS` antes, `dt=$((SECONDS - t0))` después) y el tiempo total de toda la ejecución en esa VM
(`START=$SECONDS` al principio, `TOTAL_DT` al final). Una función `fmt_time()` convierte segundos a un
formato legible: `Ns` si es menos de un minuto, `Mm SSs` si es un minuto o más. Se imprime tras cada
sub-test (`    (tiempo: Ns)`) y en la línea de resultado final, y viaja también en la línea de datos
`##HOST_SUMMARY## <host> <pass> <fail> <OK|FALLOS> <tiempo>` que lee `scripts/lab.sh`.

**`scripts/lab.sh`**: define la misma `fmt_time()`, mide su propio tiempo de ida y vuelta (conexión SSH +
ejecución remota) como respaldo, pero **prefiere el tiempo que reporta `run_all.sh`** cuando está
disponible (más preciso, cuenta solo la ejecución real, sin el margen de la propia conexión SSH). La
tabla final de `lab.sh test <script> all` gana una columna `TIEMPO`.

## Resultado real de la primera ejecución (evidencia, no solo el código)

```
### test_install.sh     ... (tiempo: 0s)
### test_users.sh       ... (tiempo: 0s)
### test_permissions.sh ... (tiempo: 0s)
### test_storage.sh     ... (tiempo: 1s)
### test_services.sh    ... (tiempo: 8s)
### test_network.sh     ... (tiempo: 10s)

RESULTADO del host rhel9-app01: OK (106 PASS, 0 FAIL, 19s)
```

Confirma con datos, no solo intuición, algo que se sospechaba desde el principio (ver el hilo de
"¿por qué tarda 30s por host?"): **`test_network.sh` y `test_services.sh` concentran 18 de los 19
segundos totales**, casi todo el tiempo de la batería completa. Explica por qué: `test_network.sh` hace
varios `ping` con timeout (`-W2`, `-W3`) y una resolución DNS externa; `test_services.sh` hace varias
comprobaciones vía `systemctl`/`journalctl` y, en particular, la comprobación de AVC con `timeout 8
ausearch` del caso 20 — que en la mayoría de VMs no necesita agotar el timeout, pero aporta varios
segundos de todas formas por la naturaleza de `ausearch`.

## Dificultad de proceso: ediciones repetidas con `vim` dejaron el fichero roto

Al aplicar el cambio a `scripts/lab.sh` con `vim` a mano (preferencia expresa del usuario, sin
herramientas de edición automatizada), el patrón `:N,Md` (borrar rango) seguido de `O` (abrir línea
encima e insertar) **falló repetidamente de la misma forma**: el contenido nuevo terminaba insertado una
línea más abajo de lo esperado, dejando la rama `facts)` del `case` sin su cuerpo (huérfana, a veces
duplicada) y la rama `test)` con la indentación incorrecta (6 espacios en vez de 2) — un error de sintaxis
bash (`syntax error near unexpected token ')'`) que **no dice directamente qué está mal**, solo dónde
falla el intérprete.

Cada vez se diagnosticó de la misma manera, sin asumir nada: pedir `sed -n 'rango'p` del estado real,
localizar con `grep -n '^  facts)$'` cuántas veces aparecía esa rama (revelando duplicados huérfanos),
y corregir con `sed -i` de una sola operación dirigida por lo observado — nunca aplicando un segundo
intento de `vim` a ciegas sobre el mismo problema. Tras la tercera repetición del mismo patrón de fallo,
se cambió de estrategia: en vez de insertar un fragmento dentro del fichero, se sustituyó el **fichero
completo** (`:%d` + pegado íntegro), lo que eliminó por completo la clase de error (no hay "sitio
equivocado" posible cuando no queda nada del fichero anterior que pueda interferir).

## Validación

```bash
bash -n scripts/lab.sh && bash -n tests/run_all.sh   # sintaxis OK en ambos
bash scripts/lab.sh test all rhel9-app01             # ejecución real, ver salida arriba
```

## Prevención

1. Al editar un bloque `case ... esac` de bash en `vim` insertando contenido nuevo dentro de un rango
   borrado, verificar **inmediatamente** con `sed -n 'rango'p` tras cada operación (no encadenar varias
   ediciones sin comprobar el resultado intermedio) — exactamente lo que ya recomendaba el caso 24, y que
   aquí se repitió por no aplicarlo con suficiente disciplina en cada intento.
2. Cuando un mismo tipo de error de edición se repite dos veces seguidas con el mismo método, **cambiar
   de método** (aquí: pasar de "insertar un fragmento" a "reemplazar el fichero completo") en vez de
   reintentar el mismo procedimiento esperando un resultado distinto.
3. Para instrumentación de tiempos en scripts bash, el builtin `$SECONDS` es suficiente y no requiere
   dependencias externas (`date +%s`, el comando `time`) — se reinicia a 0 en cada invocación nueva de
   bash y se incrementa automáticamente, ideal para medir intervalos dentro del mismo proceso.
