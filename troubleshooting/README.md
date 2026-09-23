# Escenarios de troubleshooting

Cada caso se **provoca a propósito** en una VM con snapshot previo (`lab.sh snapshot create <host> N` antes; `revert` después),
se diagnostica con evidencias y se valida. Formato: Objetivo · Preparación · Cómo provocar · Síntoma · Hipótesis · Diagnóstico · Causa raíz · Solución · Validación · Prevención.

| Caso | Tema | Etapa |
|---|---|---|
| 01 dns-failure | dns01 caído: clientes sin resolución | 4 |
| 02 firewall-block | Puerto bloqueado por firewalld | 3 |
| 03 service-down | Servicio parado (sshd) y servicio que se cae (lab-app) | 2-3 |
| 04 bad-fstab | fstab con UUID erróneo → modo emergencia | 2 |
| 05 permission-denied | ACL/permisos: acceso denegado | 2 |
| 06 selinux-denial | Etiqueta SELinux incorrecta → 203/EXEC | 2 |
| 07 ssh-failure | `Permission denied (publickey)` | 4 |
| 08 time-sync-failure | Cliente sin sincronizar con dns01 | 4 |
| 09 wrong-ip | IP equivocada | 3 |
| 10 wrong-gateway | Gateway equivocado | 3 |
| 11 wrong-dns | Servidor DNS del cliente equivocado | 3 |
| 12 wrong-route | Ruta estática incorrecta | 3 |
| 13 dns-wrong-record | Registro A erróneo en la zona | 4 |
| 14 dns-wrong-zone | Zona que no carga | 4 |
| 15 rhel10-bios-gpt-biosboot | RHEL 10 en BIOS: falta partición biosboot (GPT por defecto) | 1 |
| 16 limpieza-scripts-alternativos-rhel10 | Consolidación: scripts alternativos de RHEL 10 eliminados en favor de lab.sh | 1 |
| 17 rhel8-checksum-version-real-vs-planeada | RHEL 8: versión real instalada (8.6) distinta de la planeada (8.10) | 1 |

**Regla**: anota hipótesis y evidencia *antes* de arreglar. Los mensajes exactos pueden variar entre versiones (documenta las diferencias que veas en `results/`).
