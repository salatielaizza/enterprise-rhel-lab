# 🎯 Etapa N3 — Práctica de Ansible sin scripts (`scripts/stageN3/`)

## Qué hace esta etapa

Práctica guiada de Ansible **sin `lab.sh` y sin el proyecto del lab**: diez ejercicios (P1-P10) escritos a mano,
desde cero, y ejecutados contra las cinco VMs gestionadas (`rhel7/8/9/10-app01` y `dns01`). Cubre configuración,
inventario por grupos, comandos ad-hoc, playbooks con handlers, variables y *facts*, roles propios, Ansible Vault,
plantillas Jinja2, control de errores, colecciones de Galaxy y un ejercicio final que lo junta todo.

Guía completa (enunciados, comandos, resultados reales y diferencias entre versiones):
[`automation/etapaN3-practica-ansible.md`](../../automation/etapaN3-practica-ansible.md).

## Diferencias con las demás carpetas `stageN/`

- **No hay comandos `lab.sh`** a propósito: el objetivo es trabajar sin los scripts del lab.
- **No crea hosts ni marca `LAB_STAGE`**: usa las VMs de las Etapas 1-7 tal como están.
- `files/practica-ansible/` no se despliega en ninguna VM: es el **proyecto de referencia** con las soluciones
  validadas, para comparar con el propio y para repetir la práctica.
- El proyecto de trabajo de cada uno vive **fuera de Git**: en `practica/` del repositorio (ignorada) o en
  `ansible01:~/practica-ansible` (fuera de `~/ansible-lab`, que `stage7-setup` sincroniza con `rsync --delete`).

## Contenido

| Fichero | Dónde corre | Qué hace | Qué modifica |
|---|---|---|---|
| `validar.sh` | Host o `ansible01` | Validación **estática** del proyecto de referencia sobre una copia temporal: estructura de los roles (solo `main.yml` en `defaults/`, `tasks/` y `handlers/`; sin carpetas de rol sueltas), vault no expuesto, grupos del inventario, `--syntax-check` de cada playbook, plantillas sin fechas, `yamllint` y `ansible-lint` si están instalados | Nada (borra su copia temporal al salir). Código de salida = número de FAIL |
| `files/practica-ansible/` | Nodo de control | Soluciones P1-P10 + `limpieza.yml` | Las VMs, solo si se ejecutan sus playbooks |

Ficheros del proyecto de referencia:

| Ejercicio | Ficheros |
|---|---|
| P1 | `ansible.cfg`, `inventory/hosts.ini` |
| P2 | (solo comandos ad-hoc: ver la guía) |
| P3 | `p3-servicio.yml` |
| P4 | `p4-usuarios.yml`, `inventory/group_vars/all/vars.yml` |
| P5 | `p5-rol.yml`, `roles/practica_base/`, `inventory/group_vars/servicios.yml` |
| P6 | `p6-vault.yml`, `inventory/group_vars/all/vault.yml.example` |
| P7 | `p7-plantilla.yml`, `templates/practica-info.j2`, `inventory/group_vars/{legacy,modernos,servicios}.yml` |
| P8 | `p8-errores.yml` |
| P9 | `p9-firewalld.yml`, `requirements.yml` |
| P10 | `p10-final.yml`, `roles/practica_final/` |
| Cierre | `limpieza.yml` (usuarios, ficheros, tarea `cron`, paquete `at` y puerto 8080) |

## Requisitos previos

- Etapa 7 completa (clave SSH de `adminlab` en los nodos, `sudo` sin contraseña del grupo `sysadmins`).
- Ansible en el nodo de control; para P9 y `limpieza.yml`, la colección `ansible.posix`.
- Para `validar.sh`: `ansible-playbook` y `ansible-inventory`; opcionales `yamllint` y `ansible-lint`.

## Cómo se usa

**Validar el proyecto de referencia** (no toca ninguna VM):

```bash
scripts/stageN3/validar.sh
```

Salida esperada: líneas `PASS`/`FAIL`/`SKIP` y un resumen `PASS=… FAIL=0 SKIP=…`. Un `SKIP` en `p9-firewalld.yml`
y `limpieza.yml` significa que falta `ansible.posix`; se instala dentro del proyecto con
`ansible-galaxy collection install -r requirements.yml -p ./collections` (la carpeta `collections/` está en
`.gitignore`).

**Repetir la práctica** a partir de la referencia, sin tocar el repositorio:

```bash
cp -a scripts/stageN3/files/practica-ansible ~/mi-practica-ansible && cd ~/mi-practica-ansible
ansible-vault create inventory/group_vars/all/vault.yml     # vault_practica_password: "<tu contraseña>"
ansible --version | head -2 && ansible-inventory --graph
ansible-playbook p3-servicio.yml --syntax-check -J
```

**Dejar las VMs como estaban** al terminar (antes de volver a lanzar `scripts/lab.sh test all all`):

```bash
ansible-playbook limpieza.yml -J          # o, desde el host: scripts/lab.sh snapshot revert all 7
```

## Cómo se verifica

- `scripts/stageN3/validar.sh` con `FAIL=0`.
- En cada ejercicio: `--syntax-check`, `--check --diff`, ejecución real y **segunda ejecución con `changed=0`**.
- Después de `limpieza.yml`: `scripts/lab.sh test all all` en 0 FAIL (los tests de las Etapas 1-7 no deben verse
  afectados por la práctica).

## Enlaces

- Guía: [`automation/etapaN3-practica-ansible.md`](../../automation/etapaN3-practica-ansible.md)
- Checklist: [`checklists/etapaN3.md`](../../checklists/etapaN3.md)
- Troubleshooting y guía de estudio: [`troubleshooting/etapaN3/README_troubleshooting_etapaN3.md`](../../troubleshooting/etapaN3/README_troubleshooting_etapaN3.md)
- Etapa 7 (la base): [`automation/ansible.md`](../../automation/ansible.md), [`scripts/stage7/README_stage7.md`](../stage7/README_stage7.md)
