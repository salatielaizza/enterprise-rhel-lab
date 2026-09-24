# 21 — `lab-app.env` queda en modo 650 en vez de 640 (ACL heredada del directorio)

**Objetivo**: reconocer por qué `chmod` puede no producir el resultado esperado cuando el fichero está
dentro de un directorio con una ACL por defecto (heredable), y corregirlo sin depender de que `chmod`
"gane" a una entrada de ACL con nombre ya existente.

**Preparación**: Etapa 2 aplicada al menos una vez (`stage2/03-permissions.sh` ejecutado; el escenario de
permisos con ACL ya montado sobre `/opt/application`, `/opt/application/config`, `/opt/application/data`).

## Síntoma

`scripts/lab.sh test all all` reportaba, en **las 6 VMs sin excepción**:
```
FAIL  lab-app.env es 0640 root:application
```
a pesar de que `stage2/03-permissions.sh` termina con `chown root:application ...` y `chmod 0640 ...`
explícitos sobre ese mismo fichero.

## Diagnóstico

```bash
ssh <host> 'sudo stat -c "%U:%G:%a" /opt/application/config/lab-app.env'
# root:application:650   <- no 640

ssh <host> 'sudo getfacl -p /opt/application/config/lab-app.env'
# user::rw-
# group::r-x              <- 'x' de más; debería ser r--
# group:developers:r--
# mask::r-x                <- 'x' de más también en la máscara
# other::---
```
El propietario y grupo eran correctos; solo el bit de "grupo" (que en un fichero con ACL extendida es la
**máscara** la que se reporta en `stat`/`ls -l`, no la entrada `group::` por sí sola) llevaba un `x` que
no debería estar.

## Causa raíz

`stage2/03-permissions.sh` aplica, **antes** de crear `lab-app.env`, una ACL por defecto (heredable) sobre
el directorio `config`:
```bash
setfacl -m d:g:developers:rx /opt/application/config /opt/application/data
```
Cuando el fichero se crea justo después (`printf ... > lab-app.env`), **hereda automáticamente** esa ACL
por defecto (`developers:rx`) como ACL propia del fichero nuevo. El `chmod 0640` que se ejecuta a
continuación solo recalcula la **máscara** de la ACL existente — no elimina ni reescribe las entradas con
nombre ya presentes — por lo que el `x` heredado sobrevive tanto en la entrada de grupo como en la
máscara, dando como resultado `650` en vez de `640`. El posterior `setfacl -m g:developers:r` solo
actualiza la entrada `developers` a `r--`, pero no toca `group::` ni fuerza un recálculo limpio de la
máscara a partir de cero.

## Solución aplicada

Añadir `setfacl -b` (borra **todas** las ACL del fichero) inmediatamente después de crearlo y antes de
aplicar los permisos/ACL definitivos, para partir de un estado limpio sin herencia:

```diff
 if [[ ! -f /opt/application/config/lab-app.env ]]; then
   printf 'LAB_APP_INTERVAL=5\nLAB_APP_CRASH_AFTER=0\n' > /opt/application/config/lab-app.env
 fi
+setfacl -b /opt/application/config/lab-app.env
 chown root:application /opt/application/config/lab-app.env
 chmod 0640 /opt/application/config/lab-app.env
 setfacl -m g:developers:r /opt/application/config/lab-app.env
```

Como `chown`/`chmod`/`setfacl` sobre el fichero se ejecutan **fuera** del `if [[ ! -f ... ]]`, relanzar el
script sobre un fichero ya existente (con el permiso incorrecto de una ejecución anterior) también lo
corrige — no hizo falta borrar nada a mano en ninguna VM.

## Validación

Aplicado y confirmado en las 6 VMs (`rhel7/8/9/10-app01`, `dns01`, `ansible01`):
```bash
ssh <host> 'sudo stat -c "%U:%G:%a" /opt/application/config/lab-app.env'
# root:application:640   <- correcto en las 6
```

## Prevención

Cuando un directorio tiene una ACL por defecto (`d:g:...`) y un script va a crear ficheros nuevos dentro
con permisos exactos y predecibles, no basta con `chmod` al final: hay que **limpiar explícitamente**
cualquier ACL heredada primero (`setfacl -b`) antes de aplicar la configuración definitiva, o alternativamente
crear el fichero en una ubicación temporal sin herencia y moverlo después (aunque `mv` conserva
metadatos, incluidas ACL, así que tampoco evita el problema salvo que se cree fuera del árbol con ACL
heredable). La regla general: **`chmod` nunca debe asumirse como "reinicio completo" de los permisos de
un fichero que ya tiene una ACL extendida** — solo ajusta la máscara.

## Nota metodológica

Este caso, junto al 19 y al 20, forma un patrón reconocible en esta sesión: los tres fueron descubiertos
"detrás" de otro problema más ruidoso (los cuelgues de `UseDNS`/`ausearch`). Ninguno de los tres era, en
sí, particularmente difícil de diagnosticar una vez aislado — la dificultad real estuvo en **separar**
varios problemas independientes que se solapaban en el tiempo. La disciplina de "una hipótesis, una
prueba, un descarte" (evidencia con `stat`/`getfacl` en este caso, no solo una suposición sobre cómo
"debería" comportarse `chmod` con ACL) fue lo que permitió encontrar la causa exacta en vez de aplicar un
parche genérico (como re-`chmod`ar en el test, que hubiera ocultado el problema real en el script).
