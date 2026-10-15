# 05 — El módulo propio `lab.utils.lab_uptime_pretty` falla en RHEL 7 (`SyntaxError` con Python 2.7)

## Objetivo

Documentar un fallo real del módulo propio de la colección local `lab.utils`, detectado al ejecutar `playbooks/advanced.yml` contra las VMs (Fase 16 de la Etapa 7): el módulo usaba sintaxis exclusiva de Python 3 y **solo fallaba en `rhel7-app01`**, cuyo intérprete es Python 2.7.

## Preparación

- Lab con las 6 VMs encendidas y `ansible lab -m ping` en verde en los 5 nodos gestionados.
- Intérpretes detectados por Ansible (Fases 5 y 7):

  | Host | Intérprete | Versión (medida en el lab) |
  |---|---|---|
  | rhel7-app01 | `/usr/bin/python` | **2.7.5** (`ansible_python_version`, traceback) |
  | rhel8-app01 | `/usr/libexec/platform-python` | Python 3 |
  | rhel9-app01, dns01 | `/usr/bin/python3` | Python 3 (`python3.9` en el descubrimiento de `-vvv` de la Fase 14) |
  | rhel10-app01 | `/usr/bin/python3` | Python 3 |
  | ansible01 (control) | `/usr/bin/python3` | 3.9.25 (`ansible --version`) |

- Colección local en `~/ansible-lab/collections/ansible_collections/lab/utils/`, visible para Ansible gracias a `collections_path = ./collections` en `ansible.cfg` (`ansible-galaxy collection list` muestra `lab.utils 1.0.0`).

## Síntoma

```bash
ansible-playbook playbooks/advanced.yml --check
```

```
TASK [Usar el módulo propio de la colección lab.utils (solo lectura)]
An exception occurred during task execution. To see the full traceback, use -vvv. The error was: SyntaxError: invalid syntax
fatal: [rhel7-app01]: FAILED! => {"changed": false, "module_stderr": "Shared connection to 10.10.10.11 closed.\r\n",
  "module_stdout": "Traceback (most recent call last):
    ...
    File \"/usr/lib64/python2.7/runpy.py\", line 113, in _get_module_details
      code = loader.get_code(mod_name)
    File \".../ansible_collections/lab/utils/plugins/modules/lab_uptime_pretty.py\", line 78
      return f\"{days}d {hours}h {minutes}m\"
                                          ^
  SyntaxError: invalid syntax", "msg": "MODULE FAILURE\nSee stdout/stderr for the exact error", "rc": 1}
ok: [rhel8-app01]
...
PLAY RECAP
rhel7-app01                : ok=3    changed=1    unreachable=0    failed=1    skipped=1    rescued=0    ignored=0
rhel8-app01 / rhel9-app01 / rhel10-app01 / dns01 : ok=6  changed=1  failed=0
```

Los otros 4 hosts ejecutaron el módulo y el filtro sin problemas.

## Hipótesis descartadas

| Hipótesis | Por qué se descartó |
|---|---|
| Ansible no encuentra la colección `lab.utils` | El traceback sale **del propio fichero del módulo** (`lab_uptime_pretty.py`, línea 78): Ansible lo encontró, lo empaquetó y lo envió. Además, funcionó en 4 de los 5 hosts |
| Problema de conectividad o de `become` con rhel7-app01 | `Gathering Facts` y las tareas anteriores del play salieron `ok` en rhel7-app01; el fallo es `MODULE FAILURE`, no `UNREACHABLE` |
| Error del shebang (el caso del "Errores comunes" de `automation/ansible.md`) | El shebang ya era `#!/usr/bin/python`, el correcto, y Ansible lo sustituyó por el intérprete detectado: el traceback muestra `/usr/lib64/python2.7/runpy.py` |
| El filtro `to_lab_slug` también falla en RHEL 7 | Los filtros se ejecutan en el **nodo de control** (Python 3.9 de `ansible01`), no en el nodo gestionado; no dependen del Python de rhel7 |

## Diagnóstico

1. **Qué Python ejecuta el módulo en rhel7-app01.** El traceback lo dice (`/usr/lib64/python2.7/runpy.py`) y se confirma con:

   ```bash
   ansible rhel7-app01 -m setup -a "filter=ansible_python_version"
   ```
   → `2.7.5`.

2. **Dónde falla y por qué.** El error es en la **compilación**, antes de ejecutar nada: `loader.get_code()` → `SyntaxError` en la línea 78. El código usaba dos construcciones que no existen en Python 2:
   - **f-strings** (`f"{days}d {hours}h {minutes}m"` y `f"No se pudo leer…: {exc}"`), que llegaron con Python 3.6.
   - **`open(..., encoding="utf-8")`**: el `open()` de Python 2 no tiene ese parámetro (habría fallado después, al ejecutar).

3. **Por qué no se detectó al escribir la colección.** Se probó con `ansible localhost -m lab.utils.lab_uptime_pretty`, es decir, con el Python 3.9 del nodo de control (ver la fila del shebang en `checklists/etapa7.md`). La prueba era correcta para el shebang, pero no representaba al nodo más antiguo del lab.

4. **Concepto clave — dónde se ejecuta cada plugin:**

   | | Módulo (`plugins/modules/`) | Filtro (`plugins/filter/`) |
   |---|---|---|
   | Dónde se ejecuta | En cada **nodo gestionado**, con su Python | En el **nodo de control** |
   | Cómo llega | Empaquetado (AnsiballZ), copiado por sftp y ejecutado (ver `-vvv` en la Fase 14) | Ansible lo importa localmente al evaluar Jinja2 |
   | Debe soportar | El Python **más antiguo** de los nodos gestionados | Solo el Python del nodo de control |

5. **Por qué el `rescue` del playbook no lo capturó.** La tarea del módulo está **fuera** del `block`; `rescue` solo captura los fallos de su propio `block`. Por eso el resultado fue `failed=1` y no `rescued=1`. Con `serial: 2`, el fallo de 1 de los 2 hosts del primer lote no detuvo los lotes siguientes (sin `max_fail_percentage`, Ansible solo se detiene si falla el lote entero).

## Causa raíz

Un **módulo** de Ansible se ejecuta con el Python del nodo gestionado. El módulo `lab_uptime_pretty` se escribió con sintaxis exclusiva de Python 3 (f-strings y `open(..., encoding=...)`), y el lab gestiona un RHEL 7 cuyo único intérprete es **Python 2.7.5**. ansible-core 2.14 todavía admite Python 2.7 en los nodos gestionados, así que el problema no es de Ansible sino del código del módulo.

## Solución aplicada

Reescribir el módulo para que sea compatible con Python 2.7 y 3, en el repo (`scripts/stage7/files/collections/ansible_collections/lab/utils/plugins/modules/lab_uptime_pretty.py`), y llevarlo a `ansible01` con `scripts/lab.sh stage7-setup`:

| Antes (solo Python 3) | Después (Python 2.7 y 3) |
|---|---|
| `return f"{days}d {hours}h {minutes}m"` | `return "%dd %dh %dm" % (days, hours, minutes)` |
| `msg=f"No se pudo leer …: {exc}"` | `msg="No se pudo leer …: %s" % exc` |
| `open("/proc/uptime", "r", encoding="utf-8")` | `open("/proc/uptime", "r")` (ficheros ASCII de `/proc`) |
| `except OSError as exc:` | `except (IOError, OSError) as exc:` (en Python 2 `open()` lanza `IOError`) |
| — | Cabecera estándar de los módulos de Ansible: `from __future__ import absolute_import, division, print_function` y `__metaclass__ = type` |

Antes de entregarlo se comprobó la versión mínima de Python con `vermin`: **2.6 / 3.0** (antes, las f-strings exigían 3.6).

## Validación

Prueba directa del módulo en el nodo afectado:

```bash
ansible rhel7-app01 -m lab.utils.lab_uptime_pretty
```
```
rhel7-app01 | SUCCESS => {
    "ansible_facts": {"discovered_interpreter_python": "/usr/bin/python"},
    "changed": false,
    "load1": 0.0, "load15": 0.05, "load5": 0.01,
    "pretty": "0d 3h 35m",
    "seconds": 12936.52
}
```

Simulación completa del playbook:

```bash
ansible-playbook playbooks/advanced.yml --check | tail -8
```
```
rhel7-app01   : ok=6  changed=1  unreachable=0  failed=0  skipped=1  rescued=0  ignored=0
(los otros 4 hosts, igual)
```

`rhel7-app01` pasa de `ok=3 failed=1` a `ok=6 failed=0`. El `changed=1` es la tarea de `always`, que añade una línea al log en cada ejecución (intencionado).

## Prevención

- **Probar los módulos propios contra el nodo más antiguo del inventario**, no solo con `ansible localhost`: `ansible rhel7-app01 -m <módulo>`.
- **Comprobar la sintaxis con el Python del nodo antiguo** sin necesidad de Ansible:
  `scp -O modulo.py adminlab@rhel7-app01:/tmp/ && ssh adminlab@rhel7-app01 'python -m py_compile /tmp/modulo.py'`.
- **Analizar la versión mínima de Python** que exige el código con `vermin` (o `ansible-test sanity --python 2.7` si la colección se publica).
- **Escribir los módulos en el subconjunto común de Python 2.7 y 3** mientras se gestionen nodos RHEL 7: sin f-strings, sin `encoding=` en `open()`, capturando `(IOError, OSError)` y con la cabecera `__future__` / `__metaclass__`.
- Para que un fallo así no deje a medias un despliegue por lotes, valorar `max_fail_percentage` en los plays con `serial`, o meter las tareas críticas dentro de un `block` con su `rescue`.
- Relacionados: la fila del shebang `#!/usr/bin/env python3` en `checklists/etapa7.md` (el mismo módulo, probado solo en el nodo de control) y la diferencia Python 2/3 entre RHEL 7 y RHEL 8/9/10 en `automation/ansible.md`.
