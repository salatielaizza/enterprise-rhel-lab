# SSH y SFTP

## 1. Objetivo
Acceso por clave, gestión de `authorized_keys`, `ssh-agent`, endurecimiento de `sshd`, SFTP enjaulado y aplicación **segura** de cambios.

## 2. Prerrequisitos
Etapa 2 hecha (adminlab ∈ sysadmins); acceso a consola (`virsh console`) como red de seguridad.

## 3. Arquitectura
Clave `~/.ssh/lab_ed25519` en el host; alias en `~/.ssh/lab_config` (`ssh rhel9-app01`). Endurecimiento (`stage4/03-ssh-hardening.sh`): `PermitRootLogin no`, `PasswordAuthentication no`, `PubkeyAuthentication yes`, `PermitEmptyPasswords no`, `MaxAuthTries 3`, `LoginGraceTime 30`, `X11Forwarding no`, `ClientAliveInterval 300`/`CountMax 2`, `AllowGroups sysadmins developers application backup sftponly`.
SFTP: usuario `sftpdemo` (UID 1005) en el grupo `sftponly`, jaula `/srv/sftp/sftpdemo` (root:root 755) con `upload/` escribible, `ForceCommand internal-sftp`, claves en `/etc/ssh/lab-keys/%u`.

## 4. Procedimiento manual y comandos
| Comando | Qué hace | Por qué | Salida / fallo |
|---|---|---|---|
| `ssh-keygen -t ed25519 -C "adminlab@lab.local"` | Genera el par de claves | ed25519: corta y moderna (OpenSSH ≥ 6.5) | Usa passphrase |
| `ssh-copy-id -i ~/.ssh/lab_ed25519.pub adminlab@10.10.10.13` | Instala la clave pública | Alternativa a la del kickstart | — |
| `eval "$(ssh-agent)"; ssh-add ~/.ssh/lab_ed25519` | Agente con la clave desbloqueada | Sin reescribir la passphrase | `ssh-add -l` |
| `ssh -J adminlab@rhel9-app01 adminlab@10.10.10.14` | Salto (ProxyJump) | Acceso vía bastión | — |
| `sudo sshd -t` | Valida `sshd_config` | **Antes** de recargar | Sin salida = OK |
| `sudo sshd -T \| grep -i -E 'permitroot\|passwordauth'` | Configuración **efectiva** | Los drop-ins y `Match` pueden sorprender | — |
| `sudo systemctl reload sshd` | Recarga sin cortar sesiones | Aplicar cambios | Las sesiones abiertas sobreviven |
| `sftp -i ~/.ssh/lab_ed25519 sftpdemo@10.10.10.13` | Cliente SFTP | Prueba de la jaula | `pwd` → `/`; `put fichero upload/` |
| `chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys; restorecon -Rv ~/.ssh` | Permisos y contexto | sshd rechaza claves si los permisos son laxos | `ssh_home_t` |
| `sudo journalctl -u sshd -n 30`, `sudo tail /var/log/secure` | Log de sshd | Causa exacta del rechazo | `Authentication refused: bad ownership or modes` |

**Procedimiento seguro de cambio**: (1) sesión abierta que no se cierra; (2) copia `sshd_config.lab-bak.*`; (3) cambio + `sshd -t`; (4) `reload`; (5) abrir una **segunda sesión** nueva; (6) solo entonces cerrar la primera. `lab.sh stage4-clients` hace 2-5 automáticamente.

## 5. Resultado esperado y validación
`scripts/lab.sh test test_ssh.sh all`. Manual: `ssh -o PubkeyAuthentication=no adminlab@10.10.10.13` → `Permission denied (publickey)`; `ssh root@…` → denegado.

## 6. Troubleshooting
`Permission denied (publickey)`: permisos/propietario de `~/.ssh` o de `$HOME` (no debe ser escribible por el grupo), clave equivocada (`ssh -v`), usuario fuera de `AllowGroups`, contexto SELinux. SFTP `Permission denied` al subir: dueño de la jaula (debe ser root), etiqueta SELinux de `upload` (`user_home_t` + boolean `ssh_chroot_rw_homedirs`; **no probado** en las 4 versiones: confirma con `ausearch -m avc`). Ver `troubleshooting/07-ssh-failure.md`.

## 7. Errores comunes
Desactivar contraseñas sin comprobar la clave; `AllowGroups` sin tu propio grupo; jaula SFTP con el directorio escribible por el usuario (sshd la rechaza: `bad ownership or modes for chroot directory`); `known_hosts` obsoleto tras reinstalar (`ssh-keygen -R IP -f ~/.ssh/known_hosts_lab`).

## 8. Diferencias RHEL 7 / 8 / 9 / 10
OpenSSH: 7.4 (RHEL 7 ◦), 8.0 (RHEL 8 ◦), **8.7 (RHEL 9 ✔)**, **9.9 (RHEL 10 ✔)**. `Include /etc/ssh/sshd_config.d/*.conf`: presente en RHEL 9/10, ausente en 7 (y en 8 según parche ◦) → el script detecta `Include` en lugar de asumir la versión. Las **políticas criptográficas** (`update-crypto-policies`, desde 8 ◦) condicionan algoritmos aceptados; las nuevas versiones son más estrictas (p. ej. SHA-1 ◦), lo que puede bloquear clientes/claves antiguas.

## 9. Automatización
`scripts/stage4/03-ssh-hardening.sh` (+ `test_ssh.sh`).

## 10. Ejercicio
Prueba que root y contraseña quedan denegados; añade una segunda clave a `authorized_keys` y bórrala; rompe `sshd_config` a propósito, comprueba que `sshd -t` lo detecta y que **no** se recarga; sube un fichero por SFTP y verifica que no puedes salir de la jaula.

## 11. Criterios de aceptación
`test_ssh.sh` PASS; nunca pierdes el acceso al aplicar un cambio; resuelves `07-ssh-failure`.
