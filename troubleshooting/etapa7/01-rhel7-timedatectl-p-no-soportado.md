# Etapa 7 · Caso 01 — `timedatectl show -p Timezone --value` falla en RHEL 7 (`systemd` demasiado antiguo)

**Objetivo**: reconocer que un mismo comando de `systemd` puede aceptar flags distintas según la versión
instalada, y escribir una tarea de Ansible que lea el huso horario actual de forma idéntica en las 4
versiones de RHEL del lab (7 a 10), sin ramificar por versión.

**Preparación**: `ansible01` operativo como nodo de control (Etapa 7), inventario `lab` con los 5 nodos
gestionados accesible por clave SSH, primera ejecución real de `ansible-playbook playbooks/site.yml`
contra las VMs (no en `--check`).

## Síntoma

En la primera ejecución real de `site.yml`, la tarea `common : Leer huso horario actual` falla con
`fatal` **solo en `rhel7-app01`**, mientras los otros 4 hosts (`rhel8/9/10-app01`, `dns01`) la completan
sin problema:

```
fatal: [rhel7-app01]: FAILED! => {"changed": false, "cmd": ["timedatectl", "show", "-p", "Timezone", "--value"],
"msg": "non-zero return code", "rc": 1, "stderr": "timedatectl: invalid option -- 'p'", "stdout": ""}
```

Como Ansible detiene el play para ese host en cuanto una tarea falla (sin `ignore_errors`), el resto de
tareas del `common` y todo el rol `lab_users` se saltan para `rhel7-app01` en esa misma pasada
(`PLAY RECAP` mostraba `ok=2 failed=1` solo para ese host).

## Diagnóstico

```bash
ssh adminlab@rhel7-app01
timedatectl show -p Timezone --value
# timedatectl: invalid option -- 'p'

timedatectl --version    # systemd 219 (el que trae RHEL 7)
```
El mismo comando en `rhel8/9/10-app01` funciona sin problema (`systemd` bastante más nuevo en cada una).
`getopt`/`timedatectl` de `systemd 219` no reconoce la flag corta `-p` en absoluto — no es un problema de
sintaxis del valor, es que la opción no existe en esa versión (aunque `systemctl show -p` sí la tiene, no
es el mismo binario ni la misma tabla de opciones).

## Causa raíz

`timedatectl show -p <Propiedad> --value` es sintaxis introducida en una versión de `systemd` posterior a
la que trae RHEL 7 (219). El playbook original asumía que `timedatectl show` se comporta igual en las 4
versiones del lab, lo cual es falso — una diferencia real entre RHEL 7 y el resto, del mismo tipo que ya
se documentó para otros comandos en etapas anteriores (por ejemplo `journalctl -u`, ver
[etapa2/09](../etapa2/09-journalctl-u-no-encuentra-lab-app-rhel8.md)).

## Solución aplicada

Sustituir el comando por uno basado en `timedatectl status` (formato estable desde RHEL 7 hasta RHEL 10),
parseado con `sed`, en vez de depender de flags de `timedatectl show`:

```diff
 - name: Leer huso horario actual (para no marcar 'changed' si ya es el correcto)
-  ansible.builtin.command: timedatectl show -p Timezone --value
+  ansible.builtin.shell: |
+    set -o pipefail
+    timedatectl status | sed -nE 's/.*Time zone:\s*([^ ]+).*/\1/p'
+  args:
+    executable: /bin/bash
   register: lab_current_tz
   changed_when: false
```

(En el primer intento de aplicar este parche se introdujo un segundo bug, autoinducido: un script de
sustitución con doble backslash (`\\s`, `\\1`) en vez de uno solo, que dejaba la expresión regular sin
efecto. Se detectó comparando el fichero editado con lo esperado antes de relanzar el playbook, y se
corrigió con `sed -i 's/\\\\s/\\s/g; s/\\\\1/\\1/g'` sobre el propio fichero de tareas.)

## Validación

```bash
ansible-playbook playbooks/site.yml --syntax-check   # limpio
ansible-playbook playbooks/site.yml                  # ahora completa las 8 tareas en las 5 hosts, incluido rhel7-app01
```
`PLAY RECAP` pasó de `rhel7-app01: ok=2 failed=1` a `rhel7-app01: ok=7 changed=... failed=0`, en línea con
el resto de hosts.

## Prevención

Cuando una tarea de Ansible use un comando de `systemd` (`timedatectl`, `systemctl`, `hostnamectl`...) con
flags que no sean las más básicas, comprobar primero la versión de `systemd` del host más antiguo del
inventario (aquí, RHEL 7 con `systemd 219`) en vez de asumir que el comportamiento es uniforme. Preferir,
cuando exista, el subcomando de solo-lectura más estable (`status`) sobre variantes con flags más
modernas (`show -p ... --value`), y parsear la salida si hace falta — es más texto de shell, pero
funciona igual en las 4 versiones del lab.
