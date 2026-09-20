# Arquitectura del laboratorio

## Objetivo
Un entorno reproducible donde **la misma aplicación y los mismos servicios** se comparan en RHEL 7, 8, 9 y 10, y que
sirva de base para las etapas 5-19 (seguridad, Ansible, NGINX, Satellite, NFS, LDAP/Kerberos, HA, monitorización,
contenedores, Kubernetes, CI/CD).

## Capas
| Capa | Componente | Decisión |
|---|---|---|
| Hardware | PC principal (i5-12400F, 31 GB RAM) | Único host de virtualización de las etapas 1-4; el portátil Debian queda para backup/NFS/HA futuros |
| Hipervisor | KVM + libvirt (`qemu:///system`) | CPU `host-passthrough` (RHEL 10 exige x86-64-v3) |
| Firmware | BIOS (SeaBIOS) | UEFI se estudiará más adelante; simplifica snapshots y kickstart |
| Almacenamiento | Pools `lab-isos` y `lab-images` en `/var/lib/libvirt/lab` | Fuera de `$HOME`: `libvirt-qemu` no puede leerlo |
| Red | `lab-net` NAT 10.10.10.0/24 | Un bridge sobre Wi-Fi no es fiable; NAT sí |
| Servicios | dns01 (BIND + NTP), ansible01 (futuro) | Jerarquía típica enterprise: DNS y hora internos |
| Automatización | `scripts/lab.sh` + kickstart | Todo es repetible; los `.md` documentan el procedimiento manual |

## Principios
1. **Estabilidad de identidad**: hostnames, IPs y UID/GID fijos (necesarios para NFS/LDAP/Ansible).
2. **Un cambio, una validación**: cada script valida antes de aplicar (`visudo -cf`, `named-checkconf`, `sshd -t`).
3. **Reversibilidad**: snapshots por etapa (`rhelN-stageM-complete`) y copias `*.lab-bak` de ficheros críticos.
4. **Datos verificados**: nada de la comparación entre versiones se da por cierto sin pasar por una VM real.
5. **Secretos fuera del repositorio**.

## Progresión de etapas
`Etapa 1 instalación → 2 administración → 3 red → 4 servicios (DNS/hora/SSH)`. Cada etapa deja un snapshot por VM y
un checklist en `checklists/`. Las etapas 5+ reutilizan los mismos hosts (`rhel9-web01` .40 y `rhel9-monitor01` .50 están reservados).
