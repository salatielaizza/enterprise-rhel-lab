# 🤖 Etapa 7 — Ansible (`scripts/stage7/`)

## Qué hace esta etapa

Convierte `ansible01` (10.10.10.30) en el **nodo de control** de Ansible del laboratorio. Desde ahí gestiona
por SSH (sin agente) `rhel7/8/9/10-app01` y `dns01` con roles idempotentes, secretos cifrados con
**Ansible Vault** y, en la parte avanzada, `block/rescue/always`, `serial`, una colección propia (módulo +
filtro), inventario dinámico y pruebas con Molecule.

## Cómo se lanza

```bash
scripts/lab.sh stage7-setup          # una vez: ansible-core, proyecto, clave SSH distribuida, vault, ping
scripts/lab.sh stage7 facts          # exploración (no cambia nada)
scripts/lab.sh stage7 site           # configuración real (repetible: el 2º pase debe dar changed=0)
scripts/lab.sh stage7 site --limit rhel9-app01
scripts/lab.sh stage7 advanced [-e lab_simulate_failure=true]
scripts/lab.sh stage7 dynamic_inventory_demo
```

## Scripts

| Script | Corre en | Qué hace | Qué modifica |
|---|---|---|---|
| `01-ansible-control-setup.sh` | `ansible01` (root) | Instala `ansible-core` (EPEL si hace falta), copia `files/` a `~adminlab/ansible-lab`, genera la clave SSH de `adminlab`, la contraseña de Vault (`~/.vault_pass.txt`, 0600) y cifra `vault.yml` la 1ª vez; imprime la clave pública para que `lab.sh` la reparta | `~adminlab/ansible-lab/`, `~adminlab/.ssh/`, `~adminlab/.vault_pass.txt` |
| `02-run-playbook.sh <site\|facts\|ping\|advanced\|dynamic_inventory_demo>` | `ansible01` | Lanza el playbook **como `adminlab`** (`runuser`), desde `~/ansible-lab` (donde está su `ansible.cfg`) | Lo que haga el playbook en los nodos |
| `03-mark-stage.sh` | cada nodo gestionado | `set_stage 7`, solo si existe `/etc/ansible-lab-managed.txt` (prueba de que `site` se aplicó) | `/etc/lab-release` |

`lab.sh stage7-setup` reparte la clave de `ansible01` usando el acceso que el host ya tiene desde la Etapa 1
(sin contraseñas nuevas). `lab.sh stage7 site` llama a `03-mark-stage.sh` en cada nodo **solo si el
playbook terminó sin errores**.

## El proyecto Ansible: `files/` → `~adminlab/ansible-lab`

| Ruta | Contenido |
|---|---|
| `ansible.cfg` | Inventario, `roles_path`, `collections_path`, `vault_password_file`, `become` por sudo |
| `inventory/hosts.ini` | Grupos `app` y `dns`, padre `lab` (sin `ansible01`: es el controlador) |
| `inventory/group_vars/all/vars.yml` | Variables no secretas (`lab_timezone`, paquetes, usuarios demo) |
| `inventory/group_vars/all/vault.yml` | Secreto de demo **cifrado** (se crea en `ansible01`; no está en el repo) |
| `inventory/dynamic_inventory_demo.py` | Inventario dinámico de ejemplo (contrato `--list`/`--host`) contra una API pública |
| `playbooks/site.yml` | Roles `common` + `lab_users` sobre el grupo `lab` |
| `playbooks/facts.yml` | Solo lectura: distro, versión, intérprete Python detectado |
| `playbooks/advanced.yml` | `block/rescue/always`, `serial: 2`, módulo y filtro propios |
| `playbooks/dynamic_inventory_demo.yml` | Uso del inventario dinámico |
| `roles/common/` | Paquetes base, zona horaria (leída con `stat`, válida en RHEL 7 y en `--check`), marcador `/etc/ansible-lab-managed.txt`, handler; escenario de **Molecule** |
| `roles/lab_users/` | Usuarios `ansible.demo1/2` con la contraseña bloqueada |
| `collections/ansible_collections/lab/utils/` | Colección propia: módulo `lab_uptime_pretty` y filtros `lab_filters` |

## Reglas aprendidas en esta etapa

- **La fuente de verdad es `scripts/stage7/files/` en git**: `stage7-setup` recopia `ansible-lab` con
  `cp -a`, así que un arreglo hecho solo en `ansible01` se pierde (caso `etapa7/03`).
- Los comandos `ansible`/`ansible-playbook` se lanzan **desde `~/ansible-lab`**, porque `ansible.cfg` se
  busca en el directorio actual.
- Nada de valores cambiantes (fechas) en plantillas: rompen la idempotencia (caso `etapa7/02`).

## Cómo se verifica

```bash
scripts/lab.sh stage7 site && scripts/lab.sh stage7 site    # 2º pase: changed=0 en todos
scripts/lab.sh test all all                                 # incluye test_ansible
```

## Documentación relacionada

- Checklist: [`checklists/etapa7.md`](../../checklists/etapa7.md)
- Tema: [`automation/ansible.md`](../../automation/ansible.md)
- Casos reales: [`troubleshooting/etapa7/`](../../troubleshooting/etapa7/README.md) (su guía de estudio se crea al cerrar la etapa)
- La Etapa 8 reutiliza sus roles, su clave SSH y su contraseña de Vault: [`scripts/stage8/README_stage8.md`](../stage8/README_stage8.md)
