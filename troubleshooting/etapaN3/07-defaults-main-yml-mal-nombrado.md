# Etapa N3 · Caso 07 — `defaults/main-yml` (con guion): el rol pierde sus variables y `no_log` lo oculta

**Objetivo**: reconocer un fichero de rol mal nombrado. Ansible carga `defaults/main.yml` por su nombre exacto; con
otro nombre lo ignora sin avisar, y si la tarea afectada lleva `no_log: true`, el error tampoco se ve.

**Preparación**: ejercicio P10 (2026-10-29): rol `practica_final` (cronie + crond, usuario `operador` con contraseña
del vault, tarea `cron` y fichero de resumen) aplicado con `p10-final.yml` a `app:!legacy`.

## Cómo provocarlo

```bash
mv roles/practica_final/defaults/main.yml roles/practica_final/defaults/main-yml
```

## Síntoma

Salida real (`--check --diff --limit rhel9-app01`): las dos tareas del principio pasan y la del usuario falla oculta.

```text
TASK [practica_final : Cronie instalado (el módulo cron necesita el comando crontab)] ****
ok: [rhel9-app01]
TASK [practica_final : Crond arrancado y habilitado] ****
ok: [rhel9-app01]
TASK [practica_final : Usuario operador con contraseña del vault] ****
fatal: [rhel9-app01]: FAILED! => {"censored": "the output has been hidden due to the fact that 'no_log: true' was specified for this result"}
```

## Hipótesis descartadas

| Hipótesis | Evidencia | Resultado |
|---|---|---|
| El secreto no llega (como el caso 05) | `ansible rhel9-app01 -m debug -a 'msg="{{ practica_password \| length }}"'` → `"13"` | Descartada |
| Grupo inexistente | La tarea no usa `groups:` | Descartada |
| Sal no válida | `operadorsalt2026`: 16 caracteres, solo letras y números | Descartada |
| Conexión o `become` | Las dos tareas anteriores del rol salen `ok` | Descartada |

Dos comprobaciones intermedias no valieron y se repitieron: se escribieron literalmente los marcadores
`<variable>` y `<grupo>` de la guía, y en una de ellas se tecleó mal la contraseña de vault (`Decryption failed`).

## Diagnóstico

```bash
grep -rn -A12 'Usuario operador' roles/practica_final/tasks/      # usa practica_password y practica_final_usuario
grep -rn 'practica_final_usuario' roles/practica_final/ inventory/ p10-final.yml
#   roles/practica_final/defaults/main-yml:2:practica_final_usuario: operador     <- "main-yml"
cat roles/practica_final/defaults/main.yml
#   cat: roles/practica_final/defaults/main.yml: No such file or directory
```

## Causa raíz

El fichero de variables por defecto se llamaba `main-yml`. Ansible solo carga `defaults/main.yml` (o `main.yaml`,
o `main`), así que `practica_final_usuario` no estaba definida y la tarea `user` fallaba al construir `name:`.
`no_log: true` ocultó el `undefined variable`.

## Solución aplicada

```bash
mv roles/practica_final/defaults/main-yml roles/practica_final/defaults/main.yml
find roles/practica_final -type f | sort      # revisar que no haya más nombres incorrectos
```

## Validación

- `--check --diff --limit rhel9-app01`: la tarea del usuario pasa a `changed`.
- Ejecución real y segunda ejecución con `changed=0`: P10 terminado con éxito (2026-10-29).

## Prevención

- Los ficheros que Ansible carga solos se llaman `main.yml`; las plantillas (`templates/*.j2`) pueden tener
  cualquier nombre porque se citan desde la tarea.
- `scripts/stageN3/validar.sh` marca `FAIL` si `defaults/`, `tasks/` o `handlers/` contienen algo distinto de `main.yml`.
- Mismo método que el caso [05](05-vault-con-contenido-comentado.md); misma familia de causa que el caso
  [03](03-rol-ficheros-fuera-de-su-sitio.md).
