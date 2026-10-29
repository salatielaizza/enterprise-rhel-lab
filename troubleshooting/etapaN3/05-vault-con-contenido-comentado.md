# Etapa N3 · Caso 05 — `no_log` oculta el error: el `vault.yml` solo tenía comentarios (`#`)

**Objetivo**: diagnosticar una tarea con `no_log: true` que falla sin mostrar el motivo, **sin quitar la
protección y sin revelar el secreto**, comprobando por partes: variable → filtro → datos del vault.

**Preparación**: ejercicio P6 (2026-10-29). `inventory/group_vars/all/vault.yml` creado con
`ansible-vault create`, `vars.yml` con `practica_password: "{{ vault_practica_password }}"` y `p6-vault.yml`
fijando la contraseña de `practica1` con `password_hash('sha512', ...)` y `no_log: true`.

## Cómo provocarlo

Al crear el vault, copiar el ejemplo del manual **con** los `#` delante de cada línea:

```text
#   ---
#   vault_practica_password: "..."
```

## Síntoma

Salida real (dos ejecuciones iguales):

```text
TASK [Fijar la contraseña de practica1 (el valor viene cifrado del vault)] *****
fatal: [rhel7-app01]: FAILED! => {"censored": "the output has been hidden due to the fact that 'no_log: true' was specified for this result"}
fatal: [rhel8-app01]: FAILED! => {"censored": "..."}
fatal: [rhel9-app01]: FAILED! => {"censored": "..."}
fatal: [rhel10-app01]: FAILED! => {"censored": "..."}
```

## Hipótesis descartadas

- **Problema en los nodos**: improbable, falla igual en las cuatro versiones (RHEL 7 incluido); apunta al
  **controlador** (variables o filtro).
- **Sal no válida** en `password_hash`: descartada, `practicasalt2026` solo tiene letras y números (máximo 16).
- **Contraseña de vault incorrecta**: descartada, en ese caso el error sería `Decryption failed` y no llegaría a la tarea.

## Diagnóstico

```bash
# 1. ¿Llega la variable? (solo su longitud, nunca el valor)
ansible rhel9-app01 -m debug -a 'msg="{{ practica_password | length }}"' --ask-vault-pass
#   FAILED: "{{ vault_practica_password }}: 'vault_practica_password' is undefined"
#   -> vars.yml SÍ se carga (practica_password existe); falta la del vault

# 2. ¿Funciona el filtro? (texto de prueba)
ansible localhost -m debug -a "msg={{ 'prueba' | password_hash('sha512', 'salprueba') }}"
#   ERROR! Attempting to decrypt but no vault secrets found
#   -> hay un fichero cifrado en el inventario (también para localhost hace falta --ask-vault-pass)

# 3. ¿Qué variables contiene el vault? (solo los nombres)
ansible-vault view inventory/group_vars/all/vault.yml | cut -d: -f1
#   #   ---
#   #   vault_practica_password
```

## Causa raíz

El vault estaba cifrado y se descifraba bien, pero su contenido eran **comentarios**: YAML ignora todo lo que va
detrás de `#`, así que el fichero no definía ninguna variable. `no_log: true` hizo lo que debe: ocultar también el
mensaje de error (`undefined variable`).

## Solución aplicada

```bash
ansible-vault edit inventory/group_vars/all/vault.yml     # nunca vim directamente: el fichero está cifrado en disco
```

Contenido final, sin nada delante de cada línea:

```yaml
---
vault_practica_password: "<contraseña de práctica>"
```

## Validación

```bash
head -1 inventory/group_vars/all/vault.yml                 # $ANSIBLE_VAULT;1.1;AES256 (sigue cifrado)
ansible-vault view inventory/group_vars/all/vault.yml | cut -d: -f1   # ---  /  vault_practica_password
ansible rhel9-app01 -m debug -a 'msg="{{ practica_password | length }}"' --ask-vault-pass   # "msg": "13"
```

Después, `p6-vault.yml` dos veces: la segunda con `changed=0` (P6 terminado el 2026-10-29).

## Prevención

- No copiar bloques con los `#` de la documentación: `grep -n '^#  ' <fichero>` los encuentra.
- Método para tareas con `no_log`: comprobar por partes (longitud de la variable, filtro con un texto de prueba,
  nombres del vault con `cut -d: -f1`). Si aun así hace falta ver el error, quitar `no_log` **temporalmente**, con
  `--check --limit <un host>`; el parámetro `password` del módulo `user` ya se muestra como `NOT_LOGGING_PASSWORD`.
- Mismo síntoma, otra causa: caso [07](07-defaults-main-yml-mal-nombrado.md).
