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

Además: cuando el fix se aplica a mano dentro de `~/ansible-lab` en la VM (como aquí), no está completo
hasta que se replica también en el **origen versionado** que la genera — ver la nota siguiente, que es
justo el error que se cometió con este mismo caso.

## Nota posterior (2026-09-28): el fix no se había llevado al origen

Al retomar la Etapa 7 semanas después (integrando por fin `stage7`/`stage7-setup` en `scripts/lab.sh`,
que se había quedado sin los 4 sitios del checklist), se detectó que `scripts/stage7/files/group_vars/`
—la plantilla de origen que `01-ansible-control-setup.sh` copia con `cp -a` a `~adminlab/ansible-lab` en
cada ejecución— **seguía teniendo `group_vars/` en la raíz**, sin el `mv` a `inventory/group_vars/`
descrito arriba. El `mv` de "Solución aplicada" se había ejecutado en su momento solo sobre la copia
desplegada en la VM, nunca sobre la plantilla versionada en el repo.

Consecuencia práctica: la próxima vez que se ejecutara `lab.sh stage7-setup` (por ejemplo, tras recrear
`ansible01` desde cero), `cp -a` habría vuelto a desplegar la estructura rota, reproduciendo el bug de
este mismo caso pese a estar documentado como resuelto. Se encontró **antes** de ejecutar nada, comparando
el árbol real del repo (`find scripts/stage7/files -maxdepth 2 -type d`) contra lo que este documento
decía — no como fallo en caliente contra las VMs.

Se aprovechó para revisar `scripts/stage7/01-ansible-control-setup.sh` y se encontró un segundo efecto
del mismo desajuste: `VAULT_FILE` seguía apuntando a la ruta vieja
(`"$ANSIBLE_DIR/group_vars/all/vault.yml"`). Con `group_vars/` ya movido y esa variable sin actualizar,
la comprobación `ansible-vault view "$VAULT_FILE"` habría fallado siempre (ruta inexistente), entrando en
la rama que intenta **generar y cifrar un vault nuevo** en el sitio equivocado.

**Corrección aplicada (esta vez sí, en el origen):**
```bash
cd scripts/stage7/files
mkdir -p inventory/group_vars
mv group_vars/all inventory/group_vars/all
rmdir group_vars
```
```bash
sed -i 's#VAULT_FILE="$ANSIBLE_DIR/group_vars/all/vault.yml"#VAULT_FILE="$ANSIBLE_DIR/inventory/group_vars/all/vault.yml"#' \
  scripts/stage7/01-ansible-control-setup.sh
```

**Validado** con `scripts/lab.sh stage7-setup` real: `vault.yml ya estaba cifrado y se descifra
correctamente con la contraseña local` — confirma que `VAULT_FILE` ya apunta al sitio correcto.

**Lección añadida a "Prevención"**: cuando un fix de estructura de directorios se prueba y valida
directamente en una VM (edición en caliente sobre `~/ansible-lab`), **no se considera cerrado** hasta
replicarlo también en la plantilla de origen que reconstruye ese directorio (`scripts/stage7/files/` en
este proyecto) y en cualquier ruta hardcodeada en los scripts de automatización que dependa de esa
estructura (`VAULT_FILE`, en este caso). Antes de dar un `troubleshooting/*.md` por "aplicado", conviene
volver a comprobar la plantilla de origen, no solo el sistema en el que se probó.
