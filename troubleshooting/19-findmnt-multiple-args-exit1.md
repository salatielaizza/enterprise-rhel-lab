# 19 — `stage2/02-lvm.sh` se detiene tras "Montajes:" (findmnt con varias rutas devuelve 1)

**Objetivo**: reconocer un fallo silencioso de `set -e` causado por un comando puramente informativo
que devuelve código de salida distinto de cero sin que nada esté realmente roto en el sistema.

**Preparación**: Etapa 2 en curso, `stage2/02-lvm.sh` ya ejecutado al menos una vez con éxito (VG/LV/fstab
ya creados; el script es idempotente y en la segunda ejecución solo verifica).

## Contexto: por qué costó tanto encontrarlo

Este caso apareció encadenado justo detrás del caso 18 (SSH lentísimo por `UseDNS`). Mientras SSH tardaba
~80 segundos por conexión, cada intento de reproducir el problema "a mano" (ejecutando comandos sueltos
por SSH para medir tiempos) tardaba tanto que resultaba indistinguible de un cuelgue real — y como cada
comando individual (`findmnt` con una sola ruta, `vgs`, `mount -a`...) SÍ devolvía éxito al probarlo
suelto, el fallo real quedó enmascarado hasta que se resolvió primero la lentitud de SSH y se pudo ver
con claridad que el script terminaba (rápido) pero con error.

## Síntoma

`scripts/lab.sh stage2 all` (o `stage2/02-lvm.sh` ejecutado directamente en la VM) se detiene justo
después de imprimir `Montajes:`, sin ningún mensaje de `fatal`/`ERROR`, y sin llegar a la línea siguiente
del script (`vgs vg_data`) ni a `set_stage 2`.

## Hipótesis descartadas (ver también el caso 18, del que este es continuación directa)

Antes de aislar este fallo se descartaron, con evidencia: sobrecarga del host, lentitud de comandos LVM
individuales, y GSSAPI — ninguna de las tres era la causa de "por qué se detiene", solo enmascaraban el
verdadero problema al hacer indistinguible "tarda mucho" de "falla".

## Diagnóstico que dio con la causa

```bash
ssh <host> 'findmnt -no TARGET,SOURCE,FSTYPE /opt/application/data /var/log/lab-app /backup; echo "EXIT=$?"'
# EXIT=1

ssh <host> 'findmnt /opt/application/data; findmnt /var/log/lab-app; findmnt /backup'
# Las 3 rutas SÍ aparecen correctamente montadas, cada una por separado
```

`findmnt` con **varias rutas posicionales a la vez** junto con `-no TARGET,SOURCE,FSTYPE` devuelve código
de salida 1 en esta combinación (RHEL 7, `util-linux` de esa versión), a pesar de que las 3 rutas están
montadas y correctas — un comportamiento de la propia herramienta, no un fallo del sistema.

## Causa raíz

Línea 53 de `scripts/stage2/02-lvm.sh`:
```bash
say "Montajes:"; findmnt -no TARGET,SOURCE,FSTYPE /opt/application/data /var/log/lab-app /backup
```
es puramente informativa (solo imprime un resumen), pero con `set -euo pipefail` activo en el script, su
código de salida 1 mata el script completo ahí mismo — sin que nada estuviera realmente roto.

## Solución aplicada

```diff
-say "Montajes:"; findmnt -no TARGET,SOURCE,FSTYPE /opt/application/data /var/log/lab-app /backup
+say "Montajes:"
+for mp in /opt/application/data /var/log/lab-app /backup; do
+  findmnt -no TARGET,SOURCE,FSTYPE "$mp" || true
+done
```

Iterar una ruta a la vez (en vez de las 3 en una sola llamada) tanto evita el código de salida espurio
como, además, mejora el diagnóstico: si una ruta concreta fallara de verdad en el futuro, se vería cuál
exactamente, en vez de un fallo opaco de las 3 juntas.

## Validación

```bash
bash -n scripts/stage2/02-lvm.sh
ssh <host> 'sudo bash lab-scripts/stage2/02-lvm.sh; echo "EXIT=$?"'   # EXIT=0
scripts/lab.sh stage2 all      # debe completar 01 a 05 en cada host, sin cortes
```
Confirmado en `rhel7-app01`: tras el parche, `stage2 all` completó correctamente `01-users-groups.sh`,
`02-lvm.sh`, `03-permissions.sh`, `04-sudo.sh` y `05-systemd-app.sh` (servicio `lab-app` activo,
`heartbeat 1` en el journal).

## Prevención

Cuando un comando en un script con `set -e` es puramente informativo (solo imprime algo, no cambia
estado del sistema ni condiciona un paso posterior), envolverlo con `|| true` explícitamente, o preferir
iterar sobre listas de un elemento a la vez en vez de pasarlas todas juntas a una herramienta cuyo
comportamiento con múltiples argumentos posicionales no se ha verificado en la versión concreta de RHEL
que se está soportando (en este caso, RHEL 7 con una versión de `findmnt` distinta a la de RHEL 9/10 con
la que se validaron originalmente los kickstarts, pero **no** este script en concreto).
