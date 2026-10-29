# Etapa N3 — Práctica de Ansible sin scripts (P1-P10)

> **Estado: ✅ Completa** (2026-10-26 → 2026-10-29). Los diez ejercicios se escribieron a mano, desde cero, y se
> ejecutaron contra las VMs reales del lab. Dejó **7 casos reales** en
> [`troubleshooting/etapaN3/`](../troubleshooting/etapaN3/README_troubleshooting_etapaN3.md).
> Proyecto de referencia (soluciones validadas): [`scripts/stageN3/files/practica-ansible/`](../scripts/stageN3/files/practica-ansible/) ·
> Scripts y validación: [`scripts/stageN3/README_stageN3.md`](../scripts/stageN3/README_stageN3.md) ·
> Checklist: [`checklists/etapaN3.md`](../checklists/etapaN3.md)

## Objetivo

Consolidar la Etapa 7 practicando Ansible **sin `lab.sh` y sin el proyecto del lab**: crear un proyecto propio
desde cero (configuración, inventario, playbooks, roles, Vault, plantillas, control de errores y colecciones) y
operarlo contra las cinco VMs gestionadas. Es el paso *manual* de la regla del proyecto aplicado a la propia
herramienta de automatización: en la Etapa 7 los ficheros venían hechos; aquí se escriben y se depuran.

Alcance:

- **Entra:** los diez ejercicios P1-P10, su depuración real, un proyecto de referencia limpio con las soluciones y una
  validación estática (`scripts/stageN3/validar.sh`).
- **No entra:** cambios en `~/ansible-lab` ni en `scripts/stage7/`; comandos nuevos en `lab.sh`; hosts nuevos.

## Prerrequisitos

- Etapa 7 completa: clave SSH de `adminlab` en los 5 nodos y `sudo` sin contraseña del grupo `sysadmins` (Etapa 2).
- Las 6 VMs base encendidas (`rhel7/8/9/10-app01`, `dns01`, `ansible01`).
- Ansible en el nodo de control. En el lab la práctica se hizo **desde el equipo host** (Linux Mint), en la
  carpeta local `practica/` del repositorio (ignorada por Git), usando la clave `adminlab@lab.local` cargada en el
  `ssh-agent`. También vale `ansible01:~/practica-ansible`, fuera de `~/ansible-lab` (caso
  [etapa7/04](../troubleshooting/etapa7/04-restos-de-ejercicios-en-nodo-de-control.md)).
- Snapshots `*-stage7-complete` como red de seguridad (`scripts/lab.sh snapshot revert all 7`).

## Arquitectura

```text
 Nodo de control (host Mint en practica/, o ansible01:~/practica-ansible)
   ansible.cfg (become = False) · inventory/ · p3…p10 · roles/practica_base · roles/practica_final
        │  SSH como adminlab + Python del nodo (sudo solo con become/-b)
        ▼
 ┌────────────── app ───────────────────────────────┐
 │ legacy           modernos                        │      servicios
 │ rhel7-app01 .11  rhel8 .12  rhel9 .13  rhel10 .14 │      dns01 .20
 └──────────────────────────────────────────────────┘
```

| Grupo | Hosts | Uso en la práctica |
|---|---|---|
| `legacy` | `rhel7-app01` | Diferencias de RHEL 7 (yum, Python 2.7); `fail` controlado en P8 |
| `modernos` | `rhel8/9/10-app01` | `when` por versión, firewalld en P9 |
| `app` (`:children`) | `legacy` + `modernos` | P3, P6, P8; `app:!legacy` en P10 |
| `servicios` | `dns01` | Variables de grupo que pisan a las del rol (P5, P7) |

Estructura del proyecto (la de referencia, en `scripts/stageN3/files/practica-ansible/`):

```text
practica-ansible/
├── ansible.cfg
├── requirements.yml                  # P9: ansible.posix fijada a 1.5.4
├── inventory/
│   ├── hosts.ini
│   └── group_vars/
│       ├── all/
│       │   ├── vars.yml              # P4 y P6
│       │   └── vault.yml.example     # P6: el real (cifrado) en .gitignore
│       ├── legacy.yml  modernos.yml  servicios.yml   # P5 y P7
├── p3-servicio.yml … p10-final.yml
├── limpieza.yml
├── templates/practica-info.j2        # P7 (plantilla de un playbook sin rol)
└── roles/
    ├── practica_base/                # P5: defaults, tasks, handlers, templates
    └── practica_final/               # P10: defaults, tasks, templates
```

Ideas de base: el **inventario** dice *quién*, el **playbook** *a quién y qué*, el **rol** *cómo* y las
**variables** *con qué valores*. Niveles de un playbook: Play → Role → Block → Task; una *keyword* se hereda hacia abajo y gana la más
específica (task > block > role > play). Se consultan sin Internet con `ansible-doc -t keyword <nombre>`.

## Procedimiento

Orden de trabajo en cada ejercicio (el mismo que en un cambio real):

1. Escribir los ficheros a mano y consultar los módulos con `ansible-doc -s <módulo>`.
2. `ansible-playbook <p>.yml --syntax-check`.
3. `ansible-playbook <p>.yml --check --diff` (simulación; ver caso [02](../troubleshooting/etapaN3/02-check-servicio-de-paquete-no-instalado.md)).
4. Ejecución real.
5. **Segunda** ejecución real: `changed=0` (idempotencia; ver caso [06](../troubleshooting/etapaN3/06-check-repetido-no-prueba-idempotencia.md)).

Desde P6, todos los comandos del proyecto llevan `--ask-vault-pass` (`-J`), porque `vault.yml` se carga con el inventario.

### Enunciados

#### P1 — Proyecto mínimo desde cero

En el nodo de control (`ansible01:~/practica-ansible`, o en el equipo host dentro de `practica/`, como se hizo en el lab), crea el proyecto con:

1. Un `ansible.cfg` con: inventario `./inventory/hosts.ini`, usuario remoto `adminlab`, sin comprobación de
   claves de host, detección automática silenciosa del intérprete y `become = False`.
2. Un inventario `inventory/hosts.ini` con estos grupos: `legacy` (rhel7-app01), `modernos` (rhel8, rhel9 y
   rhel10-app01), `servicios` (dns01) y un grupo padre `app` que agrupe `legacy` y `modernos`. Usa
   `ansible_host` con las IPs del lab.

Comprueba: `ansible --version | head -2` (¿qué `ansible.cfg` usa?), `ansible-inventory --graph`,
`ansible app -m ping -o`, `ansible all -m ping -o`, `ansible all -m command -a whoami -o` y lo mismo con `-b`.

**Preguntas:** (a) ¿por qué `all` incluye a dns01? (b) ¿qué pasa si lanzas lo mismo desde `~`? (c) sin
`ansible_ssh_private_key_file` en el inventario, ¿con qué clave entra Ansible?

#### P2 — Ad-hoc útiles (sin playbook)

1. El `uptime` de todos los hosts, en una línea por host.
2. El espacio libre de `/` solo en el grupo `modernos`.
3. **Sin ejecutar nada**, lista los hosts que **no** son `legacy`.
4. **Sin ejecutar nada**, lista los hosts que están a la vez en `app` **y** en `modernos`.
5. La distribución y versión de cada host, usando solo *facts* filtrados.
6. Crea `/tmp/hola.txt` con el texto `hola` en dns01 (sin `sudo`). Repite el comando (¿qué cambia en la
   salida?) y después bórralo con un módulo, no con `rm`.
7. Trae `/etc/redhat-release` de todos los hosts al nodo de control, a `./traidos/`. ¿Qué estructura de
   directorios crea?
8. Comprueba que `sshd` está activo en todos sin cambiar nada.
9. Consulta la documentación resumida del módulo que has usado en el punto 7.

#### P3 — Primer playbook: paquete + servicio + fichero + handler

Antes, apunta si `at` ya estaba instalado: `ansible app -m command -a 'rpm -q at' -o`.

`p3-servicio.yml`, sobre el grupo `app`, con `sudo` **a nivel de play**:

1. Paquete `at` instalado (con el módulo genérico, que funcione en RHEL 7 y en 8/9/10).
2. Servicio `atd` arrancado y habilitado.
3. Fichero `/etc/practica-ansible.conf` (root:root, 0644) con dos líneas: un comentario y `entorno=laboratorio`.
4. Un **handler** que reinicie `atd`, notificado **solo** por la tarea del fichero.

Comprueba: `--syntax-check`, `--check --diff`, ejecución real, segunda ejecución (`changed=0`). Después
cambia el contenido del fichero y vuelve a ejecutar: ¿qué tareas salen `changed` y se dispara el handler?

#### P4 — Variables, facts, `when` y `loop`

1. Define en `inventory/group_vars/all/vars.yml` una lista `practica_usuarios` con dos elementos
   (`nombre`, `comentario`): `practica1` y `practica2`.
2. `p4-usuarios.yml` sobre **todos** los hosts, con `sudo`:
   - Un `debug` que muestre, por host: distribución, versión, versión de Python y memoria total (*facts*).
   - Crear los usuarios de la lista con **un solo** `ansible.builtin.user` y `loop` (que la salida muestre
     solo el nombre, no el diccionario entero).
   - Crear `/etc/practica-moderno.txt` **solo** en hosts con versión mayor ≥ 8 (usa un *fact*).
   - Un `debug` que se ejecute **solo** en los hosts del grupo `legacy` (usa el inventario, no un *fact*).

**Pregunta:** ¿por qué `group_vars` va dentro de `inventory/` y no en la raíz del proyecto? (caso `etapa7/03`)

#### P5 — Tu propio rol con `ansible-galaxy`

1. `ansible-galaxy role init roles/practica_base` y mira qué estructura crea.
2. En `defaults/main.yml`: `practica_base_mensaje` ("Servidor gestionado por Ansible") y
   `practica_base_fichero` (`/etc/practica-role.txt`). Las variables de un rol llevan su nombre como prefijo.
3. Una tarea que despliegue `practica_base_fichero` desde una plantilla con `ansible_managed`, el mensaje y
   el nombre del host, y que notifique un handler.
4. El handler añade una línea con fecha a `/var/log/practica.log` (usa `ansible_facts['date_time']`, la
   forma moderna).
5. En `inventory/group_vars/servicios.yml`, pisa el mensaje para dns01: "Servidor de servicios del lab (DNS)".
6. `p5-rol.yml` aplica el rol a todos, con la etiqueta `base` **a nivel de rol**.

Comprueba: `--list-tags` (¿de dónde sale la etiqueta?), el contenido del fichero en dns01 frente a
rhel9-app01, y la segunda ejecución.

#### P6 — Tu propio Vault

1. Crea `inventory/group_vars/all/vault.yml` **con `ansible-vault create`** (te pedirá una contraseña nueva:
   en esta práctica **no** hay `vault_password_file`), con `vault_practica_password: "Practica.2026"`.
2. En `vars.yml`: `practica_password: "{{ vault_practica_password }}"` (el patrón del lab).
3. `p6-vault.yml` sobre `app`: fija la contraseña de `practica1` con el filtro `password_hash('sha512', …)`,
   sin que el secreto ni su hash aparezcan nunca en la salida.
4. Ejecuta con `--ask-vault-pass` dos veces: la segunda debe dar `changed=0`.
5. **Experimento:** quita la sal del `password_hash` y ejecuta dos veces. ¿Qué pasa y por qué?

**Ojo:** desde este ejercicio, **cualquier** comando del proyecto (`ansible`, `ansible-playbook`,
`ansible-inventory`) necesita la contraseña de vault, porque `vault.yml` se carga con el inventario. Usa
`--ask-vault-pass` (o `-J`), o crea `~/.vault_practica.txt` (0600) y añade
`vault_password_file = ~/.vault_practica.txt` al `ansible.cfg` de la práctica.

#### P7 — Plantillas Jinja2: un fichero distinto en cada host

1. `inventory/group_vars/legacy.yml`, `modernos.yml` y `servicios.yml` con una variable `practica_rol`
   (`legacy`, `aplicaciones`, `dns`).
2. `templates/practica-info.j2` con: `ansible_managed`; host y FQDN; distribución y versión; un `if` que diga
   "yum (legacy)" si la versión mayor es < 8 y "dnf" si no; `practica_rol` en mayúsculas con un valor por
   defecto si faltara; un `for` sobre las IPv4 del host (protegido con `default([])`); y los nombres de
   `practica_usuarios` separados por comas (`map` + `join`).
3. `p7-plantilla.yml` lo despliega en `/etc/practica-info.txt` en todos los hosts.

Comprueba: `ansible all -m command -a 'cat /etc/practica-info.txt'` (más vault). ¿En qué se diferencia el de
rhel7-app01?

#### P8 — Controlar los errores

`p8-errores.yml` sobre `app`:

1. Un `test -f /etc/no-existe.conf` que **no** cuente como error si el fichero falta (rc 1), pero sí ante
   cualquier otro código; que nunca marque `changed` y que **también se ejecute en `--check`**. Muestra si
   existe o no.
2. Un `/bin/false` que falle sin parar el play.
3. Un `block` con un `fail` que solo salte en el grupo `legacy` y una tarea normal; un `rescue` que muestre el
   mensaje del fallo; y un `always`.

Predice el PLAY RECAP de rhel7-app01 frente a rhel9-app01 (`rescued`, `ignored`) antes de ejecutar.
Después ejecútalo también con `--check` sin el `check_mode: false` del punto 1: ¿qué dice?

#### P9 — Una colección de Ansible Galaxy

1. Un `requirements.yml` con la colección `ansible.posix`, **versión fijada** `1.5.4`.
2. Instálala **dentro del proyecto**: `ansible-galaxy collection install -r requirements.yml -p ./collections`.
   Añade `collections_path = ./collections` al `ansible.cfg` y comprueba con
   `ansible-galaxy collection list` y `ansible-doc ansible.posix.firewalld`.
3. `p9-firewalld.yml` sobre `modernos`: abre `8080/tcp` en firewalld (permanente y en caliente). El estado
   debe salir de una variable `practica_fw_state` con valor por defecto `enabled`.
4. Compruébalo con un ad-hoc (`firewall-cmd --list-ports`) y ciérralo con el **mismo** playbook y
   `-e practica_fw_state=disabled`.

#### P10 — Ejercicio final (sin mirar los anteriores)

Crea un rol `practica_final` y un playbook `p10-final.yml` que cumplan **todo** esto:

1. Solo afecta a los hosts de `app` que **no** son `legacy` (patrón de hosts en el play).
2. Asegura el paquete `cronie` y el servicio `crond` (arrancado y habilitado).
3. Crea el usuario `operador` con la contraseña del vault (`practica_password`), sin mostrarla.
4. Le programa con el módulo `cron` la tarea "uptime del operador": `uptime >> /tmp/operador-uptime.log`
   cada 15 minutos.
5. Despliega `/etc/practica-final.txt` desde una plantilla con: host, distribución y versión mayor, el
   operador y su frecuencia, y los grupos del inventario a los que pertenece el host.
6. Usuario, frecuencia y ruta del fichero son variables del rol, con prefijo, en `defaults/`.
7. Etiquetas por tarea: `usuarios`, `cron` y `fichero`.
8. Pasa `--syntax-check`, `--check --diff` y, en la ejecución real, la **segunda** da `changed=0`.

Comprueba: `--list-hosts` (3 hosts), `--list-tags`, `ansible 'app:!legacy' -b -m command -a 'crontab -l -u operador'`.

---

## Comandos

| Comando | Qué hace | Por qué se usa | Salida esperada / si sale otra cosa |
|---|---|---|---|
| `ansible --version \| head -2` | Muestra la versión y el `ansible.cfg` en uso | Ansible lee `./ansible.cfg` del directorio actual | `config file = …/practica-ansible/ansible.cfg`; si sale `/etc/ansible/ansible.cfg`, estás en otro directorio |
| `ansible-inventory --graph` | Árbol de grupos y hosts | Comprobar el inventario sin conectar | `@app` con `@legacy` y `@modernos`; `@servicios`. Si `app` contiene "hosts" llamados `legacy`, falta `:children` |
| `ansible all -m ping -o` | Conecta por SSH y ejecuta un módulo Python | Prueba conexión + Python, no ICMP | 5 × `pong`; `UNREACHABLE` = SSH/red (diagnóstico por capas) |
| `ansible all -b -m command -a whoami -o` | Igual, con `sudo` | Comprobar `become` | 5 × `root` |
| `ansible 'all:!legacy' --list-hosts` · `'app:&modernos'` | Patrones: exclusión e intersección | Ver a quién afecta un patrón sin ejecutar nada | 4 hosts · 3 hosts |
| `ansible all -m setup -a 'filter=ansible_distribution*'` | *Facts* filtrados | Consultar el SO de cada host | Si sale vacío, revisar el patrón (caso [01](../troubleshooting/etapaN3/01-setup-filter-errata-devuelve-vacio.md)) |
| `ansible dns01 -m copy -a 'content="hola\n" dest=/tmp/hola.txt'` | Crea un fichero (módulo, idempotente) | Ad-hoc que cambia algo | 1.ª `CHANGED`, 2.ª `SUCCESS` con `changed: false` |
| `ansible dns01 -m file -a 'path=/tmp/hola.txt state=absent'` | Borra el fichero | Mejor que `rm`: idempotente y admite `--check` | `changed: true` y después `false` |
| `ansible all -m fetch -a 'src=/etc/redhat-release dest=./traidos/'` | Trae ficheros al controlador | Recoger evidencias | `traidos/<host>/etc/redhat-release` (una carpeta por host) |
| `ansible all -m command -a 'systemctl is-active sshd' -o` | Consulta un servicio sin cambiarlo | Comprobar estado sin riesgo | `active` en los 5 (sale `CHANGED`: `command` no sabe si cambió algo) |
| `ansible-playbook X --syntax-check` | Valida la estructura del YAML | Antes de nada | No detecta parámetros inexistentes de un módulo |
| `ansible-playbook X --check --diff` | Simula y enseña diferencias | Revisar antes de aplicar | Ver límites en los casos 02 y 06 |
| `ansible-playbook X --list-tasks` / `--list-tags` / `--list-hosts` | Qué tareas, etiquetas y hosts hay | Comprobar que un rol se carga y la herencia de etiquetas | Tareas con prefijo `rol : …` |
| `ansible-galaxy role init roles/<rol>` | Crea el esqueleto de un rol | Estructura estándar | Los `main.yml` solo traen `---` y un comentario: hay que rellenarlos (caso 03) |
| `ansible-vault create\|view\|edit <f>` | Crea, lee o edita un fichero cifrado | Secretos fuera de Git | `head -1` → `$ANSIBLE_VAULT;1.1;AES256` |
| `ansible-galaxy collection install -r requirements.yml -p ./collections` | Instala colecciones dentro del proyecto | Versión fijada y reproducible | `ansible-galaxy collection list` muestra `ansible.posix 1.5.4` |
| `ansible-config dump --only-changed` | Configuración que difiere de la de por defecto, y su origen | Comprobar `ansible.cfg` | Aparecen `COLLECTIONS_PATHS`, `DEFAULT_ROLES_PATH`… |
| `scripts/stageN3/validar.sh` | Validación estática del proyecto de referencia | Comprobación repetible sin tocar las VMs | `FAIL=0` |

## Resultado esperado

- Un proyecto Ansible propio, legible y separado del lab, con la estructura de la sección *Arquitectura*.
- Cada playbook pasa `--syntax-check`, `--check --diff` y dos ejecuciones reales (la segunda con `changed=0`).
- Secretos solo en `vault.yml` cifrado y nunca en la salida (`no_log: true`).
- Al terminar, los nodos vuelven a su estado anterior con `limpieza.yml` (o con los snapshots de la Etapa 7).

## Validación

Resultados **reales** registrados durante la práctica (2026-10-26 a 2026-10-29). Lo que no se pegó en la sesión
figura como "confirmado por el usuario"; los detalles se completan en [`checklists/etapaN3.md`](../checklists/etapaN3.md).

| Ejercicio | Resultado obtenido |
|---|---|
| P1 | Proyecto creado; 5 hosts alcanzables con `ping` (confirmado por el usuario) |
| P2 | `all:!legacy` → 4 hosts (`dns01`, `rhel8/9/10-app01`); `app:&modernos` → 3 hosts; intérpretes detectados: RHEL 7 `/usr/bin/python`, RHEL 8 `/usr/libexec/platform-python`, RHEL 9/10 y `dns01` `/usr/bin/python3`; errata en el filtro de `setup` (caso 01) |
| P3 | Estado previo: `at` **no instalado** en las 4 `app01` (`rpm -q at` → `rc=1`); `--check` falla en `atd` (caso 02); ejecución real e idempotencia correctas (confirmado por el usuario) |
| P4 | Completado (confirmado por el usuario) |
| P5 | Rol sin contenido y ficheros fuera del rol (caso 03); tras corregirlo: `changed` + handler en los 5, mensaje propio en `dns01` y `changed=0` en la 2.ª ejecución |
| P6 | Indentación del play (caso 04) y vault con contenido comentado (caso 05); después `practica_password \| length` → `13` y 2.ª ejecución con `changed=0` |
| P7 | Diff real: `RedHat 7.9` + `yum (legacy)` + `LEGACY`; `RedHat 8.6`, `9.8` (`rhel9-app01` y `dns01`) y `10.2` + `dnf`; `APLICACIONES` y `DNS`; una IPv4 por host; `practica1, practica2`. Dos `--check` seguidos no prueban la idempotencia (caso 06) |
| P8, P9 | Completados (confirmado por el usuario) |
| P10 | `defaults/main-yml` mal nombrado (caso 07); tras renombrarlo, ejecución real y 2.ª ejecución correctas (confirmado por el usuario, 2026-10-29) |

Validación estática del proyecto de referencia (en la sesión de preparación, con ansible-core 2.21, yamllint y
`ansible.posix` instalados): `scripts/stageN3/validar.sh` → `PASS=18 FAIL=0 SKIP=1` (el SKIP es `ansible-lint`, que
avisa solo del `ignore_errors` intencionado de P8).

## Troubleshooting

| Caso | Ejercicio | Lección |
|---|---|---|
| [01](../troubleshooting/etapaN3/01-setup-filter-errata-devuelve-vacio.md) | P2 | Un filtro de `setup` mal escrito devuelve vacío sin error |
| [02](../troubleshooting/etapaN3/02-check-servicio-de-paquete-no-instalado.md) | P3 | `--check` no instala: el servicio de un paquete nuevo "no existe" en la simulación |
| [03](../troubleshooting/etapaN3/03-rol-ficheros-fuera-de-su-sitio.md) | P5 | Esqueleto de `role init` sin rellenar y ficheros fuera del rol: Ansible no avisa |
| [04](../troubleshooting/etapaN3/04-yaml-indentacion-claves-del-play.md) | P6 | `mapping values are not allowed`: claves del play con distinta sangría |
| [05](../troubleshooting/etapaN3/05-vault-con-contenido-comentado.md) | P6 | `no_log` oculta el error; el vault solo tenía comentarios |
| [06](../troubleshooting/etapaN3/06-check-repetido-no-prueba-idempotencia.md) | P7 | Dos `--check` seguidos no prueban la idempotencia (`@@ -0,0`) |
| [07](../troubleshooting/etapaN3/07-defaults-main-yml-mal-nombrado.md) | P10 | `defaults/main-yml` no se carga; `no_log` vuelve a ocultar el `undefined variable` |

Guía de estudio con comandos, chuleta y preguntas: [`README_troubleshooting_etapaN3.md`](../troubleshooting/etapaN3/README_troubleshooting_etapaN3.md).

## Errores comunes

- Lanzar los comandos fuera del directorio del proyecto: Ansible usa `/etc/ansible/ansible.cfg` y no encuentra el inventario.
- Confundir `command` y `shell`: `command` no procesa tuberías, redirecciones ni variables de entorno.
- Interpretar `FAILED` con `rc=1` de `rpm -q` como un fallo: es la respuesta "no instalado".
- Parámetros de un módulo en otro (`content:` dentro de `service`): comprobar con `ansible-doc -s`.
- `group_vars` fuera de `inventory/` (caso [etapa7/03](../troubleshooting/etapa7/03-group-vars-ubicacion-incorrecta.md)).
- Nombres de `notify:` y `name:` del handler distintos (mayúsculas incluidas).
- Copiar ejemplos con los `#` de la documentación, o los marcadores `<variable>` tal cual.
- Editar un vault con `vim` en lugar de `ansible-vault edit`.
- `password_hash` sin sal fija: el hash cambia en cada ejecución y la tarea sale siempre `changed`.
- Fechas dentro de una plantilla (rompen la idempotencia, caso [etapa7/02](../troubleshooting/etapa7/02-plantilla-timestamp-rompe-idempotencia.md)).
- Errores del equipo host vistos durante la práctica: `virsh start` admite **un** dominio por llamada
  (`for v in 7 8 9 10; do virsh start rhel$v-app01; done`) y en un `for` la lista va separada por espacios, no
  por comas.

## Diferencias RHEL 7/8/9/10

Verificadas en las VMs del lab durante la práctica:

| Aspecto | RHEL 7 | RHEL 8 | RHEL 9 | RHEL 10 | Impacto en una migración |
|---|---|---|---|---|---|
| Versión instalada (*fact*) | 7.9 | 8.6 | 9.8 | 10.2 | `when` por `distribution_major_version` (con `\| int`) |
| Intérprete que usa Ansible | `/usr/bin/python` (Python 2) | `/usr/libexec/platform-python` | `/usr/bin/python3` | `/usr/bin/python3` | Módulos propios deben ser compatibles con Python 2.7 mientras quede RHEL 7 ([etapa7/05](../troubleshooting/etapa7/05-modulo-propio-python3-falla-en-rhel7.md)) |
| Gestor de paquetes | yum | dnf | dnf | dnf | `ansible.builtin.package` abstrae la diferencia (P3, P10) |
| Paquete/servicio `at`/`atd` | Igual en las cuatro | | | | Mismo playbook para todas |

## Automatización

- **El propio proyecto es la automatización**: playbooks y roles idempotentes, versionados como proyecto de
  referencia en `scripts/stageN3/files/practica-ansible/`.
- **Validación repetible**: `scripts/stageN3/validar.sh` (estructura de roles, vault no expuesto, inventario,
  `--syntax-check`, plantillas sin fechas, `yamllint` y `ansible-lint` si están instalados).
- **Sin comandos `lab.sh`** a propósito: el objetivo de la etapa es trabajar sin scripts del lab.
- **Pendiente** (ampliación): pasar `validar.sh` en el CI de la Etapa 20 y probar `practica_final` con Molecule y
  Podman, como el rol `common` de la Etapa 7.

## Ejercicio práctico

Sin mirar el proyecto de referencia:

1. Repite P10 desde cero en una carpeta nueva y compara con `scripts/stageN3/files/practica-ansible/`.
2. Añade un `host_vars/rhel9-app01.yml` que pise `practica_rol` y explica la precedencia con
   `ansible rhel9-app01 -m debug -a var=practica_rol -J`.
3. Provoca y diagnostica el caso 07 en tu copia (renombrar `defaults/main.yml`) sin quitar `no_log`.
4. Lanza `limpieza.yml` y comprueba que no quedan restos (`id operador`, `ls /etc/practica-*`).

## Criterios de aceptación

- [x] P1-P10 hechos a mano y ejecutados contra las VMs reales.
- [x] Cada playbook con segunda ejecución `changed=0`.
- [x] Fallos reales documentados en `troubleshooting/etapaN3/` (7 casos) y guía de estudio.
- [x] Proyecto de referencia en el repositorio, sin secretos (`vault.yml` en `.gitignore`).
- [x] `scripts/stageN3/validar.sh` con `FAIL=0`.
- [ ] `limpieza.yml` aplicado (o `snapshot revert all 7`) y `scripts/lab.sh test all all` en 0 FAIL después.
- [ ] Checklist [`checklists/etapaN3.md`](../checklists/etapaN3.md) con los resultados pendientes rellenados.
