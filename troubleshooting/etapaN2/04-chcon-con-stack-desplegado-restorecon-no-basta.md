# 04 — Avería de `chcon` con el stack desplegado: `restorecon` no basta 🔎

## Objetivo
Practicar la avería provocada 1 del bloque 1 de la guía (etiqueta SELinux incorrecta en `/var/lib/docker`) y
recuperar el SIEM con 0 FAIL en `test_siem.sh`.

## Preparación
Stack de Graylog ya desplegado con `siem-stack` (MongoDB, OpenSearch y Graylog en marcha), y ejercicio básico de
contenedores (`hello-world`, `nginx`) hecho. En ese estado se lanzó la avería tal como la escribía la guía:

```bash
sudo chcon -Rv -t var_lib_t /var/lib/docker
```

## Síntoma
```text
$ scripts/lab.sh siem-stack
 Container siem-mongodb Error dependency mongodb failed to start
dependency failed to start: container siem-mongodb is unhealthy

$ docker ps -a --format 'table {{.Names}}\t{{.Status}}'
siem-graylog      Up 15 minutes (unhealthy)
siem-opensearch   Up 15 minutes (unhealthy)
siem-mongodb      Restarting (127) 50 seconds ago

$ docker logs --tail 40 siem-mongodb
... "s":"__wt_panic_func" ... "s":"__log_fs_write" ...
/usr/bin/env: error while loading shared libraries: libc.so.6: cannot change memory protections
```

Graylog y OpenSearch siguen `Up` (sus procesos ya estaban cargados), pero sus *healthchecks* fallan.

## Hipótesis (descartadas)
- *CPU de la VM sin AVX* (MongoDB 5.0+ lo exige): descartada. La VM está en `host-passthrough` y
  `/proc/cpuinfo` muestra `avx` y `avx2`.
- *Memoria*: descartada. `oom=false` y 5,8 GB libres.
- *fapolicyd* (mismo mensaje `cannot change memory protections`): descartada. `systemctl is-active fapolicyd` →
  `inactive`, y no hay eventos `FANOTIFY`.
- *`restorecon -R` del propio `01-docker-host.sh` relanzado con contenedores en marcha*: descartada.
  La política es correcta y `restorecon` habría puesto tipos de contenedor, no `var_lib_t`:
  ```text
  $ matchpathcon /var/lib/docker /var/lib/docker/overlay2/x /var/lib/docker/volumes/x
  /var/lib/docker             system_u:object_r:container_var_lib_t:s0
  /var/lib/docker/overlay2/x  system_u:object_r:container_ro_file_t:s0
  /var/lib/docker/volumes/x   system_u:object_r:container_var_lib_t:s0
  $ sudo semanage fcontext -l -C        # sin reglas locales
  ```

## Diagnóstico
Los AVC dicen exactamente qué se deniega y con qué etiquetas:

```text
$ sudo timeout 30 ausearch -m AVC,USER_AVC,FANOTIFY -ts today -i | grep -E 'mongo|env|libc|container'
avc: denied { read }  ... path=/usr/lib/x86_64-linux-gnu/libc.so.6
     scontext=system_u:system_r:container_t:s0:c76,c520  tcontext=system_u:object_r:var_lib_t:s0
avc: denied { read }  ... name=hosts
     scontext=system_u:system_r:container_t:s0:c76,c520  tcontext=system_u:object_r:var_lib_t:s0:c76,c520
avc: denied { write } ... name=journal
     scontext=system_u:system_r:container_t:s0:c76,c520  tcontext=system_u:object_r:var_lib_t:s0:c76,c520

$ docker inspect -f '{{.MountLabel}}' siem-mongodb
system_u:object_r:container_file_t:s0:c239,c362
$ sudo ls -Z /var/lib/docker/volumes/siem_mongodb_data/_data | head -2
system_u:object_r:var_lib_t:s0:c239,c362 collection-0--235691120487794559.wt
```

- El **tipo** ha cambiado a `var_lib_t` y las **categorías MCS** siguen siendo las del contenedor.
  Solo `chcon -t` hace eso: cambia el tipo y conserva usuario, rol y nivel.
- La salida de `chcon -Rv` lo confirma: ~51.000 líneas `changing security context` (capas `overlay2/*/diff`,
  `containers/*/hosts`, volúmenes `siem_*`) y ~18.600 `Operation not supported` en las vistas `merged` de los dos
  contenedores en marcha (el montaje overlay no admite el cambio; los ficheros de debajo sí cambiaron).
- MongoDB cae el primero porque es el que más escribe (journal de WiredTiger → *panic*). Los demás mueren al
  lanzar cualquier proceso nuevo (*healthcheck*, reinicio): el cargador no puede mapear `libc.so.6`.

## Causa raíz
La avería de la guía se hizo **con el stack desplegado**, y su arreglo (`restorecon -Rv /var/lib/docker`) solo
recupera lo que la **política** sabe etiquetar:

| Qué | Etiqueta correcta | ¿La recupera `restorecon`? |
|---|---|---|
| `/var/lib/docker`, metadatos | `container_var_lib_t:s0` | Sí |
| Capas de imagen (`overlay2/*/diff` de solo lectura) | `container_ro_file_t:s0` | Sí |
| Volúmenes y capa escribible de cada contenedor | `container_file_t:s0:cX,cY` | **No**: ese tipo y esas categorías los pone **Docker** al crear el contenedor; la política solo conoce `container_var_lib_t` |

Así que, con contenedores con datos, `restorecon` deja a MongoDB sin poder escribir aunque `ls -Zd /var/lib/docker`
parezca correcto.

## Solución aplicada
1. Recrear contenedores y volúmenes (solo había datos de hoy; el `.env` y la contraseña de admin están en
   `/opt/siem` y `/root/.siem`, fuera de los volúmenes, y se conservan):
   ```bash
   sudo docker compose --project-directory /opt/siem down -v
   ```
   `/opt/siem` es `root` 0750 (guarda el `.env`): `cd /opt/siem` como `adminlab` da `Permission denied` y un
   `docker compose down` lanzado desde otro directorio responde `no configuration file provided` **sin borrar
   nada**. Hay que usar `sudo` y `--project-directory` (o `sudo -i` y `cd /opt/siem`).
2. Devolver los tipos de la política a imágenes y directorios: `sudo restorecon -R /var/lib/docker`.
3. `scripts/lab.sh siem-stack`: Docker crea contenedores y volúmenes nuevos con `container_file_t` y categorías
   nuevas.

La guía (`siem/etapaN2-siem.md`, avería 1 del bloque 1) se corrige: con el stack desplegado, el arreglo incluye el
paso 1, o el ejercicio se hace antes de `siem-stack`.

## Validación
```text
$ scripts/lab.sh siem-stack
 Container siem-mongodb Healthy
 Container siem-opensearch Healthy
 Container siem-graylog Started
[siem01] Graylog responde: 7.1.10+393917f running

$ scripts/lab.sh test test_siem.sh siem01
PASS  contenedor siem-mongodb healthy
PASS  contenedor siem-opensearch healthy
PASS  API de Graylog: lbstatus ALIVE
PASS  OpenSearch: clúster green o yellow
--- test_siem en siem01: 23 PASS, 0 FAIL
```

## Prevención
- `restorecon` restaura la **política**, no lo que un programa etiquetó en tiempo de ejecución. Docker, Podman o
  libvirt (`svirt`) asignan tipos y categorías MCS propios: después de un `chcon` sobre sus datos, se recrea el
  recurso, no se "restaura".
- Leer el AVC completo: `tcontext` con categorías correctas y tipo equivocado → `chcon -t`; tipo correcto y
  categorías ajenas → otro contenedor o un volumen compartido sin `:z`.
- Una avería provocada se ensaya en el estado que indica la guía y con snapshot (`siem01-stage5-complete`).
- `ls -Zd` del directorio raíz no basta como verificación: mirar también un fichero de datos del contenedor.
