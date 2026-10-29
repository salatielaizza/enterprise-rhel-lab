# Etapa N3 · Caso 06 — "La idempotencia no funciona": dos `--check` seguidos no prueban nada

**Objetivo**: distinguir la simulación (`--check --diff`, "qué haría") de la prueba de idempotencia (dos
ejecuciones **reales** seguidas, la segunda con `changed=0`).

**Preparación**: ejercicio P7 (2026-10-29): plantilla `templates/practica-info.j2` (facts, `if`, `for`, filtros
`default`, `upper`, `map`, `join`) desplegada con `p7-plantilla.yml` en `/etc/practica-info.txt` de los 5 hosts.

## Cómo provocarlo

Lanzar dos veces seguidas solo en modo simulación, sin ninguna ejecución real entre medias:

```bash
ansible-playbook p7-plantilla.yml --check --diff --ask-vault-pass
ansible-playbook p7-plantilla.yml --check --diff --ask-vault-pass
```

## Síntoma

Las dos ejecuciones dan `changed=1` en los 5 hosts y el mismo diff (salida real, un host):

```text
--- before
+++ after: /home/salatux/.ansible/tmp/ansible-local-.../practica-info.j2
@@ -0,0 +1,8 @@
+# Ansible managed
+Host:    rhel7-app01 (rhel7-app01.lab.local)
+Sistema: RedHat 7.9
+Paquetes: yum (legacy)
+Rol en el lab: LEGACY
+IPs:
+  - 10.10.10.11
+Usuarios de práctica: practica1, practica2

changed: [rhel7-app01]
```

## Hipótesis descartadas

- **La plantilla cambia en cada ejecución** (una fecha, como en [etapa7/02](../etapa7/02-plantilla-timestamp-rompe-idempotencia.md)):
  descartada, no hay ningún dato variable en la plantilla y los dos diffs son idénticos.

## Diagnóstico

La cabecera del diff `@@ -0,0 +1,8 @@` significa: "antes, **0 líneas**; después, 8". El fichero no existía en el
host en **ninguna** de las dos ejecuciones. `--check` no lo creó la primera vez, así que la segunda vuelve a
decir "lo crearía".

Antes ya había otra pista: `ansible all -m command -a 'cat /etc/practica-info.txt'` daba `No such file or
directory` en los 5 hosts.

## Causa raíz

Interpretación de la prueba, no un fallo de Ansible: `--check` simula y no modifica los hosts, de modo que nunca
puede mostrar `changed=0` para un fichero que todavía no existe.

## Solución aplicada

```bash
ansible-playbook p7-plantilla.yml --ask-vault-pass                  # 1ª real: changed=1 en los 5
ansible-playbook p7-plantilla.yml --ask-vault-pass                  # 2ª real: changed=0
ansible-playbook p7-plantilla.yml --check --diff --ask-vault-pass   # ahora: ok, sin diff
```

## Validación

- Segunda ejecución real con `changed=0` (P7 terminado el 2026-10-29).
- La plantilla es correcta según el propio diff: `yum (legacy)` solo en RHEL 7; `practica_rol` distinto por grupo
  (`LEGACY`, `APLICACIONES`, `DNS`); versiones reales 7.9, 8.6, 9.8 (`rhel9-app01` y `dns01`) y 10.2.

## Prevención

- Idempotencia = **dos ejecuciones reales**; `--check --diff` = revisar antes de aplicar.
- Leer la cabecera del diff: `-0,0` indica que el fichero no existe en el destino.
- `--limit all` no hace falta: sin `--limit` el play ya va contra sus `hosts:`.
