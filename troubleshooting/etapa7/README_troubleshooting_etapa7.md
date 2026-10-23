# 🤖 Troubleshooting y guía de estudio — Etapa 7 (automatización con Ansible)

Ver formato y regla general en [`troubleshooting/README.md`](../README.md).

Este documento tiene dos usos:

1. **Índice de los casos reales** de troubleshooting de la Etapa 7.
2. **Base de estudio**: los comandos de Ansible y de bash que usan los scripts y el test de esta etapa, con
   una explicación sencilla de qué hace cada uno y para qué sirve.

> Regla del proyecto: *manual → documentado → repetible → automatizado*. Toda esta etapa se hizo primero a
> mano, fase a fase: ver el recorrido completo en [`scripts/stage7/README_stage7.md`](../../scripts/stage7/README_stage7.md).

---

## 1. Casos documentados

| Caso | Tema |
|---|---|
| [01 rhel7-timedatectl-p-no-soportado](01-rhel7-timedatectl-p-no-soportado.md) 🔎 | `timedatectl show -p Timezone --value` falla en RHEL 7 (`systemd` 219); el arreglo se perdió y reapareció; solución definitiva con `stat` |
| [02 plantilla-timestamp-rompe-idempotencia](02-plantilla-timestamp-rompe-idempotencia.md) 🔎 | Un timestamp dentro de una plantilla comparada rompe la idempotencia (también reapareció) |
| [03 group-vars-ubicacion-incorrecta](03-group-vars-ubicacion-incorrecta.md) 🔎 | `group_vars/` en la raíz del proyecto: invisible para `ansible-playbook`, visible por casualidad en ad-hoc |
| [04 restos-de-ejercicios-en-nodo-de-control](04-restos-de-ejercicios-en-nodo-de-control.md) 🔎 | Variables de prueba olvidadas en `ansible01` sobreviven a `stage7-setup` (`cp -a` no borra) y desvían el huso de dos hosts; `--check` sin `-v` lo ocultaba |
| [05 modulo-propio-python3-falla-en-rhel7](05-modulo-propio-python3-falla-en-rhel7.md) 🔎 | El módulo propio `lab.utils.lab_uptime_pretty` da `SyntaxError` solo en RHEL 7: usaba f-strings y el nodo ejecuta los módulos con Python 2.7 |
| [06 marca-etapa7-no-se-aplica-ni-se-comprueba](06-marca-etapa7-no-se-aplica-ni-se-comprueba.md) 🔎 | `lab.sh stage7 site` no copiaba `03-mark-stage.sh` a los nodos, el test de la marca usaba una función de `lib.sh` dentro de `bash -c` y `ansible01` nunca se marcaba |
| [07 molecule-escenario-nunca-ejecutado](07-molecule-escenario-nunca-ejecutado.md) 🔎 | El escenario de Molecule nunca se había ejecutado: Docker → Podman, credenciales caducadas de Docker Hub en el host, `sudo` siendo root en el contenedor y ruta de roles |

🔎 = encontrado de forma orgánica al ejecutar contra las VMs reales (o, el 07, contra Podman en el host).

**El hilo común** de 01, 02, 04 y 06: el estado del nodo de control o de los nodos **no coincidía con el repo**
(arreglos solo en `ansible01`, restos que no estaban en git, scripts que dependían de una copia anterior). La
regla que sale de ellos: *la fuente de verdad es git, y cada script lleva al host lo que necesita*.

Relacionados de otras etapas: [etapa2/09](../etapa2/09-journalctl-u-no-encuentra-lab-app-rhel8.md) (un comando
que se comporta distinto según la versión, como el 01) y [etapa6/01](../etapa6/01-log-verbose-set-e-lab-healthcheck.md)
(trampas de bash en scripts y tests, como el 06).

---

## 2. Flujo de la etapa (orden exacto)

| # | Comando | Script que ejecuta | Dónde corre |
|---|---|---|---|
| 1 | `scripts/lab.sh stage7-setup` | `push ansible01` → `stage7/01-ansible-control-setup.sh` → reparto de la clave → `02-run-playbook.sh ping` → `03-mark-stage.sh` | Host → `ansible01` (root) y nodos (`authorized_keys`) |
| 2 | `scripts/lab.sh stage7 facts` | `02-run-playbook.sh facts` → `playbooks/facts.yml` | `ansible01` (como `adminlab`) |
| 3 | `scripts/lab.sh stage7 site` | `02-run-playbook.sh site` → `playbooks/site.yml`; después `push` + `03-mark-stage.sh` en cada nodo | `ansible01` → los 5 nodos |
| 4 | `scripts/lab.sh stage7 advanced [-e lab_simulate_failure=true]` | `02-run-playbook.sh advanced` | `ansible01` → los 5 nodos |
| 5 | `scripts/lab.sh stage7 dynamic_inventory_demo` | `02-run-playbook.sh dynamic_inventory_demo` | `ansible01` (conexión local) |
| 6 | `scripts/lab.sh test all all` | `run_all.sh` → añade `test_ansible.sh` desde `LAB_STAGE` ≥ 7 | Las 6 VMs |
| 7 | `molecule test` (en `roles/common`, venv activado) | Escenario `molecule/default` | Host (Podman) |
| 8 | `scripts/lab.sh snapshot create all 7` | `scripts/03-snapshot.sh` | Host |

---

## 3. Comandos de los scripts, explicados

### 3.1 `01-ansible-control-setup.sh` — nodo de control

| Comando | Qué hace | Por qué |
|---|---|---|
| `command -v ansible-playbook` | Devuelve 0 si el comando existe | Instalar solo si falta (idempotente) |
| `dnf install -y ansible-core` | Instala el motor de Ansible | En RHEL 8/9/10 está en AppStream; en RHEL 7, EPEL |
| `rsync -a --delete --itemize-changes --exclude … SRC/ DEST/` | Deja `DEST` idéntico a `SRC`: copia, actualiza **y borra lo que sobra**. `--itemize-changes` describe cada cambio (`*deleting` para los borrados) | Con `cp -a` sobrevivían restos (caso 04). Lo excluido no se copia ni se borra (`vault.yml`) |
| `awk '$1 == "*deleting" {print $2}'` | Se queda con las rutas borradas | Para listarlas: nada desaparece sin que se vea |
| `chown -R adminlab:adminlab ~/ansible-lab` | Todo el proyecto pasa a ser de `adminlab` | Ansible se ejecuta como `adminlab`, no como root |
| `ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519 -C …` | Par de claves sin passphrase | `ansible01` debe entrar en los nodos sin intervención; ed25519 es corta y moderna |
| `openssl rand -base64 24 > ~/.vault_pass.txt` + `chmod 600` | Contraseña aleatoria de 32 caracteres, legible solo por su dueño | Nunca va a git |
| `sudo -u adminlab env ANSIBLE_CONFIG=… ansible-vault view …` | Comprueba si el vault ya se descifra | Si sí, no se vuelve a cifrar (idempotente). `ANSIBLE_CONFIG` fuerza el `ansible.cfg` del lab aunque el directorio actual sea otro |
| `ansible-vault encrypt vault.yml` | Cifra el fichero con AES-256 | Sin `--vault-password-file`: ya lo da `ansible.cfg` (repetirlo crea dos vault-id en conflicto) |

### 3.2 `02-run-playbook.sh` — lanzar un playbook como `adminlab`

| Comando | Qué hace | Por qué |
|---|---|---|
| `runuser -l adminlab -c "cd ~/ansible-lab && ansible-playbook …"` | Ejecuta como `adminlab` con su entorno de login | La clave SSH, `ansible.cfg` y `.vault_pass.txt` son suyos. `runuser` es para root (no pide contraseña); `su` sí la pediría |
| `printf '%q ' "$@"` | Escapa cada argumento para pasarlo dentro de una cadena de shell | **Sin argumentos devuelve `''`**: por eso solo se usa si `$# -gt 0` (si no, Ansible veía un segundo playbook de nombre vacío) |
| `ansible-playbook -i inventory/dynamic_inventory_demo.py …` | Usa otro inventario en vez del de `ansible.cfg` | `-i` sustituye al inventario por defecto; se puede repetir para combinar varios |

### 3.3 `03-mark-stage.sh` y `lab.sh`

| Comando | Qué hace | Por qué |
|---|---|---|
| `hostname -s` | Nombre corto del host | En `ansible01` se exige `ansible.cfg` y `.vault_pass.txt`; en los nodos, el marcador del rol |
| `set_stage 7` | `LAB_STAGE=7` en `/etc/lab-release`, **solo si la etapa actual es menor** | Nunca baja la etapa de un host más avanzado |
| `push <host>` | Borra y vuelve a copiar `~/lab-scripts` en el host | Todo `run_remote` debe ir precedido de su `push` (caso 06) |
| `run_remote <host> stage7/03-mark-stage.sh` | `ssh` + `sudo -n bash lab-scripts/…` | `-n`: si `sudo` pidiera contraseña, falla en vez de quedarse esperando |
| `grep -qxF "$pubkey" ~/.ssh/authorized_keys \|\| echo "$pubkey" >> …` | Añade la clave solo si no está | `-x` línea exacta, `-F` texto literal (no expresión regular): idempotente |

---

## 4. Comandos de Ansible de la etapa, explicados

### 4.1 Ad-hoc (`ansible`)

| Comando | Qué hace |
|---|---|
| `ansible lab -m ping` | Comprueba SSH + Python en cada host (no es ICMP) |
| `ansible lab -b -m command -a whoami` | `-b` (*become*): ejecuta con sudo. Debe responder `root` |
| `ansible lab -m setup -a 'filter=ansible_distribution*'` | Muestra los *facts* filtrados |
| `ansible lab -m debug -a 'var=lab_timezone' -o` | Valor efectivo de una variable en cada host; `-o` = una línea por host |
| `ansible <host> -m command -a '…'` frente a `-m shell -a '…'` | `command` no usa shell (sin tuberías, redirecciones ni `&&`); `shell` sí |
| `ansible app -m package -a 'name=tree state=present' --check` | Módulo genérico: `yum` en RHEL 7, `dnf` en 8/9/10 |
| `ansible <host> -m copy -a 'content=… dest=…' --diff` | Idempotente: la 2ª vez compara el checksum y no cambia nada |
| `ansible-doc -l` / `ansible-doc -s <módulo>` | Documentación offline (en el examen EX294 no hay Internet) |

### 4.2 Playbooks (`ansible-playbook`)

| Opción | Qué hace |
|---|---|
| `--syntax-check` | Valida el YAML y la estructura sin conectar a nadie |
| `--list-tasks` / `--list-hosts` / `--list-tags` | Qué tareas, en qué hosts y con qué etiquetas, sin ejecutar nada |
| `--check` | Simulación: no cambia nada. **No ejecuta `command`/`shell`** |
| `--diff` | Muestra el antes/después de cada fichero |
| `-v` … `-vvvv` | Más detalle: motivo de cada `skipping` (`-v`), conexión SSH completa (`-vvv`) |
| `--limit <host\|grupo>` | Reduce los hosts del play (nunca los amplía) |
| `--tags <a,b>` / `--skip-tags <a>` | Solo / todo menos las tareas con esas etiquetas |
| `--start-at-task '<nombre*>'` | Empieza en una tarea (ojo con las variables que registraban las anteriores) |
| `--step` | Pide confirmación antes de cada tarea (interactivo: `ssh -t`) |
| `-e var=valor` | Variable extra: **la máxima precedencia**. Siempre llega como texto (de ahí `\| bool`) |

### 4.3 Inventario, configuración y Vault

| Comando | Qué hace |
|---|---|
| `ansible --version \| head -2` | Qué `ansible.cfg` se está usando |
| `ansible-config dump --only-changed` | Qué cambia ese `ansible.cfg` respecto al defecto |
| `ansible-inventory --graph` | Grupos y hosts tal como los entiende Ansible |
| `ansible-inventory --host <host>` | Todas las variables de un host (**muestra el vault descifrado**) |
| `ansible-inventory -i a.ini -i b.py --graph` | Combina varios inventarios |
| `ansible-vault view \| edit \| create <f>` | Ver / editar / crear un fichero cifrado sin dejarlo en claro en disco |
| `ansible-vault encrypt_string '<valor>' --name '<var>'` | Cifra solo un valor dentro de un YAML normal |
| `ansible-vault rekey <f> --new-vault-password-file <p>` | Cambia la contraseña de un fichero cifrado |
| `ansible-vault decrypt --output - <f>` | Descifra a la pantalla; **sin `--output -` deja el fichero en claro** |

### 4.4 Molecule (equipo host)

| Comando | Qué hace |
|---|---|
| `molecule create` / `converge` / `idempotence` / `verify` / `destroy` | Cada fase por separado (encadenadas con `&&`) |
| `molecule test` | Secuencia completa, de cero, destruyendo al final |
| `molecule login` | Shell dentro del contenedor, para investigar |
| `podman ps -a` | Contenedores de Molecule (el escenario se llama `lab-common-rhel9`) |

---

## 5. `tests/test_ansible.sh`, explicado

| Comprobación | Host | Cómo | Por qué así |
|---|---|---|---|
| `ansible-core` / `ansible-playbook` instalados | `ansible01` | `command -v` | |
| Inventario, `ansible.cfg`, `site.yml` presentes | `ansible01` | `test -f` | |
| Clave privada y `.vault_pass.txt` con permisos 600 | `ansible01` | `stat -c %a` | `ssh` rechaza claves con permisos abiertos |
| `vault.yml` cifrado | `ansible01` | `head -1 … \| grep -q '^$ANSIBLE_VAULT'` | Ruta `inventory/group_vars/all/` (caso 03) |
| Proyecto sin restos | `ansible01` | `find … -name '*.lab-bak.*' -o -name '*.swp' -o -path …/host_vars` | Regresión del caso 04 |
| Marcador de gestión presente | nodos | `test -f /etc/ansible-lab-managed.txt` | Lo deja el rol `common` |
| Huso `Europe/Madrid` | nodos | `readlink /etc/localtime` | `timedatectl show -p` no existe en RHEL 7 (caso 01) |
| `tree`, usuarios demo, contraseña bloqueada | nodos | `rpm -q`, `id`, `passwd -S` (`L`/`LK`) | |
| Etapa 7 marcada | todos | Función `etapa7_marcada` pasada a `check` | Una función de `lib.sh` no existe dentro de `bash -c` (caso 06) |

---

## 6. Chuleta: síntoma → comandos

| Síntoma | Primeros comandos |
|---|---|
| `No inventory was parsed` / `Could not match supplied host pattern` | `pwd` (¿estás en `~/ansible-lab` de `ansible01`?) · `ansible --version \| head -2` |
| `UNREACHABLE` | `ssh -i ~/.ssh/id_ed25519 adminlab@<ip>` · `virsh list` (¿VM encendida?) · `ansible <host> -m ping -vvv` |
| `Missing sudo password` / `a password is required` | `ansible <host> -b -m command -a whoami` · ¿`become` necesario? (en contenedores, no: caso 07) |
| Una variable no tiene el valor esperado | `ansible <host> -m debug -a var=<var> -o` · `ansible-inventory --host <host>` · `find inventory -type f` (restos: caso 04) |
| `changed` en cada ejecución | `ansible-playbook … --check --diff` (¿qué línea cambia? ¿una fecha?: caso 02) · tareas `command` sin `changed_when` |
| `skipping` sospechoso en `--check` | Repetir con `-v` y buscar *"would have run"* |
| Falla solo en `rhel7-app01` | `ansible rhel7-app01 -m setup -a 'filter=ansible_python_version'` (Python 2.7) · versión de `systemd` (219) · `dnf` frente a `package` |
| `SyntaxError` en un módulo propio | ¿f-strings u otra sintaxis solo de Python 3? (caso 05) · `python -m py_compile` en el nodo antiguo |
| `Decryption failed (no vault secrets …)` | ¿`vault_password_file` en `ansible.cfg`? · ¿se hizo `rekey`? · `ls -l ~/.vault_pass.txt` |
| Un arreglo "vuelve" tras `stage7-setup` | `git status` / `git log` (¿está en el repo o solo en `ansible01`?: casos 01 y 02) |
| `the playbook: could not be found` | `ls playbooks/` · ¿argumento vacío? (bug del `printf`, corregido) |
| Molecule: `Can't pull image` / `incorrect username or password` | `podman login --get-login docker.io` · credenciales en `~/.docker/config.json` (caso 07) |
| Molecule: `The role '…' was not found` | `ANSIBLE_ROLES_PATH` en `provisioner.env` de `molecule.yml` |

---

## 7. Preguntas de repaso

1. **¿Qué significa que Ansible sea *agentless* y *push*?** Que los nodos no tienen ningún demonio: el
   controlador entra por SSH, sube un módulo Python, lo ejecuta y lo borra. *Push* porque el controlador decide
   cuándo; en un modelo *pull*, cada nodo pide su configuración.
2. **¿Qué es la idempotencia y cómo se demuestra?** Aplicar lo mismo 1 o N veces deja el mismo estado; a partir
   de la 2ª vez, `changed=0`. Se demuestra con dos ejecuciones seguidas.
3. **¿Por qué `--check` no basta para fiarse de un cambio?** Porque no ejecuta `command`/`shell` y su `skipping`
   no distingue "no hace falta" de "haría falta". Hay que usar `-v` y módulos de solo lectura.
4. **Orden de búsqueda de `ansible.cfg`.** `ANSIBLE_CONFIG` → `./ansible.cfg` → `~/.ansible.cfg` →
   `/etc/ansible/ansible.cfg`; gana el primero, no se combinan.
5. **Precedencia de variables, de menor a mayor.** `defaults` del rol → `group_vars/all` → `group_vars/<grupo>` →
   `host_vars/<host>` → `vars` del play → `-e`.
6. **¿`command` o `shell`?** `command` siempre que se pueda (sin shell, más seguro); `shell` solo si hacen falta
   tuberías o redirecciones. Y antes que los dos, el módulo específico.
7. **¿`dnf` o `package`?** `package`, si el inventario mezcla RHEL 7 (`yum`) con 8/9/10 (`dnf`).
8. **¿Qué protege Ansible Vault y qué no?** Protege el secreto en git y en disco; no frente a quien tenga la
   contraseña de vault en el nodo de control. Si esta se filtra, `rekey` no basta: hay que cambiar los secretos.
9. **¿Dónde se ejecuta un módulo propio y dónde un filtro?** El módulo, en el nodo gestionado con **su** Python;
   el filtro, en el nodo de control.
10. **¿Qué hace `block/rescue/always`?** Es el `try/catch/finally` de Ansible: `rescue` solo si falla algo del
    `block`; `always`, siempre. Un fallo rescatado no cuenta como `failed` (pero un `rescue` que solo informa
    esconde el error).
11. **¿Para qué sirve `serial`?** Para desplegar por lotes (*rolling update*): con `serial: 2` y 5 hosts, 3 lotes.
    Con `max_fail_percentage`, un lote fallido detiene los siguientes.
12. **¿Qué devuelve un inventario dinámico?** Con `--list`, un JSON con los grupos y `_meta.hostvars`; con
    `--host`, las variables de un host. Si trae `_meta`, Ansible no llama a `--host` por cada host.
13. **¿Para qué sirve Molecule?** Para probar un rol en un contenedor desechable (`converge`, `idempotence`,
    `verify`) antes de lanzarlo contra servidores reales.
14. **¿Por qué un `become = True` global puede ser un problema?** Porque se aplica a todo, incluso a conexiones
    locales y a `delegate_to: localhost`. Mínimo privilegio: activarlo solo donde haga falta.
