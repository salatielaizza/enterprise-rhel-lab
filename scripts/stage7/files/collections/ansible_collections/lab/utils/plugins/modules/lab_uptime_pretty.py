#!/usr/bin/python
# -*- coding: utf-8 -*-
"""Módulo Ansible propio (Etapa 7, parte avanzada): uptime en formato legible.

Es deliberadamente pequeño: el objetivo pedagógico es ver el esqueleto MÍNIMO
de un módulo Ansible de verdad (AnsibleModule, DOCUMENTATION/EXAMPLES/RETURN,
supports_check_mode, exit_json/fail_json) — no sustituir 'ansible.builtin.setup'
(los facts ya traen uptime en segundos; aquí se practica ESCRIBIR el módulo).

COMPATIBILIDAD PYTHON 2.7 / 3 (ver troubleshooting/etapa7/05):
un módulo se ejecuta en el NODO GESTIONADO, con el Python de ese nodo, no con
el del nodo de control. rhel7-app01 usa Python 2.7.5, así que aquí NO se usan
f-strings ni open(..., encoding=...), y se incluye la cabecera estándar de los
módulos de Ansible (__future__ + __metaclass__) para que el mismo fichero
funcione igual en RHEL 7 (Python 2.7) y en RHEL 8/9/10 (Python 3).
"""

from __future__ import absolute_import, division, print_function
__metaclass__ = type

from ansible.module_utils.basic import AnsibleModule

DOCUMENTATION = r"""
---
module: lab_uptime_pretty
short_description: Devuelve el uptime del host en formato "Nd Nh Nm" y la carga media
description:
  - Lee C(/proc/uptime) y C(/proc/loadavg) y devuelve el tiempo de actividad
    en un formato legible para humanos, junto con la carga media a 1/5/15 min.
  - Módulo de solo lectura, nunca cambia el estado del sistema (C(changed=false)
    siempre) y soporta C(--check) sin ninguna salvedad.
  - Compatible con Python 2.7 (RHEL 7) y Python 3 (RHEL 8/9/10).
author:
  - enterprise-rhel-lab
options: {}
"""

EXAMPLES = r"""
- name: Leer el uptime en formato legible
  lab.utils.lab_uptime_pretty:
  register: lab_uptime

- name: Mostrarlo
  ansible.builtin.debug:
    msg: "{{ inventory_hostname }} lleva encendida {{ lab_uptime.pretty }} (carga: {{ lab_uptime.load1 }})"
"""

RETURN = r"""
pretty:
  description: Uptime en formato "Nd Nh Nm".
  type: str
  returned: always
  sample: "3d 4h 12m"
seconds:
  description: Uptime en segundos, sin redondear.
  type: float
  returned: always
load1:
  description: Carga media del último minuto.
  type: float
  returned: always
load5:
  description: Carga media de los últimos 5 minutos.
  type: float
  returned: always
load15:
  description: Carga media de los últimos 15 minutos.
  type: float
  returned: always
"""


def read_uptime_seconds():
    # /proc/uptime es ASCII: open() sin 'encoding' (parámetro que no existe
    # en el open() de Python 2).
    with open("/proc/uptime", "r") as f:
        return float(f.read().split()[0])


def read_loadavg():
    with open("/proc/loadavg", "r") as f:
        parts = f.read().split()
    return float(parts[0]), float(parts[1]), float(parts[2])


def pretty_uptime(total_seconds):
    total = int(total_seconds)
    days, rem = divmod(total, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, _ = divmod(rem, 60)
    # Formato con '%' en vez de f-string: válido en Python 2.7 y 3.
    return "%dd %dh %dm" % (days, hours, minutes)


def main():
    # Sin 'argument_spec' porque el módulo no toma parámetros: es intencional,
    # para mantener el ejemplo lo más simple posible.
    module = AnsibleModule(argument_spec={}, supports_check_mode=True)

    try:
        seconds = read_uptime_seconds()
        load1, load5, load15 = read_loadavg()
    except (IOError, OSError) as exc:
        # En Python 2, un fallo de open() lanza IOError (en Python 3 es un alias de OSError).
        module.fail_json(msg="No se pudo leer /proc/uptime o /proc/loadavg: %s" % exc)
        return  # inalcanzable, pero deja claro el flujo para quien lo lea

    module.exit_json(
        changed=False,  # módulo de solo lectura: NUNCA cambia nada
        pretty=pretty_uptime(seconds),
        seconds=seconds,
        load1=load1,
        load5=load5,
        load15=load15,
    )


if __name__ == "__main__":
    main()
