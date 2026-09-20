# 06 — Denegación de SELinux (etiqueta incorrecta)

**Objetivo**: reconocer y corregir un problema de contexto SELinux sin desactivar SELinux.
**Preparación**: Etapa 2 aplicada; SELinux `Enforcing`; snapshot de rhel9-app01.

## Cómo provocar
```bash
sudo cp /opt/application/bin/lab-app.sh /tmp/lab-app.sh
sudo mv /tmp/lab-app.sh /opt/application/bin/lab-app.sh   # mv CONSERVA la etiqueta de /tmp
sudo systemctl restart lab-app
```

## Síntoma
`systemctl status lab-app` → `status=203/EXEC`; permisos POSIX correctos (`ls -l` OK).

## Hipótesis
Permisos (descartados: `namei -l` limpio), shebang/`noexec`, **SELinux**.

## Diagnóstico
```bash
ls -lZ /opt/application/bin/lab-app.sh        # tipo tmp_t / user_tmp_t en vez de bin_t
sudo ausearch -m avc -ts recent               # denied { execute … } scontext=…init_t tcontext=…tmp…
sudo setenforce 0 ; sudo systemctl restart lab-app ; sudo setenforce 1   # prueba temporal: funciona ⇒ es SELinux
matchpathcon /opt/application/bin/lab-app.sh   # etiqueta esperada (bin_t)
```
(El tipo y el permiso exactos del AVC pueden variar según versión: anota lo que veas.)

## Causa raíz
El fichero movido conserva el contexto de `/tmp`; `init_t` no puede ejecutar ese tipo.

## Solución
`sudo restorecon -v /opt/application/bin/lab-app.sh && sudo systemctl restart lab-app`. Para rutas no estándar: `sudo semanage fcontext -a -t bin_t '/ruta(/.*)?'` + `restorecon -R`. **No** dejes SELinux en permissive.

## Validación
`ls -lZ` → `bin_t`; `systemctl is-active lab-app`; sin AVC nuevos; `test_services.sh` y `test_permissions.sh` PASS.

## Prevención
Usar `cp` (hereda) o `restorecon` tras `mv`; `semanage fcontext` para ubicaciones personalizadas; `ausearch -m avc` antes de tocar permisos. Otros casos típicos: puertos no estándar (`semanage port`), booleanos (`getsebool -a`).
