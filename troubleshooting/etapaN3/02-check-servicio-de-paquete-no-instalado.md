# Etapa N3 · Caso 02 — `--check` falla en el servicio `atd`: el paquete solo se "instaló" en la simulación

**Objetivo**: entender los límites del modo `--check`. Una tarea que depende de un cambio que la tarea anterior
solo ha simulado puede fallar, aunque el playbook sea correcto.

**Preparación**: ejercicio P3 (`p3-servicio.yml`: paquete `at` + servicio `atd` + fichero + handler) sobre el
grupo `app`. Estado previo comprobado el 2026-10-28 con `ansible app -m command -a 'rpm -q at' -o`:
`package at is not installed` (`rc=1`) en las cuatro `app01`.

## Cómo provocarlo

En hosts sin `at`, lanzar la primera vez en modo simulación:

```bash
ansible-playbook p3-servicio.yml --check --diff
```

## Síntoma

Salida real (2026-10-28):

```text
TASK [Instalar el paquete at] **************************************************
changed: [rhel9-app01]
changed: [rhel7-app01]
changed: [rhel10-app01]
changed: [rhel8-app01]

TASK [Servicio atd arrancado y habilitado] *************************************
fatal: [rhel7-app01]: FAILED! => {"changed": false, "msg": "Could not find the requested service atd: host"}
fatal: [rhel8-app01]: FAILED! => {"changed": false, "msg": "Could not find the requested service atd: host"}
fatal: [rhel9-app01]: FAILED! => {"changed": false, "msg": "Could not find the requested service atd: host"}
fatal: [rhel10-app01]: FAILED! => {"changed": false, "msg": "Could not find the requested service atd: host"}
```

## Hipótesis descartadas

- **Nombre del servicio distinto según la versión**: descartada, falla igual en RHEL 7, 8, 9 y 10; el servicio de
  `at` se llama `atd` en las cuatro.
- **Error en el playbook**: descartada, `--syntax-check` correcto y el módulo `service` con `name`, `state` y
  `enabled` es válido.

## Diagnóstico

- En `--check`, `changed` significa "lo cambiaría": el paquete **no** se ha instalado.
- Comprobación en el host, sin cambiar nada: `ansible app -m command -a 'rpm -q at' -o` sigue diciendo
  `package at is not installed`, así que `atd.service` no existe todavía y `service` no lo encuentra.

## Causa raíz

Limitación documentada del modo check (documentación oficial, *"Validating tasks: check mode and diff mode"*):
cada tarea se simula por separado y las tareas que dependen del resultado real de otra pueden fallar.

## Solución aplicada

1. Ejecutar de verdad (el cambio es reversible: `limpieza.yml` quita `at`):
   `ansible-playbook p3-servicio.yml`.
2. Dejar el playbook preparado para futuras simulaciones, a nivel de **tarea** (no del módulo):

```yaml
    - name: Servicio atd arrancado y habilitado
      ansible.builtin.service:
        name: atd
        state: started
        enabled: true
      ignore_errors: "{{ ansible_check_mode }}"
```

`ansible_check_mode` vale `true` solo con `--check`: en la ejecución real el fallo sigue contando.

## Validación

- Ejecución real: `changed` en los 4 hosts y el handler `Reiniciar atd`.
- Segunda ejecución: `changed=0`.
- `--check --diff` posterior: ya no falla, porque el servicio existe.

## Prevención

- Pasar `--check` antes de cada cambio, pero leer su resultado sabiendo qué tareas dependen de otras.
- Patrón `ignore_errors: "{{ ansible_check_mode }}"` (o `when: not ansible_check_mode`) solo en las tareas que
  dependen de un cambio previo; nunca un `ignore_errors: true` general.
- Error relacionado del mismo ejercicio (detectado al revisar el fichero, antes de ejecutarlo): poner `content:`
  dentro de `ansible.builtin.service`. `service` no tiene ese parámetro; el contenido de un fichero va en `copy` o
  `template`. Comprobar los parámetros con `ansible-doc -s ansible.builtin.service`.
