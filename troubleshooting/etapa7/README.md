# Troubleshooting — Etapa 7 (automatización con Ansible)

Ver formato y regla general en [`troubleshooting/README.md`](../README.md).

| Caso | Tema |
|---|---|
| [01 rhel7-timedatectl-p-no-soportado](01-rhel7-timedatectl-p-no-soportado.md) | `timedatectl show -p Timezone --value` falla en RHEL 7 (`systemd` demasiado antiguo) |
| [02 plantilla-timestamp-rompe-idempotencia](02-plantilla-timestamp-rompe-idempotencia.md) | Un timestamp dentro de una plantilla comparada rompe la idempotencia |
| [03 group-vars-ubicacion-incorrecta](03-group-vars-ubicacion-incorrecta.md) | `group_vars/` en la raíz del proyecto: invisible para `ansible-playbook`, visible por casualidad en ad-hoc |
