# 🌐 Troubleshooting y guía de estudio — Etapa 3 (networking, NetworkManager, diagnóstico)

Ver formato y regla general en [`troubleshooting/README.md`](../README.md).

Este documento tiene dos usos:

1. **Índice de los casos reales** de troubleshooting de la Etapa 3.
2. **Base de estudio**: todos los comandos que usan el script y el test de esta etapa, con una
   explicación sencilla de qué hace cada uno y para qué sirve al diagnosticar.

> Regla del proyecto: *manual → documentado → repetible → automatizado*. Cada comando de esta
> guía se puede lanzar a mano dentro de una VM; el script solo los encadena.

---

## 1. Casos documentados

| Caso | Tema |
|---|---|
| [01 firewall-block](01-firewall-block.md) | Puerto bloqueado por firewalld |
| [02 wrong-ip](02-wrong-ip.md) | Dirección IP incorrecta |
| [03 wrong-gateway](03-wrong-gateway.md) | Gateway incorrecto |
| [04 wrong-dns](04-wrong-dns.md) | Servidor DNS del cliente incorrecto |
| [05 wrong-route](05-wrong-route.md) | Ruta estática incorrecta |
| [06 ssh-lento-usedns-fqdn-inexistente](06-ssh-lento-usedns-fqdn-inexistente.md) 🔎 | SSH ~80s por conexión: `UseDNS` + FQDN inexistente (`lab.local` sin `dns01` aún) |
| [07 tabla-resumen-tests-set-e-command-substitution](07-tabla-resumen-tests-set-e-command-substitution.md) 🔎 | Regresión `scp -O` + bug de `set -e` con `out="$(...)"; ec=$?` en `lab.sh test` |
| [08 medicion-tiempo-por-test-y-tabla-final](08-medicion-tiempo-por-test-y-tabla-final.md) 🔎 | Medición de tiempo por sub-test/VM (`fmt_time` Ns/Mm SSs) + ediciones vim fallidas |

🔎 = encontrado de forma orgánica al ejecutar contra las VMs reales.

Nota: el caso 06 (`ssh-lento-usedns-fqdn-inexistente`) es un estado intermedio entre esta etapa y la
Etapa 4 (se resuelve del todo al desplegar `dns01`); ver también
[etapa2/05](../etapa2/05-findmnt-multiple-args-exit1.md) y
[etapa2/06](../etapa2/06-ausearch-colgado-timeout.md), encontrados "detrás" de este mismo caso.

---

## 2. Flujo de la etapa (orden exacto)

| # | Comando | Script que ejecuta | Dónde corre |
|---|---|---|---|
| 1 | `scripts/lab.sh stage3 <host\|all>` | `stage3/01-configure-network.sh --ip <IP> --gw 10.10.10.1 --dns 10.10.10.1 --hostname <host>.lab.local --domain lab.local` | VM (root) |
| 2 | `scripts/lab.sh test all <host\|all>` | `tests/run_all.sh` → añade `test_network.sh` | VM |
| 3 | `scripts/lab.sh snapshot create <host> 3` | `scripts/03-snapshot.sh` | Host |
| (Etapa 4) | `scripts/lab.sh stage3 <host\|all> --lab-dns` | El mismo script con `--dns 10.10.10.20` | VM |

`lab.sh` obtiene la IP de cada VM de `scripts/hosts.conf` (`ip_of`), así que la IP nunca se escribe
a mano. En esta etapa el DNS es **de arranque**: `10.10.10.1`, el `dnsmasq` que libvirt levanta en la
red `lab-net`. En la Etapa 4 se cambia a `dns01` (`10.10.10.20`).

---

## 3. Comandos del script, explicados

### 3.1 `01-configure-network.sh` — IP estática, gateway, DNS y hostname con `nmcli`

| Comando | Qué hace | Por qué |
|---|---|---|
| `systemctl is-active --quiet NetworkManager` | ¿Está NetworkManager en marcha? | `nmcli` es solo el cliente: sin el demonio no hace nada |
| `nmcli -t -f DEVICE,TYPE device` | Lista interfaces y su tipo; `-t` = salida "para scripts" separada por `:`, `-f` = solo esos campos | Para encontrar la interfaz ethernet sin suponer su nombre (`eth0`, `ens3`, `enp1s0`...) |
| `awk -F: '$2=="ethernet"{print $1; exit}'` | Se queda con la primera interfaz de tipo ethernet | El nombre cambia entre versiones de RHEL |
| `nmcli -t -f NAME,DEVICE connection show --active` | Perfiles activos y en qué interfaz | **Dispositivo** ≠ **conexión**: la conexión es el perfil de configuración que se aplica a un dispositivo |
| `nmcli connection add type ethernet ifname <dev> con-name lab0` | Crea un perfil nuevo si no había ninguno activo | |
| `nmcli connection modify <nombre> connection.id lab0` | Renombra el perfil existente (el kickstart crea uno con otro nombre) | Mismo nombre `lab0` en RHEL 7/8/9/10: los tests y la documentación no dependen de la versión |
| `nmcli connection modify lab0 ipv4.method manual ipv4.addresses IP/24 ipv4.gateway GW` | IP estática y puerta de enlace | `manual` = sin DHCP (la red no tiene DHCP) |
| `... ipv4.dns DNS ipv4.dns-search lab.local ipv4.ignore-auto-dns yes` | Servidor DNS y dominio de búsqueda | Con `dns-search`, `ping dns01` se convierte en `dns01.lab.local` |
| `... connection.autoconnect yes ipv6.method ignore` | Se levanta sola al arrancar; IPv6 no se configura | El laboratorio es solo IPv4 |
| `nmcli device reapply <dev>` | Aplica los cambios **sin desconectar** la interfaz | Evita cortar la sesión SSH desde la que se ejecuta el script |
| `nmcli connection up lab0` | Reactiva el perfil (si `reapply` no puede) | Puede cortar la conexión un instante |
| `hostnamectl set-hostname <host>.lab.local` | Fija el hostname estático (FQDN) | Escribe en `/etc/hostname` |
| `ip -br -4 addr show dev <dev>` | IPs IPv4 de la interfaz, en formato breve | Comprobación visual |
| `ip route show default` | Ruta por defecto | Debe salir `default via 10.10.10.1` |
| `grep -E '^(search\|nameserver)' /etc/resolv.conf` | DNS efectivo del sistema | NetworkManager **genera** este fichero: no se edita a mano |
| `nmcli -t -f NAME,FILENAME connection show` | Fichero donde se guarda el perfil | RHEL 7: `ifcfg` en `/etc/sysconfig/network-scripts/`; RHEL 9/10: keyfile en `/etc/NetworkManager/system-connections/` (RHEL 10 ya no admite `ifcfg`) |

**Persistente frente a temporal (runtime)** — una idea clave de esta etapa:

| Herramienta | ¿Sobrevive a un reinicio? |
|---|---|
| `nmcli connection modify ...` + `up`/`reapply` | **Sí** (se guarda en el perfil) |
| `ip addr add ...`, `ip route add ...` | **No** (solo en memoria; se pierde al reiniciar o reactivar el perfil) |
| Editar `/etc/resolv.conf` a mano | **No** (NetworkManager lo reescribe) |
| `firewall-cmd --add-port=...` | **No**; con `--permanent` + `--reload`, sí |

---

## 4. Comandos del test (`tests/test_network.sh`), explicados

Se lanza con `scripts/lab.sh test all <host|all>` o `lab.sh test test_network.sh <host>`. `run_all.sh`
lo añade a partir de `LAB_STAGE=3`. Todos los checks son de **solo lectura**.

El test se adapta a la etapa: si `LAB_STAGE` ≥ 4, espera el DNS `10.10.10.20` en vez de `10.10.10.1`
y añade el ping a `dns01`. Con `TEST_PEERS=all` hace ping a todas las demás VMs.

| Comprobación | Comando manual equivalente | Qué demuestra | Capa |
|---|---|---|---|
| IP `X/24` configurada | `ip -4 -o addr show` | La IP de `hosts.conf` está en la interfaz | 3 (IP) |
| Ruta por defecto vía `10.10.10.1` | `ip route show default` | Sabe por dónde salir de la red | 3 |
| Conexión `lab0` activa | `nmcli connection show --active` | El perfil correcto está aplicado | Configuración |
| Primer `nameserver` correcto | `cat /etc/resolv.conf` | El DNS que NetworkManager escribió | DNS |
| `search lab.local` | `grep search /etc/resolv.conf` | Nombres cortos resolubles | DNS |
| Hostname FQDN | `hostnamectl --static` | | Sistema |
| Ping al gateway | `ping -c1 -W2 10.10.10.1` | Llega al router del host; `-W2` = espera máx. 2 s | 2-3 |
| Ping a `1.1.1.1` | `ping -c1 -W3 1.1.1.1` | Sale a Internet **por IP** (sin DNS): NAT de libvirt funcionando | 3 |
| Resolución externa | `getent hosts redhat.com` | Resuelve nombres usando **la misma vía que las aplicaciones** (NSS) | DNS |
| `sshd` en 22/tcp | `ss -ltn \| grep ':22 '` | El servicio escucha | 4 (transporte) |
| Sin IPv6 global | `ip -6 addr show scope global` | `ipv6.method ignore` aplicado | 3 |
| Ping a `dns01` (etapa ≥ 4) | `ping -c1 -W2 10.10.10.20` | | 3 |

**Por qué `getent hosts` y no `dig`:** `dig` pregunta directamente a un servidor DNS e ignora
`/etc/hosts` y `nsswitch.conf`. `getent` resuelve como lo haría `ssh`, `dnf` o cualquier aplicación.
Si `dig` funciona y `getent` no, el problema está en el cliente, no en el servidor.

---

## 5. Comandos de diagnóstico de los casos reales

| Comando | Qué hace | Caso |
|---|---|---|
| `nc -lk 8080` | Abre un puerto en escucha para hacer pruebas (`-l` escucha, `-k` acepta varias conexiones) | 01 — provocar |
| `nc -zv <ip> 8080` | Prueba si un puerto TCP acepta conexión, sin enviar datos (`-z`) | 01 — `No route to host` = rechazo del firewall |
| `ss -ltnp \| grep 8080` | ¿Hay un proceso escuchando en ese puerto? | 01 — servicio vivo ≠ servicio accesible |
| `firewall-cmd --get-active-zones` / `--list-all` | Zona activa y qué permite | 01 |
| `tcpdump -ni any tcp port 8080` | Captura el tráfico real (`-n` sin resolver nombres) | 01 — se ve el SYN llegar y el rechazo |
| `firewall-cmd --add-port=8080/tcp` → `--permanent` + `--reload` | Abrir en caliente y luego de forma persistente | 01 — solución |
| `ip -br a` | Todas las IPs en formato breve | 02 |
| `nmcli -f ipv4.addresses,ipv4.gateway con show lab0` | Lo que dice el **perfil** (lo configurado) | 02 — comparar con lo aplicado |
| `ip neigh` | Tabla ARP: qué MAC corresponde a cada IP vecina | 02/03 — `FAILED`/`INCOMPLETE` = nadie responde en esa IP |
| `ip route get 1.1.1.1` | Qué ruta usaría el kernel para llegar a esa IP | 03/05 — la herramienta más directa para rutas |
| `dig @10.10.10.20 redhat.com +short` | Pregunta a un servidor DNS concreto | 04 — si responde, el servidor está bien |
| `tcpdump -ni any port 53` | Ver las consultas DNS en el cable | 04/06 |
| `ip route add/del 10.10.10.20/32 via ...` | Añadir o quitar una ruta en caliente (no persistente) | 05 |
| `nmcli con mod lab0 +ipv4.routes "..."` / `-ipv4.routes "..."` | Añadir o quitar una ruta **persistente** del perfil | 05 |
| `tcpdump -ni virbr-lab udp port 53 -v` (en el host) | Capturar el DNS de todas las VMs desde el bridge | 06 — reveló la búsqueda inversa (PTR) de `sshd` |
| `time ssh <host> 'echo OK'` | Mide cuánto tarda una conexión SSH | 06 — ~80 s por intento |
| `UseDNS no` en `sshd_config` + `systemctl reload sshd` | `sshd` deja de resolver la IP del cliente | 06 — solución |
| `bash -n script.sh` | Comprueba la sintaxis sin ejecutar | 07/08 |
| `if out="$(cmd)"; then ec=0; else ec=$?; fi` | Captura salida y código de salida sin que `set -e` aborte | 07 — patrón correcto |

---

## 6. Método de diagnóstico por capas

Ante "no hay red", se va de abajo arriba y se para en la primera capa que falle:

| # | Pregunta | Comando |
|---|---|---|
| 1 | ¿La interfaz está levantada? | `ip -br link`, `nmcli device status` |
| 2 | ¿Tiene la IP correcta? | `ip -br a`, `nmcli con show lab0` |
| 3 | ¿Llego a mi red local? | `ping -c2 10.10.10.1`, `ip neigh` |
| 4 | ¿Tengo ruta de salida? | `ip route`, `ip route get 1.1.1.1` |
| 5 | ¿Salgo a Internet por IP? | `ping -c2 1.1.1.1` |
| 6 | ¿Resuelvo nombres? | `cat /etc/resolv.conf`, `getent hosts redhat.com`, `dig @<dns> redhat.com` |
| 7 | ¿El puerto está abierto en el destino? | `ss -ltnp` (destino), `firewall-cmd --list-all`, `nc -zv <ip> <puerto>` |
| 8 | ¿Qué pasa realmente en el cable? | `tcpdump -ni any host <ip>` |

---

## 7. Chuleta: síntoma → primeros comandos

| Síntoma | Primeros comandos |
|---|---|
| `ping` por IP funciona pero por nombre no | `cat /etc/resolv.conf`, `getent hosts <nombre>`, `dig @<dns> <nombre>` |
| Llego a la red local pero no a Internet | `ip route`, `ip route get 1.1.1.1`, `ip neigh` |
| Solo un host concreto es inalcanzable | `ip route get <ip>` (¿ruta /32 rara?), `ip neigh show <ip>` |
| Un puerto da `No route to host` pero el ping va | `firewall-cmd --list-all` en el destino |
| Un puerto da `Connection refused` | `ss -ltnp` en el destino: nada escucha ahí |
| SSH tarda mucho en conectar | `time ssh ...`, `UseDNS` en `sshd_config`, `tcpdump` en el puerto 53 |
| El cambio de red se pierde al reiniciar | Se hizo con `ip` (runtime); repetir con `nmcli con mod` |
| Edité `resolv.conf` y volvió a cambiar | Cambiar el perfil: `nmcli con mod lab0 ipv4.dns ...` |

---

## 8. Preguntas de repaso

1. ¿Qué diferencia hay entre un dispositivo y una conexión en NetworkManager?
2. ¿Qué diferencia hay entre `nmcli device reapply` y `nmcli connection up`?
3. ¿Por qué no se debe editar `/etc/resolv.conf` a mano en RHEL 8/9/10?
4. ¿Qué cambios de red son persistentes y cuáles se pierden al reiniciar?
5. ¿Qué diferencia hay entre `No route to host` y `Connection refused`?
6. ¿Por qué `dig` puede funcionar mientras `getent hosts` falla?
7. ¿Qué hace `ip route get` y por qué una ruta /32 tiene prioridad?
8. ¿Dónde guarda NetworkManager el perfil en RHEL 7 y en RHEL 10?
9. ¿Por qué `UseDNS yes` puede hacer que SSH tarde más de un minuto en conectar?
10. ¿Por qué `out="$(cmd)"; ec=$?` es un problema con `set -e`?
