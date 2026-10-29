# Etapa N3 · Caso 04 — `mapping values are not allowed in this context`: `hosts:` con más sangría que `name:`

**Objetivo**: leer un error de carga de YAML y entender la regla de la indentación: las claves de un mismo nivel
empiezan en la misma columna.

**Preparación**: ejercicio P6 (2026-10-29), primer intento de `p6-vault.yml`.

## Cómo provocarlo

Escribir las claves del play con distinta sangría:

```yaml
    - name: P6 - contraseña de usuario desde Ansible Vault
        hosts: app
```

## Síntoma

Salida real (ruta del proyecto recortada):

```text
ERROR! We were unable to read either as JSON nor YAML, these are the errors we got from each:
JSON: Expecting value: line 1 column 1 (char 0)

Syntax Error while loading YAML.
  mapping values are not allowed in this context

The error appears to be in '.../practica/p6-vault.yml': line 14, column 14, but may
be elsewhere in the file depending on the exact syntax problem.

The offending line appears to be:

    - name: P6 - contraseña de usuario desde Ansible Vault
        hosts: app
             ^ here
```

## Hipótesis descartadas

- **Problema con el vault o su contraseña**: descartada, el error es de carga del fichero (`Syntax Error while
  loading YAML`): Ansible no llegó a descifrar nada ni a conectar con los hosts.

## Diagnóstico

- El `^` señala los `:` de `hosts:`. YAML interpreta que `hosts: app` está **dentro** del valor de `name`
  (un texto), y un texto no puede contener claves: de ahí *mapping values are not allowed*.
- `line 14` en un playbook de un solo play indica que había 13 líneas antes del play: `cat -n p6-vault.yml | head -20`.

## Causa raíz

Indentación: `name`, `hosts`, `become` y `tasks` son claves hermanas del mismo play y deben empezar en la misma
columna; además, el `- name:` del play estaba desplazado cuatro espacios.

## Solución aplicada

Reescribir el play con la estructura de referencia (como en el manual de la práctica):

```yaml
---
- name: P6 - contraseña de usuario desde Ansible Vault
  hosts: app
  become: true
  tasks:
    - name: ...
```

## Validación

`ansible-playbook p6-vault.yml --syntax-check --ask-vault-pass` → `playbook: p6-vault.yml`. El siguiente error
ya fue de otro tipo (caso [05](05-vault-con-contenido-comentado.md)).

## Prevención

- Regla de lectura: misma columna = mismo nivel; dos espacios más = "dentro de". YAML no admite tabuladores
  (`cat -A` los muestra como `^I`).
- `--syntax-check` antes de ejecutar y `yamllint` si está instalado (`scripts/stageN3/validar.sh` los pasa al
  proyecto de referencia).
- `ignore_errors`, `no_log`, `notify`, `when`… son *keywords* de **tarea**: van alineadas con el nombre del módulo,
  no dentro de él.
