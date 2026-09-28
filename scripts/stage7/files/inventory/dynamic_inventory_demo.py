#!/usr/bin/env python3
"""Inventario dinámico DE DEMOSTRACIÓN (Etapa 7, parte avanzada).

Qué es y qué NO es:
  - Es un ejemplo real y ejecutable de cómo se construye un script de
    inventario dinámico para Ansible (el contrato "--list"/"--host" que
    cualquier herramienta de inventario dinámico real -AWS, VMware, NetBox...-
    implementa). Aquí, en vez de una nube o un CMDB, la fuente de datos es
    JSONPlaceholder (https://jsonplaceholder.typicode.com/users), una API
    pública, gratuita y pensada precisamente para pruebas: no requiere clave
    ni autenticación, y no expone ningún dato sensible (son datos ficticios).
  - NO forma parte del inventario real del lab (inventory/hosts.ini, con las
    IPs reales de las VMs) y NUNCA intenta conectarse por SSH a nada: cada
    entrada usa 'ansible_connection=local', así que cualquier tarea que se le
    aplique se ejecuta en ansible01 usando solo los DATOS descargados de la
    API, jamás una conexión remota hacia esos "hosts" ficticios.
  - Objetivo puramente pedagógico: entender el MECANISMO de un inventario
    dinámico sin tocar infraestructura real ni necesitar credenciales.

Uso:
  ./dynamic_inventory_demo.py --list      # lo que Ansible invoca de verdad
  ./dynamic_inventory_demo.py --host <n>  # vars de un host suelto (aquí vacío;
                                           # ya se rellenan todas en --list,
                                           # como permite la especificación)

Requisitos: solo librería estándar de Python 3 (urllib) — sin 'requests', para
no depender de nada que no venga ya instalado en un RHEL mínimo con Python 3.
"""
import argparse
import json
import re
import sys
import urllib.request

API_URL = "https://jsonplaceholder.typicode.com/users"
TIMEOUT_SECONDS = 8


def slug(text):
    text = str(text).lower().strip()
    text = re.sub(r"[^a-z0-9]+", "-", text)
    return text.strip("-")


def fetch_users():
    """Descarga la lista de usuarios de demo. Nunca lanza: si falla, [] vacío
    (un inventario dinámico roto NO debe tumbar todo el playbook con una
    traza de Python; debe degradarse a "sin hosts" y avisar por stderr)."""
    try:
        with urllib.request.urlopen(API_URL, timeout=TIMEOUT_SECONDS) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception as exc:  # noqa: BLE001 (a propósito: cualquier fallo de red cuenta)
        print(f"[dynamic_inventory_demo] aviso: no se pudo consultar {API_URL}: {exc}",
              file=sys.stderr)
        return []


def build_inventory(users):
    inventory = {
        "_meta": {"hostvars": {}},
        "demo_api": {"hosts": []},
    }
    for u in users:
        host = f"demo-{u['id']}-{slug(u['username'])}"
        # Los nombres de GRUPO de Ansible no admiten guiones sin avisar
        # ("Invalid characters were found in group names"); los de HOST sí.
        company = slug(u.get("company", {}).get("name", "sin-empresa")).replace("-", "_")
        group = f"demo_api_empresa_{company}"

        inventory["demo_api"]["hosts"].append(host)
        inventory.setdefault(group, {"hosts": []})["hosts"].append(host)

        inventory["_meta"]["hostvars"][host] = {
            "ansible_connection": "local",  # NUNCA se intenta SSH a esto
            "api_id": u.get("id"),
            "api_name": u.get("name"),
            "api_username": u.get("username"),
            "api_email": u.get("email"),
            "api_city": u.get("address", {}).get("city"),
            "api_company": u.get("company", {}).get("name"),
        }
    return inventory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--list", action="store_true", help="Vuelca el inventario completo (JSON)")
    group.add_argument("--host", help="Vars de un host suelto (compatibilidad con la especificación)")
    args = parser.parse_args()

    users = fetch_users()

    if args.list:
        print(json.dumps(build_inventory(users), indent=2, ensure_ascii=False))
    else:
        # Ya se devuelven todas las vars en "_meta.hostvars" de --list, así que
        # Ansible ni siquiera debería llamar a "--host": se responde vacío.
        print(json.dumps({}))


if __name__ == "__main__":
    main()
