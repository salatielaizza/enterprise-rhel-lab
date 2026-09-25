# 24 — Tabla resumen de `lab.sh test`: regresión del `scp -O` y bug de `set -e` con `out="$(...)"`

**Objetivo**: documentar dos problemas encontrados al implementar una mejora de presentación (tabla
resumen de resultados por host al final de `lab.sh test <script> all`), útiles como lección general sobre
`set -e` y sobre el riesgo de sobrescribir un fichero completo sin comparar antes con `diff`.

**No es un fallo del laboratorio en sí**: son dos errores introducidos durante el propio desarrollo de una
mejora, documentados aquí porque ambos son instructivos y podrían repetirse al modificar otros scripts.

## Contexto: la mejora solicitada

Se pidió que `tests/run_all.sh` informara `RESULTADO del host <nombre>: ...` en vez de
`RESULTADO GLOBAL: ...` (ya que ese mensaje, al ejecutarse dentro de una sola VM, nunca tuvo alcance
"global" real), y que `scripts/lab.sh` (que sí ve el resultado de las 6 VMs) agregara al final una tabla
con PASS/FAIL/estado de cada host. Para lograrlo, `tests/run_all.sh` emite una línea de datos
(`##HOST_SUMMARY## <host> <pass> <fail> <OK|FALLOS>`) que `scripts/lab.sh` lee de la salida capturada de
cada `run_remote()`.

## Problema 1 — Regresión: se perdió el fix `scp -O` de un caso anterior

**Síntoma**: al aplicar la nueva versión de `scripts/lab.sh` (entregada como fichero completo para
sobrescribir), reapareció el error ya resuelto en una sesión anterior:
```
scp: realpath lab-scripts/stage2: No such file
scp: upload "lab-scripts/stage2": path canonicalization failed
```
en `rhel8-app01`, idéntico al síntoma original que llevó a añadir `-O` a la llamada de `scp` en `push()`.

**Causa raíz**: el fichero `scripts/lab.sh` completo se generó a partir de una copia de referencia que no
incorporaba el `-O` que el usuario había aplicado manualmente con `nano` en una sesión previa (ver el
caso de esta misma serie sobre SFTP vs `scp` clásico entre OpenSSH 7.4/8.0). Al sobrescribir el fichero
completo sin comparar antes con `diff` contra la copia real, el arreglo anterior quedó revertido sin que
nadie se diera cuenta hasta volver a probar.

**Solución**: reaplicar `-O` en la línea de `scp` dentro de `push()`, y **no volver a entregar ficheros
completos para sobrescribir sin pedir primero un `diff`** contra la copia real del usuario — exactamente
la disciplina que ya se seguía para los ficheros de documentación (`.md`), pero que en este caso concreto
no se aplicó a un fichero de código.

## Problema 2 — `set -e` no detiene la ejecución donde se esperaba... o sí, donde NO se esperaba

**Síntoma**: `bash scripts/lab.sh test all all` se detenía en seco, sin ningún mensaje de error, justo
después de imprimir `[INFO] === run_all.sh en dns01 ===` — exactamente la VM que **siempre** tiene un
`FAIL` esperado (`named`, pendiente de la Etapa 4). Las VMs anteriores (sin ningún FAIL) se procesaban
con normalidad.

**Causa raíz**: la línea
```bash
out="$(run_remote "$h" "tests/$script" 2>&1)"; ec=$?
```
son **dos comandos separados** por el `;`: la asignación con sustitución de comando, y luego la lectura
de `$?`. Bajo `set -euo pipefail` (activo en `scripts/lab.sh` desde su primera línea), si el comando
dentro de `$(...)` devuelve un código distinto de cero, **la asignación en sí hereda ese código de
salida**, y como una asignación de variable no está entre las excepciones que `set -e` respeta (a
diferencia de la condición de un `if`, un `while`, o un operando de `&&`/`||`), el shell completo termina
inmediatamente en esa línea — nunca se llega a ejecutar `ec=$?`, así que el error ni siquiera se llega a
capturar como dato, se pierde junto con el control del script.

**Solución aplicada**:
```diff
-      out="$(run_remote "$h" "tests/$script" 2>&1)"; ec=$?
+      if out="$(run_remote "$h" "tests/$script" 2>&1)"; then
+        ec=0
+      else
+        ec=$?
+      fi
```
Envolver la asignación dentro de la condición de un `if` la coloca en uno de los contextos donde `set -e`
explícitamente **no** actúa (la propia documentación de bash lo llama "no se aplica a comandos cuyo valor
de salida se está comprobando" — condiciones de `if`/`while`/`until`, operandos de `&&`/`||`, y el último
comando de una tubería precedida de `!`). Así se captura `ec` de forma fiable sin perder el control del
script, sea cual sea el código de salida real.

## Complicación adicional durante la edición manual (nota de proceso, no de código)

Al aplicar la corrección con `vim` a mano (sin herramientas de edición automatizada, por preferencia
expresa del usuario), un primer intento de borrar y reinsertar el bloque `test)` con `dd`/`O` dejó el
fichero en un estado inconsistente dos veces seguidas: la primera, con el bloque nuevo insertado dentro
de la cadena de formato de un `printf` ya existente; la segunda, con la cabecera `facts)` eliminada por
completo y el bloque `test)` con indentación incorrecta (6 espacios en vez de 2). Ambas se diagnosticaron
pidiendo la salida exacta de `sed -n 'rango'p` antes de tocar nada más, y se corrigieron con `sed -i` de
una sola línea cada vez, dirigido por el contenido exacto observado (nunca "a ciegas").

## Validación

```bash
bash -n scripts/lab.sh && echo "sintaxis OK"
bash scripts/lab.sh test all all
```
Debe completar las 6 VMs sin abortar en ninguna (incluida `dns01`, con su FAIL esperado), y terminar
mostrando la tabla resumen con una fila por host.

## Prevención

1. Antes de entregar o aplicar un fichero de **código** completo (no solo documentación) para sobrescribir
   uno ya existente y modificado, comparar primero con `diff` contra la copia real — la misma disciplina
   que ya se aplicaba a los `.md`, extendida a los `.sh`.
2. Nunca asumir que `var="$(comando)"; código_que_usa_$?` captura el código de salida bajo `set -e` — hay
   que envolver la asignación en un `if`, o desactivar `set -e` temporalmente con `set +e ... set -e`
   alrededor de ese punto concreto, o añadir `|| true` a la propia sustitución si no importa el código
   real (aunque eso perdería el dato de `$?` para usarlo después, que es justo lo que aquí sí hacía falta).
3. Al editar un fichero grande a mano en `vim` sin herramientas automatizadas, preferir comandos de rango
   explícito (`:170,215d` seguido de inserción exacta) y **verificar con `sed -n` inmediatamente después**
   de cada operación, en vez de encadenar varias ediciones interactivas (`dd`, `O`, etc.) sin comprobar el
   resultado intermedio — así se detecta un desplazamiento o un error de una sola línea antes de que se
   acumule con el siguiente cambio.
