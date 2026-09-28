# Etapa 7 · Caso 03 — `group_vars/` en la raíz del proyecto: invisible para `ansible-playbook`, visible por casualidad en ad-hoc

**Objetivo**: entender exactamente dónde busca Ansible los directorios `group_vars/`/`host_vars/` de forma
automática (junto al inventario y junto al playbook — **no** el directorio de trabajo por sí solo), para
no depender de una coincidencia de `cwd` que solo funciona con comandos ad-hoc.

**Preparación**: estructura de `~/ansible-lab` con `group_vars/all/{vars.yml,vault.yml}` en la **raíz** del
proyecto, `inventory/hosts.ini` y `playbooks/site.yml` en subdirectorios propios (`inventory/`,
`playbooks/`).

## Síntoma

`ansible-playbook playbooks/site.yml` aplicaba valores por defecto de los roles (`lab_timezone: "UTC"`,
`lab_demo_users: []` de `roles/*/defaults/main.yml`) en vez de los definidos en
`group_vars/all/vars.yml` (`lab_timezone: "Europe/Madrid"`, la lista real de usuarios demo). Se veía en
el propio nombre de la tarea, renderizado con Jinja2:
```
TASK [common : Fijar huso horario del lab (UTC)] ***    <- debería decir "(Europe/Madrid)"
```
y en dos tareas que se saltaban siempre, con `-v`:
```
TASK [lab_users : Crear usuarios de demostración] ***
skipping: [rhel7-app01] => {"changed": false, "skipped_reason": "No items in the list"}
```
Sin embargo, un comando ad-hoc ejecutado justo antes, desde el mismo directorio, mostraba las variables
**correctas**:
```bash
ansible lab -m debug -a "var=lab_demo_users"
# lab_demo_users: [ {name: ansible.demo1, ...}, {name: ansible.demo2, ...} ]   <- correcto aquí
```

## Hipótesis descartadas

- **La variable no está definida / el fichero está vacío o mal escrito**: descartada con
  `cat group_vars/all/vars.yml` — el fichero existía, con permisos correctos (`adminlab:adminlab`, `644`)
  y el contenido esperado completo.
- **Problema de precedencia entre `group_vars` y los `defaults` de los roles**: en Ansible, `group_vars`
  siempre tiene prioridad sobre los `defaults` de un rol — si el fichero se hubiera cargado, habría
  ganado. La pista real no era de precedencia, sino de **descubrimiento**: el fichero simplemente no se
  estaba cargando en absoluto durante el playbook.

## Diagnóstico

La diferencia entre el comando ad-hoc (que sí veía las variables) y `ansible-playbook` (que no) fue la
pista clave: Ansible busca `group_vars/`/`host_vars/` automáticamente en dos sitios — junto al **fichero
de inventario** y junto al **playbook** que se está ejecutando — no en el directorio de trabajo por sí
solo. Un comando ad-hoc, al no tener playbook, usa el directorio de trabajo actual (`cwd`) como base de
búsqueda, y por eso "encontraba" `group_vars/` en la raíz de `~/ansible-lab` (porque habíamos hecho
`cd` ahí). `ansible-playbook playbooks/site.yml`, en cambio, busca junto a `playbooks/` (o junto a
`inventory/`) — y en ninguno de los dos sitios estaba `group_vars/`, porque vivía en la raíz del proyecto,
que no es hermano de ninguno de los dos.

## Causa raíz

Estructura de directorios: `group_vars/` no era hermano ni del fichero de inventario
(`inventory/hosts.ini`) ni del playbook (`playbooks/site.yml`). Solo un comando ad-hoc, cuya base de
búsqueda por defecto es el directorio de trabajo, llegaba a encontrarlo — de forma incidental, no porque
la estructura fuera correcta.

## Solución aplicada

Mover `group_vars/` para que sea hermano del inventario, dentro de `inventory/group_vars/` (Ansible
también reconoce esa ubicación, además de junto al playbook):

```bash
mkdir -p inventory/group_vars
mv group_vars/all inventory/group_vars/all
rmdir group_vars
```

## Validación

```bash
ansible-playbook playbooks/site.yml -v 2>&1 | grep -E "Fijar huso|No items|Conditional result"
# TASK [common : Fijar huso horario del lab (Europe/Madrid)] ***    <- ahora correcto

ansible-playbook playbooks/site.yml   # 1ª vez tras el fix
ansible-playbook playbooks/site.yml   # 2ª vez, inmediatamente después: changed=0 en los 5, incluidos
                                       # 'Vault OK: ... (35 caracteres)' y la creación de los 2 usuarios demo
```

## Prevención

`group_vars/`/`host_vars/` deben colocarse **junto al inventario o junto al playbook**, nunca "en algún
sitio del árbol y ya se verá" — y comprobar que se cargan de verdad con un comando ad-hoc **no es
suficiente**, porque ad-hoc usa una regla de búsqueda distinta (basada en `cwd`) a la de
`ansible-playbook` (basada en la ubicación real del inventario/playbook). La forma fiable de verificar es
mirar un valor que solo puede venir de `group_vars` renderizado **dentro del propio play** — por ejemplo,
el nombre de una tarea que interpola esa variable (`"Fijar huso horario del lab ({{ lab_timezone }})"`) —
en vez de fiarse de un `ansible -m debug` ejecutado por separado.
