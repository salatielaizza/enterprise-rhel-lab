# systemd: servicios, targets y journal

## 1. Objetivo
Gestionar servicios, escribir unidades correctas, entender dependencias/targets y diagnosticar fallos de arranque con `systemctl` y `journalctl`.

## 2. Prerrequisitos
`lab-app.service` desplegado (`stage2/05-systemd-app.sh`).

## 3. Arquitectura
`lab-app.service`: `Type=simple`, `User=appuser`, `Group=application`, `EnvironmentFile=-/opt/application/config/lab-app.env`,
`ExecStart=/opt/application/bin/lab-app.sh`, `Restart=on-failure`, `RestartSec=5`, `NoNewPrivileges`, `PrivateTmp`, `WantedBy=multi-user.target`.
Parámetros en `lab-app.env`: `LAB_APP_INTERVAL` (segundos) y `LAB_APP_CRASH_AFTER` (>0 provoca un fallo simulado).

## 4. Procedimiento manual y comandos
| Comando | Qué hace | Por qué | Salida / fallo |
|---|---|---|---|
| `systemctl status lab-app` | Estado, PID, últimas líneas del log | Primer paso de todo diagnóstico | `Active: active (running)`; `failed` + `status=203/EXEC` → problema al ejecutar el binario |
| `sudo systemctl start\|stop\|restart\|reload lab-app` | Ciclo de vida | `reload` solo si la unidad lo soporta | — |
| `sudo systemctl enable --now lab-app` | Arranque automático + inicia ya | `enable` crea el symlink en `multi-user.target.wants` | `Created symlink …` |
| `systemctl is-active\|is-enabled\|is-failed lab-app` | Estado en una palabra | Scripts y tests | Código de salida 0/≠0 |
| `systemctl cat lab-app` / `systemctl show lab-app -p Restart` | Unidad efectiva / propiedades | Ver *drop-ins* y valores reales | — |
| `sudo systemctl edit lab-app` | Crea `override.conf` en `/etc/systemd/system/lab-app.service.d/` | Cambiar sin tocar el fichero original | Recarga automática |
| `sudo systemctl daemon-reload` | Relee unidades | **Obligatorio** tras editar a mano un `.service` o `fstab` | Aviso "unit file changed on disk" si se olvida |
| `systemctl list-units --failed` / `list-dependencies multi-user.target` | Fallos / árbol de dependencias | Visión global | — |
| `systemctl get-default` / `set-default multi-user.target` / `isolate rescue.target` | Targets | 7 runlevels → targets | `multi-user.target` = sin gráfico |
| `systemd-analyze blame` / `critical-chain` | Tiempos de arranque | Diagnóstico de arranque lento | — |
| `journalctl -u lab-app -f` | Log de la unidad en vivo | Ver latidos y errores | Ver `logging.md` |

Códigos de salida útiles: `200/CHDIR` (WorkingDirectory), `203/EXEC` (no se puede ejecutar: ruta, permisos, SELinux), `217/USER` (usuario inexistente), `1/FAILURE` (la app falló).
Dependencias: `Wants=` (débil), `Requires=` (fuerte), `After=`/`Before=` (solo **orden**). `Restart=on-failure` reinicia si sale con código ≠0 o por señal, **no** si se detiene con `systemctl stop`.

## 5. Resultado esperado y validación
`systemctl is-active lab-app` → `active`; `journalctl -u lab-app -n 3` muestra `heartbeat`; `test_services.sh` PASS.
Prueba de reinicio: `echo LAB_APP_CRASH_AFTER=3 | sudo tee -a /opt/application/config/lab-app.env; sudo systemctl restart lab-app` → observa fallos y reinicios cada ~5 s; luego restaura el valor 0.

## 6. Troubleshooting
`203/EXEC` → `ls -lZ /opt/application/bin/lab-app.sh` (¿`bin_t`?), `ausearch -m avc -ts recent`, bit `x`, shebang → `troubleshooting/06-selinux-denial.md`. `start-limit-hit` → demasiados fallos: `systemctl reset-failed lab-app`.

## 7. Errores comunes
Olvidar `daemon-reload`; usar `After=` creyendo que crea dependencia; `Type=forking` sin PIDFile; confundir `enable` con `start`; editar en `/usr/lib/systemd/system` (se pierde con actualizaciones; usar `/etc/systemd/system`).

## 8. Diferencias RHEL 7 / 8 / 9 / 10
- Versión de systemd distinta en cada una (219 en RHEL 7 ◦; confirmar con `systemctl --version`).
- RHEL 7 (219) **no** soporta `StandardOutput=append:` ni `systemctl show --value` ◦. `journalctl --list-boots` requiere journal persistente.
- Límites de recursos: `MemoryLimit=` (cgroup v1) vs `MemoryMax=` (cgroup v2, por defecto en 9+ ◦).
- `network-online.target`/NetworkManager-wait-online: mismo comportamiento general ◦.

## 9. Automatización
`stage2/05-systemd-app.sh` (+ `test_services.sh`).

## 10. Ejercicio
Añade un `override.conf` con `Environment=LAB_APP_INTERVAL=2`; provoca 203/EXEC copiando el script con `mv` desde `/tmp`; usa `systemd-analyze blame`; cambia el target por defecto a `rescue.target` **en una VM con snapshot** y vuelve.

## 11. Criterios de aceptación
Explicas la diferencia entre `enable` y `start`, entre `After=` y `Requires=`, y arreglas un 203/EXEC.
