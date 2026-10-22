# Etapa 7 · Caso 02 — Un timestamp dentro de una plantilla comparada rompe la idempotencia

> **Actualización 2026-09-29:** el arreglo descrito abajo se aplicó solo en `ansible01` y **nunca llegó al
> repositorio**, así que el siguiente `stage7-setup` lo sobrescribió y el timestamp reapareció. Ver
> [Reaparición y solución definitiva](#reaparición-y-solución-definitiva).

**Objetivo**: reconocer un error de diseño clásico en Ansible — incluir un valor que cambia en cada
ejecución (la hora actual) dentro del contenido de un fichero que el módulo `template` usa para decidir
si algo "cambió" — y corregirlo sin perder la información de auditoría que ese valor pretendía dar.

**Preparación**: rol `common` con la tarea `Desplegar marcador de gestión por Ansible` (módulo
`ansible.builtin.template`) ya aplicada al menos una vez contra los 5 nodos gestionados.

## Síntoma

Al ejecutar `ansible-playbook playbooks/site.yml` **dos veces seguidas**, sin tocar nada entre medias, la
tarea `common : Desplegar marcador de gestión por Ansible` vuelve a salir `changed` en la segunda pasada
(y con ella el *handler* que registra el cambio en `/var/log/lab-ansible-lab.log`), en vez del `changed=0`
que se espera de una tarea idempotente:

```
TASK [common : Desplegar marcador de gestión por Ansible ...]
changed: [rhel8-app01]
changed: [rhel9-app01]
changed: [dns01]
changed: [rhel10-app01]

RUNNING HANDLER [common : registrar cambio de configuracion gestionada por ansible]
changed: [rhel8-app01]
...
```
Esto viola el criterio de aceptación de la etapa (`scripts/lab.sh stage7 site` ejecutado dos veces: la
segunda debe dar `changed=0` en todos los nodos).

## Diagnóstico

```bash
ansible-playbook playbooks/site.yml --check --diff
```
El `--diff` muestra que el contenido "antes/después" que Ansible compara para decidir si el fichero
cambió incluye una línea con la hora exacta de la ejecución:
```
+ultima_aplicacion: 2026-09-28T13:37:41Z
```
Esa línea sale de la plantilla `roles/common/templates/ansible-lab-managed.j2`:
```jinja2
ultima_aplicacion: {{ ansible_date_time.iso8601 }}
```
`ansible_date_time.iso8601` es la hora **actual** del sistema en el momento de la ejecución — cambia en
cada pasada del playbook, así que el contenido renderizado nunca puede coincidir con el que ya hay en
disco de la ejecución anterior.

## Causa raíz

El módulo `template` decide `changed`/`ok` comparando el contenido que renderizaría con el contenido ya
existente en el destino. Meter un valor que cambia por sí solo en cada ejecución (un timestamp de "ahora")
dentro de ese contenido garantiza que la comparación **siempre** dé diferente, por diseño — no es un fallo
de Ansible, es una contradicción en cómo se usó la plantilla: se le pidió simultáneamente "sé idempotente"
y "cambia siempre".

## Solución aplicada

Quitar el timestamp del contenido que se compara (la plantilla del marcador), dejando solo datos que de
verdad reflejan el estado del sistema (host, distro, intérprete Python, huso horario objetivo):

```diff
 # Gestionado por Ansible — enterprise-rhel-lab (Etapa 7)
 # NO EDITAR A MANO: se sobrescribe en cada 'lab.sh stage7 site' (módulo template)
 host: {{ inventory_hostname }}
 distro: {{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }} (major {{ ansible_facts['distribution_major_version'] }})
 interprete_python_detectado: {{ ansible_facts['python']['executable'] }}
 huso_horario_objetivo: {{ lab_timezone }}
-ultima_aplicacion: {{ ansible_date_time.iso8601 }}
```
El registro de *cuándo* hubo un cambio real sigue existiendo, pero en el sitio correcto: el *handler* que
añade una línea con fecha a `/var/log/lab-ansible-lab.log` — ese sí debe llevar timestamp, porque es un
**log que acumula histórico** (cada línea es un evento distinto por diseño), no un fichero de estado cuyo
contenido se compara para decidir idempotencia. Al quitar el timestamp de la plantilla, el handler
también deja de dispararse en ejecuciones sin cambios reales, porque ya no se le notifica desde una tarea
que antes cambiaba siempre.

## Validación

```bash
ansible-playbook playbooks/site.yml   # 1ª vez: template 'changed' solo si de verdad difiere el contenido
ansible-playbook playbooks/site.yml   # 2ª vez, inmediatamente después: 'ok', no 'changed'
```
`PLAY RECAP` de la segunda pasada: `changed=0` en los 5 nodos.

## Reaparición y solución definitiva

**2026-09-29.** Tras `scripts/lab.sh stage7-setup`, la simulación volvió a proponer el timestamp en los 5
nodos:

```bash
ansible-playbook playbooks/site.yml --check --diff
```
```
 huso_horario_objetivo: Europe/Madrid
+ultima_aplicacion: 2026-09-29T08:53:55Z
changed: [rhel7-app01] ... (los 5 hosts, más el handler)
PLAY RECAP: ok=7 changed=2 ... en los 5
```

Lo llamativo: el fichero **desplegado** en los nodos ya no tenía esa línea (la versión corregida se había
aplicado el día anterior), pero la plantilla de `ansible01`, recién recopiada desde el repo, sí. El arreglo
se había hecho **solo en el nodo de control** y `stage7-setup` lo sobrescribió con la versión de git.

**Solución definitiva, en el repo (commit `7461a5e`).** Plantilla sin la línea `ultima_aplicacion` y con el
motivo explicado en un comentario Jinja, que no aparece en el fichero renderizado (así el contenido
desplegado sigue siendo idéntico y no provoca ningún cambio):

```jinja2
{# Sin marca de tiempo a propósito: un valor que cambia en cada ejecución hace
   que esta tarea salga 'changed' siempre y rompe la idempotencia. La fecha de
   cada cambio real queda en /var/log/lab-ansible-lab.log (handler). Este
   comentario Jinja no aparece en el fichero renderizado. #}
```

Validado con `--check --diff` (template `ok` sin diff, sin handler) y con **4 ejecuciones seguidas de
`site.yml` con `changed=0`** en los 5 hosts (Fase 11 del recorrido manual).

## Prevención

Nunca incluir un valor "vivo" (hora actual, PID, número aleatorio) dentro del contenido de un fichero que
un módulo declarativo (`template`, `copy`, `lineinfile` con `line:` variable...) usa para decidir si algo
cambió. Si hace falta un registro de *cuándo* pasó algo, que viva en un *log* que se **añade** (una línea
nueva por evento, nunca se reescribe el fichero entero) y se dispare solo mediante `notify`/handler desde
una tarea que sí sea idempotente por sí misma — nunca en el propio contenido comparado.

Y, de la reaparición: **todo arreglo se hace en el repo** (`scripts/stage7/files/`) y se lleva al nodo de
control con `stage7-setup`, nunca al revés. Ver también [01](01-rhel7-timedatectl-p-no-soportado.md) (la
misma causa) y [04](04-restos-de-ejercicios-en-nodo-de-control.md) (el problema simétrico).
