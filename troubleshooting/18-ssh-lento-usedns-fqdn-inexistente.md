# 18 — SSH extremadamente lento (~80s por conexión): UseDNS + FQDN inexistente

**Objetivo**: reconocer y resolver un `sshd` con arranque de sesión anormalmente lento (pero que sí termina
autenticando), causado por resolución DNS bloqueante durante el establecimiento de la conexión, no por
GSSAPI ni por carga del sistema (dos hipótesis descartadas con evidencia en el proceso).

**Preparación**: Etapa 3 aplicada (VMs con `search lab.local` en `/etc/resolv.conf`, DNS de arranque
10.10.10.1 = dnsmasq de libvirt), Etapa 4 (dns01) **todavía no** desplegada.

## Síntoma

Cualquier conexión SSH nueva a cualquier VM del laboratorio (incluida `ssh host 'echo hola'`, el comando
más simple posible) tarda **~80 segundos exactos, de forma consistente**, antes de devolver el resultado
— a pesar de que la autenticación por clave se acepta casi al instante según el propio log de `sshd`
(`Accepted publickey ... ssh2`). Esto provoca que `scripts/lab.sh stage2 all` (y cualquier comando que
encadene varias conexiones SSH, como `push()`/`run_remote()`) parezca "colgado" durante varios minutos,
o se corte por completo si algún paso previo (p. ej. `scp` en `push()`) tiene su propio timeout más corto
que esos 80 segundos.

## Hipótesis descartadas (con evidencia, no solo intuición)

1. **Sobrecarga del host** (6 VMs corriendo a la vez). Descartada: `uptime` en el host mostraba
   `load average: 0.6-0.7` sobre 12 hilos, y `free -h` con 17-18 GB disponibles — sin presión real.
   `uptime`/`w` **dentro** de la VM también mostraban `load average: 0.00, 0.01, 0.02`.
2. **Comandos LVM lentos** (`vgs`, `pvs`, `mount -a`, `restorecon`, `findmnt`, `systemctl daemon-reload`).
   Descartada: cada uno, medido individualmente con `time` en una sesión SSH ya abierta, tardó entre 6 y
   55 **milisegundos** — nada que explique 80 segundos.
3. **GSSAPI del lado cliente** (`Next authentication method: gssapi-with-mic` visible en `ssh -v`).
   Descartada con una prueba directa: `ssh -o GSSAPIAuthentication=no -o GSSAPIKeyExchange=no host 'echo VIVA'`
   tardó exactamente el mismo tiempo (1m20s) que sin esas opciones. Como esas opciones solo actúan sobre
   el lado **cliente**, y `sudo sshd -T` en el servidor mostraba `gssapiauthentication yes` pero
   `gssapikeyexchange no`, GSSAPI quedó descartado como causa real (aunque sí aparece en la negociación,
   no es lo que bloquea el tiempo).

## Diagnóstico que sí dio con la causa

Captura de tráfico DNS en el host, en la interfaz de la red del laboratorio, durante una conexión SSH real:

```bash
sudo tcpdump -ni virbr-lab udp port 53 -v
# (en otra terminal) time ssh <host> 'echo VIVA'
```

Reveló el patrón exacto:
```
10.10.10.11.55304 > 10.10.10.1.53: PTR? 1.10.10.10.in-addr.arpa.          <- PTR de la IP del HOST (10.10.10.1)
10.10.10.1.53 > 10.10.10.11.55304: PTR linuxmint22., PTR linuxmint22.local.   <- SÍ responde, rápido
10.10.10.11.40604 > 10.10.10.1.53: A? linuxmint22.lab.local.             <- forward-lookup del nombre obtenido, CON el
10.10.10.11.40604 > 10.10.10.1.53: A? linuxmint22.lab.local. (reintento) <- dominio de búsqueda del laboratorio anexado
... (reintentos cada 5s, varias veces, sin respuesta) ...
```

`sshd` con `UseDNS yes` (confirmado con `sudo sshd -T | grep -i usedns` → `usedns yes`) hace, para cada
conexión: (1) resolución PTR inversa de la IP del cliente — aquí SÍ responde el dnsmasq de libvirt con
`linuxmint22.`/`linuxmint22.local.`; (2) una comprobación **forward-confirmed** del nombre obtenido, que
al hacerse con `search lab.local` activo en la VM se construye como `linuxmint22.lab.local` — un nombre
que **no existe en ningún sitio** (ni el dnsmasq de libvirt lo conoce, ni `dns01` existe todavía como zona
autoritativa de `lab.local`). Esa consulta sin respuesta se reintenta hasta agotar el timeout de resolución,
bloqueando el establecimiento completo de la sesión SSH.

## Causa raíz

`UseDNS yes` (valor por defecto de OpenSSH en RHEL) combinado con: (a) un dominio de búsqueda `lab.local`
ya activo en las VMs desde la Etapa 3, y (b) la ausencia de un DNS autoritativo para ese dominio, que solo
llega con `dns01` en la Etapa 4. Es decir: un orden de dependencias no explícito entre la Etapa 3
(networking) y la Etapa 4 (DNS) — el laboratorio queda en un estado intermedio válido pero con SSH
degradado hasta que dns01 esté desplegada, **salvo que se desactive `UseDNS` mientras tanto**.

## Solución aplicada

```bash
ssh <host> 'sudo bash -c "sed -i \"s/^#\?UseDNS.*/UseDNS no/\" /etc/ssh/sshd_config && \
  grep -i usedns /etc/ssh/sshd_config && systemctl reload sshd"'
```

Aplicado a las 6 VMs (`rhel7/8/9/10-app01`, `dns01`, `ansible01`) como parche manual, **antes** de la
Etapa 4 formal. `time ssh <host> 'echo VIVA'` pasó de ~80s a milisegundos en cada una.

## Validación

```bash
for h in rhel7-app01 rhel8-app01 rhel9-app01 rhel10-app01 dns01 ansible01; do
  echo -n "$h: "; time ssh "$h" 'echo OK' 2>&1 | tr '\n' ' '; echo
done
scripts/lab.sh stage2 all      # debe completar las 6 VMs sin cortes ni esperas largas
```

## Prevención / mejora pendiente en el proyecto

`scripts/stage4/03-ssh-hardening.sh` ya desactiva varias directivas de `sshd_config`, pero **no incluye
`UseDNS no`** en su bloque `GLOBAL`. Debería añadirse ahí, tanto por rendimiento (este caso) como por
buena práctica de hardening (evitar que `sshd` dependa de la disponibilidad/fiabilidad de un DNS externo
para aceptar conexiones). Además, el kickstart de las 4 versiones de RHEL podría fijar `UseDNS no` desde
el primer arranque (Etapa 1), ya que ningún caso de uso de este laboratorio depende de esa resolución
inversa, y evitaría este mismo problema en instalaciones futuras antes de llegar siquiera a la Etapa 3.

## Nota metodológica

Este caso es un buen ejemplo de la disciplina de "una hipótesis, una prueba, un descarte" que pide
`networking/troubleshooting.md`: dos hipótesis razonables (sobrecarga, GSSAPI) fueron descartadas con
medición real antes de llegar a la causa correcta, en vez de aplicar un arreglo a ciegas basado en la
primera sospecha plausible.
