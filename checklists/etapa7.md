# ETAPA 7 — CHECKLIST: Automatización con Ansible

> Una etapa **no está completa** hasta marcar TODO: documentación + tests + troubleshooting + diferencias entre versiones + snapshot.
> Rellena las columnas "Resultado obtenido" con lo que veas **de verdad** (pega salidas en `results/etapa7/`).

## Objetivo
`ansible01` operativo como nodo de control de todo el lab (rhel7/8/9/10-app01, dns01), gestionando de forma **idempotente** paquetes base, huso horario y usuarios de demostración, con secretos manejados con Ansible Vault — sin sustituir el trabajo manual/bash de las Etapas 2-6, sino automatizándolo con la herramienta correcta para "muchos hosts a la vez".

## Comandos (orden)
| # | Comando | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 1 | `scripts/lab.sh stage7-setup` | ansible-core instalado en ansible01, clave SSH generada y distribuida a los 5 nodos gestionados, `ansible lab -m ping` y `-b -m command -a whoami` en verde | |
| 2 | `scripts/lab.sh stage7 facts` | por cada host: distro, versión mayor e intérprete Python detectado (RHEL 7 vs 8/9/10 se ve aquí) | |
| 3 | `scripts/lab.sh stage7 site` | `changed=` > 0 la primera vez, en los 5 nodos gestionados | |
| 4 | `scripts/lab.sh stage7 site` (repetido) | **`changed=0`** en todos — es la prueba de idempotencia | |
| 5 | `scripts/lab.sh test all all` | 0 FAIL (incluye `test_ansible`) | |
| 6 | Ejercicio: cambia `lab_timezone` en `group_vars/all/vars.yml` a `UTC`, repite `stage7 site` y comprueba `timedatectl` en una VM | solo esa VM marca `changed=1`, el resto de tareas siguen en 0 | |
| 7 | Ejercicio: comenta `lab_common_packages` de `group_vars/all/vars.yml` y repite `stage7 site` | cae al *default* del rol (`[tree]`) — demuestra la precedencia de variables | |
| 8 | `scripts/lab.sh stage7 site --limit rhel9-app01` | el playbook se aplica SOLO a esa VM | |
| 9 | `sudo -u adminlab ansible-vault view ~/ansible-lab/group_vars/all/vault.yml` (en ansible01) | el secreto de demo se descifra sin pedir contraseña (usa `vault_password_file`) | |
| 10 | `scripts/lab.sh facts all && scripts/lab.sh matrix` | `comparison/matrix.generated.md` con datos reales | |
| 11 | `scripts/lab.sh snapshot create all 7` | `…-stage7-complete` | |

### Parte avanzada (block/rescue, serial, colección propia, inventario dinámico, Molecule)
| # | Comando | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 12 | `scripts/lab.sh stage7 advanced` | `PLAY RECAP` con `rescued=0` en los 5 nodos; se ven dos lotes (`serial: 2`) | |
| 13 | `scripts/lab.sh stage7 advanced -e lab_simulate_failure=true` | `rescued=N` en vez de `failed=N`: el play NO aborta | |
| 14 | `ansible-doc lab.utils.lab_uptime_pretty` (en ansible01) | Documentación del módulo propio (DOCUMENTATION/EXAMPLES/RETURN) | |
| 15 | `scripts/lab.sh stage7 dynamic_inventory_demo` | Datos de la API pública mostrados por host, e informe en `~adminlab/dynamic-inventory-demo-report.txt` | |
| 16 | `cd scripts/stage7/files/roles/common && molecule test` (en el equipo HOST, con Docker) | Secuencia completa `create → converge → idempotence → verify → destroy` en verde | |

## Documentación
- [ ] `automation/ansible.md`

## Criterios de aceptación
- [ ] `scripts/lab.sh stage7 site` ejecutado dos veces seguidas: la segunda vez `changed=0` en todos los nodos (idempotencia real, no solo teórica)
- [ ] `ansible.cfg`/`hosts.ini`/`playbooks/*.yml`/`roles/**/*.yml` con `ansible-playbook --syntax-check` limpio
- [ ] El secreto de demo vive SOLO cifrado con Ansible Vault en el repositorio; la contraseña de vault nunca se ha subido a git
- [ ] Sabes explicar: agentless/push vs pull, idempotencia, inventario, `become`, roles, `group_vars` vs `defaults` (precedencia), Ansible Vault
- [ ] Sabes explicar (parte avanzada): `block`/`rescue`/`always`, qué hace `serial`, cómo se resuelve una colección local por `collections_path`, qué es un inventario dinámico y por qué el de demo usa `ansible_connection=local`
- [ ] `molecule test` pasa en local (equipo host) para el rol `common`
- [ ] Repositorio en Git con historial limpio

## Errores encontrados y solución
| Error | Causa | Solución |
|---|---|---|
| `ansible-vault encrypt` con `--vault-password-file` rechazado ("Specify the vault-id to encrypt with --encrypt-vault-id") | `ansible.cfg` ya define `vault_password_file`; pasar además el flag crea dos vault-id `default` en conflicto | Detectado durante la elaboración de esta etapa (antes de tocar las VMs reales); corregido en `01-ansible-control-setup.sh` dejando que `ansible.cfg` (vía `ANSIBLE_CONFIG`) sea la ÚNICA fuente de `vault_password_file`, sin repetir el flag en la línea de comandos |
| Módulo propio `lab_uptime_pretty` fallaba con `The module interpreter '/usr/bin/env python3' was not found` | El shebang `#!/usr/bin/env python3` no es el que Ansible reconoce para sustituir el intérprete; solo reescribe `#!/usr/bin/python` | Detectado durante la elaboración (probado con `ansible localhost -m lab.utils.lab_uptime_pretty` antes de tocar las VMs); corregido cambiando el shebang del módulo a `#!/usr/bin/python` |

## Conocimientos adquiridos (resumen propio)
-

## Ampliaciones futuras (fuera del alcance actual de esta etapa)
- Un rol `lab_webapp` que despliegue una app de demostración con Apache httpd o NGINX (Etapa 9), reutilizando `group_vars`/`roles` de esta etapa.
- `ansible-lint` en un hook de pre-commit, si se instala en el equipo host.
- Un inventario dinámico DE VERDAD sobre las propias VMs del lab (no el de demo, que es deliberadamente ficticio), generado desde `results/facts/` o `virsh list`.
- Llevar el escenario de Molecule a integración continua (GitHub Actions) si el repositorio se sube a un remoto con CI.
