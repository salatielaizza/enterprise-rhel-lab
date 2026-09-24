# 22 — `pwck` reporta `user 'ftp': directory '/var/ftp' does not exist` (solo RHEL 7)

**Objetivo**: reconocer una advertencia de `pwck` que no proviene de ningún script del laboratorio, sino
de la propia instalación base de RHEL 7, y corregirla de forma segura sin afectar a nada en uso.

**Preparación**: Etapa 2 aplicada (`test_users.sh` incluye una comprobación con `pwck -r`).

## Síntoma

`scripts/lab.sh test all all` reportaba, **solo en `rhel7-app01`** (ninguna otra versión):
```
FAIL  pwck sin errores en /etc/passwd y /etc/shadow
```

## Diagnóstico

```bash
ssh rhel7-app01 'sudo pwck -r'
# user 'ftp': directory '/var/ftp' does not exist
# pwck: no changes
```

La cuenta de sistema `ftp` (creada por el propio RHEL 7 al instalar, no por ningún script de este
laboratorio) declara `/var/ftp` como su directorio home en `/etc/passwd`, pero ese directorio no existe
en el sistema instalado. `pwck: no changes` confirma que es una advertencia informativa, no una
inconsistencia que `pwck` considere necesario corregir por sí mismo.

## Causa raíz

Diferencia real entre versiones de RHEL en cómo se aprovisiona la cuenta de sistema `ftp` durante la
instalación base: en RHEL 7 el usuario existe en `/etc/passwd` pero su directorio home no se crea por
defecto (posiblemente porque el paquete que lo crearía, típicamente asociado a `vsftpd`, no forma parte
del grupo de paquetes mínimo `@core` usado en el kickstart). En RHEL 8/9/10 no se reprodujo el mismo
síntoma. No se investigó más a fondo el motivo exacto del cambio entre versiones; el hecho verificado es
que el comportamiento difiere.

## Solución aplicada

Crear el directorio que falta, con los permisos estándar de un directorio de sistema (no se instala ni
configura ningún servicio FTP; el directorio se crea únicamente para que la cuenta de sistema `ftp` quede
consistente con lo que `/etc/passwd` declara):

```bash
sudo mkdir -p /var/ftp
sudo chown root:root /var/ftp
sudo chmod 755 /var/ftp
```

Aplicado manualmente en `rhel7-app01` (única VM afectada).

## Validación

```bash
ssh rhel7-app01 'sudo pwck -r'          # sin salida (limpio)
ssh rhel7-app01 'sudo bash lab-scripts/tests/test_users.sh'
# --- test_users en rhel7-app01: 25 PASS, 0 FAIL
```

`rhel7-app01` pasa a tener **0 FAIL** en `test_users.sh`, y por tanto en el conjunto de tests de la
Etapa 2 (junto con el arreglo del caso 21).

## Prevención / mejora pendiente en el proyecto

Este arreglo se aplicó manualmente, no dentro de ningún script de `scripts/stage2/`. Como es una
particularidad de la instalación base de RHEL 7 y no algo que el laboratorio provoque, el lugar más
correcto para automatizarlo (si se quiere que sea repetible sin intervención manual la próxima vez que se
reinstale `rhel7-app01` desde cero) sería el propio `%post` del kickstart `scripts/kickstart/rhel7.ks.tpl`,
con una comprobación condicional (`mkdir -p /var/ftp` solo si no existe), o alternativamente documentarlo
como un paso esperado de `rhel7/installation.md` a verificar tras cada instalación nueva de esa versión.
No se ha aplicado ninguna de las dos automatizaciones en esta sesión; queda como mejora futura.

## Nota

A diferencia de los casos 19-21, este no es un fallo introducido por ningún script del proyecto —
es la primera diferencia real de comportamiento **entre versiones de RHEL** que aparece durante la
ejecución real de la Etapa 2 (más allá de las ya documentadas en `rhelN/differences.md` a nivel teórico).
Vale la pena anotarlo también ahí como un dato ✔ verificado.
