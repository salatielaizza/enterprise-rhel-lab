# 🔐 Etapa 4 — Servicios enterprise: DNS, hora y SSH (`scripts/stage4/`)

## Qué hace esta etapa

Convierte `dns01` en el servidor de **DNS (BIND)** y de **hora (chrony)** del laboratorio, apunta el resto
de VMs a él y **endurece SSH** en todas, con un usuario SFTP enjaulado de demostración.

## Cómo se lanza

```bash
scripts/lab.sh stage4-dns                  # 1º: servidor en dns01 (BIND + red con DNS propio + chrony servidor)
scripts/lab.sh stage4-clients <host|all>   # 2º: DNS del lab + chrony cliente + endurecimiento SSH
scripts/lab.sh host-dns                    # opcional: el host resuelve *.lab.local (no persistente)
```

`stage4-clients` reutiliza `stage3/01-configure-network.sh --dns 10.10.10.20` y, tras endurecer SSH, abre
**una sesión nueva** para comprobar que se sigue pudiendo entrar.

## Scripts y plantillas

| Fichero | Corre en | Qué hace | Qué modifica | Copia / seguridad |
|---|---|---|---|---|
| `01-setup-dns.sh` | `dns01` | Instala BIND, genera las zonas desde las plantillas con un **serial** nuevo (AAMMDDhhmm), abre `dns` en firewalld | `/etc/named.conf`, `/var/named/*.zone`, firewalld | `named.conf.lab-orig`; valida con `named-checkconf -z` y `named-checkzone` **antes** de reiniciar `named` |
| `02-setup-chrony.sh --role server\|client` | todas | Servidor: pool público + `allow 10.10.10.0/24` + `local stratum 10`. Cliente: única fuente `10.10.10.20` | `/etc/chrony.conf`, firewalld (`ntp`, solo servidor) | `chrony.conf.lab-orig`; bloque entre marcas `BEGIN/END lab-chrony` (repetible); fuentes originales comentadas con `#lab-disabled#` (reversible) |
| `03-ssh-hardening.sh` | todas | `PermitRootLogin no`, solo claves, `MaxAuthTries 3`, `AllowGroups`, `UseDNS no`... + usuario `sftpdemo` en chroot | `sshd_config` o drop-in `00-lab-hardening.conf` (RHEL 9/10), `/srv/sftp/`, SELinux | `sshd_config.lab-bak.<fecha>`; `sshd -t` y, si falla, **restaura y no recarga**; `reload` (no `restart`) para no cortar sesiones; aborta si `adminlab` no tiene clave o no está en `sysadmins` |
| `dns/named.conf` | — | Escucha en `127.0.0.1` y `10.10.10.20`, recursión solo para el lab, forwarder `10.10.10.1` | — | — |
| `dns/lab.local.zone.tpl` · `dns/10.10.10.rev.tpl` | — | Zona directa e inversa (también los registros reservados de la Etapa 9: `esxi01-03`, `vcsa01`, `rhel9-vm01`) | — | Son la **fuente de verdad**: un cambio se aplica con `lab.sh stage4-dns` |

Los scripts terminan con `set_stage 4`.

## Requisitos previos

- Etapas 2 y 3 completas en todas las VMs (`adminlab` en `sysadmins`, conexión `lab0`).
- `dns01` con repositorios (registrado con `lab.sh register dns01 ...` o ISO como repo) para instalar `bind`.
- Orden obligatorio: **`stage4-dns` antes de `stage4-clients`**.
- Antes de endurecer SSH, tener a mano la consola (`virsh console <vm>`) por si hubiera que restaurar.

## Cómo se verifica

```bash
scripts/lab.sh test all <host|all>     # test_dns, test_time, test_ssh (+ named en test_services de dns01)
```

## Documentación relacionada

- Checklist: [`checklists/etapa4.md`](../../checklists/etapa4.md)
- Tema: [`networking/dns.md`](../../networking/dns.md) · [`time/chrony.md`](../../time/chrony.md) · [`networking/ssh.md`](../../networking/ssh.md)
- Comandos explicados y 7 casos reales: [`troubleshooting/etapa4/README_troubleshooting_etapa4.md`](../../troubleshooting/etapa4/README_troubleshooting_etapa4.md)
