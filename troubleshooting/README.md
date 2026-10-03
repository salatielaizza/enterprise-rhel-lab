# Escenarios de troubleshooting

Cada caso se **provoca a propósito** en una VM con snapshot previo (`lab.sh snapshot create <host> N` antes; `revert` después) —
o, en los casos marcados con 🔎, se encontró de forma orgánica al ejecutar de verdad contra las VMs reales — y
se diagnostica con evidencias y se valida. Formato: Objetivo · Preparación · Cómo provocar (si aplica) · Síntoma ·
Hipótesis (descartadas) · Diagnóstico · Causa raíz · Solución (aplicada) · Validación · Prevención.

Organizado en un directorio por etapa, con numeración propia desde 01 en cada una (`etapaN/NN-slug.md`).
Cada etapa finalizada tiene su guía `etapaN/README_troubleshooting_etapaN.md`: índice de casos más los
comandos de los scripts y de los tests de esa etapa, explicados, como base de estudio.
Un caso que se referencia desde fuera de su propia etapa se enlaza como `etapaN/NN`.

## [Etapa 1](etapa1/README_troubleshooting_etapa1.md) — instalación RHEL 7/8/9/10 (3 casos)
| Caso | Tema |
|---|---|
| [01 rhel10-bios-gpt-biosboot](etapa1/01-rhel10-bios-gpt-biosboot.md) | RHEL 10 en BIOS: falta partición biosboot (GPT por defecto) |
| [02 limpieza-scripts-alternativos-rhel10](etapa1/02-limpieza-scripts-alternativos-rhel10.md) | Consolidación: scripts alternativos de RHEL 10 eliminados en favor de `lab.sh` |
| [03 rhel8-checksum-version-real-vs-planeada](etapa1/03-rhel8-checksum-version-real-vs-planeada.md) | RHEL 8: versión real instalada (8.6) distinta de la planeada (8.10) |

## [Etapa 2](etapa2/README_troubleshooting_etapa2.md) — administración Linux (9 casos)
| Caso | Tema |
|---|---|
| [01 service-down](etapa2/01-service-down.md) | Servicio parado (sshd) y servicio que se cae (lab-app) |
| [02 bad-fstab](etapa2/02-bad-fstab.md) | fstab con UUID erróneo → modo emergencia |
| [03 permission-denied](etapa2/03-permission-denied.md) | ACL/permisos: acceso denegado |
| [04 selinux-denial](etapa2/04-selinux-denial.md) | Etiqueta SELinux incorrecta → 203/EXEC |
| [05 findmnt-multiple-args-exit1](etapa2/05-findmnt-multiple-args-exit1.md) 🔎 | `stage2/02-lvm.sh` se detiene tras "Montajes:": `findmnt` con varias rutas devuelve 1 |
| [06 ausearch-colgado-timeout](etapa2/06-ausearch-colgado-timeout.md) 🔎 | `test_services.sh` se cuelga indefinidamente: `ausearch` sin responder |
| [07 acl-heredada-lab-app-env-modo-650](etapa2/07-acl-heredada-lab-app-env-modo-650.md) 🔎 | `lab-app.env` queda en 650 en vez de 640: ACL heredada del directorio config |
| [08 pwck-usuario-ftp-var-ftp-inexistente](etapa2/08-pwck-usuario-ftp-var-ftp-inexistente.md) 🔎 | `pwck`: usuario `ftp` sin `/var/ftp` (solo RHEL 7) |
| [09 journalctl-u-no-encuentra-lab-app-rhel8](etapa2/09-journalctl-u-no-encuentra-lab-app-rhel8.md) 🔎 | `journalctl -u` no encuentra heartbeats en RHEL 8; usar `-t` |

## [Etapa 3](etapa3/README_troubleshooting_etapa3.md) — networking, NetworkManager, diagnóstico (8 casos)
| Caso | Tema |
|---|---|
| [01 firewall-block](etapa3/01-firewall-block.md) | Puerto bloqueado por firewalld |
| [02 wrong-ip](etapa3/02-wrong-ip.md) | Dirección IP incorrecta |
| [03 wrong-gateway](etapa3/03-wrong-gateway.md) | Gateway incorrecto |
| [04 wrong-dns](etapa3/04-wrong-dns.md) | Servidor DNS del cliente incorrecto |
| [05 wrong-route](etapa3/05-wrong-route.md) | Ruta estática incorrecta |
| [06 ssh-lento-usedns-fqdn-inexistente](etapa3/06-ssh-lento-usedns-fqdn-inexistente.md) 🔎 | SSH ~80s por conexión: `UseDNS` + FQDN inexistente (`lab.local` sin `dns01` aún) |
| [07 tabla-resumen-tests-set-e-command-substitution](etapa3/07-tabla-resumen-tests-set-e-command-substitution.md) 🔎 | Regresión `scp -O` + bug de `set -e` con `out="$(...)"; ec=$?` en `lab.sh test` |
| [08 medicion-tiempo-por-test-y-tabla-final](etapa3/08-medicion-tiempo-por-test-y-tabla-final.md) 🔎 | Medición de tiempo por sub-test/VM (`fmt_time` Ns/Mm SSs) + ediciones vim fallidas |

## [Etapa 4](etapa4/README_troubleshooting_etapa4.md) — BIND, chrony, SSH/SFTP (7 casos)
| Caso | Tema |
|---|---|
| [01 dns-failure](etapa4/01-dns-failure.md) | `dns01` caído: clientes sin resolución |
| [02 ssh-failure](etapa4/02-ssh-failure.md) | `Permission denied (publickey)` |
| [03 time-sync-failure](etapa4/03-time-sync-failure.md) | Cliente sin sincronizar con `dns01` |
| [04 dns-wrong-record](etapa4/04-dns-wrong-record.md) | Registro A erróneo en la zona |
| [05 dns-wrong-zone](etapa4/05-dns-wrong-zone.md) | Zona que no carga |
| [06 dns-cambiado-en-perfil-pero-no-en-resolv-rhel8](etapa4/06-dns-cambiado-en-perfil-pero-no-en-resolv-rhel8.md) 🔎 | DNS actualizado en nmcli pero no en `resolv.conf` (solo RHEL 8) |
| [07 sftpdemo-falsos-positivos-pwck-y-test-ssh](etapa4/07-sftpdemo-falsos-positivos-pwck-y-test-ssh.md) 🔎 | `sftpdemo` con chroot: `pwck` y test de `ChrootDirectory` con falsos positivos |

## [Etapa 5](etapa5/README_troubleshooting_etapa5.md) — seguridad: SELinux, auditd, hardening (0 casos)
Sin incidencias propias al ejecutarla: la guía recoge los comandos de los scripts y tests de la etapa y
enlaza los casos de otras etapas que practican lo mismo ([etapa2/04](etapa2/04-selinux-denial.md),
[etapa2/06](etapa2/06-ausearch-colgado-timeout.md), [etapa4/02](etapa4/02-ssh-failure.md)).

## [Etapa 6](etapa6/README_troubleshooting_etapa6.md) — bash avanzado y scripting (1 caso)
| Caso | Tema |
|---|---|
| [01 log-verbose-set-e-lab-healthcheck](etapa6/01-log-verbose-set-e-lab-healthcheck.md) 🔎 | `lab-healthcheck.timer` fallaba: función `log()` devolvía 1 bajo `set -e` sin `-v` |

## [Etapa 7](etapa7/README.md) — automatización con Ansible (3 casos)
| Caso | Tema |
|---|---|
| [01 rhel7-timedatectl-p-no-soportado](etapa7/01-rhel7-timedatectl-p-no-soportado.md) 🔎 | `timedatectl show -p Timezone --value` falla en RHEL 7 (`systemd` demasiado antiguo) |
| [02 plantilla-timestamp-rompe-idempotencia](etapa7/02-plantilla-timestamp-rompe-idempotencia.md) 🔎 | Un timestamp dentro de una plantilla comparada rompe la idempotencia |
| [03 group-vars-ubicacion-incorrecta](etapa7/03-group-vars-ubicacion-incorrecta.md) 🔎 | `group_vars/` en la raíz del proyecto: invisible para `ansible-playbook`, visible por casualidad en ad-hoc |

**Regla**: anota hipótesis y evidencia *antes* de arreglar. Los mensajes exactos pueden variar entre versiones (documenta las diferencias que veas en `results/`).
