# Etapa 8 · Caso 01 — El preflight dice "red lab-net no activa" con la red activa

| Campo | Valor |
|---|---|
| Fecha | 2026-10-06 / 2026-10-07 |
| Host | KVM (Linux Mint 22), libvirt 10.0.0, QEMU 8.2.2, bash 5 |
| Script | `scripts/stage8/00-preflight.sh` (`lab.sh esxi-preflight A`) |
| Tipo | Fallo real del propio script (falso positivo), no de la infraestructura |

## Síntoma

```text
$ scripts/lab.sh esxi-preflight A
...
FAIL  red lab-net no activa (lab.sh network)
...
--- preflight fase A: 15 PASS, 3 WARN, 1 FAIL
```

Pero la red estaba activa:

```text
$ virsh -c qemu:///system net-info lab-net | grep -E 'Active|Autostart'
Active:         yes
Autostart:      yes
```

## Diagnóstico

1. **¿Es la red?** No: `net-info` dice `Active: yes`, y `net-start` responde
   `network is already active`.
2. **¿Apunta `virsh` a otro libvirt (`qemu:///session`)?** Primera hipótesis, descartada:

   ```text
   $ echo $LIBVIRT_DEFAULT_URI ; virsh uri
   qemu:///system
   qemu:///system
   $ virsh net-info lab-net ; echo rc=$?
   ...Active: yes ... rc=0
   ```

   Además, la línea siguiente del mismo script (`virsh pool-info lab-images`, sin tubería)
   daba PASS. La conexión era correcta.
3. **¿Es la línea en sí?** Se reproduce exactamente con las opciones del script:

   ```text
   $ bash -c 'set -euo pipefail; if virsh net-info lab-net 2>/dev/null \
       | grep -Eq "Active:[[:space:]]+yes"; then echo OK; else echo FALLA; fi'
   FALLA
   ```

   Misma orden, misma red, y falla solo dentro de un bash con `pipefail`.

## Causa raíz

La línea 50 era:

```bash
if virsh net-info "$LAB_NET" 2>/dev/null | grep -Eq 'Active:[[:space:]]+yes'; then
```

con `set -o pipefail` al principio del script. La secuencia es:

1. `grep -q` encuentra `Active: yes` y **termina inmediatamente** (no lee el resto).
2. `virsh` intenta seguir escribiendo en una tubería sin lector: el kernel le envía
   **SIGPIPE** y muere con el código **141** (128 + 13).
3. Sin `pipefail`, el código de la tubería es el del último comando (`grep` = 0, éxito).
   **Con `pipefail`, es el del último comando que falla**: 141. El `if` lo toma como falso.

Resultado: cuanto antes encuentra `grep` el texto, más probable es el fallo. Es una
condición de carrera (depende de cuánto escribe el productor y de cuándo cierra el
consumidor), por eso puede no reproducirse siempre igual.

Reproducción mínima sin libvirt (productor que escribe mucho):

```bash
bash -c 'set -o pipefail
gen() { yes "Active: yes" | head -c 300000; }
if gen | grep -Eq "Active:[[:space:]]+yes"; then echo OK; else echo "FALSO FAIL ${PIPESTATUS[*]}"; fi'
# FALSO FAIL 141 0
```

## Alcance (mismo patrón en otros scripts de la Etapa 8)

| Fichero:línea | Patrón | Efecto si falla | Corregido |
|---|---|---|---|
| `00-preflight.sh:48` | `qemu ... -device help \| grep -q` | Falso FAIL de vmxnet3 | Sí |
| `00-preflight.sh:50` | `virsh net-info \| grep -Eq` | **Este caso** | Sí |
| `02-create-esxi.sh:89` | `virsh domblklist \| awk '...exit'` | Con `set -e`, aborta tras instalar ESXi sin expulsar el ISO | Sí |
| `06-dns01-nfs-disk.sh:30` | `virsh dumpxml \| grep -q` | Falso "no hay controlador": intenta añadir otro a `dns01` | Sí |
| `06-dns01-nfs-disk.sh:49` | `domblklist \| awk \| grep -qx` | Falso "disco no conectado": intenta conectarlo otra vez | Sí |
| `03`, `07`, `10`, `99` | `ssh/esxcli/exportfs \| grep -q` | Salidas cortas: riesgo bajo | Pendiente de revisar |

## Solución

No encadenar un productor con un consumidor que sale antes de tiempo (`grep -q`,
`head`, `awk ... exit`) cuando el script usa `pipefail`. Capturar la salida en una
variable y buscar sobre ella; así no hay tubería ni SIGPIPE:

```bash
# Antes
if virsh net-info "$LAB_NET" 2>/dev/null | grep -Eq 'Active:[[:space:]]+yes'; then

# Después
net_info="$(virsh net-info "$LAB_NET" 2>/dev/null || true)"
if grep -Eq 'Active:[[:space:]]+yes' <<<"$net_info"; then
```

Para "¿está este valor en la columna 4?" se usa un solo `awk` que devuelve el código:

```bash
blk="$(virsh domblklist "$DOM" --details)"
if awk -v p="$path" '$4 == p {f = 1} END {exit !f}' <<<"$blk"; then
```

## Validación

```bash
bash -n scripts/stage8/{00-preflight,02-create-esxi,06-dns01-nfs-disk}.sh
shellcheck -x scripts/stage8/{00-preflight,02-create-esxi,06-dns01-nfs-disk}.sh
scripts/lab.sh esxi-preflight A      # esperado: PASS  red lab-net activa
scripts/stage8/06-dns01-nfs-disk.sh --dry-run   # no cambia nada
```

## Errores comunes al diagnosticarlo

- Dar por buena la primera hipótesis ("`virsh` mira `qemu:///session`") sin comprobarla:
  la línea siguiente del mismo script daba PASS con el mismo `virsh`, y eso la contradecía.
- Pensar que `cmd | grep -q` es siempre seguro: lo es **sin** `pipefail`.
- "Arreglarlo" quitando `pipefail` del script: oculta también los fallos reales del
  productor (por ejemplo, que `virsh` no pueda conectar).

## Pregunta de entrevista

> *Un script con `set -o pipefail` falla en `cmd | grep -q patrón` aunque el patrón está.
> ¿Por qué?*

`grep -q` termina al primer acierto; `cmd` recibe SIGPIPE al seguir escribiendo y sale
con 141; con `pipefail` la tubería devuelve ese 141 en lugar del 0 de `grep`. Se arregla
guardando la salida en una variable (`out="$(cmd)"; grep -q patrón <<<"$out"`) o, si
la salida es enorme, con `grep` sin `-q` redirigido a `/dev/null` (lee todo).
