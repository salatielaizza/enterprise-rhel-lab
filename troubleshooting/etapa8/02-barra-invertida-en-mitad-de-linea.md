# Etapa 8 · Caso 02 — Una `\` en mitad de la línea: `executable file ' bash' not found` y pod `Degraded` 🔎

**Objetivo**: reconocer cuándo un comando de varias líneas pegado en una sola rompe los argumentos, y entender que
`podman kube generate` copia el estado tal cual, errores incluidos.

**Preparación**: `ansible01`, Podman 5.8.2, como `adminlab`. Ejercicio 8.1.5 (pod `saludo-pod` con `web` y `cliente`,
2026-10-31). Encontrado al ejecutar, no provocado.

## Cómo se produjo

En la guía, el contenedor `cliente` se crea con un comando en dos líneas, unidas por una `\` al final de la primera.
Se escribió en **una sola línea**, dejando la `\` en medio:

```bash
podman run -d --pod saludo-pod --name cliente registry.access.redhat.com/ubi9/ubi-minimal:9.8 \ bash -c 'while true; do curl -s localhost:9898/version; echo; sleep 10; done'
```

## Síntoma

```text
Error: crun: executable file ` bash` not found in $PATH: No such file or directory: OCI runtime attempted to invoke a command that was not found
```

Al repetirlo: `the container name "cliente" is already in use`. `podman ps --pod` solo mostraba `infra` y `web`, y
`podman logs cliente` salía vacío. Después, `podman kube play` del YAML generado falló igual y el pod quedó `Degraded`:

```text
starting container 07cd5b5a2ff0...: crun: executable file ` bash` not found in $PATH ...
Error: failed to start 1 containers
POD ID        NAME        STATUS      CREATED         INFRA ID      # OF CONTAINERS
a1857b1e3149  saludo-pod  Degraded    32 seconds ago  16ef1c0e176d  3
```

## Hipótesis descartadas

- **La imagen UBI minimal no trae `bash`**: descartada. Sí lo trae, y el mensaje dice ` bash`, con un **espacio** dentro
  de las comillas.
- **Fallo de `kube play`**: descartada. Reproduce exactamente el pod del que se generó el YAML.

## Diagnóstico

```bash
podman ps -a --pod                                  # cliente en estado Created: se creó, pero no pudo arrancar
grep -A3 'command' ~/podman-lab/saludo-pod.yaml     # - ' bash'  (con el espacio)
```

## Causa raíz

La `\` solo continúa la línea cuando es **el último carácter**. En medio de una línea, bash la interpreta como
"escapar el carácter siguiente": el espacio pasa a formar parte de la palabra, y el comando del contenedor es ` bash`
(espacio + `bash`), que no existe. El primer intento **creó** el contenedor aunque no pudiera arrancarlo (por eso el
nombre quedó ocupado y `podman ps`, que solo lista los contenedores en marcha, no lo mostraba). `podman kube generate`
retrató ese pod, con su comando roto, y `kube play` lo reprodujo.

## Solución aplicada

```bash
podman pod rm -f saludo-pod 2>/dev/null; podman rm -f cliente web 2>/dev/null
podman pod create --name saludo-pod -p 8081:9898
podman run -d --pod saludo-pod --name web ghcr.io/stefanprodan/podinfo:6.15.0
podman run -d --pod saludo-pod --name cliente registry.access.redhat.com/ubi9/ubi-minimal:9.8 bash -c 'while true; do curl -s localhost:9898/version; echo; sleep 10; done'
```

## Validación

Tres contenedores `Up` en el pod (`infra`, `web` y `cliente`), el JSON de la versión en `podman logs cliente`, y la ida
y vuelta `kube generate` → `kube play` → `kube down` sin errores (confirmado por el usuario).

## Prevención

- Pegar los comandos de varias líneas **tal cual**, o escribirlos en una sola línea **sin** la `\`.
- Ante `executable file ... not found`, mirar si hay espacios u otros caracteres dentro de las comillas del mensaje.
- `podman ps -a` (no solo `podman ps`) cuando un nombre "ya está en uso".
- Revisar lo que se genera (`kube generate`, `kubectl get -o yaml`) antes de reutilizarlo: es una fotografía, no una
  corrección.
