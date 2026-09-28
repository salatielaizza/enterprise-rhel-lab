# Etapa 4 · Caso 06 — DNS actualizado en el perfil de NetworkManager pero no en `/etc/resolv.conf` (solo RHEL 8)

**Objetivo**: reconocer un caso donde `nmcli device reapply` devuelve éxito sin que el cambio de DNS
llegue a aplicarse realmente al sistema, y por qué la lógica de respaldo del script (`|| nmcli con up`)
no llegó a activarse.

**Preparación**: Etapa 4 (`stage4-clients all`) ejecutada sobre las 6 VMs, tras haber desplegado `dns01`
con éxito.

## Síntoma

Tras `scripts/lab.sh stage4-clients all`, 5 de las 6 VMs (`rhel7-app01`, `rhel9-app01`, `rhel10-app01`,
`dns01`, `ansible01`) mostraron correctamente `nameserver 10.10.10.20` en su resultado. **Solo
`rhel8-app01`** siguió apuntando al DNS provisional:
```
[rhel8-app01] Resultado:
...
nameserver 10.10.10.1
```
sin ningún mensaje de error visible durante la ejecución del script.

## Diagnóstico

```bash
ssh rhel8-app01 'cat /etc/resolv.conf'
# nameserver 10.10.10.1        <- el sistema sigue usando el DNS viejo

ssh rhel8-app01 'nmcli -f ipv4.dns con show lab0'
# ipv4.dns: 10.10.10.20        <- el PERFIL guardado sí tiene el valor correcto
```
El dato clave: la configuración se guardó bien en el perfil de NetworkManager, pero nunca llegó a
aplicarse al sistema en ejecución. Es decir, el problema no está en `nmcli con mod` (que escribió el
perfil correctamente), sino en el paso siguiente, el que debía **activar** ese cambio.

## Causa (hipótesis mejor sustentada, sin verificación adicional en vivo para no volver a romper el DNS ya corregido)

`scripts/stage3/01-configure-network.sh` aplica el cambio así:
```bash
nmcli device reapply "$dev" >/dev/null 2>&1 || nmcli connection up lab0 >/dev/null
```
La intención es no cortar la sesión SSH: `device reapply` aplica cambios de configuración sin desactivar
y reactivar la interfaz (a diferencia de `connection up`, que si la IP no cambia tampoco debería cortar
la sesión, pero es una operación más "completa"). El problema: en esta ejecución concreta, `nmcli device
reapply` en `rhel8-app01` **devolvió código de salida 0** (éxito) sin que el cambio de DNS se propagara
realmente a `/etc/resolv.conf` — es un comportamiento conocido de `device reapply` en ciertas versiones
de NetworkManager: puede aplicar cambios "de nivel de dispositivo" sin necesariamente disparar la
regeneración de `resolv.conf` cuando el único cambio real es el DNS. Como el código de salida fue 0, la
parte `|| nmcli connection up lab0` del `||` **nunca se ejecutó** — el script asumió éxito basándose
solo en el código de salida, sin comprobar el resultado real.

Las demás VMs (incluida `rhel7-app01`, que también usa formato `ifcfg` igual que RHEL 8, no `keyfile`)
no mostraron el mismo síntoma, lo que sugiere que es una particularidad de la versión de NetworkManager
de RHEL 8 en esta combinación concreta, no del formato de perfil en sí. No se profundizó más en la causa
exacta (comparar versiones de NetworkManager entre RHEL 7 y 8) para evitar volver a tocar la configuración
de red ya corregida.

## Solución aplicada

```bash
ssh rhel8-app01 'sudo nmcli con up lab0'
```
Reactivación completa de la conexión (en vez de solo `reapply`), que sí regeneró `/etc/resolv.conf`
correctamente con `10.10.10.20`.

## Validación

```bash
ssh rhel8-app01 'cat /etc/resolv.conf'
# search lab.local
# nameserver 10.10.10.20
```

## Prevención / mejora pendiente en el proyecto

`scripts/stage3/01-configure-network.sh` confía en el código de salida de `nmcli device reapply` para
decidir si hace falta el respaldo `connection up`, pero ese código de salida no garantiza que el cambio
de DNS se haya propagado de verdad. Una mejora más robusta sería comprobar el resultado real después de
aplicar, no solo el código de salida:
```bash
nmcli device reapply "$dev" >/dev/null 2>&1
if ! grep -q "^nameserver ${LAB_DNS//./\\.}$" /etc/resolv.conf 2>/dev/null; then
  nmcli connection up lab0 >/dev/null
fi
```
No se aplicó este cambio en esta sesión (el problema ya estaba resuelto manualmente cuando se detectó);
queda anotado como mejora futura para que `stage3`/`stage4-clients` sean menos frágiles ante esta
particularidad de NetworkManager en RHEL 8.

## Nota

Este es el primer caso de esta serie donde la causa exacta queda como **hipótesis razonable, no
verificada al 100%** (a diferencia de los demás casos de esta lista, todos confirmados con evidencia directa antes de
aplicar la solución). Se documenta así explícitamente, en vez de presentarlo como certeza, siguiendo la
misma disciplina de no inventar una causa raíz sin evidencia suficiente.
