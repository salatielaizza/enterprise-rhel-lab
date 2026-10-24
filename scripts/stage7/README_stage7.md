# 🤖 Etapa 7 — Ansible (`scripts/stage7/`)

> **Estado: ✅ Completa** (2026-10-22). `scripts/lab.sh test all all` con **0 FAIL en las 6 VMs**
> (180/181/181/181/167/166 PASS), `test_ansible` en las 6, `molecule test` en verde con Podman y snapshots
> `*-stage7-complete`. 7 casos reales de troubleshooting, todos encontrados al ejecutar.

## Qué hace esta etapa

Convierte `ansible01` (10.10.10.30) en el **nodo de control** de Ansible del laboratorio. Desde ahí gestiona
por SSH (sin agente) `rhel7/8/9/10-app01` y `dns01` con roles idempotentes, secretos cifrados con
**Ansible Vault** y, en la parte avanzada, `block/rescue/always`, `serial`, una colección propia (módulo +
filtro), inventario dinámico y pruebas del rol `common` con **Molecule + Podman** en el equipo host.

La etapa se hizo **dos veces**: primero **a mano, fase a fase** (ver [Recorrido manual](#recorrido-manual-paso-a-paso-19-fases)),
para entender cada pieza; después con `lab.sh`, para que sea repetible. Los scripts no esconden nada que no
se haya hecho antes a mano.

## Requisitos

| Qué | VMs encendidas |
|---|---|
| `lab.sh stage7-setup`, `lab.sh stage7 site`, `lab.sh test all all` | **Las 6** (`stage7-setup` reparte la clave y hace `ping` a los 5 nodos gestionados) |
| `lab.sh stage7 dynamic_inventory_demo` | `ansible01` + `dns01` (DNS de `ansible01`) y salida a Internet |
| Molecule | Ninguna: corre en el equipo host con Podman |

## Cómo se lanza

```bash
scripts/lab.sh stage7-setup          # ansible-core, proyecto (espejo del repo), clave SSH, vault, ping, marca ansible01
scripts/lab.sh stage7 facts          # exploración (no cambia nada)
scripts/lab.sh stage7 site           # configuración real + marca LAB_STAGE=7 en los 5 nodos (repetible: changed=0)
scripts/lab.sh stage7 site --limit rhel9-app01
scripts/lab.sh stage7 advanced [-e lab_simulate_failure=true]
scripts/lab.sh stage7 dynamic_inventory_demo
scripts/lab.sh test all all          # incluye test_ansible en las 6 VMs
```

## Scripts

| Script | Corre en | Qué hace | Qué modifica |
|---|---|---|---|
| `01-ansible-control-setup.sh` | `ansible01` (root) | Instala `ansible-core` (EPEL si hace falta). **Sincroniza** `files/` con `~adminlab/ansible-lab` con `rsync -a --delete` (espejo exacto del repo; excluye `vault.yml` y `__pycache__/`) y **lista lo que borra**. Genera la clave SSH de `adminlab` y la contraseña de Vault (`~/.vault_pass.txt`, 0600); cifra `inventory/group_vars/all/vault.yml` la 1ª vez; imprime la clave pública para que `lab.sh` la reparta | `~adminlab/ansible-lab/`, `~adminlab/.ssh/`, `~adminlab/.vault_pass.txt` |
| `02-run-playbook.sh <site\|facts\|ping\|advanced\|dynamic_inventory_demo> [--limit …\|-e …]` | `ansible01` | Lanza el playbook **como `adminlab`** (`runuser`), desde `~/ansible-lab` (donde está su `ansible.cfg`). Los argumentos extra solo se pasan si los hay | Lo que haga el playbook en los nodos |
| `03-mark-stage.sh` | cada nodo gestionado **y** `ansible01` | `set_stage 7` (nunca reduce la etapa). En los nodos exige `/etc/ansible-lab-managed.txt` (prueba de que `site` se aplicó); en `ansible01`, `ansible.cfg` y `.vault_pass.txt` | `/etc/lab-release` |

Qué hace `lab.sh` alrededor de los scripts:

- **`stage7-setup`**: `push ansible01` → `01` → reparte la clave pública a los 5 nodos (con el acceso que el
  host ya tiene desde la Etapa 1, sin contraseñas nuevas) → `02 ping` (ping + become) → `03` en `ansible01`.
- **`stage7 site`**: `02 site` y, **solo si terminó sin errores**, `push` + `03` en cada nodo gestionado.

## El proyecto Ansible: `files/` → `~adminlab/ansible-lab`

| Ruta | Contenido |
|---|---|
| `ansible.cfg` | Inventario, `roles_path`, `collections_path`, `vault_password_file`, `become` por sudo, `interpreter_python = auto_silent` |
| `inventory/hosts.ini` | Grupos `app` y `dns`, padre `lab` (sin `ansible01`: es el controlador) |
| `inventory/group_vars/all/vars.yml` | Variables no secretas (`lab_timezone`, paquetes, usuarios demo) y `lab_demo_api_token: "{{ vault_demo_api_token }}"` |
| `inventory/group_vars/all/vault.yml` | Secreto de demo **cifrado** (se crea en `ansible01`; no está en el repo) |
| `inventory/dynamic_inventory_demo.py` | Inventario dinámico de ejemplo (contrato `--list`/`--host`) contra una API pública |
| `playbooks/site.yml` | Roles `common` (tag `common`) + `lab_users` (tag `usuarios`) sobre el grupo `lab` |
| `playbooks/facts.yml` | Solo lectura: distro, versión, intérprete Python detectado |
| `playbooks/advanced.yml` | `block/rescue/always`, `serial: 2`, módulo y filtro propios |
| `playbooks/dynamic_inventory_demo.yml` | Uso del inventario dinámico (`become: false`: no necesita privilegios) |
| `roles/common/` | Paquetes base (tag `paquetes`), huso horario leído con `stat` (tag `huso`), marcador `/etc/ansible-lab-managed.txt` (tag `marcador`), comprobación del vault (tag `vault`), handler; escenario de **Molecule** para Podman |
| `roles/lab_users/` | Usuarios `ansible.demo1/2` con la contraseña bloqueada |
| `collections/ansible_collections/lab/utils/` | Colección propia: módulo `lab_uptime_pretty` (compatible con Python 2.7 y 3) y filtro `to_lab_slug` |

## Recorrido manual paso a paso (19 fases)

Todo lo que hace `lab.sh` se hizo antes a mano. Los comandos `ansible*` se lanzan **en `ansible01`, desde
`~/ansible-lab`** (`ssh adminlab@ansible01`, `cd ~/ansible-lab`) o desde el host con
`ssh adminlab@ansible01 'cd ~/ansible-lab && <comando>'`. Las explicaciones de fondo están en
[`automation/ansible.md`](../../automation/ansible.md) y en la guía de estudio
[`README_troubleshooting_etapa7.md`](../../troubleshooting/etapa7/README_troubleshooting_etapa7.md).

| Fase | Qué se hace | Qué demuestra |
|---|---|---|
| 0 | Enviar los ficheros a `ansible01` (`scp -O`) | Lo único que no tiene nada que aprender a mano |
| 1 | Instalar `ansible-core` | `core 2.14.18`, Python 3.9 en el nodo de control |
| 2 | Copiar el proyecto a `~/ansible-lab` | Dónde vive el proyecto que usa Ansible |
| 3 | Clave SSH del controlador | Ansible entra por SSH con clave, sin contraseña |
| 4 | Distribuir la clave a los 5 nodos | *Agentless*: solo hace falta SSH + Python en los nodos |
| 5 | `ping` + `become` | Conectividad, intérprete por versión y `sudo` |
| 6 | Ansible Vault: contraseña y cifrado | Secretos versionables sin exponerlos |
| 7 | `facts.yml` | RHEL 7 usa Python 2; RHEL 8/9/10, Python 3 |
| 8 | Anatomía del proyecto | Dónde busca Ansible su configuración e inventario |
| 9 | `--check --diff` | Simular antes de aplicar (y sus límites) |
| 10 | Aplicar y corregir la deriva | Declarativo: Ansible devuelve el sistema a su estado |
| 11 | Idempotencia formal | `changed=0` en ejecuciones repetidas |
| 12 | Ad-hoc a fondo | Módulos frente a `command`/`shell` |
| 13 | Variables y precedencia | `defaults` < `group_vars/all` < `group_vars/<grupo>` < `host_vars` < `-e` |
| 14 | Tags, `--limit`, `--start-at-task`, `--step`, `-vvv` | Ejecutar solo una parte y depurar |
| 15 | Vault a fondo | `encrypt_string`, `rekey`, `decrypt --output -`, `edit` |
| 16 | `advanced.yml` | `block/rescue/always`, `serial`, colección propia |
| 17 | Inventario dinámico | Inventario generado por un programa |
| 18 | Cierre de la etapa | Arreglos, `test all all` 0 FAIL, Molecule, snapshots y documentación |

### Fase 0 — Enviar los ficheros a `ansible01` (desde el host)

```bash
ssh adminlab@ansible01 'rm -rf ~/lab-scripts && mkdir -p ~/lab-scripts'
scp -O -q -r scripts/common.sh scripts/stage7 adminlab@ansible01:lab-scripts/
```

### Fase 1 — Instalar `ansible-core` (en `ansible01`)

```bash
sudo -i
dnf repolist                  # la VM debe estar registrada (lab.sh register ansible01 <usuario>)
dnf install -y ansible-core
ansible --version             # ansible [core 2.14.18], python 3.9.25
```

En RHEL 8/9/10 está en **AppStream**; en RHEL 7 haría falta EPEL. `ansible-core` trae solo `ansible.builtin`
(73 módulos), frente a los miles del paquete completo `ansible` (8354 en el equipo host).

### Fase 2 — Copiar el proyecto a la home de `adminlab`

```bash
mkdir -p /home/adminlab/ansible-lab
cp -a /home/adminlab/lab-scripts/stage7/files/. /home/adminlab/ansible-lab/
chown -R adminlab:adminlab /home/adminlab/ansible-lab
```

Hoy `stage7-setup` lo hace con `rsync -a --delete` (espejo exacto del repo): con `cp -a` sobrevivían restos
de ejercicios en el nodo de control (caso [04](../../troubleshooting/etapa7/04-restos-de-ejercicios-en-nodo-de-control.md)).

### Fase 3 — Clave SSH del controlador (como `adminlab`)

```bash
ls ~/.ssh/id_ed25519 2>/dev/null || ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519 -C "adminlab@ansible01-lab-controller"
cat ~/.ssh/id_ed25519.pub
```

### Fase 4 — Distribuir la clave a los 5 nodos (desde el host)

```bash
PUBKEY="ssh-ed25519 AAAA... adminlab@ansible01-lab-controller"    # la línea real de la fase 3
for h in rhel7-app01 rhel8-app01 rhel9-app01 rhel10-app01 dns01; do
  echo "=== $h ==="
  ssh adminlab@"$h" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && grep -qxF '$PUBKEY' ~/.ssh/authorized_keys 2>/dev/null || echo '$PUBKEY' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
done
```

Lección del primer intento: una variable mal escrita (`PUKEY=` frente a `$PUBKEY`) añadió líneas vacías a
`authorized_keys` sin dar ningún error. `grep -qxF` hace la operación idempotente.

### Fase 5 — Conectividad: `ping` + `become`

```bash
ansible lab -m ping                       # 5 x pong; discovered_interpreter_python por host
ansible lab -b -m command -a whoami       # 5 x root
```

`ping` de Ansible **no es ICMP**: entra por SSH, sube un módulo Python, lo ejecuta y responde `pong`.

### Fase 6 — Ansible Vault: contraseña local y cifrado

```bash
openssl rand -base64 24 > ~/.vault_pass.txt && chmod 600 ~/.vault_pass.txt
cat > ~/ansible-lab/inventory/group_vars/all/vault.yml <<'EOF'
---
vault_demo_api_token: "lab-demo-token-CHANGE-ME-0123456789"
EOF
cd ~/ansible-lab
ansible-vault encrypt inventory/group_vars/all/vault.yml   # usa vault_password_file de ansible.cfg
head -1 inventory/group_vars/all/vault.yml                  # $ANSIBLE_VAULT;1.1;AES256
ansible-vault view inventory/group_vars/all/vault.yml
```

No se pasa `--vault-password-file` porque `ansible.cfg` ya lo define: repetirlo crea dos *vault-id* en conflicto.

### Fase 7 — Explorar facts (`facts.yml`, sin cambiar nada)

```bash
ansible-playbook playbooks/facts.yml
```

| Host | Versión | Python detectado |
|---|---|---|
| rhel7-app01 | RedHat 7.9 | `/usr/bin/python` (Python 2) |
| rhel8-app01 | RedHat 8.6 | `/usr/libexec/platform-python` |
| rhel9-app01, dns01 | RedHat 9.8 | `/usr/bin/python3` |
| rhel10-app01 | RedHat 10.2 | `/usr/bin/python3` |

### Fase 8 — Anatomía del proyecto (solo lectura)

```bash
cd ~/ansible-lab
ansible --version | head -2               # config file = /home/adminlab/ansible-lab/ansible.cfg
ansible-config dump --only-changed        # qué cambia nuestro ansible.cfg respecto al defecto
ansible-inventory --graph                 # @all > @lab > @app / @dns
ansible-inventory --host rhel7-app01      # variables que recibe un host (¡incluido el vault descifrado!)
ansible-playbook playbooks/site.yml --list-tasks
ansible-playbook playbooks/site.yml --list-hosts
```

Fuera de `~/ansible-lab`, Ansible usa `/etc/ansible/ansible.cfg` y "no hay inventario". Orden de búsqueda:
`ANSIBLE_CONFIG` → `./ansible.cfg` → `~/.ansible.cfg` → `/etc/ansible/ansible.cfg` (gana el primero).

### Fase 9 — Simular antes de aplicar (`--check --diff`)

```bash
ansible rhel7-app01,rhel9-app01 -m command -a 'timedatectl show -p Timezone --value'   # rhel7: invalid option -- 'p'
ansible-playbook playbooks/site.yml --check --diff
```

Destapó dos arreglos que solo existían en `ansible01` y se habían perdido (casos
[01](../../troubleshooting/etapa7/01-rhel7-timedatectl-p-no-soportado.md) y
[02](../../troubleshooting/etapa7/02-plantilla-timestamp-rompe-idempotencia.md)). Lección: **`--check` no ejecuta
`command`/`shell`** y puede ocultar fallos; las lecturas van con módulos (aquí, `stat` sobre `/etc/localtime`).

### Fase 10 — Aplicar de verdad y corregir la deriva

```bash
ansible-playbook playbooks/site.yml --diff
ansible rhel7-app01 -m command -a 'timedatectl set-timezone UTC'                     # deriva provocada
ansible rhel9-app01 -m shell -a 'echo "# editado a mano" >> /etc/ansible-lab-managed.txt'
ansible-playbook playbooks/site.yml --check --diff -v --limit rhel7-app01,rhel9-app01
ansible-playbook playbooks/site.yml --diff --limit rhel7-app01,rhel9-app01           # corrige ambas
```

Con `-v` se distinguen los dos `skipping`: *"Conditional result was False"* (no hace falta) y *"Command would
have run if not in check mode"* (sí haría falta). El handler solo se dispara donde cambió el template.

### Fase 11 — Idempotencia formal

```bash
ansible-playbook playbooks/site.yml | grep -E 'changed=[1-9]' && echo "NO idempotente" || echo "IDEMPOTENTE"
```

4 ejecuciones seguidas con `ok=7 changed=0 failed=0 skipped=1` en los 5 hosts.

### Fase 12 — Ad-hoc a fondo

```bash
ansible-doc -l | wc -l                                   # 73 en ansible01 (ansible-core)
ansible-doc -s ansible.builtin.stat
ansible rhel9-app01 -m command -a 'echo $HOME | wc -c'   # "/root | wc -c": command no usa shell
ansible rhel9-app01 -m shell   -a 'echo $HOME | wc -c'   # 6
ansible app -m ansible.builtin.dnf     -a 'name=tree state=present' --check   # falla en RHEL 7 (yum)
ansible app -m ansible.builtin.package -a 'name=tree state=present' --check   # funciona en las 4
ansible lab -m ansible.builtin.service -a 'name=chronyd state=started enabled=true' --check
ansible rhel9-app01 -m ansible.builtin.copy -a 'content="hola\n" dest=/tmp/adhoc.txt mode=0644' --diff   # x2: CHANGED y SUCCESS
ansible rhel9-app01 -m ansible.builtin.file -a 'path=/tmp/adhoc.txt state=absent'
```

### Fase 13 — Variables y precedencia (todo se limpia al final)

```bash
ansible lab -m debug -a 'var=lab_timezone' -o                        # Europe/Madrid en los 5
mkdir -p inventory/group_vars/dns && echo 'lab_timezone: "Europe/London"' > inventory/group_vars/dns/vars.yml
mkdir -p inventory/host_vars && echo 'lab_timezone: "Atlantic/Canary"' > inventory/host_vars/rhel8-app01.yml
ansible lab -m debug -a 'var=lab_timezone' -o                        # dns01 London, rhel8 Canary
ansible lab -m debug -a 'var=lab_timezone' -o -e lab_timezone=UTC    # UTC en los 5: -e gana siempre
rm -r inventory/group_vars/dns inventory/host_vars                   # ¡limpiar! (caso 04)
```

Apartando `group_vars/all/vars.yml`, el rol cae a sus `defaults/` (UTC y `[tree]`), la tarea del vault se omite
(`when: … is defined`) y quitar un paquete de la lista **no lo desinstala** (`state: present`).

### Fase 14 — Tags, límites y depuración

```bash
ansible-playbook playbooks/site.yml --list-tags                      # common, huso, marcador, paquetes, usuarios, vault
ansible-playbook playbooks/site.yml --check --tags usuarios
ansible-playbook playbooks/site.yml --check --skip-tags usuarios
ansible-playbook playbooks/site.yml --check --tags huso --limit rhel7-app01
ansible-playbook playbooks/site.yml --check --limit rhel9-app01 --start-at-task 'Desplegar marcador*'
ansible-playbook playbooks/site.yml --check --step --limit rhel9-app01     # interactivo: ssh -t
ansible rhel9-app01 -m ping -vvv                                      # SSH, ControlPersist, AnsiballZ, sudo
```

Las dos tareas del huso llevan la misma etiqueta: "Fijar" depende de la variable que registra "Leer".
`Gathering Facts` siempre se ejecuta (etiqueta especial `always`). Aquí apareció el caso
[04](../../troubleshooting/etapa7/04-restos-de-ejercicios-en-nodo-de-control.md).

### Fase 15 — Vault a fondo (en `~/vault-demo`, fuera del proyecto)

```bash
ansible-vault encrypt_string 'S3cr3to' --name 'demo_password' > ~/vault-demo/vars.yml   # solo el valor cifrado
ansible-vault encrypt ~/vault-demo/secreto.yml                                         # fichero entero
ansible-vault rekey ~/vault-demo/secreto.yml --new-vault-password-file ~/vault-demo/pass-nueva.txt
ansible-vault decrypt --vault-password-file ~/vault-demo/pass-nueva.txt --output - ~/vault-demo/secreto.yml
EDITOR=vim ansible-vault create ~/vault-demo/nuevo.yml ; EDITOR=vim ansible-vault edit ~/vault-demo/nuevo.yml
rm -rf ~/vault-demo
```

`rekey` no protege copias antiguas (historial de git): si se filtra la contraseña de vault, se cambian los
**secretos**. Nunca `decrypt` sin `--output -`: deja el fichero en claro en disco.

### Fase 16 — `advanced.yml`: block/rescue/always, serial y colección propia

```bash
ansible-playbook playbooks/advanced.yml --check
ansible-playbook playbooks/advanced.yml                                  # failed=0 en los 5
ansible-playbook playbooks/advanced.yml -e lab_simulate_failure=true     # rescued=1, failed=0 en los 5
ansible lab -m command -a 'tail -2 /var/log/lab-ansible-lab.log'         # always: False / true
ansible rhel7-app01 -m lab.utils.lab_uptime_pretty
```

`serial: 2` → 3 lotes (2 + 2 + 1). El módulo propio fallaba en RHEL 7 (Python 2.7) por usar f-strings (caso
[05](../../troubleshooting/etapa7/05-modulo-propio-python3-falla-en-rhel7.md)); el filtro no, porque se ejecuta en
el nodo de control. `-e clave=valor` siempre llega como texto: de ahí el `| bool`.

### Fase 17 — Inventario dinámico (solo `ansible01` + `dns01`)

```bash
DI=inventory/dynamic_inventory_demo.py
./$DI --list | head -30                     # el JSON con _meta.hostvars
ansible-inventory -i $DI --graph            # 10 hosts, demo_api + 10 grupos por empresa
ansible-inventory -i inventory/hosts.ini -i $DI --graph      # dos inventarios a la vez
ansible -i $DI demo-1-bret -m command -a hostname -o         # ansible01.lab.local: ansible_connection=local
ansible-playbook -i $DI playbooks/dynamic_inventory_demo.yml
```

Los `group_vars/` de `inventory/` (incluido el vault) también llegan a los hosts de la demo. El informe se
creaba como `root:root` por el `become = True` de `ansible.cfg`: corregido con `become: false` en el play.

### Fase 18 — Cierre de la etapa

- Arreglos en el repo: `printf '%q '` vacío en `02-run-playbook.sh`, `stage7-setup` con `rsync --delete`,
  `test_ansible.sh` sin `timedatectl show -p` y la marca de etapa (caso
  [06](../../troubleshooting/etapa7/06-marca-etapa7-no-se-aplica-ni-se-comprueba.md)).
- `scripts/lab.sh test all all`: **0 FAIL en las 6 VMs**, `test_ansible` también en `ansible01` (11 PASS).
- `scripts/lab.sh facts all && scripts/lab.sh matrix` y `scripts/lab.sh snapshot create all 7`.
- Molecule con Podman (caso [07](../../troubleshooting/etapa7/07-molecule-escenario-nunca-ejecutado.md)).

## Molecule (equipo host, Podman)

```bash
python3 -m venv ~/venvs/molecule
~/venvs/molecule/bin/pip install molecule 'molecule-plugins[podman]' ansible-core
~/venvs/molecule/bin/ansible-galaxy collection install containers.podman

source ~/venvs/molecule/bin/activate
cd scripts/stage7/files/roles/common
molecule test        # destroy → syntax → create → converge → idempotence → verify → destroy
```

Por fases: `molecule create && molecule converge && molecule idempotence && molecule verify`
(`molecule login` para entrar en el contenedor; `molecule destroy` para borrarlo).

## Reglas aprendidas en esta etapa

- **La fuente de verdad es `scripts/stage7/files/` en git.** Un arreglo hecho solo en `ansible01` se pierde
  (casos [01](../../troubleshooting/etapa7/01-rhel7-timedatectl-p-no-soportado.md) y
  [02](../../troubleshooting/etapa7/02-plantilla-timestamp-rompe-idempotencia.md)), y un resto que no está en git
  sobrevivía (caso [04](../../troubleshooting/etapa7/04-restos-de-ejercicios-en-nodo-de-control.md)). Hoy
  `stage7-setup` deja `ansible01` como espejo exacto del repo.
- Los comandos `ansible`/`ansible-playbook` se lanzan **desde `~/ansible-lab`**, porque `ansible.cfg` se busca en
  el directorio actual.
- **Leer con módulos, no con `command`/`shell`**: los módulos corren en `--check` y no marcan `changed`.
- **Simular con `-v`** cuando haya `command`/`shell`: un `skipping` puede esconder un *"would have run"*.
- Nada de valores cambiantes (fechas) en plantillas: rompen la idempotencia.
- **Los módulos propios se ejecutan con el Python del nodo** (2.7 en RHEL 7); los filtros, en el controlador.
- **Practicar fuera del proyecto** (`~/vault-demo`, `/tmp`) o limpiar en el mismo bloque.
- **Mínimo privilegio**: `become: false` en los plays que no lo necesitan.
- **Un test que no se ejecuta no falla**: comprobar que aparece `### test_ansible.sh` en cada host.

## Cómo se verifica

```bash
scripts/lab.sh stage7 site && scripts/lab.sh stage7 site    # 2º pase: changed=0 en todos
scripts/lab.sh test all all                                 # 0 FAIL; test_ansible en las 6 VMs
```

## Documentación relacionada

- Checklist: [`checklists/etapa7.md`](../../checklists/etapa7.md)
- Tema: [`automation/ansible.md`](../../automation/ansible.md)
- Guía de estudio y casos reales: [`README_troubleshooting_etapa7.md`](../../troubleshooting/etapa7/README_troubleshooting_etapa7.md)
- La Etapa 10 reutiliza sus roles, su clave SSH y su contraseña de Vault: [`scripts/stage10/README_stage10.md`](../stage10/README_stage10.md)
