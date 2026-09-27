# ETAPA 5 — CHECKLIST: Seguridad (SELinux avanzado, auditoría, hardening)

> Una etapa **no está completa** hasta marcar TODO: documentación + tests + troubleshooting + diferencias entre versiones + snapshot.
> Rellena las columnas "Resultado obtenido" con lo que veas **de verdad** (pega salidas en `results/etapa5/`).

## Objetivo
SELinux en Enforcing con contextos propios saneados, auditoría (auditd) vigilando ficheros críticos, y un hardening base (contraseñas, caducidad, sysctl, banner) aplicado y verificado en los 6 hosts.

## Comandos (orden)
| # | Comando | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 1 | `scripts/lab.sh stage5 all` | SELinux Enforcing, reglas de auditd cargadas, hardening aplicado en los 6 hosts | |
| 2 | `scripts/lab.sh test all all` | 0 FAIL (incluye `test_selinux`, `test_audit`, `test_hardening`) | |
| 3 | `sudo ausearch -m avc -ts recent` | sin denegaciones nuevas tras el hardening (o explicadas) | |
| 4 | `sudo auditctl -l` | reglas sobre `/etc/passwd`, `/etc/shadow`, `/etc/ssh/sshd_config`, `/etc/sudoers` | |
| 5 | Provoca una denegación SELinux a propósito (ver `security/selinux.md`, ejercicio) | `sealert`/`audit2allow` explican la causa | |
| 6 | `scripts/lab.sh facts all && scripts/lab.sh matrix` | `comparison/matrix.generated.md` con datos reales | |
| 7 | `scripts/lab.sh snapshot create all 5` | `…-stage5-complete` | |

## Documentación
- [ ] `security/selinux.md` · [ ] `security/audit.md` · [ ] `security/hardening.md` · [ ] `comparison/matrix.md` reconciliada

## Criterios de aceptación
- [ ] Los 6 hosts en Enforcing y sin denegaciones AVC sin explicar · [ ] auditd activo y con las 4 reglas mínimas · [ ] pwquality/login.defs/sysctl aplicados · [ ] Ningún acceso SSH roto por el hardening
- [ ] Valores ◦ de `differences.md` promovidos a ✔ o corregidos con datos reales · [ ] Repositorio en Git con historial limpio

## Errores encontrados y solución
| Error | Causa | Solución |
|---|---|---|
| | | |

## Conocimientos adquiridos (resumen propio)
-

## Ampliaciones futuras (fuera del alcance actual de esta etapa)
- Más pruebas de auditoría: creación/baja de usuarios de prueba controlados, vigilancia de `su`/`sudo` de un usuario concreto.
- Desplegar una aplicación de demostración servida por Apache httpd o NGINX (Etapa 9) y repetir este mismo hardening (SELinux, auditd) sobre un servicio web real, para comparar.
