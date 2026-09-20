# NetworkManager, direccionamiento y nombres

## 1. Objetivo
Configurar IP estática, gateway, DNS, dominio de búsqueda y hostname con `nmcli`, leyendo bien el estado con `ip`, `ss` y `resolv.conf`.

## 2. Prerrequisitos
VMs instaladas (Etapa 1) y `dns01` creada para la parte final. Snapshot `…-stage2-complete`.

## 3. Arquitectura
`dispositivo` (interfaz, p. ej. `ens3`/`eth0`) ≠ `conexión` (perfil NM). Todas las VMs usan la conexión **`lab0`** con IP manual /24, gateway 10.10.10.1, `ipv4.dns-search lab.local`, IPv6 ignorado.
DNS: 10.10.10.1 durante la Etapa 3; 10.10.10.20 (dns01) desde la Etapa 4. NetworkManager escribe `/etc/resolv.conf` (no lo edites a mano).

## 4. Procedimiento manual y comandos
| Comando | Qué hace | Por qué | Salida / fallo |
|---|---|---|---|
| `nmcli device status` / `nmcli connection show` | Dispositivos / perfiles | Ver qué perfil usa cada interfaz | `STATE connected` |
| `ip -br a`, `ip -br link`, `ip r` | Direcciones / enlaces / rutas | Estado real del kernel | `default via 10.10.10.1 dev ens3` |
| `sudo nmcli con mod "Wired connection 1" connection.id lab0` | Renombra el perfil | Mismo nombre en 7/8/9/10 | — |
| `sudo nmcli con mod lab0 ipv4.method manual ipv4.addresses 10.10.10.13/24 ipv4.gateway 10.10.10.1 ipv4.dns 10.10.10.1 ipv4.dns-search lab.local ipv4.ignore-auto-dns yes` | Configura IPv4 | Persistente (se guarda en el perfil) | Sin salida |
| `sudo nmcli con mod lab0 ipv6.method ignore` | Desactiva IPv6 | Evitar rutas/DNS IPv6 no deseados | — |
| `sudo nmcli device reapply ens3` o `sudo nmcli con up lab0` | Aplica sin reiniciar | `reapply` no corta SSH si la IP no cambia | `Connection successfully activated` |
| `sudo hostnamectl set-hostname rhel9-app01.lab.local`; `hostnamectl` | Nombre de host estático | FQDN coherente con el DNS | `Static hostname:` |
| `nmtui` | Interfaz de texto | Cómodo en consola | Paquete `NetworkManager-tui` |
| `cat /etc/resolv.conf`, `getent hosts NOMBRE` | Resolución real del sistema | `getent` usa la misma ruta que las aplicaciones (nsswitch) | `dig`/`nslookup` consultan DNS **directamente**, saltándose `/etc/hosts` |
| `nmcli -f NAME,FILENAME con show` | Dónde guarda el perfil | Ver ifcfg vs keyfile | Ver diferencias |
| `ping -c3 10.10.10.1`, `ss -tulpn` | Conectividad / puertos escuchando | Comprobación básica | — |

Orden de resolución: `/etc/nsswitch.conf` (`hosts: files dns …`) → `/etc/hosts` → DNS de `resolv.conf`.

## 5. Resultado esperado y validación
`scripts/lab.sh stage3 all` → `scripts/lab.sh test test_network.sh all`. En cada VM: IP correcta, ruta por defecto, nameserver 10.10.10.1 (10.10.10.20 tras Etapa 4), ping al gateway, salida a Internet, resolución externa.

## 6. Troubleshooting
Ver `networking/troubleshooting.md` y los casos `09-wrong-ip`, `10-wrong-gateway`, `11-wrong-dns`, `12-wrong-route`. Cambiaste el perfil y "no pasa nada": falta `reapply`/`con up`.

## 7. Errores comunes
Editar `resolv.conf` a mano (NM lo sobrescribe); cambiar la IP por SSH sin plan de retorno (usa consola `virsh console`); no poner `ipv4.method manual`; confundir hostname corto/FQDN.

## 8. Diferencias RHEL 7 / 8 / 9 / 10
- Formato de perfiles: RHEL 7 y 8 → **ifcfg** (`/etc/sysconfig/network-scripts/ifcfg-*`) ◦; RHEL 9 → **keyfile** por defecto, ifcfg **deprecado** ✔; RHEL 10 → ifcfg **eliminado**, solo keyfile ✔ (y `dhclient` eliminado ✔).
- RHEL 7 mantiene además el servicio heredado `network` (initscripts) y `net-tools` (`ifconfig`, `netstat`) ◦; en 8+ están en desuso/ausentes por defecto ◦.
- Anaconda/kickstart puede generar el perfil con un nombre distinto por versión: por eso el script lo renombra a `lab0`.
- Si tienes ifcfg heredados: `nmcli connection migrate` (RHEL 9) ◦ para convertir a keyfile.

## 9. Automatización
`scripts/stage3/01-configure-network.sh` (lo lanza `lab.sh stage3`; se repite en la Etapa 4 con `--dns 10.10.10.20`).

## 10. Ejercicio
Cambia manualmente la IP de rhel8-app01 a .112, comprueba que pierdes SSH (usa consola), revierte; añade un segundo servidor DNS y observa `resolv.conf`; compara `ls /etc/sysconfig/network-scripts` en 7, 8, 9 y 10.

## 11. Criterios de aceptación
`test_network.sh` PASS en todos; explicas dispositivo vs conexión y por qué `getent` y `dig` pueden discrepar.
