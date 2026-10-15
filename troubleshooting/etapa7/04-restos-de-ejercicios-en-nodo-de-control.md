# 04 — Restos de ejercicios en el nodo de control sobreviven a `stage7-setup`

## Objetivo

Documentar una deriva de configuración detectada durante la Fase 14 de la Etapa 7. Su causa no estaba en los nodos gestionados, sino en **ficheros de variables sobrantes en el nodo de control** (`ansible01`) que no existen en el repositorio y que `lab.sh stage7-setup` no elimina.

## Preparación

- Lab con las 6 VMs encendidas y `ansible lab -m ping` en verde en los 5 nodos gestionados.
- Repositorio limpio (`git status -s` vacío). Rol `common` con etiquetas (commit `f195bcf`).
- Antecedente: en la Fase 13 (precedencia de variables, 2026-10-04) se crearon en `ansible01` dos ficheros de prueba:
  - `~/ansible-lab/inventory/host_vars/rhel8-app01.yml` → `lab_timezone: "Atlantic/Canary"`
  - `~/ansible-lab/inventory/group_vars/dns/vars.yml` → `lab_timezone: "Europe/London"`

  El paso 5 de esa fase los borró y comprobó que los 5 hosts volvían a `Europe/Madrid`.

## Síntoma

El 2026-10-15, tras `scripts/lab.sh stage7-setup`, una simulación sin cambios esperados mostró cambios en dos hosts:

```bash
ansible-playbook playbooks/site.yml --check --skip-tags usuarios
```

```
TASK [common : Fijar huso horario del lab (Europe/Madrid)]
skipping: [rhel7-app01] ... skipping: [rhel8-app01] ... skipping: [dns01]

TASK [common : Desplegar marcador de gestión por Ansible ...]
changed: [rhel8-app01]
changed: [dns01]

RUNNING HANDLER [common : registrar cambio de configuracion gestionada por ansible]
changed: [rhel8-app01]
changed: [dns01]
```

En la Fase 11 (2026-10-04) los 5 hosts daban `changed=0` en 4 ejecuciones seguidas.

## Hipótesis descartadas

| Hipótesis | Por qué se descartó |
|---|---|
| Los nodos se actualizaron (cambio de `distribution_version` en el template) | El `--diff` mostró que las líneas `distro:` no cambiaban (`RedHat 8.6`, `RedHat 9.8`) |
| Alguien editó `/etc/ansible-lab-managed.txt` a mano en los nodos | El contenido `before` era el correcto (`Europe/Madrid`): lo que cambiaba era el valor **objetivo** |
| Los ficheros de prueba se colaron en el repo (por ejemplo en los commits de la Etapa 8) | `find scripts/stage7/files/inventory -type f` solo muestra `hosts.ini`, `group_vars/all/vars.yml` y `dynamic_inventory_demo.py`; `git status -s` vacío |
| La tarea "Fijar huso" no se iba a ejecutar porque salía `skipping` | Ver Diagnóstico: en `--check` el `skipping` ocultaba un *"Command would have run"* |

## Diagnóstico

1. **Ver qué cambiaría exactamente**, usando las etiquetas para limitar a la tarea y a los hosts afectados:

   ```bash
   ansible-playbook playbooks/site.yml --check --diff --tags marcador --limit rhel8-app01,dns01
   ```
   ```
   -huso_horario_objetivo: Europe/Madrid
   +huso_horario_objetivo: Atlantic/Canary      (rhel8-app01)
   -huso_horario_objetivo: Europe/Madrid
   +huso_horario_objetivo: Europe/London        (dns01)
   ```
   Eran exactamente los valores de prueba de la Fase 13.

2. **Comparar el repo con el nodo de control:**

   ```bash
   find scripts/stage7/files/inventory -type f | sort                       # en el host: no están
   ssh adminlab@ansible01 'cd ~/ansible-lab && find inventory -type f | sort \
     && ls -la --time-style=long-iso inventory/host_vars inventory/group_vars/dns'
   ```
   ```
   inventory/group_vars/dns/vars.yml        2026-10-04 20:11
   inventory/host_vars/rhel8-app01.yml      2026-10-04 20:11
   ```
   Fecha de creación posterior a la limpieza del paso 5 de la Fase 13 (≈19:40): los ficheros se **volvieron a crear** al repasar a mano los pasos 1 y 2 de esa fase, sin repetir la limpieza.

3. **Valor efectivo por host:**

   ```bash
   ansible lab -m debug -a "var=lab_timezone" -o
   ```
   ```
   rhel8-app01 | ... "lab_timezone": "Atlantic/Canary"
   dns01       | ... "lab_timezone": "Europe/London"
   (resto)     | ... "lab_timezone": "Europe/Madrid"
   ```

4. **Dos engaños de la salida de Ansible que retrasaron el diagnóstico:**
   - **`skipping` en `--check` no siempre significa "no hace falta".** Sin `-v`, *"Conditional result was False"* (no hace falta) y *"Command would have run if not in check mode"* (sí haría falta, pero `command` no se ejecuta en simulación) se muestran igual. En rhel8-app01 y dns01 era el segundo caso: **aplicado de verdad, el playbook habría cambiado su huso horario a Canarias y Londres.**
   - **El nombre de la tarea se renderiza una sola vez, con las variables del primer host.** "Fijar huso horario del lab (Europe/Madrid)" mostraba el valor de rhel7-app01, no el de cada host.

## Causa raíz

`scripts/stage7/01-ansible-control-setup.sh` (lanzado por `lab.sh stage7-setup`) copia el proyecto a `~adminlab/ansible-lab` con `cp -a`. **`cp -a` añade y sobrescribe, pero nunca borra** lo que sobra en el destino. Cualquier fichero creado a mano en el nodo de control que no esté en el repo **sobrevive a cada `stage7-setup`** y sigue participando en la precedencia de variables.

Es el problema simétrico al de los casos `01` y `02`: entonces se **perdía** en `ansible01` un arreglo que no estaba en el repo; ahora **sobrevive** en `ansible01` un fichero que no está en el repo. En ambos casos el nodo de control deja de ser un reflejo fiel de git.

## Solución aplicada

**Inmediata (2026-10-15):** borrar los restos solo en el nodo de control. No se tocó ningún nodo gestionado, porque todo el diagnóstico se hizo con `--check`.

```bash
ssh adminlab@ansible01 'cd ~/ansible-lab && rm -v inventory/host_vars/rhel8-app01.yml inventory/group_vars/dns/vars.yml \
  && rmdir -v inventory/host_vars inventory/group_vars/dns'
```

**Definitiva (pendiente, Fase 18):** que `01-ansible-control-setup.sh` deje `~/ansible-lab` como **espejo exacto** del repo (por ejemplo `rsync -a --delete`), **excluyendo** `inventory/group_vars/all/vault.yml`, que se genera y cifra en `ansible01` y no está en el repo.

## Validación

```bash
ansible lab -m debug -a "var=lab_timezone" -o
```
```
Europe/Madrid en los 5 hosts
```

```bash
ansible-playbook playbooks/site.yml --check --diff -v --tags huso,marcador \
  | grep -E 'skip_reason|would have run|changed:|PLAY RECAP|ok='
```
```
skipping: [...] => {"changed": false, "skip_reason": "Conditional result was False"}   (x5)
dns01 / rhel7-app01 / rhel8-app01 / rhel9-app01 / rhel10-app01 : ok=3  changed=0  failed=0  skipped=1
```

Ningún *"would have run"* oculto y `changed=0` en los 5 hosts.

## Prevención

- **Practicar fuera del proyecto:** los ejercicios que crean ficheros (variables, vault de prueba…) se hacen en una carpeta aparte (`~/vault-demo`, `/tmp/...`) o se limpian en el mismo bloque de comandos que los crea.
- **Simular siempre con `-v` cuando haya tareas `command`/`shell`**, para distinguir *"Conditional result was False"* de *"Command would have run"*.
- **Antes de aplicar, comparar el nodo de control con el repo**, o mejor, hacer que `stage7-setup` sincronice con `--delete` (solución definitiva).
- **No fiarse del nombre de una tarea** para conocer el valor de una variable por host: usar `ansible <hosts> -m debug -a var=<variable> -o`.
- Relacionados: `etapa7/01` y `etapa7/02` (arreglos hechos solo en el nodo de control que se perdieron), `etapa7/03` (ubicación de `group_vars`).
