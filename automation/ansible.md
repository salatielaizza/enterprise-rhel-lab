# Automatización con Ansible (Etapa 7)

## Objetivo
Convertir `ansible01` en un **nodo de control** real que gestiona el resto del lab (`rhel7/8/9/10-app01`, `dns01`) de forma **agentless**, **idempotente** y **reproducible**: los mismos tres verbos que ya rigen las Etapas 1-6 (*manual → documentado → repetible → automatizado*), aplicados ahora a "muchos hosts a la vez" con la herramienta que el mercado espera para ese trabajo.

## Preparación
- Etapas 1-6 completadas (`ansible01` existe desde la Etapa 1, con IP `10.10.10.30` reservada; ver `architecture/hosts.md`).
- El equipo host (Linux Mint) ya tiene acceso SSH de confianza a los 6 hosts desde la Etapa 1 (`~/.ssh/lab_config`) — esto es lo que `lab.sh stage7-setup` reutiliza para no pedir ninguna contraseña nueva.
- `scripts/stage7/01-ansible-control-setup.sh` y `02-run-playbook.sh` (ejecutados por `lab.sh stage7-setup`/`stage7`) dejan `ansible01` con Ansible instalado, su propia clave SSH, y el inventario/playbooks/roles de `scripts/stage7/files/` copiados a `~adminlab/ansible-lab/`.

## Conceptos y motivación (por qué Ansible, y no solo "más bash")

**Qué es y qué lo hace distinto.** Ansible es una herramienta de automatización **agentless**: no instala ningún demonio en los nodos gestionados (a diferencia de Puppet/Chef/Salt en su modo agente clásico), solo necesita SSH y Python en el extremo — ambos ya presentes en cualquier RHEL. El **nodo de control** (aquí, `ansible01`) es quien decide qué hacer y se conecta *hacia* los nodos gestionados: es un modelo **push**, al contrario que herramientas *pull* (donde cada nodo tira de su propia configuración periódicamente). Esto encaja de forma natural con el propio `lab.sh`, que ya empuja scripts a las VMs (`push`/`run_remote`) — Ansible formaliza y generaliza exactamente ese mismo patrón, con un lenguaje declarativo (YAML) en vez de bash imperativo.

**Por qué importa en ESTE proyecto.** Las Etapas 2, 5 y 6 ya resuelven "aplica esto en 6 hosts" con un bucle `for h in $(targets "$1")` en `lab.sh` + scripts bash idempotentes. Funciona, pero con limitaciones reales que Ansible resuelve de fábrica:
- **Idempotencia declarada, no programada a mano.** En bash, cada script tiene que comprobar "¿ya está así?" antes de cambiar algo (`grep -Eq ... || sed -i ...`, como en `stage5/03-os-hardening.sh`). En Ansible, la mayoría de módulos (`package`, `user`, `service`, `template`...) ya son idempotentes por diseño: declaras el **estado deseado** (`state: present`) y el módulo decide si hay que actuar.
- **Reporte de "qué cambió" gratis.** `changed=0` en el PLAY RECAP es una prueba automática de idempotencia en cada ejecución — en bash hay que fabricar esa señal a mano (o no se tiene).
- **Un mismo lenguaje para "un servidor" y para "mil".** El inventario (`inventory/hosts.ini`) desacopla "qué hago" (el playbook) de "a quién se lo hago" (el grupo de hosts); con `--limit` se aplica a un subconjunto sin tocar el playbook.
- **Secretos gestionados, no evitados.** Ansible Vault permite versionar en git un valor cifrado (ver más abajo) — con bash puro, la alternativa habitual es "no lo automatices" o "pídelo por `read -s`" en cada ejecución.

**Piezas del lenguaje, con su porqué:**
| Concepto | Qué es | Dónde se usa en esta etapa |
|---|---|---|
| **Inventario** | Lista de hosts gestionados, agrupados | `inventory/hosts.ini`: grupos `app`, `dns`, y `lab` (unión de ambos) |
| **Módulo** | Unidad de trabajo reutilizable (crear usuario, instalar paquete...) | `ansible.builtin.package`, `.user`, `.template`, `.command` |
| **Ad-hoc** | Un módulo, una vez, sin escribir un playbook | `ansible lab -m ping`, `ansible app -b -m command -a "df -h"` |
| **Playbook** | Secuencia de tareas en YAML, repetible | `playbooks/site.yml`, `playbooks/facts.yml` |
| **Rol** | Playbook empaquetado y reutilizable (tasks/defaults/templates/handlers) | `roles/common/`, `roles/lab_users/` |
| **Facts** | Datos que Ansible recoge de cada host antes de actuar | `ansible_facts['distribution_major_version']`, usado para ver RHEL7 vs 8/9/10 |
| **Variable y su precedencia** | Mismo nombre, valor distinto según de dónde venga | `defaults/main.yml` (más bajo) < `group_vars/all/vars.yml` < `-e` en la CLI (más alto) — ver el ejercicio del paso 7 del checklist |
| **Handler** | Tarea que solo se ejecuta si algo cambió de verdad | `roles/common/handlers/main.yml`, disparado por `notify` al desplegar la plantilla |
| **Plantilla (Jinja2)** | Fichero generado con variables/facts embebidos | `roles/common/templates/ansible-lab-managed.j2` |
| **Vault** | Cifrado de variables sensibles, versionable en git | `group_vars/all/vault.yml` (ver más abajo) |
| **`become`** | Escalado de privilegios (equivalente a `sudo`) en el nodo gestionado | Todo el playbook corre con `become: true` vía `ansible.cfg`, como usuario `adminlab` |

## Procedimiento manual y comandos

Antes de automatizar con `lab.sh`, esto es lo que hace cada pieza si se ejecutara a mano:

| Comando | Qué hace | Por qué | Salida / fallo |
|---|---|---|---|
| `sudo dnf install -y ansible-core` (RHEL 8-10) / `sudo dnf install -y epel-release && sudo dnf install -y ansible-core` (RHEL 7) | Instala el paquete | `ansible-core` está en AppStream desde RHEL 8; en RHEL 7 hace falta EPEL | `ansible --version` muestra `core 2.x` |
| `ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519` (como `adminlab`, en ansible01) | Genera el par de claves del controlador | Es la identidad con la que ansible01 entra por SSH en el resto de VMs | `~/.ssh/id_ed25519.pub` |
| Añadir esa clave pública a `~/.ssh/authorized_keys` en cada nodo gestionado | Confía en ansible01 | Sin esto, cualquier módulo falla con `Permission denied` | — |
| `ansible lab -m ping` | Ad-hoc: comprueba conectividad + que Python responde | Primer chequeo, sin tocar nada | `pong` por cada host |
| `ansible lab -b -m command -a whoami` | Ad-hoc con `become`: comprueba que el `sudo` funciona | Sin esto, cualquier tarea que necesite privilegios fallará más adelante, no antes | `root` por cada host |
| `ansible-playbook playbooks/facts.yml` | Vuelca facts relevantes de cada host | Explorar qué sabe Ansible de cada VM sin cambiar nada | Distro, versión, intérprete Python, IP |
| `ansible-playbook playbooks/site.yml` | Aplica el rol `common` + `lab_users` | La automatización real de esta etapa | `PLAY RECAP` con `changed=`/`failed=` por host |
| `ansible-playbook playbooks/site.yml --limit rhel9-app01` | Igual, pero solo en un host | Practicar/depurar sin tocar el resto | — |
| `ansible-playbook playbooks/site.yml --check --diff` | Simulación: qué cambiaría, sin aplicarlo | Revisar el impacto antes de ejecutar de verdad | Muestra el diff de lo que tocaría |
| `ansible-vault view group_vars/all/vault.yml` | Descifra y muestra el contenido | Ver el secreto de demo sin dejarlo en claro en el fichero | Pide la contraseña si no hay `vault_password_file` configurado |
| `ansible-vault edit group_vars/all/vault.yml` | Edita el secreto cifrado in-place | Cambiarlo sin exponerlo nunca en texto plano en disco | — |

## Automatización

`scripts/lab.sh stage7-setup` (una vez): instala Ansible en `ansible01`, genera su clave SSH y la distribuye a los 5 nodos gestionados usando el acceso que el host ya tenía desde la Etapa 1, sube `inventory/`, `ansible.cfg`, `playbooks/` y `roles/`, genera la contraseña de Ansible Vault (local, nunca en git) y cifra `group_vars/all/vault.yml` la primera vez, y termina comprobando conectividad con `ansible lab -m ping` + `-b -m command -a whoami`.

`scripts/lab.sh stage7 <site|facts|ping> [--limit <grupo|host>]` (las veces que haga falta): ejecuta el playbook indicado desde `ansible01`. Tras un `site` que termina sin errores, `lab.sh` marca la Etapa 7 como alcanzada (`set_stage 7`) en cada uno de los 5 nodos gestionados — la propia Etapa 7 la aplica Ansible, pero el marcador de progreso del lab sigue siendo el mismo que en el resto de etapas.

## Cómo experimentar (cambiar variables, límites, ad-hoc)

Esto es exploración real, no solo lectura — todo lo siguiente es seguro de repetir cuantas veces se quiera:

1. **Cambia una variable y repite.** Edita `lab_timezone` en `group_vars/all/vars.yml` (por ejemplo a `UTC`), sube el cambio (`push`/`stage7-setup` vuelve a copiar `files/`) y ejecuta `lab.sh stage7 site`. Solo la tarea de huso horario debería marcar `changed`; el resto sigue en `ok`.
2. **Observa la precedencia de variables.** Comenta temporalmente `lab_common_packages` en `group_vars/all/vars.yml` y repite `stage7 site`: el rol cae al *default* (`roles/common/defaults/main.yml`, solo `tree`) en vez del valor de tres paquetes. Esto es exactamente lo que un entrevistador espera que sepas explicar: `defaults` < `group_vars` < `-e` de la línea de comandos.
3. **Limita el alcance.** `lab.sh stage7 site --limit rhel9-app01` aplica el playbook SOLO a esa VM — útil para probar un cambio antes de lanzarlo a los 5 nodos.
4. **Simula sin aplicar.** Desde `ansible01`: `cd ~/ansible-lab && ansible-playbook playbooks/site.yml --check --diff` muestra qué cambiaría sin tocar nada.
5. **Ad-hoc, sin playbook.** `ansible app -b -m dnf -a "name=htop state=present"` instala algo puntual en el grupo `app`; `ansible lab -a "uptime"` lo ejecuta en todos. Un ad-hoc es la herramienta correcta para "esto lo necesito una vez", un playbook para "esto quiero que se mantenga así".
6. **Añade tu propia variable de usuario de prueba.** Amplía la lista `lab_demo_users` de `group_vars/all/vars.yml` con un tercer usuario y repite `stage7 site`: verás `changed` solo para ese usuario nuevo, cero cambios en los otros dos — la prueba práctica de idempotencia que pedían las "ampliaciones futuras" de las Etapas 5 y 6.
7. **Rompe algo a propósito y depúralo.** Cambia el nombre de un módulo en `roles/common/tasks/main.yml` (p. ej. `ansible.builtin.pakage`, con una errata) y ejecuta `ansible-playbook --syntax-check playbooks/site.yml`: verás cómo Ansible localiza el fichero y la línea exactos del error, igual que `bash -n` en las etapas anteriores.

## Parte avanzada

Todo lo que sigue se ha probado de verdad antes de entregarse (no es solo teoría): el módulo y el filtro propios se ejecutaron con `ansible-doc`/`ansible localhost`, el playbook `advanced.yml` se corrió dos veces (con y sin fallo simulado) contra hosts locales, el inventario dinámico se validó contra un servidor de prueba con la forma real de la API, y el escenario de Molecule se aceptó con `molecule list`.

### Manejo de errores estructurado: `block`/`rescue`/`always`, y `serial`

`playbooks/advanced.yml` aplica esto sobre el grupo `lab` real (no sobre el inventario de demo):
- **`block`**: agrupa tareas relacionadas como una unidad.
- **`rescue`**: se ejecuta SOLO si algo del `block` falló — y evita que ese fallo aborte el play para el resto de hosts del lote, algo que un `when` normal no puede hacer.
- **`always`**: se ejecuta pase lo que pase (haya fallado el `block` o no) — aquí, deja constancia en `/var/log/lab-ansible-lab.log`.
- **`serial: 2`**: procesa los 5 nodos gestionados en lotes de 2 (un *rolling update* básico) en vez de lanzarlos todos a la vez — la base de cualquier despliegue por lotes en producción.

Pruébalo tú mismo, cambiando una sola variable:
```bash
scripts/lab.sh stage7 advanced                              # camino normal: 'rescued=0' en el PLAY RECAP
scripts/lab.sh stage7 advanced -e lab_simulate_failure=true  # dispara el rescue: 'rescued=N', el play NO aborta
```

### Módulos y filtros propios: la colección local `lab.utils`

`scripts/stage7/files/collections/ansible_collections/lab/utils/` es una colección **local** (no publicada en Galaxy), resuelta gracias a `collections_path = ./collections` en `ansible.cfg`:
- **Módulo** `lab.utils.lab_uptime_pretty` (`plugins/modules/lab_uptime_pretty.py`): lee `/proc/uptime`/`/proc/loadavg` y devuelve el uptime en formato "Nd Nh Nm". Es de solo lectura (`changed=False` siempre, soporta `--check`) — el esqueleto mínimo real de un módulo Ansible: `AnsibleModule`, `DOCUMENTATION`/`EXAMPLES`/`RETURN`, `exit_json`/`fail_json`.
- **Filtro** `lab.utils.to_lab_slug` (`plugins/filter/lab_filters.py`): convierte un texto en un "slug" (minúsculas, guiones) — una `FilterModule` con un método `filters()`, el contrato mínimo de un filtro Jinja2 propio.
- Ambos se usan en `playbooks/advanced.yml`, y se pueden probar sueltos:
  ```bash
  ansible-doc lab.utils.lab_uptime_pretty
  ansible lab -m lab.utils.lab_uptime_pretty --limit rhel9-app01
  ansible lab -m debug -a "msg={{ inventory_hostname | lab.utils.to_lab_slug }}"
  ```

**Un error real, encontrado y corregido durante la elaboración:** el primer borrador del módulo llevaba el shebang `#!/usr/bin/env python3` (la forma "normal" de cualquier script Python). Al ejecutarlo con Ansible fallaba con `The module interpreter '/usr/bin/env python3' was not found`, aunque `/usr/bin/env python3` funciona perfectamente en una terminal normal. La causa: el mecanismo de *interpreter discovery* de Ansible (que sustituye el intérprete por el que detecta en cada host) solo reconoce y reescribe el shebang **`#!/usr/bin/python`** — el que usan todos los módulos `builtin` — no `#!/usr/bin/env python3`. Cambiar el shebang a `#!/usr/bin/python` lo arregló al instante (confirmado ejecutándolo de verdad). Es la convención documentada oficialmente para escribir módulos Ansible, y precisamente por no ser obvia es un error habitual la primera vez que se escribe uno.

### Inventario dinámico (demo con una API pública)

`scripts/stage7/files/inventory/dynamic_inventory_demo.py` es un script de inventario dinámico real y ejecutable: implementa el contrato `--list`/`--host` que usa cualquier inventario dinámico de verdad (AWS, VMware, NetBox...), pero en vez de una nube consulta [JSONPlaceholder](https://jsonplaceholder.typicode.com/users), una API pública gratuita pensada para pruebas (sin clave, sin datos reales). Cada "host" que genera usa `ansible_connection=local` — **nunca** intenta una conexión SSH real; el objetivo es entender el mecanismo, no gestionar esos datos como si fueran servidores.

```bash
scripts/lab.sh stage7 dynamic_inventory_demo     # requiere que ansible01 tenga salida a Internet (ya la tiene, vía el NAT del lab)
```

El script agrupa dinámicamente por empresa (un dato que solo se conoce en tiempo de ejecución, al llegar la respuesta de la API) y se degrada con elegancia: si la API no responde, imprime un aviso por stderr y un inventario vacío, en vez de reventar con una traza de Python — así lo verás tú mismo si lo pruebas sin red (`ansible-inventory -i inventory/dynamic_inventory_demo.py --list`).

### Testing de roles con Molecule

`scripts/stage7/files/roles/common/molecule/default/` (`molecule.yml`, `converge.yml`, `verify.yml`) es un escenario real de [Molecule](https://ansible.readthedocs.io/projects/molecule/) para probar el rol `common` **aislado**, en un contenedor Docker, sin tocar ninguna VM del lab — el mismo tipo de ciclo rápido que se usa en cualquier equipo que mantenga roles de Ansible en serio (probar el rol antes de aplicarlo a infraestructura real). Se ejecuta en el **equipo host** (Linux Mint con Docker), no en ansible01:

```bash
pip install --user molecule "molecule-plugins[docker]"
ansible-galaxy collection install community.docker ansible.posix
cd scripts/stage7/files/roles/common
molecule test        # dependency -> create -> converge -> idempotence -> verify -> destroy, todo automático
```

La imagen usada (`geerlingguy/docker-rockylinux9-ansible`) es la que usa buena parte de la comunidad de roles de Ansible para simular un RHEL 9 con **systemd real** dentro del contenedor — necesario porque el rol usa `timedatectl`, que exige systemd como PID 1 (un contenedor "pelado" no lo tiene). `molecule test` incluye un paso de **idempotencia** automático: falla si una segunda ejecución del rol marca algún `changed` — exactamente la misma prueba que el paso 4 del checklist de esta etapa, pero aislada y sin necesitar las VMs reales.

## Verificación
`tests/test_ansible.sh` distingue por host (como `lab-healthcheck.sh` en la Etapa 6): en `ansible01` comprueba que Ansible está instalado, que existen inventario/playbooks/clave SSH, y que `vault.yml` está realmente cifrado (no en texto plano); en los 5 nodos gestionados comprueba el marcador `/etc/ansible-lab-managed.txt`, el huso horario, el paquete `tree`, los dos usuarios de demostración (creados y con la contraseña bloqueada) y que la Etapa 7 quedó marcada.

## Troubleshooting relacionado
Todavía no hay ningún caso real de esta etapa en `troubleshooting/` — la lección que sí se encontró (el conflicto de `--vault-password-file` duplicado, ver "Errores comunes" más abajo) se detectó y corrigió **durante la elaboración**, antes de tocar las VMs reales, así que no se documenta como caso de troubleshooting (esos se reservan para fallos reales al ejecutar en las VMs; ver `troubleshooting/README.md`). En cuanto `lab.sh stage7-setup`/`stage7 site` se ejecuten de verdad y aparezca algo inesperado, se documentará aquí con el mismo formato que los casos `20` y `28`.

## Errores comunes
- **Pasar `--vault-password-file` en la línea de comandos cuando `ansible.cfg` ya lo define.** Produce `Specify the vault-id to encrypt with --encrypt-vault-id` (dos vault-id `default` en conflicto). Solución: dejar que `ansible.cfg` sea la única fuente (vía `ANSIBLE_CONFIG` apuntando al directorio del lab), sin repetir el flag — así se hizo en `01-ansible-control-setup.sh`.
- **Confundir `hosts: all` con `hosts: lab`.** `all` incluiría también `ansible01` si estuviera en el inventario; aquí `lab` (el grupo explícito de nodos gestionados) evita que el controlador se gestione accidentalmente a sí mismo.
- **Editar `group_vars/all/vault.yml` a mano.** Un fichero cifrado por Ansible Vault NUNCA se edita con `vim` directamente (se corrompe el cifrado); siempre `ansible-vault edit`.
- **Poner un secreto real en `group_vars/all/vars.yml` "porque es más rápido".** Ese fichero se sube a git en claro — el secreto va SIEMPRE en el `vault.yml` cifrado; `vars.yml` solo referencia su nombre de variable.
- **Módulo `command`/`shell` marcado `changed` siempre.** Si una tarea con `command`/`shell` no declara `changed_when`, Ansible la marca como "cambiada" en cada ejecución aunque no haya hecho nada (rompe la idempotencia visible en el PLAY RECAP) — por eso `roles/common/tasks/main.yml` usa `changed_when: false` en la lectura del huso horario.
- **Shebang `#!/usr/bin/env python3` en un módulo propio.** Falla con `The module interpreter '/usr/bin/env python3' was not found`, aunque ese mismo comando funcione perfectamente en una terminal. Un módulo Ansible se escribe con `#!/usr/bin/python` (sin `env`, sin versión): es el único shebang que el *interpreter discovery* de Ansible reconoce y sustituye por el intérprete real de cada host. Ver la sección "Parte avanzada" para el caso real encontrado al escribir `lab.utils.lab_uptime_pretty`.

## Diferencias RHEL 7 / 8 / 9 / 10
`ansible-core` está en el repositorio **AppStream** desde RHEL 8 en adelante; en **RHEL 7** hace falta habilitar **EPEL** primero (`01-ansible-control-setup.sh` lo detecta y lo hace automáticamente, sin intervención). RHEL 7 trae **Python 2** por defecto (`/usr/bin/python2`), mientras que RHEL 8/9/10 traen **Python 3** (`/usr/libexec/platform-python` o `/usr/bin/python3` según la versión) — `interpreter_python = auto_silent` en `ansible.cfg` deja que Ansible detecte el intérprete correcto por host automáticamente en vez de fijarlo a mano; `playbooks/facts.yml` muestra qué intérprete detectó realmente en cada uno. El módulo `ansible.builtin.package` traduce a `dnf`/`yum` según lo que encuentre instalado, sin que el playbook tenga que saber cuál es cuál.

## Prevención
Ejecutar siempre `ansible-playbook --syntax-check` antes de un `site` real; usar `--check --diff` para ver el impacto antes de aplicar un cambio nuevo; nunca guardar un secreto sin cifrar, ni la contraseña de vault, en el repositorio; mantener `hosts: lab` (nunca `all`) para que el controlador no se autogestione por accidente.

## Relevancia profesional
Ansible es, con diferencia, la herramienta de automatización más solicitada en vacantes de administración de sistemas Linux/Red Hat: la propia Red Hat lo confirma dedicándole una certificación específica, el examen **EX294 (Red Hat Certified Engineer, RHCE)** — ver la [página oficial de Red Hat Training para el EX294](https://www.redhat.com/en/services/training/ex294-red-hat-certified-engineer-rhce-exam-red-hat-enterprise-linux) — que en la práctica se pide en gran parte de las ofertas de sysadmin/DevOps junior-mid con Red Hat. Los propios listados de vacantes (por ejemplo en [ZipRecruiter, "Ansible Jobs"](https://www.ziprecruiter.com/Jobs/Ansible)) muestran un rango salarial muy amplio (desde roles junior hasta especialistas senior) precisamente porque la demanda cubre desde "sabe escribir un playbook" hasta "diseña roles y arquitectura de automatización para cientos de hosts". En entrevista, los temas de esta etapa (idempotencia, `become`, inventario, precedencia de variables, Ansible Vault) aparecen de forma recurrente como preguntas de fondo, no solo de sintaxis — ver el compendio de [RHCE Interview Questions (DevOps Training Institute)](https://www.devopstraininginstitute.com/blog/most-asked-rhce-interview-questions-updated). Saber explicar **por qué** Ansible es agentless/push y **cuándo** conviene un ad-hoc frente a un playbook suele distinguir a quien solo ha memorizado sintaxis de quien lo ha usado de verdad en producción.

## Ampliaciones futuras
Un rol `lab_webapp` cuando se despliegue Apache httpd/NGINX (Etapa 9), reutilizando los mismos `group_vars`/patrones de esta etapa; `ansible-lint` como comprobación adicional a `--syntax-check`, si se instala en el equipo host; explorar `ansible-pull` como contraste pedagógico frente al modelo *push* usado aquí; un inventario dinámico de verdad sobre las propias VMs del lab (generado desde `results/facts/` o desde `virsh list`, en vez de IPs fijas en `hosts.ini`) — el de `dynamic_inventory_demo.py` es deliberadamente ficticio para no arriesgar nada, pero la mecánica es la misma; llevar el escenario de Molecule a CI (GitHub Actions) si el repositorio se sube a un remoto con integración continua.
