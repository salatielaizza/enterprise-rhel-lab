# Etapa N3 · Caso 03 — El rol "no hace nada": esqueleto de `role init` sin rellenar y ficheros fuera del rol

**Objetivo**: saber dónde busca Ansible cada pieza de un rol y reconocer el síntoma de un rol vacío o con ficheros
en la ruta equivocada: Ansible no avisa, simplemente no los carga.

**Preparación**: ejercicio P5 (2026-10-28). `ansible-galaxy role init roles/practica_base`, un playbook
`p5-rol.yml` que aplica el rol a `all` con la etiqueta `base`, y ediciones a mano de `defaults/`, `tasks/`,
`templates/` y `handlers/`.

## Cómo provocarlo

Crear el rol con `role init` y editar con una ruta incompleta, por ejemplo `vim roles/tasks/main.yml` en lugar
de `vim roles/practica_base/tasks/main.yml` (el editor crea la carpeta y el fichero donde se le indica).

## Síntoma

Apareció en tres momentos, cada uno con su mensaje real:

1. **Variables del rol vacías.** Comprobación de `defaults/` con Python:

   ```text
   $ python3 -c "import yaml; print(yaml.safe_load(open('roles/practica_base/defaults/main.yml')))"
   None
   ```

2. **El playbook no ejecuta ninguna tarea del rol** y el handler no escribe su log:

   ```text
   PLAY [P5 - aplicar mi propio rol] ****
   TASK [Gathering Facts] ****
   ok: [rhel7-app01] ... ok: [rhel10-app01]
   PLAY RECAP ****
   dns01        : ok=1    changed=0    unreachable=0    failed=0 ...

   $ ansible all -a 'tail -1 /var/log/practica.log' -o
   rhel7-app01 | FAILED! => {... "stderr": "tail: cannot open '/var/log/practica.log' for reading: No such file or directory" ...}
   ```

3. **Con la tarea ya en su sitio, el handler no existe:**

   ```text
   TASK [practica_base : Desplegar el fichero del rol] ****
   ERROR! The requested handler 'Registrar cambio del rol' was not found in either the main handlers list nor in the listening handlers list
   ```

## Hipótesis descartadas

- **El handler no se dispara porque la tarea sale `ok`**: descartada, el `PLAY RECAP` muestra `ok=1` (solo
  *Gathering Facts*): no se ejecutó ninguna tarea del rol.
- **Error de sintaxis YAML**: descartada, el playbook arranca y no hay error de carga.
- **`/etc/practica-role.txt` ya existía**: descartada, `file state=absent` devolvió `changed: false` en los 5 hosts:
  nunca se había creado.

## Diagnóstico

```bash
grep -n notify roles/practica_base/tasks/main.yml        # sin salida (código 1): no había ningún notify
cat roles/practica_base/handlers/main.yml                 # solo "---" y el comentario de role init
cat -A roles/practica_base/handlers/main.yml              # confirma: dos líneas, sin "- name:"
grep -rn 'Registrar cambio' roles/                        # el notify aparece DOS veces...
#   roles/practica_base/tasks/main.yml:9:  notify: Registrar cambio del rol
#   roles/tasks/main.yml:9:  notify: Registrar cambio del rol          <- fuera del rol
tree                                                      # además: roles/defaults/main.yml, también fuera del rol
```

## Causa raíz

`ansible-galaxy role init` solo crea **esqueletos** (`---` y un comentario). Las ediciones acabaron en
`roles/tasks/` y `roles/defaults/`, que no pertenecen a ningún rol, y `handlers/main.yml` se quedó sin contenido.
Ansible carga únicamente `roles/<rol>/{defaults,tasks,handlers,vars,meta}/main.yml` y no da ningún aviso por un
`main.yml` vacío ni por carpetas sueltas.

## Solución aplicada

1. Escribir el contenido en `roles/practica_base/defaults/main.yml`, `tasks/main.yml`, `templates/practica-role.j2`
   y `handlers/main.yml`, con el `name:` del handler idéntico al `notify:`.
2. Comparar los sobrantes con `diff` y apartarlos (moverlos, no borrarlos):
   `mkdir -p ~/practica-sobrantes && mv roles/tasks ~/practica-sobrantes/`.
3. Forzar un cambio para probar el handler: `ansible all -b -m file -a 'path=/etc/practica-role.txt state=absent'`.

## Validación

- `--list-tasks` muestra `practica_base : Desplegar el fichero del rol`.
- Ejecución real: `changed` en los 5 hosts y `RUNNING HANDLER [practica_base : Registrar cambio del rol]`.
- `ansible all -a 'tail -1 /var/log/practica.log' -o`: una línea con fecha por host.
- `dns01` muestra el mensaje de `group_vars/servicios.yml` y el resto el de `defaults/`.
- Segunda ejecución: `changed=0` y sin handler (confirmado por el usuario el 2026-10-28).

## Prevención

- Cuando un rol "no hace nada", mirar primero **dónde están los ficheros** (`tree`, `grep -rn`), antes que la sintaxis.
- `--list-tasks` justo después de escribir las tareas: si no aparecen con el prefijo del rol, no se están cargando.
- `scripts/stageN3/validar.sh` comprueba que no haya carpetas de rol sueltas dentro de `roles/` y que
  `defaults/`, `tasks/` y `handlers/` solo contengan `main.yml`.
- Mismo tipo de causa que el caso [07](07-defaults-main-yml-mal-nombrado.md) y que
  [etapa7/03](../etapa7/03-group-vars-ubicacion-incorrecta.md): un fichero donde Ansible no lo busca.
