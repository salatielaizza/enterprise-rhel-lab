# Etapa 8 · Caso 03 — `journalctl --user`: "No journal files were found" con el servicio en marcha 🔎

**Objetivo**: distinguir un servicio que no escribe logs de un diario que no está donde se busca, y saber leer los logs
de un servicio de usuario (Quadlet) en un sistema con el diario volátil.

**Preparación**: `ansible01` (RHEL 9.8), como `adminlab`. Ejercicio 8.1.6 (servicio de usuario `saludo` generado por
Quadlet, 2026-11-01). Encontrado al ejecutar, no provocado.

## Cómo se produjo

```bash
systemctl --user daemon-reload
systemctl --user start saludo
journalctl --user -u saludo -n 5 --no-pager
```

## Síntoma

```text
No journal files were found.
-- No entries --
```

## Hipótesis descartadas

- **El servicio no arranca o no escribe**: descartada. Salida real:

  ```text
  ● saludo.service - Saludo (Etapa 8.1, Quadlet)
       Loaded: loaded (/home/adminlab/.config/containers/systemd/saludo.container; generated)
       Active: active (running) since Sun 2026-11-01 18:55:57 CET; 24s ago
       CGroup: /user.slice/user-1001.slice/user@1001.service/app.slice/saludo.service
               ├─libpod-payload-7f896474c6a3...
               │ ├─2285 /bin/bash /usr/local/bin/saludo.sh --bucle
  $ podman ps --format '{{.Names}} {{.Status}}'
  saludo Up 7 minutes
  ```
- **Error en el fichero `.container`**: descartada. `quadlet -dryrun -user` generó la unidad sin errores.

## Diagnóstico

```bash
ls -d /var/log/journal /run/log/journal 2>&1      # ls: cannot access '/var/log/journal' ... ; /run/log/journal
grep -h -i '^ *Storage' /etc/systemd/journald.conf /etc/systemd/journald.conf.d/*.conf 2>/dev/null   # nada: Storage=auto
sudo journalctl _SYSTEMD_USER_UNIT=saludo.service -n 5 --no-pager
```

```text
Nov 01 19:02:57 ansible01.lab.local saludo[2283]: 2026-11-01 18:02:57  Hola desde 7f896474c6a3 (uid=1001)
Nov 01 19:03:27 ansible01.lab.local saludo[2283]: 2026-11-01 18:03:27  Hola desde 7f896474c6a3 (uid=1001)
```

Una pista falsa por el camino: `sudo journalctl --user-unit saludo` → `-- No entries --`. `--user-unit` filtra por la
unidad **y por el UID de quien ejecuta** `journalctl`; con `sudo` es el 0 (root), no el 1001 de `adminlab`.

Detalle de paso: el diario marca `19:02:57` (CET) y el contenedor imprime `18:02:57`: la imagen UBI no tiene zona
horaria y usa UTC. Se corrige con `Environment=TZ=Europe/Madrid` en la sección `[Container]` del `.container`.

## Causa raíz

Con `Storage=auto` (el valor por defecto) y sin `/var/log/journal`, el diario es **volátil** (`/run/log/journal`).
journald solo separa ficheros de diario por usuario cuando el almacenamiento es persistente, así que los mensajes de los
servicios `--user` acaban en el diario del sistema, y `journalctl --user` no encuentra ningún fichero propio del
usuario. El servicio funcionaba; se miraba en el diario equivocado.

## Solución aplicada

Leer los logs de otra forma (las dos, verificadas):

```bash
podman logs --tail 3 saludo                                         # sin sudo
sudo journalctl _SYSTEMD_USER_UNIT=saludo.service -n 5 --no-pager    # diario del sistema, por campo
```

Opcional (cambio reversible del sistema): diario persistente, con lo que `journalctl --user` funciona y los logs
sobreviven a los reinicios:

```bash
sudo mkdir -p /var/log/journal
sudo systemd-tmpfiles --create --prefix /var/log/journal
sudo systemctl restart systemd-journald && sudo journalctl --flush
```

Vuelta atrás: `sudo rm -rf /var/log/journal && sudo systemctl restart systemd-journald`.

## Validación

Las líneas `... Hola desde 7f896474c6a3 (uid=1001)`, una cada 30 s, con los dos comandos (2026-11-01). El resto de
la 8.1.6 (relanzado tras `podman kill`, arranque tras `reboot` con `Linger=yes`; antes, `Linger=no`) funcionó
(confirmado por el usuario).

## Prevención

- Antes de diagnosticar una aplicación "que no escribe logs", comprobar **dónde** se guardan: diario de usuario o del
  sistema, volátil o persistente (`journalctl --header | head`, `ls -d /var/log/journal`).
- Para servicios de usuario: `podman logs <contenedor>` o `journalctl _SYSTEMD_USER_UNIT=<unidad>`. `journalctl --user`
  y `--user-unit` solo sirven ejecutados **como ese usuario** y con el diario persistente.
- Fuente: [journald.conf(5), `Storage=` y `SplitMode=`](https://www.freedesktop.org/software/systemd/man/latest/journald.conf.html).
