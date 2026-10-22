# Troubleshooting — Etapa 7 (automatización con Ansible)

Ver formato y regla general en [`troubleshooting/README.md`](../README.md).

| Caso | Tema |
|---|---|
| [01 rhel7-timedatectl-p-no-soportado](01-rhel7-timedatectl-p-no-soportado.md) | `timedatectl show -p Timezone --value` falla en RHEL 7 (`systemd` demasiado antiguo) |
| [02 plantilla-timestamp-rompe-idempotencia](02-plantilla-timestamp-rompe-idempotencia.md) | Un timestamp dentro de una plantilla comparada rompe la idempotencia |
| [03 group-vars-ubicacion-incorrecta](03-group-vars-ubicacion-incorrecta.md) | `group_vars/` en la raíz del proyecto: invisible para `ansible-playbook`, visible por casualidad en ad-hoc |
| [04 restos-de-ejercicios-en-nodo-de-control](04-restos-de-ejercicios-en-nodo-de-control.md) | Variables de prueba olvidadas en `ansible01` sobreviven a `stage7-setup` (`cp -a` no borra) y desvían el huso de dos hosts; `--check` sin `-v` lo ocultaba |
| [05 modulo-propio-python3-falla-en-rhel7](05-modulo-propio-python3-falla-en-rhel7.md) | El módulo propio `lab.utils.lab_uptime_pretty` da `SyntaxError` solo en RHEL 7: usaba f-strings y el nodo ejecuta los módulos con Python 2.7 |
| [06 marca-etapa7-no-se-aplica-ni-se-comprueba](06-marca-etapa7-no-se-aplica-ni-se-comprueba.md) | `lab.sh stage7 site` no copiaba `03-mark-stage.sh` a los nodos, el test de la marca usaba una función de `lib.sh` dentro de `bash -c` y `ansible01` nunca se marcaba (su `test_ansible` no se ejecutaba) |
