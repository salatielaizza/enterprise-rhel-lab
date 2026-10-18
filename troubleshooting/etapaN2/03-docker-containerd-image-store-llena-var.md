# 03 — `siem-stack`: "no space left on device" con `lv_docker` vacío 🔎

## Objetivo
Desplegar Graylog + OpenSearch + MongoDB con `scripts/lab.sh siem-stack` (bloque 2 de la guía), con las imágenes
y los datos de Docker en `lv_docker` (35 GB) y no en `/var` (4 GB).

## Preparación
`siem-preflight` con 0 FAIL y `siem-docker` completado:
```text
[siem01] LV vg_system/lv_docker (35G) creado y formateado en XFS
[siem01] fstab: /var/lib/docker por UUID
...
[siem01] Docker 29.9.1, storage driver overlayfs, raíz /var/lib/docker
[siem01] Host de contenedores listo. Siguiente: lab.sh siem-stack
```

## Síntoma
```text
$ scripts/lab.sh siem-stack
[siem01] Descargando imágenes (la primera vez tarda: ~2 GB)
 Image mongo:7.0.45 Pulled
failed to extract layer (application/vnd.oci.image.layer.v1.tar+gzip sha256:a61a98...) to overlayfs as
"extract-650021269-Wwes sha256:439d67...": write /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/
snapshots/6/fs/usr/share/opensearch/jdk/lib/modules: no space left on device
```

MongoDB se descarga; OpenSearch (la imagen más grande) falla al extraerse; Graylog se cancela.

## Hipótesis (descartadas)
- *`lv_docker` es pequeño o no está montado*: descartada. Está montado y prácticamente vacío:
  ```text
  $ df -h /var /var/lib/docker
  /dev/mapper/vg_system-lv_var     4.0G  1.7G  2.3G  43% /var
  /dev/mapper/vg_system-lv_docker   35G  282M   35G   1% /var/lib/docker
  ```
  (Los 282 MB de `df` en un XFS recién creado son metadatos: *journal* y tablas de inodos. `du` da 148 KB.)
- *Docker apunta a otra raíz (`data-root`)*: descartada. `DockerRootDir` es `/var/lib/docker`.

## Diagnóstico
La pista está en la **ruta** del error y en el **driver**, no en el tamaño:

```text
$ sudo du -sh /var/lib/containerd /var/lib/docker
1.1G    /var/lib/containerd
148K    /var/lib/docker

$ docker info --format '{{.Driver}} {{.DockerRootDir}}'
overlayfs /var/lib/docker

$ docker image ls
mongo:7.0.45   c53852c00c23   1.18GB   300MB
```

- El error escribe en `/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/…`, no en `/var/lib/docker`.
- El driver es **`overlayfs`** (el *snapshotter* de containerd), no **`overlay2`** (el driver clásico de Docker).
  Ya salía así en la última línea de `siem-docker`, pero no lo comprobaba nada.
- Los 1,1 GB de MongoDB están en `/var/lib/containerd`; `/var/lib/docker` solo tiene 148 KB.
- `/var` vuelve al 43 % después del fallo porque containerd borra las capas a medio extraer.

## Causa raíz
Desde **Docker Engine 29**, las instalaciones nuevas usan por defecto el **containerd image store**: Docker
delega imágenes y capas en containerd, que las guarda en **su** directorio, `/var/lib/containerd`, aunque
`DockerRootDir` siga diciendo `/var/lib/docker`. En `siem01` ese directorio está en `lv_var` (4 GB del kickstart),
así que el LV de 35 GB preparado para Docker no se usaba y `/var` se llenaba con la primera imagen grande.

Es el mismo patrón que un servicio con disco dedicado que escribe en otra ruta: el espacio existe, pero no donde
escribe el servicio.

## Solución aplicada
`01-docker-host.sh` añade en `/etc/docker/daemon.json`:

```json
"features": { "containerd-snapshotter": false }
```

Docker vuelve al driver clásico `overlay2` y guarda imágenes, capas y contenedores en `/var/lib/docker`
(`lv_docker`). El script avisa si, tras reiniciar, el driver no es `overlay2`, y `test_siem.sh` lo comprueba en
la fase 1 (`storage driver overlay2`).

Limpieza previa en `siem01`, **antes** de cambiar el driver (con el otro driver activo, Docker ya no ve esas
imágenes, pero seguirían ocupando `/var`). Solo había imágenes descargadas por `siem-stack`, sin contenedores ni
datos:

```bash
hostname -s                     # siem01  (comprobar SIEMPRE en qué host se borra)
sudo docker image prune -af     # solo mongo:7.0.45
sudo du -sh /var/lib/containerd
```

Alternativa descartada: crear otro LV para `/var/lib/containerd`. Funciona, pero deja dos sitios de
almacenamiento para un mismo Docker, y el resto del lab (guía, test, `restorecon`) ya asume `/var/lib/docker`.
Con k3s no hay conflicto: usa su propio containerd en `/var/lib/rancher` (`lv_rancher`).

## Validación
```bash
scripts/lab.sh siem-docker
#   [siem01] daemon.json actualizado (..., overlay2 en /var/lib/docker)
#   [siem01] Docker 29.x, storage driver overlay2, raíz /var/lib/docker
scripts/lab.sh siem-stack
# en siem01, durante la descarga: crece /var/lib/docker y /var no se mueve
df -h /var /var/lib/docker
sudo du -sh /var/lib/containerd /var/lib/docker
scripts/lab.sh test test_siem.sh siem01
#   PASS  storage driver overlay2 (imágenes en lv_docker, no en /var/lib/containerd)
```

## Prevención
- Tras preparar almacenamiento dedicado, comprobar **dónde escribe de verdad** el servicio (`du` de las rutas
  candidatas), no solo que el LV está montado.
- Validar el driver de almacenamiento (`docker info --format '{{.Driver}}'`) además de `DockerRootDir`: con el
  *containerd image store*, la raíz que se muestra no es donde están las imágenes.
- Las versiones mayores de Docker cambian valores por defecto: fijarlos en `daemon.json` en vez de heredarlos.
- Un comando que borra (`prune`) se ejecuta solo después de confirmar el host (`hostname -s`): el mismo
  `docker image prune -af` en el PC del lab borraría las imágenes propias del PC.
