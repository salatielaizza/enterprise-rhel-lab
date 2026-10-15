# 🛡️ Etapa 5 — Seguridad: SELinux, auditd y hardening (`scripts/stage5/`)

## Qué hace esta etapa

Deja todas las VMs en un estado base de seguridad **repetible**: SELinux en Enforcing (en caliente y
persistente), reglas de auditoría con clave sobre ficheros críticos, política de contraseñas, parámetros
`sysctl` de red y un aviso legal de acceso.

## Cómo se lanza

```bash
scripts/lab.sh stage5 <host|all>
```

## Scripts (en orden)

| # | Script | Qué hace | Qué modifica | Copia / seguridad |
|---|---|---|---|---|
| 1 | `01-selinux-hardening.sh` | `setenforce 1` + `SELINUX=enforcing`; booleano documentado `ssh_chroot_rw_homedirs`; reaplica contextos del lab; guarda una "foto" de las denegaciones AVC de hoy | `/etc/selinux/config`, booleanos, contextos de `/srv/sftp`, `/opt/application`, `/var/log/lab-app` | `config.lab-bak.<fecha>`; si SELinux está **Disabled** se para (hace falta reiniciar); `ausearch` siempre con `timeout` (caso `etapa2/06`) |
| 2 | `02-audit-rules.sh` | Instala y arranca `auditd`; reglas `-w ... -p wa -k lab-identity/lab-ssh/lab-sudo` | `/etc/audit/rules.d/lab-hardening.rules` | Copia del fichero de reglas si ya existía; carga con `augenrules --load` (nunca edita `audit.rules` a mano) y comprueba con `auditctl -l` |
| 3 | `03-os-hardening.sh` | `pwquality` (mínimo 12, 4 tipos de carácter), caducidad en `login.defs`, `sysctl` de red y ASLR, aviso en `/etc/issue` | `/etc/security/pwquality.conf`, `/etc/login.defs`, `/etc/sysctl.d/98-lab-hardening.conf`, `/etc/issue` | `.lab-bak.<fecha>` de cada fichero; cambia la línea si existe o la añade si no (no duplica). **Último script: `set_stage 5`** |

## Requisitos previos

- Etapas 1-4 completas (el booleano y el contexto de `/srv/sftp` dependen del SFTP de la Etapa 4).
- `login.defs` solo afecta a usuarios **creados después**: para los existentes se usa `chage`.

## Cómo se verifica

```bash
scripts/lab.sh test all <host|all>     # test_selinux, test_audit, test_hardening
```

## Documentación relacionada

- Checklist: [`checklists/etapa5.md`](../../checklists/etapa5.md)
- Tema: [`security/selinux.md`](../../security/selinux.md) · [`security/audit.md`](../../security/audit.md) · [`security/hardening.md`](../../security/hardening.md)
- Comandos explicados y diagnóstico de SELinux/auditd: [`troubleshooting/etapa5/README_troubleshooting_etapa5.md`](../../troubleshooting/etapa5/README_troubleshooting_etapa5.md)
