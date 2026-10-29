# 🎯 Troubleshooting y guía de estudio — Etapa N3 (práctica de Ansible sin scripts)

Ver formato y regla general en [`troubleshooting/README.md`](../README.md).

Este documento tiene dos usos:

1. **Índice de los casos reales** que aparecieron al escribir y ejecutar P1-P10 contra las VMs.
2. **Base de estudio**: los comandos de la práctica y de `scripts/stageN3/validar.sh`, explicados, más una chuleta
   de síntoma → primeros comandos para los fallos típicos de Ansible.

> Regla del proyecto: *manual → documentado → repetible → automatizado*. Aquí el paso manual es la propia
> herramienta: escribir el proyecto Ansible a mano. Guía: [`automation/etapaN3-practica-ansible.md`](../../automation/etapaN3-practica-ansible.md).

---

## 1. Casos documentados

| Caso | Tema |
|---|---|
| [01 setup-filter-errata-devuelve-vacio](01-setup-filter-errata-devuelve-vacio.md) 🔎 | `setup` con `filter=ansible_distribuition*` (errata) devuelve `SUCCESS` sin *facts* |
| [02 check-servicio-de-paquete-no-instalado](02-check-servicio-de-paquete-no-instalado.md) 🔎 | `--check`: `Could not find the requested service atd`, porque el paquete solo se "instaló" en la simulación |
| [03 rol-ficheros-fuera-de-su-sitio](03-rol-ficheros-fuera-de-su-sitio.md) 🔎 | El rol no ejecuta nada y el handler "no existe": esqueleto de `role init` sin rellenar y ficheros en `roles/tasks` |
| [04 yaml-indentacion-claves-del-play](04-yaml-indentacion-claves-del-play.md) 🔎 | `mapping values are not allowed in this context`: `hosts:` con más sangría que `name:` |
| [05 vault-con-contenido-comentado](05-vault-con-contenido-comentado.md) 🔎 | `no_log` oculta el error: el `vault.yml` cifrado solo contenía comentarios |
| [06 check-repetido-no-prueba-idempotencia](06-check-repetido-no-prueba-idempotencia.md) 🔎 | Dos `--check` seguidos dan `changed=1`: el fichero no existe (`@@ -0,0`) |
| [07 defaults-main-yml-mal-nombrado](07-defaults-main-yml-mal-nombrado.md) 🔎 | `defaults/main-yml` no se carga y `no_log` oculta el `undefined variable` |

🔎 = encontrado de forma orgánica al ejecutar contra las VMs reales.

Relacionados de otras etapas: [etapa4/02](../etapa4/02-ssh-failure.md) (`Permission denied (publickey)`),
[etapa7/02](../etapa7/02-plantilla-timestamp-rompe-idempotencia.md) (fecha en una plantilla),
[etapa7/03](../etapa7/03-group-vars-ubicacion-incorrecta.md) (`group_vars` mal ubicado),
[etapa7/04](../etapa7/04-restos-de-ejercicios-en-nodo-de-control.md) (practicar fuera de `~/ansible-lab`),
[etapa7/05](../etapa7/05-modulo-propio-python3-falla-en-rhel7.md) (Python 2.7 en RHEL 7),
[etapa10/01](../etapa10/01-preflight-pipefail-sigpipe.md) (`| grep -q` con `pipefail`; el mismo fallo apareció al
escribir `validar.sh` y se evitó guardando antes la salida en una variable).

**Incidencias no documentadas como caso**: un `Permission denied (publickey)` puntual en `rhel9-app01` que no se
volvió a reproducir (el servidor estaba bien y el journal mostraba que fue el cliente quien cerró la conexión:
`Connection closed by authenticating user ... [preauth]`), y un `No route to host` en las cuatro `app01` recién
arrancadas. Sin evidencia de la causa no se inventa un caso: si se repite, capturar en ese momento
`ansible <host> -m ping -vvvv`.

---

## 2. Flujo de la etapa (orden exacto)

| # | Paso | Comando | Dónde corre |
|---|---|---|---|
| 1 | Proyecto mínimo (P1) | `ansible --version \| head -2` · `ansible-inventory --graph` · `ansible all -m ping -o` | Nodo de control |
| 2 | Ad-hoc (P2) | `ansible <patrón> -m <módulo> -a '<args>'` | Nodo de control → VMs |
| 3 | Playbooks (P3-P8, P10) | `--syntax-check` → `--check --diff` → real → 2.ª real | Nodo de control → VMs |
| 4 | Colección (P9) | `ansible-galaxy collection install -r requirements.yml -p ./collections` | Nodo de control |
| 5 | Validación estática | `scripts/stageN3/validar.sh` | Host (no toca las VMs) |
| 6 | Limpieza | `ansible-playbook limpieza.yml -J` (o `scripts/lab.sh snapshot revert all 7`) | Nodo de control → VMs |
| 7 | Comprobación final | `scripts/lab.sh test all all` | Host → 6 VMs |

---

## 3. Comandos de la práctica, explicados

| Comando | Qué hace | Por qué |
|---|---|---|
| `ansible all -m command -a uptime -o` | Ejecuta un comando sin shell en cada host, una línea por host | `command` es el módulo por defecto; sale `CHANGED` porque no sabe si cambió algo |
| `ansible 'all:!legacy' --list-hosts` / `'app:&modernos'` | Resuelve un patrón sin conectar | `:!` excluye, `:&` intersecta; comillas simples por `!` y `&` |
| `ansible all -m setup -a 'filter=…'` | *Facts* filtrados por nombre | Sin filtro son cientos de líneas por host |
| `ansible dns01 -m copy -a 'content="hola\n" dest=/tmp/hola.txt'` | Escribe un fichero si su contenido difiere | Compara checksums: idempotente |
| `ansible dns01 -m file -a 'path=… state=absent'` | Borra si existe | Idempotente y admite `--check`, a diferencia de `rm` |
| `ansible all -m fetch -a 'src=… dest=./traidos/'` | Copia del nodo al controlador | Crea `traidos/<host>/<ruta>` para no pisar ficheros |
| `ansible-galaxy role init roles/<rol>` | Esqueleto de rol | Solo crea `main.yml` con `---` y un comentario |
| `ansible-playbook X --list-tasks / --list-tags / --list-hosts` | Qué se ejecutaría | Confirma que el rol se carga y de dónde salen las etiquetas |
| `ansible-vault create / view / edit` | Gestiona ficheros cifrados (AES256) | El fichero queda cifrado en disco; `edit` lo descifra solo en memoria |
| `ansible-playbook X -J` (`--ask-vault-pass`) | Pide la contraseña de vault | Sin ella: `Attempting to decrypt but no vault secrets found` |
| `ansible-galaxy collection install -r requirements.yml -p ./collections` | Instala colecciones en el proyecto | Versión fijada y reproducible; `collections_path` en `ansible.cfg` |
| `ansible-config dump --only-changed` | Muestra la configuración distinta de la de por defecto | Comprobar que `ansible.cfg` se aplica |

### `scripts/stageN3/validar.sh`

| Comando del script | Qué hace | Por qué |
|---|---|---|
| `mktemp -d` + `trap 'rm -rf "$TMP"' EXIT` | Copia de trabajo temporal que se borra siempre | No modificar nunca el repositorio |
| `cp vault.yml.example vault.yml` (en la copia) | Vault de ejemplo sin cifrar | Validar sin pedir contraseña |
| `find roles -mindepth 3 … ! -name main.yml` | Busca ficheros que Ansible no carga | Casos 03 y 07 |
| `find roles -mindepth 1 -maxdepth 1 -name tasks …` | Busca carpetas de rol sueltas en `roles/` | Caso 03 |
| `head -1 vault.yml \| grep -qF '$ANSIBLE_VAULT'` | Comprueba que un `vault.yml` del repo esté cifrado | Ningún secreto en claro |
| `ansible-inventory --graph` | Grupos del inventario | `app`, `legacy`, `modernos`, `servicios` |
| `colecciones="$(ansible-galaxy collection list)"` y después `grep` | Detecta `ansible.posix` | Sin `\| grep -q` directo: con `pipefail` daría SIGPIPE (etapa10/01) |
| `ansible-playbook --syntax-check` | Estructura de cada playbook | No detecta parámetros inexistentes |
| `grep -rnE 'date_time\|now\(' --include='*.j2'` | Fechas en plantillas | Idempotencia (etapa7/02) |
| `yamllint` · `ansible-lint --offline` | Estilo y buenas prácticas | Opcionales; `ansible-lint` solo avisa del `ignore_errors` intencionado de P8 |

---

## 4. Comprobaciones de `validar.sh`, explicadas

| Comprobación | Comando manual equivalente | Qué demuestra |
|---|---|---|
| `roles: defaults/tasks/handlers solo contienen main.yml` | `find roles -path '*/defaults/*' -type f` | Que Ansible carga todo lo escrito |
| `roles/: sin carpetas de rol sueltas` | `ls roles/` | Que no hay ediciones fuera de un rol |
| `vault.yml: ausente o cifrado` | `head -1 inventory/group_vars/all/vault.yml` | Ningún secreto en claro en Git |
| `inventario: grupo X` | `ansible-inventory --graph` | Estructura de grupos de P1 |
| `--syntax-check pN.yml` | `ansible-playbook pN.yml --syntax-check` | YAML y estructura del play correctos (caso 04) |
| `plantillas sin fechas` | `grep -rn date_time templates roles/*/templates` | Plantillas idempotentes |

`validar.sh` no sustituye a la prueba real: la idempotencia se comprueba con dos ejecuciones reales contra las VMs.

---

## 5. Comandos de diagnóstico de los casos reales

```bash
# Dónde está cada cosa (casos 03 y 07)
tree -I 'collections|traidos'
grep -rn '<texto>' roles/ inventory/ *.yml
cat -A <fichero>                          # invisibles: $ fin de línea, ^I tabulador
find roles/<rol> -type f | sort

# Variables y vault sin revelar secretos (casos 05 y 07)
ansible <host> -m debug -a 'msg="{{ <variable> | length }}"' -J
ansible localhost -m debug -a "msg={{ 'prueba' | password_hash('sha512', 'salprueba') }}" -J
ansible-vault view inventory/group_vars/all/vault.yml | cut -d: -f1
ansible-inventory --host <host> -J | grep -o '"practica_[a-z_]*"'

# Simulación frente a ejecución real (casos 02 y 06)
ansible-playbook X --check --diff --limit <host>      # cabecera @@ -0,0 = el fichero no existe
ansible app -m command -a 'rpm -q at' -o              # rc=1 = no instalado

# YAML (caso 04)
cat -n X | head -20
ansible-playbook X --syntax-check

# Conexión (incidencias no reproducibles)
ssh -v adminlab@<ip> true 2>&1 | grep -E 'Offering|Server accepts|denied'
ssh-add -l
ansible <host> -m ping -vvvv 2>&1 | grep -E 'Offering|accepts|denied|SSH: EXEC'
```

---

## 6. Chuleta: síntoma → primeros comandos

| Síntoma | Primeros comandos |
|---|---|
| `Could not match supplied host pattern` / `No inventory was parsed` | `pwd`; `ansible --version \| head -2` |
| `UNREACHABLE … No route to host` | `virsh list --all`; `virsh net-list --all`; `ping -c2 <ip>` |
| `UNREACHABLE … Permission denied (publickey)` | `ssh -v adminlab@<ip> true`; `ssh-add -l`; en el nodo: `ls -ldZ ~/.ssh`, `journalctl -u sshd` |
| `setup` con filtro devuelve vacío | Revisar el patrón; `ansible <host> -m setup \| grep -o '"ansible_[a-z_]*"' \| sort -u` |
| `--check` falla en una tarea que depende de otra | Ejecutar de verdad o `ignore_errors: "{{ ansible_check_mode }}"` |
| Rol que solo hace *Gathering Facts* | `--list-tasks`; `tree roles/`; `cat roles/<rol>/tasks/main.yml` |
| `The requested handler '…' was not found` | `grep -rn '<nombre>' roles/`; `cat -A roles/<rol>/handlers/main.yml` |
| `mapping values are not allowed in this context` | `cat -n X`; alinear las claves del mismo nivel |
| `"censored": … 'no_log: true'` | Longitud de la variable; filtro con texto de prueba; nombres del vault; `defaults/main.yml` existe |
| `VARIABLE IS NOT DEFINED!` | `ansible-inventory --host <host>`; `ls inventory/group_vars/`; nombre del fichero del rol |
| `Attempting to decrypt but no vault secrets found` | Añadir `-J` (también para `localhost` y `ansible-inventory`) |
| `Decryption failed` | Contraseña de vault mal escrita |
| La 2.ª ejecución sigue con `changed` | ¿Fueron ejecuciones reales?; fechas en plantillas; `password_hash` sin sal fija; `command` sin `changed_when` |

---

## 7. Preguntas de repaso

1. **¿Dónde busca Ansible su `ansible.cfg` y en qué orden?** `ANSIBLE_CONFIG`, `./ansible.cfg`, `~/.ansible.cfg`,
   `/etc/ansible/ansible.cfg`. Por eso los comandos se lanzan desde la raíz del proyecto.
2. **¿Qué significa `[app:children]`?** Que `app` contiene los **grupos** listados debajo, no hosts.
3. **¿Por qué `all` incluye a `dns01`?** `all` es un grupo implícito con todos los hosts del inventario.
4. **¿Diferencia entre `command` y `shell`?** `command` no pasa por una shell (sin tuberías, redirecciones ni
   variables); `shell` sí. Se usa `command` siempre que basta.
5. **¿Por qué un módulo es mejor que `rm` en un ad-hoc?** Es idempotente, informa bien de `changed` y admite `--check`.
6. **¿Qué demuestra `--check --diff` y qué no?** Muestra qué cambiaría; no prueba la idempotencia ni puede ejecutar
   tareas que dependen de un cambio previo real.
7. **¿Cuándo se ejecuta un handler?** Una sola vez, al terminar la sección de tareas (o en un `meta: flush_handlers`),
   y solo si alguna tarea que lo notifica sale `changed`.
8. **¿Qué ficheros carga Ansible solo dentro de un rol?** `defaults/`, `vars/`, `tasks/`, `handlers/` y `meta/`,
   cada uno con su `main.yml`; plantillas y ficheros se citan desde las tareas.
9. **¿Por qué `group_vars` pisa a `defaults/` de un rol?** `defaults/` tiene la precedencia más baja de todas.
10. **¿Por qué el `password_hash` necesita una sal fija?** Con sal aleatoria el hash cambia cada vez y la tarea
    sale `changed` siempre.
11. **¿Cómo se diagnostica una tarea con `no_log` sin revelar el secreto?** Por partes: longitud de la variable,
    filtro con un texto de prueba, nombres de las claves del vault; y, como último recurso, sin `no_log` en
    `--check` contra un solo host.
12. **¿Dónde se renderiza una plantilla Jinja2?** En el controlador; al nodo llega el fichero final.
13. **¿Para qué sirve `check_mode: false` en una tarea de lectura?** Para que se ejecute también en `--check`; si
    no, `command` no se ejecuta y su `rc` no es real.
14. **¿Qué trae `ansible-core` y qué no?** Solo `ansible.builtin`; `ansible.posix` (firewalld, selinux, mount…) se
    instala aparte, mejor con versión fijada en `requirements.yml`.
