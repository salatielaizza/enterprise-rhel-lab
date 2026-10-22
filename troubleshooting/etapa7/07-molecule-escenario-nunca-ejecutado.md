# 07 — El escenario de Molecule del rol `common` nunca se había ejecutado (cuatro fallos para hacerlo funcionar con Podman)

## Objetivo

Documentar los fallos encontrados al ejecutar **por primera vez** el escenario de Molecule del rol `common`
(`scripts/stage7/files/roles/common/molecule/default/`) en la Fase 18, con **Podman** en lugar de Docker.
El comentario de `molecule.yml` decía *"validado de verdad en un sandbox con `molecule list`"*, pero
`molecule list` solo lista el escenario: **nunca había creado un contenedor ni aplicado el rol**.

## Preparación

- Equipo host: Linux Mint 22, **Podman 4.9.3** sin root (comprobado con
  `podman run --rm registry.access.redhat.com/ubi9/ubi-minimal:latest cat /etc/redhat-release` → RHEL 9.8).
- Molecule instalado en un **venv propio**, separado del Ansible del sistema (`ansible-core 2.16.3`) y del de
  pipx (`ansible 11.3.0`):

  ```bash
  python3 -m venv ~/venvs/molecule
  ~/venvs/molecule/bin/pip install molecule 'molecule-plugins[podman]' ansible-core
  ~/venvs/molecule/bin/ansible-galaxy collection install containers.podman
  source ~/venvs/molecule/bin/activate
  ```
- Escenario original: driver `docker`, imagen `docker.io/geerlingguy/docker-rockylinux9-ansible` (Rocky 9 con
  systemd), `privileged`, `cgroupns_mode: host` y `/sys/fs/cgroup` montado; `converge.yml` con `become: true`
  e `include_role: name: common`.

## Síntoma

Ejecución por fases (`molecule create`, `converge`, `idempotence`, `verify`), cada una con un fallo distinto a
medida que se resolvía el anterior:

```
1) molecule create
   failed: Can't pull image docker.io/geerlingguy/docker-rockylinux9-ansible:latest
   "Requesting bearer token: invalid status code from registry 400 (Bad Request)"
   (2º intento) "unable to retrieve auth token: invalid username/password: unauthorized:
                 incorrect username or password"

2) molecule converge  (con el contenedor ya creado)
   TASK [Gathering Facts]
   "module_stderr": "sudo: PAM account management error: Authentication service cannot retrieve
                     authentication info\nsudo: a password is required\n"

3) molecule converge  (tras quitar 'become')
   TASK [Incluir el rol common bajo prueba]
   [ERROR]: The role 'common' was not found in:
     .../roles/common/molecule/default/roles:~/.ansible/roles:/usr/share/ansible/roles:
     /etc/ansible/roles:.../roles/common/molecule/default
```

En el primer intento se lanzaron las 4 fases seguidas (sin `&&`): `idempotence` (*"Instances not converged"*)
y `verify` (*"Container 'lab-common-rhel9' not found"*) fallaron en cascada por el fallo de `create`.

## Hipótesis descartadas

| Hipótesis | Por qué se descartó |
|---|---|
| Podman no funciona sin root en el equipo | El contenedor UBI de prueba arrancó con el usuario normal |
| La imagen de geerlingguy ya no existe o es privada | Es pública; el error no era "not found" sino de **autenticación** |
| Molecule no está bien instalado | `molecule drivers` listaba `podman` y el playbook `create.yml` del plugin llegó hasta la descarga |
| `sudo` falla por un problema del rol | Falló en `Gathering Facts`, antes de entrar en el rol: es la conexión al contenedor |
| El rol tiene un nombre incorrecto | El directorio es `roles/common`; el problema es que `roles/` no estaba en la ruta de búsqueda |

## Diagnóstico

**1. Docker → Podman.** El escenario asumía Docker (`driver: docker`) y sus trucos para ejecutar systemd
(`privileged`, `cgroupns_mode: host`, montar `/sys/fs/cgroup`). Con Podman basta `systemd: always`: Podman
prepara él mismo cgroups, `/run` y `/tmp` para systemd, sin privilegios extra.

**2. Credenciales caducadas de Docker Hub (configuración del equipo, no del repo).** "incorrect username or
password" sin haber introducido ninguna contraseña indicaba que Podman enviaba credenciales guardadas. Podman
también lee el fichero de Docker:

```bash
# (solo lista para qué registros hay credenciales, sin mostrarlas)
/run/user/1000/containers/auth.json   → no existe
~/.config/containers/auth.json        → no existe
~/.docker/config.json                 → ['https://index.docker.io/v1', 'https://index.docker.io/v1/',
                                         'https://index.docker.io/v1/access-token', '.../refresh-token']
podman login --get-login docker.io    → AWS
```

El usuario **`AWS`** es el que usa siempre Amazon ECR (`aws ecr get-login-password | docker login …`):
probablemente un `docker login` de ECR hecho sin indicar el registro, que Docker guardó como credencial de
Docker Hub. El token de ECR caduca y no vale para Docker Hub; con él, Docker Hub rechaza incluso la descarga de
una imagen pública.

**3. `become: true` dentro del contenedor.** Molecule con Podman no entra por SSH sino con `podman exec`, ya
como root. `become: true` hacía que Ansible ejecutara `sudo` siendo root, y en esta imagen (sin PAM ni `sudo`
configurados para ello) falla. Se confirma de forma indirecta: con `become: false`, `Gathering Facts` y las
tareas que necesitan root (`dnf`, `timedatectl set-timezone`, escribir en `/etc`) funcionan.

**4. Ruta de roles.** `include_role: name: common` busca el rol en las rutas de roles. La lista del error no
incluía el directorio que **contiene** el rol (`scripts/stage7/files/roles/`): las versiones actuales de
Molecule ya no lo añaden solas, como hacían las antiguas.

## Causa raíz

El escenario se escribió para Docker y para una versión anterior de Molecule, y **nunca se ejecutó de verdad**:
`molecule list` (la única "validación") no crea contenedores ni aplica el rol. Los fallos 1, 3 y 4 estaban en
el escenario; el 2 era configuración antigua del equipo host, ajena al repo.

## Solución aplicada

| Fallo | Dónde | Cambio |
|---|---|---|
| 1 | `molecule/default/molecule.yml` | `driver: podman` y `systemd: always`; fuera `privileged`, `cgroupns_mode` y el montaje de `/sys/fs/cgroup` |
| 2 | Equipo host (no el repo) | Descargar la imagen una vez con un fichero de credenciales vacío: `echo '{}' > /tmp/auth-vacio.json; REGISTRY_AUTH_FILE=/tmp/auth-vacio.json podman pull docker.io/geerlingguy/docker-rockylinux9-ansible:latest`. Con `pre_build_image: true`, Molecule usa la imagen local y no vuelve a descargarla |
| 3 | `molecule/default/converge.yml` | `become: false` (con comentario: en las VMs reales el `become` lo pone `ansible.cfg`, no este playbook) |
| 4 | `molecule/default/molecule.yml` | `provisioner.env.ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/.."` (el padre del rol es `roles/`) |

Además, las fases se encadenan con `&&` (`molecule create && molecule converge && …`) para que un fallo pare
la secuencia y no provoque errores en cascada.

## Validación

Prueba completa desde cero (`molecule destroy && molecule test`):

```
syntax:      Successful
create:      Successful
converge:    lab-common-rhel9 : ok=7  changed=4  failed=0  skipped=1
             (paquetes: changed · huso: changed — timedatectl con systemd del contenedor ·
              marcador: changed · vault: skipping, no hay lab_demo_api_token en el inventario de Molecule)
idempotence: lab-common-rhel9 : ok=5  changed=0  failed=0  skipped=2
verify:      ok=3  failed=0  ("All assertions passed")
destroy:     Successful

SCENARIO RECAP: default : actions=12  successful=7  disabled=0  skipped=0  missing=6  failed=0
podman ps -a | grep lab-common  → (nada): contenedor destruido al terminar
```

Los `missing=6` son fases opcionales sin playbook propio (`prepare`, `side_effect`, `cleanup` y los ficheros
de requisitos de `dependency`).

## Prevención

- **Un escenario de Molecule solo está validado cuando `molecule test` termina en verde**, no con
  `molecule list` ni `molecule syntax`.
- **En contenedores, `become: false`**: la conexión de Molecule ya es root; el `become` es cosa de las VMs.
- **Declarar `ANSIBLE_ROLES_PATH`** en `provisioner.env` en vez de confiar en que Molecule lo deduzca.
- **Instalar Molecule en un venv propio** (`~/venvs/molecule`), con su driver y la colección
  `containers.podman`, sin mezclarlo con el Ansible del sistema.
- **Si una descarga de una imagen pública falla con "incorrect username or password"**, revisar las
  credenciales guardadas (`~/.docker/config.json`, `${XDG_RUNTIME_DIR}/containers/auth.json`,
  `podman login --get-login <registro>`). Pendiente opcional: quitar de `~/.docker/config.json` las
  credenciales caducadas de `index.docker.io` (con copia de seguridad, si no se usan Docker Hub ni ECR).
- **Pendiente detectado durante la prueba:** el `ansible-core` del venv (más nuevo que el de ansible01) avisa
  `[DEPRECATION WARNING]: INJECT_FACTS_AS_VARS ... will be removed from ansible-core version 2.24` por
  `{{ ansible_date_time.iso8601 }}` en `roles/common/handlers/main.yml` (y en el `always` de
  `playbooks/advanced.yml`). La forma moderna es `{{ ansible_facts['date_time']['iso8601'] }}`.
