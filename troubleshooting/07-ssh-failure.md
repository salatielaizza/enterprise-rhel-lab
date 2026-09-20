# 07 — Fallo de autenticación SSH

**Objetivo**: diagnosticar `Permission denied (publickey)` con logs del servidor.
**Preparación**: Etapa 4 aplicada (contraseñas desactivadas); snapshot de rhel9-app01; consola disponible. Se usa `devuser` para no bloquear a adminlab.

## Cómo provocar
```bash
sudo install -d -m 700 -o devuser -g developers /home/devuser/.ssh
sudo install -m 600 -o devuser -g developers /home/adminlab/.ssh/authorized_keys /home/devuser/.ssh/authorized_keys
ssh -i ~/.ssh/lab_ed25519 devuser@10.10.10.13 true      # (host)  → funciona
sudo chmod 777 /home/devuser                            # rompe StrictModes
```

## Síntoma
`ssh -i … devuser@10.10.10.13` → `Permission denied (publickey)`.

## Hipótesis
Clave incorrecta, usuario fuera de `AllowGroups`, permisos/propietario, SELinux, `sshd` sin la clave en `authorized_keys`.

## Diagnóstico
```bash
ssh -vvv -i ~/.ssh/lab_ed25519 devuser@10.10.10.13        # cliente: qué claves ofrece y cuáles rechaza
sudo tail -n 20 /var/log/secure                           # servidor (consola/adminlab)
#   Authentication refused: bad ownership or modes for directory /home/devuser
namei -l /home/devuser/.ssh/authorized_keys ; ls -lZ /home/devuser/.ssh
sudo sshd -T | grep -i allowgroups
```

## Causa raíz
`StrictModes` de sshd rechaza la clave si el directorio personal es escribible por el grupo/otros.

## Solución
`sudo chmod 755 /home/devuser` (o 700). Variante: `sudo chcon -t user_home_t /home/devuser/.ssh/authorized_keys` provoca una denegación SELinux → `sudo restorecon -Rv /home/devuser/.ssh`.

## Validación
`ssh -i … devuser@10.10.10.13 true`; `test_ssh.sh`. Limpieza: `sudo rm -rf /home/devuser/.ssh` (o revertir el snapshot).

## Prevención
Permisos 700/600, `restorecon` tras copiar claves, `sshd -T` para ver lo efectivo, y probar en **segunda sesión** antes de cerrar la primera.
