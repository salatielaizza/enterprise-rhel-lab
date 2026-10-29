# Etapa N3 · Caso 01 — `setup` con `filter=` mal escrito devuelve vacío y no da error

**Objetivo**: entender que el filtro del módulo `setup` es un patrón de nombre: si no coincide con ningún *fact*,
Ansible responde `SUCCESS` sin datos, en lugar de un error. Un fallo silencioso que hay que saber reconocer.

**Preparación**: proyecto de la práctica (`practica-ansible`) con el inventario de P1; los 5 hosts encendidos.
Ejercicio P2.5: "la distribución y versión de cada host, usando solo *facts* filtrados" (2026-10-28).

## Cómo provocarlo

```bash
ansible all -m setup -a 'filter=ansible_distribuition*'     # "distribuition", con una i de más
```

## Síntoma

Los 5 hosts responden `SUCCESS` y `"changed": false`, pero sin ningún *fact* de distribución. Lo único que aparece
es el intérprete de Python detectado (salida real, recortada):

```text
rhel7-app01 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false
}
rhel8-app01 | SUCCESS => { "ansible_facts": { "discovered_interpreter_python": "/usr/libexec/platform-python" }, ... }
rhel9-app01 | SUCCESS => { "ansible_facts": { "discovered_interpreter_python": "/usr/bin/python3" }, ... }
```

## Hipótesis descartadas

- **Problema de conexión o de privilegios**: descartada, los 5 hosts responden `SUCCESS`; `setup` no necesita `sudo`.
- **El filtro no admite comodines**: descartada en `ansible-doc ansible.builtin.setup` (opción `filter`, admite
  patrones tipo shell).

## Diagnóstico

Releer el comando letra a letra frente a un nombre real de *fact*. Listar los nombres disponibles sin filtro:

```bash
ansible rhel9-app01 -m setup | grep -o '"ansible_distribution[a-z_]*"' | sort -u
```

## Causa raíz

Errata en el patrón (`distribuition`). `setup` aplica el filtro a los nombres de primer nivel; si ninguno
coincide, devuelve una lista vacía de *facts* y lo considera un éxito. El `discovered_interpreter_python` que sí
aparece no viene del filtro: Ansible lo añade la primera vez que detecta el intérprete (`interpreter_python =
auto_silent`).

## Solución aplicada

```bash
ansible all -m setup -a 'filter=ansible_distribution*'
```

## Validación

Cada host devuelve `ansible_distribution` (`RedHat`), `ansible_distribution_version`,
`ansible_distribution_major_version` y los `ansible_distribution_file_*`.

## Prevención

- Si un filtro devuelve vacío, sospechar primero del nombre, no del host.
- Usar el mismo dato que se va a escribir en un playbook (`ansible_facts['distribution']`): un nombre mal escrito
  en un playbook sí da error (`undefined variable`), justo al revés que aquí.
- Mismo patrón que el `PUKEY`/`$PUBKEY` de la Etapa 7 (Fase 4): un nombre mal escrito que no produce ningún error.

**Dato útil obtenido de paso** (diferencia entre versiones, real): intérprete detectado por Ansible — RHEL 7.9
`/usr/bin/python` (Python 2), RHEL 8 `/usr/libexec/platform-python`, RHEL 9 y 10 (y `dns01`) `/usr/bin/python3`.
