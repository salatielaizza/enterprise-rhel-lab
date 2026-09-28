# Colección `lab.utils`

Colección **local** (no publicada en Ansible Galaxy) con dos plugins mínimos,
pensados para entender la mecánica de escribir y referenciar una colección
propia por su FQCN (*Fully Qualified Collection Name*):

- **Módulo** `lab.utils.lab_uptime_pretty`: uptime en formato "Nd Nh Nm" + carga media.
- **Filtro** `lab.utils.to_lab_slug`: convierte un texto en un "slug" (minúsculas, guiones).

## Cómo se resuelve sin publicarla en Galaxy
`ansible.cfg` del lab define `collections_path = ./collections`, y esta
colección vive en `./collections/ansible_collections/lab/utils/` — exactamente
la ruta que exige el formato de colecciones de Ansible
(`ansible_collections/<namespace>/<name>/`). No hace falta `ansible-galaxy
collection install`: Ansible la encuentra sola por estar en `collections_path`.

## Probarla
```bash
ansible-doc lab.utils.lab_uptime_pretty     # documentación (DOCUMENTATION/EXAMPLES/RETURN)
ansible localhost -m lab.utils.lab_uptime_pretty
ansible localhost -m debug -a "msg={{ 'DNS 01 (lab.local)' | lab.utils.to_lab_slug }}"
```

Ver `playbooks/advanced.yml` para un uso real de ambos dentro de un playbook.
