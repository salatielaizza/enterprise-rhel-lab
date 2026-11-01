# Etapa 8 · Caso 01 — `podman build` desde el directorio equivocado y nombre corto de imagen 🔎

**Objetivo**: reconocer dos fallos encadenados al construir una imagen: el *contexto* de build equivocado, que deja una
imagen intermedia sin nombre, y el nombre corto, que hace que Podman busque la imagen en registros remotos.

**Preparación**: `ansible01`, Podman 5.8.2 (RHEL 9.8), como `adminlab`. Ejercicio 8.1.3 (imagen propia
`lab/saludo:1.0`, 2026-10-29). Encontrado al ejecutar, no provocado.

## Cómo se produjo

El script se creó en `~/podman-lab/saludo`, pero el heredoc del `Containerfile` se pegó con el prompt en `~` (el `cd` se
había ejecutado en otra sesión). Después:

```bash
podman build -t lab/saludo:1.0 .        # lanzado desde ~
podman run --rm lab/saludo:1.0
```

## Síntoma

`podman images` mostraba una imagen **sin nombre** del mismo tamaño que la base, y el `run` intentaba descargar la
imagen de tres registros:

```text
<none>                                       <none>      7918567c2f0f  10 seconds ago  109 MB
registry.access.redhat.com/ubi9/ubi-minimal  9.8         e15848b7a7e3  17 hours ago    109 MB

✔ registry.access.redhat.com/lab/saludo:1.0
Error: ... reading manifest 1.0 in registry.access.redhat.com/lab/saludo: name unknown: Repo not found
✔ registry.redhat.io/lab/saludo:1.0
Error: ... unauthorized: Please login to the Red Hat Registry using your Customer Portal credentials.
✔ docker.io/lab/saludo:1.0
Error: ... requested access to the resource is denied
```

## Hipótesis descartadas

- **La imagen se construyó y solo le falta la etiqueta**: descartada. `podman image inspect 7918567c2f0f` devolvió
  `User=  Cmd=[/bin/bash]`, la configuración de la UBI base, sin el `USER 1001` ni el `CMD` del `Containerfile`.
- **Problema de red o de credenciales de los registros**: descartada. Los tres errores son coherentes con una imagen que
  simplemente no existe en ninguno.

## Diagnóstico

```bash
cd ~/podman-lab/saludo && pwd && ls -la          # solo saludo.sh: el Containerfile no estaba ahí
cat Containerfile                                # No such file or directory
podman history 7918567c2f0f                      # la última capa es el LABEL (paso 2 de 6): el build se paró en el COPY
```

## Causa raíz

1. **Contexto equivocado.** El `.` de `podman build` es el *contexto*: el directorio del que salen el `Containerfile` y
   los ficheros de los `COPY`. Desde `~`, Podman encontró `~/Containerfile`, pero no `saludo.sh`: el build se detuvo en
   el `COPY` y dejó la imagen intermedia de los dos primeros pasos, sin nombre. Además, con `~` como contexto, Podman
   empaqueta todo el home para el build (incluidos `.ssh/` y `.vault_pass.txt`).
2. **Nombre corto.** `lab/saludo:1.0` no indica registro. Como no existía en local, Podman la buscó en los
   `unqualified-search-registries` de `/etc/containers/registries.conf` (con `short-name-mode = "enforcing"`, pidiendo
   elegir uno cada vez).

## Solución aplicada

```bash
mv ~/Containerfile ~/podman-lab/saludo/
cd ~/podman-lab/saludo && ls                     # Containerfile  saludo.sh
podman build -t localhost/lab/saludo:1.0 .
podman image inspect localhost/lab/saludo:1.0 --format 'User={{.Config.User}}  Cmd={{.Config.Cmd}}'
podman run --rm localhost/lab/saludo:1.0
```

## Validación

`User=1001  Cmd=[/usr/local/bin/saludo.sh]`, `Capas=3`, `localhost/lab/saludo 1.0 38202e4c3e82 109 MB` y el saludo con
`uid=1001` (2026-10-30). La imagen intermedia `<none>` sigue apareciendo: es la capa padre (caché) de la imagen buena,
no una imagen huérfana.

## Prevención

- Un directorio por imagen y `pwd` antes de crear ficheros con un heredoc.
- Nombres completos siempre: `localhost/...` para las imágenes locales y `registro/ruta:etiqueta` para las remotas (regla
  de la Etapa 8). Con un nombre corto se podría ejecutar una imagen ajena de Docker Hub que se llame igual.
- Un `.containerignore` y `COPY` de ficheros concretos para no meter secretos en la imagen.
