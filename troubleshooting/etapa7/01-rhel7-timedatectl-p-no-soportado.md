# Etapa 7 · Caso 01 — `timedatectl show -p Timezone --value` falla en RHEL 7 (`systemd` demasiado antiguo)

> **Actualización 2026-09-29 / 2026-10-22:** la solución con `timedatectl status` + `sed` descrita abajo se
> aplicó solo en `ansible01` y **nunca llegó al repositorio**, así que el siguiente `stage7-setup` la
> sobrescribió y el fallo reapareció. La solución definitiva (leer el enlace `/etc/localtime` con el módulo
> `stat`) y el mismo fallo en `tests/test_ansible.sh` están en
> [Reaparición y solución definitiva](#reaparición-y-solución-definitiva).

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

*(Primera solución, del 2026-09-28. Funcionó, pero solo existió en `ansible01`: ver la sección siguiente.)*

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

## Reaparición y solución definitiva

**2026-09-29 — el fallo vuelve en el rol.** Al retomar la etapa en modo manual, `scripts/lab.sh stage7-setup`
recopió el proyecto desde `scripts/stage7/files/` a `~adminlab/ansible-lab`, y el rol volvió a tener
`timedatectl show -p Timezone --value`. El arreglo anterior se había editado **solo en `ansible01`**: el repo
nunca lo tuvo, así que cada `stage7-setup` lo sobrescribía. Además, el fallo quedó **oculto** en la
simulación: en `--check`, Ansible no ejecuta las tareas `command`/`shell`, y tanto la lectura como la
fijación del huso salían `skipping` con `failed=0` en los 5 hosts. Solo un ad-hoc lo destapó:

```bash
ansible rhel7-app01,rhel9-app01 -m command -a 'timedatectl show -p Timezone --value'
# rhel7-app01 | FAILED | rc=1 >> timedatectl: invalid option -- 'p'
# rhel9-app01 | CHANGED | rc=0 >> Europe/Madrid
```

**Solución definitiva, en el repo (commit `7461a5e`).** En RHEL 7/8/9/10, `/etc/localtime` es un enlace
simbólico a `../usr/share/zoneinfo/<Zona>`. Se lee con el módulo `stat`, que es de solo lectura (nunca
marca `changed`), funciona igual en las 4 versiones y **sí se ejecuta en `--check`**:

```yaml
- name: Leer huso horario actual (enlace simbólico /etc/localtime)
  ansible.builtin.stat:
    path: /etc/localtime
  register: lab_localtime

- name: "Fijar huso horario del lab ({{ lab_timezone }})"
  ansible.builtin.command: "timedatectl set-timezone {{ lab_timezone }}"
  when: not (lab_localtime.stat.lnk_target | default('')).endswith('zoneinfo/' ~ lab_timezone)
```

Validado con `--check --diff` (la lectura sale `ok` en los 5 hosts, también en `--check`) y con una deriva
provocada a mano (`timedatectl set-timezone UTC` en rhel7-app01): el playbook la detectó y la corrigió.

**2026-10-22 — el mismo comando seguía en el test.** Al preparar el cierre de la etapa, la lectura de
`tests/test_ansible.sh` mostró la comprobación del huso horario con
`timedatectl show -p Timezone --value`: habría dado FAIL en rhel7-app01 en `lab.sh test all all`. Se
corrigió con la misma idea que el rol: `[[ "$(readlink /etc/localtime)" == */zoneinfo/Europe/Madrid ]]`.

## Prevención

Cuando una tarea de Ansible use un comando de `systemd` (`timedatectl`, `systemctl`, `hostnamectl`...) con
flags que no sean las más básicas, comprobar primero la versión de `systemd` del host más antiguo del
inventario (aquí, RHEL 7 con `systemd 219`) en vez de asumir que el comportamiento es uniforme. Preferir,
cuando exista, un **módulo** o una fuente de datos estable (aquí, el enlace `/etc/localtime` leído con
`stat`) antes que parsear la salida de un comando.

Además, lecciones de la reaparición:

- **La fuente de verdad es git** (`scripts/stage7/files/`): un arreglo hecho solo en el nodo de control se
  pierde en el siguiente `stage7-setup`. Ver también [04](04-restos-de-ejercicios-en-nodo-de-control.md),
  el problema simétrico.
- **`--check` no valida las tareas `command`/`shell`**: las omite. Las lecturas deben hacerse con módulos
  de solo lectura (que sí corren en simulación) o llevar `check_mode: false`.
- **Al cambiar cómo se lee algo en el rol, buscar el mismo comando en los tests**
  (`grep -rn 'timedatectl show' scripts/ tests/`).
