# 03 — Servicio parado / servicio que se cae

**Objetivo**: diagnosticar un servicio caído y uno que falla en bucle.
**Preparación**: snapshot de rhel9-app01; **acceso por `virsh console`** disponible.

## Cómo provocar
A) `sudo systemctl stop sshd` (las sesiones abiertas sobreviven; las nuevas no). B) `echo LAB_APP_CRASH_AFTER=3 | sudo tee -a /opt/application/config/lab-app.env; sudo systemctl restart lab-app`.

## Síntoma
A) Desde el host: `ssh rhel9-app01` → `Connection refused`. B) `systemctl status lab-app` alterna `activating (auto-restart)` y `failed`.

## Hipótesis
A) Servicio parado (refused inmediato) vs firewall (No route to host / timeout). B) Fallo de la app vs de la unidad vs permisos/SELinux.

## Diagnóstico
```bash
# A (consola): ss -ltnp | grep :22  -> vacío ; systemctl status sshd ; journalctl -u sshd -n 20
# B:
systemctl status lab-app                 # Main PID … code=exited, status=3/n/a
journalctl -u lab-app -n 30              # "lab-app: fallo simulado tras 3 latidos"
systemctl show lab-app -p Restart,RestartUSec,NRestarts
```

## Causa raíz
A) `sshd` detenido. B) Variable `LAB_APP_CRASH_AFTER=3` → la app sale con código 3 y `Restart=on-failure` la reinicia cada 5 s.

## Solución
A) `sudo systemctl start sshd` (y `enable` si estaba deshabilitado). B) Eliminar la línea del `.env` (o ponerla a 0), `sudo systemctl restart lab-app`; si alcanzó el límite: `sudo systemctl reset-failed lab-app`.

## Validación
`ssh rhel9-app01 true`; `systemctl is-active lab-app`; `scripts/lab.sh test test_services.sh rhel9-app01`.

## Prevención
`systemctl enable`, `Restart=` adecuado, monitorización de servicios (Etapa 11), y nunca parar sshd sin consola de respaldo.
