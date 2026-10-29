# ETAPA N3 — CHECKLIST: práctica de Ansible sin scripts (P1-P10)

> Una etapa **no está completa** hasta marcar TODO: documentación + validación + troubleshooting + limpieza.
> Rellena "Resultado obtenido" con lo que veas **de verdad**. Lo que ya está escrito sale de las salidas reales de
> la práctica (2026-10-26 a 2026-10-29); lo marcado "confirmado" se dio por bueno sin pegar la salida.
> Guía: [`automation/etapaN3-practica-ansible.md`](../automation/etapaN3-practica-ansible.md) · Scripts: [`scripts/stageN3/README_stageN3.md`](../scripts/stageN3/README_stageN3.md)

## Objetivo
Escribir y operar desde cero un proyecto Ansible propio contra `rhel7/8/9/10-app01` y `dns01`, sin `lab.sh`, y
documentar los fallos reales que aparezcan.

## Entorno
| Dato | Valor |
|---|---|
| Nodo de control | Equipo host (Linux Mint 22), carpeta `practica/` del repositorio (ignorada por Git) |
| Versión de Ansible del nodo de control | (anotar `ansible --version \| head -1`) |
| Clave SSH | `adminlab@lab.local` (ED25519) en el `ssh-agent` |
| Hosts | `rhel7-app01` 7.9 · `rhel8-app01` 8.6 · `rhel9-app01` 9.8 · `rhel10-app01` 10.2 · `dns01` 9.8 |

## Comandos (orden)
| # | Comando / acción | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| P1 | `ansible --version \| head -2` · `ansible-inventory --graph` · `ansible all -m ping -o` · `-b -m command -a whoami` | `ansible.cfg` del proyecto; grupos `app`(`legacy`,`modernos`) y `servicios`; 5 × `pong`; 5 × `root` | Completado (confirmado, 2026-10-26) |
| P2.3 | `ansible 'all:!legacy' --list-hosts` | 4 hosts | 4: `dns01`, `rhel8/9/10-app01` (2026-10-28) |
| P2.4 | `ansible 'app:&modernos' --list-hosts` | 3 hosts | 3: `rhel8/9/10-app01` |
| P2.5 | `ansible all -m setup -a 'filter=ansible_distribution*'` | *Facts* de distribución | Primero vacío por una errata (caso 01); intérpretes: RHEL 7 `/usr/bin/python`, 8 `platform-python`, 9/10/`dns01` `python3` |
| P2 | Resto de puntos (uptime, `df`, `copy`/`file`, `fetch`, `sshd`, `ansible-doc`) | Ver guía | Completado (confirmado) |
| P3.0 | `ansible app -m command -a 'rpm -q at' -o` | Anotar estado previo | `package at is not installed` (`rc=1`) en las 4 `app01` (2026-10-28) |
| P3 | `p3-servicio.yml`: `--syntax-check`, `--check --diff`, real, 2.ª real | 2.ª con `changed=0`; handler solo al cambiar el fichero | `--check` falló en `atd` (caso 02); real e idempotencia correctas (confirmado) |
| P4 | `p4-usuarios.yml` | Usuarios con `loop`; fichero solo en versión ≥ 8; `debug` solo en `legacy` | Completado (confirmado) |
| P5 | `p5-rol.yml` con `roles/practica_base` | `changed` + handler; mensaje propio en `dns01`; 2.ª `changed=0` | Rol vacío y ficheros fuera del rol (caso 03); después, correcto (confirmado 2026-10-28) |
| P6 | `p6-vault.yml -J` (dos veces) | 2.ª `changed=0`; secreto nunca en la salida | Indentación (caso 04) y vault comentado (caso 05); `practica_password \| length` → `13`; correcto (2026-10-29) |
| P7 | `p7-plantilla.yml -J` (dos ejecuciones reales) | Fichero distinto por host; 2.ª `changed=0` | Diff real correcto (7.9 `yum (legacy)`/`LEGACY`, 8.6/9.8/10.2 `dnf`/`APLICACIONES`, `dns01` `DNS`); dos `--check` no prueban la idempotencia (caso 06) |
| P8 | `p8-errores.yml -J` | `rhel7-app01`: `rescued=1 ignored=1 failed=0`; resto: `ignored=1 failed=0` | Completado (confirmado; anotar el PLAY RECAP) |
| P9 | `ansible-galaxy collection install -r requirements.yml -p ./collections` · `p9-firewalld.yml -J` · `-e practica_fw_state=disabled` | `8080/tcp` abierto y después cerrado en `modernos` | Completado (confirmado; anotar versión de `ansible.posix`) |
| P10 | `p10-final.yml -J`: `--list-hosts`, `--list-tags`, `--check --diff`, real, 2.ª real | 3 hosts; etiquetas `cron`, `fichero`, `usuarios`; 2.ª `changed=0` | `defaults/main-yml` mal nombrado (caso 07); después, correcto (confirmado 2026-10-29) |
| V.1 | `scripts/stageN3/validar.sh` | `FAIL=0` | `PASS=18 FAIL=0 SKIP=1` en la sesión de preparación (repetir en el host y anotar) |
| C.1 | `ansible-playbook limpieza.yml -J` (o `scripts/lab.sh snapshot revert all 7`) | Sin usuarios `practica1/2`/`operador`, sin `/etc/practica-*`, sin `at`, 8080 cerrado | |
| C.2 | `scripts/lab.sh test all all` | 0 FAIL en las 6 VMs | |

## Documentación
- [x] `automation/etapaN3-practica-ansible.md` (plantilla completa del proyecto)
- [x] `scripts/stageN3/README_stageN3.md`, `scripts/stageN3/validar.sh`, `scripts/stageN3/files/practica-ansible/`
- [x] `troubleshooting/etapaN3/` (7 casos) + `README_troubleshooting_etapaN3.md`
- [x] `README.md` y `troubleshooting/README.md` actualizados

## Criterios de aceptación
- [x] P1-P10 hechos a mano contra las VMs reales.
- [x] Segunda ejecución con `changed=0` en todos los playbooks.
- [x] Fallos reales documentados (7 casos) con salida real.
- [x] Ningún secreto en el repositorio: `vault.yml` en `.gitignore`; solo `vault.yml.example` con `CAMBIAR`.
- [ ] `validar.sh` repetido en el equipo host con `FAIL=0`.
- [ ] Limpieza aplicada y `test all all` en 0 FAIL.

## Errores encontrados y solución
| Fecha | Síntoma | Causa raíz | Solución | Caso |
|---|---|---|---|---|
| 2026-10-28 | `setup` con filtro devuelve solo el intérprete | Errata `distribuition` | Corregir el patrón | [01](../troubleshooting/etapaN3/01-setup-filter-errata-devuelve-vacio.md) |
| 2026-10-28 | `--check`: `Could not find the requested service atd` | El paquete solo se "instaló" en la simulación | Ejecución real + `ignore_errors: "{{ ansible_check_mode }}"` | [02](../troubleshooting/etapaN3/02-check-servicio-de-paquete-no-instalado.md) |
| 2026-10-28 | Rol sin tareas; `handler ... was not found` | Esqueleto de `role init` sin rellenar y ficheros en `roles/tasks`, `roles/defaults` | Contenido en `roles/practica_base/...`; apartar los sobrantes | [03](../troubleshooting/etapaN3/03-rol-ficheros-fuera-de-su-sitio.md) |
| 2026-10-29 | `mapping values are not allowed in this context` | `hosts:` con más sangría que `name:` | Claves del play en la misma columna | [04](../troubleshooting/etapaN3/04-yaml-indentacion-claves-del-play.md) |
| 2026-10-29 | Tarea con `no_log` falla oculta; `vault_practica_password is undefined` | `vault.yml` solo con comentarios | `ansible-vault edit` sin `#` | [05](../troubleshooting/etapaN3/05-vault-con-contenido-comentado.md) |
| 2026-10-29 | Dos `--check` seguidos con `changed=1` | `--check` no crea el fichero (`@@ -0,0`) | Dos ejecuciones reales | [06](../troubleshooting/etapaN3/06-check-repetido-no-prueba-idempotencia.md) |
| 2026-10-29 | Tarea `user` con `no_log` falla oculta | `defaults/main-yml` en vez de `main.yml` | Renombrar | [07](../troubleshooting/etapaN3/07-defaults-main-yml-mal-nombrado.md) |

Incidencias no documentadas como caso (sin causa demostrable o ajenas a Ansible): un `Permission denied (publickey)`
puntual en `rhel9-app01` que no se reprodujo (servidor correcto: clave, permisos y `ssh_home_t`; el journal mostraba
que el cliente cerró la conexión); un `No route to host` en las cuatro `app01` justo después de arrancarlas; y
errores de sintaxis de shell en el host (`virsh start` con varios dominios, `for` con comas).

## Conocimientos adquiridos
- Ansible busca `ansible.cfg` en el directorio actual, `group_vars` junto al inventario y cada pieza de un rol en
  `roles/<rol>/<carpeta>/main.yml`; si algo no está ahí, no avisa.
- `--check` simula tarea a tarea: sirve para revisar, no para probar la idempotencia.
- `no_log` también oculta los errores: se diagnostica por partes sin revelar el secreto.
- Vault: patrón `vault_*` cifrado + variable pública en `vars.yml`; `password_hash` con sal fija para ser idempotente.
- Jinja2: expresiones `{{ }}` y sentencias `{% %}`; filtros `int`, `default`, `upper`, `map`, `join`; se renderiza en el controlador.
- Errores: `failed_when`, `ignore_errors`, `block`/`rescue`/`always`, `check_mode: false` para lecturas.
- Colecciones: `ansible-core` solo trae `ansible.builtin`; `ansible.posix` se instala con versión fijada dentro del proyecto.

## Ampliaciones futuras
- Probar `practica_final` con Molecule y Podman (como el rol `common` de la Etapa 7).
- `validar.sh` en el CI de la Etapa 20.
- Repetir P1-P10 en `ansible01` con su `ansible-core` y comparar versiones de módulos y colecciones.
- Ejercicio inverso: un proyecto con fallos ya metidos para encontrarlos sin escribirlo desde cero.
