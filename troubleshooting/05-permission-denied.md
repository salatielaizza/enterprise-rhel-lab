# 05 — Permission denied (permisos y ACL)

**Objetivo**: resolver dos "acceso denegado" con causas distintas.
**Preparación**: Etapa 2 aplicada; snapshot de rhel9-app01.

## Cómo provocar
A) Quitar las ACL: `sudo setfacl -bk /opt/application/config; sudo setfacl -b /opt/application/config/lab-app.env`.
B) Quitar el `x` de grupo del directorio padre: `sudo chmod 2740 /opt/application; sudo systemctl restart lab-app`.

## Síntoma
A) `su -s /bin/bash -c 'cat /opt/application/config/lab-app.env' devuser` → `Permission denied`. B) `lab-app` falla con `status=203/EXEC` (appuser no puede atravesar `/opt/application`).

## Hipótesis
Propietario/grupo/modo, ACL ausente, falta `x` en la ruta, SELinux.

## Diagnóstico
```bash
namei -l /opt/application/config/lab-app.env      # muestra permisos de CADA componente de la ruta
getfacl -p /opt/application/config                # ¿existe group:developers?
id devuser ; ls -ld /opt/application ; ls -lZ /opt/application/bin/lab-app.sh
journalctl -u lab-app -n 15 ; sudo ausearch -m avc -ts recent   # si no hay AVC, no es SELinux
```

## Causa raíz
A) developers dependía de una ACL que se eliminó. B) El grupo `application` perdió `x` en `/opt/application`.

## Solución
`sudo bash scripts/stage2/03-permissions.sh` (idempotente) o a mano: `chmod 2750 /opt/application`; `setfacl -m g:developers:rx …` y `-m d:g:developers:rx …`.

## Validación
`scripts/lab.sh test test_permissions.sh rhel9-app01` → PASS.

## Prevención
`namei -l` como primer reflejo; ACL documentadas (`+` en `ls -l`); scripts idempotentes para reponer el estado esperado.
