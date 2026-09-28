#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Filtro Jinja2 propio (Etapa 7, parte avanzada): 'to_lab_slug'.

Un filtro es la forma correcta de añadir una transformación de texto propia
reutilizable en cualquier plantilla/expresión Jinja2 del proyecto, en vez de
repetir la misma expresión 'regex_replace' larga en cada .j2 o cada 'vars:'.
"""

import re


def to_lab_slug(value):
    """Convierte un texto cualquiera en un 'slug' en minúsculas y con guiones.

    Ejemplos:
      "rhel9-app01"      -> "rhel9-app01"
      "DNS 01 (lab.local)" -> "dns-01-lab-local"
    """
    value = str(value).lower().strip()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-")


class FilterModule:
    """Punto de entrada que Ansible busca para registrar filtros de esta colección."""

    def filters(self):
        return {"to_lab_slug": to_lab_slug}
