# Metodología de diagnóstico de red

## 1. Objetivo
Aislar en minutos **en qué capa** falla algo: enlace, IP, ruta, DNS, firewall, servicio o SELinux.

## 2. Prerrequisitos
`networkmanager.md`. Dos VMs encendidas (cliente y servidor) y `dns01` para las pruebas de DNS.

## 3. Método (de abajo arriba, una hipótesis cada vez)
```
1. Enlace/interfaz    ip -br link ; nmcli device status
2. Dirección IP       ip -br a
3. Ruta y gateway     ip r ; ping -c2 10.10.10.1
4. IP remota          ping -c2 10.10.10.13        (¿llega por IP?)
5. Nombres            getent hosts host ; dig @10.10.10.20 host
6. Puerto/servicio    ss -tulpn (en el servidor) ; nc -zv host 22 (desde el cliente)
7. Firewall           firewall-cmd --list-all
8. SELinux            getenforce ; ausearch -m avc -ts recent
9. Captura            tcpdump -ni any host X and port Y
```
Regla: **cambia una cosa**, valida, anota. Toma snapshot antes de romper nada.

## 4. Comandos de referencia
| Comando | Qué hace | Por qué | Interpretación |
|---|---|---|---|
| `ip -br a` / `ip r` / `ip route get 10.10.10.13` | Estado L3 / ruta que se usaría | Ver si hay ruta y por qué interfaz | Sin `default` → sin salida fuera de la subred |
| `ping -c3 -W2 IP` | ICMP | Conectividad L3 | `Destination Host Unreachable` (local, ARP/ruta) vs *timeout* (filtrado) |
| `traceroute -n IP` / `tracepath IP` | Saltos | Localizar el salto que falla | `tracepath` no necesita root |
| `ss -tulpn` | Sockets escuchando y proceso | ¿El servicio escucha? ¿en qué IP? | Escucha en `127.0.0.1` = no accesible desde fuera |
| `nc -zv HOST 22` / `curl -v telnet://HOST:22` | Prueba TCP | Distinguir causas | ver tabla siguiente |
| `getent hosts N` / `dig @S N` / `dig -x IP` / `host N` | Resolución | Nombres y PTR | `NXDOMAIN` = no existe; `SERVFAIL` = fallo del servidor; *timeout* = no llega/ no responde |
| `sudo tcpdump -ni any port 53` | Captura | Ver si salen/vuelven paquetes | Salen consultas y no vuelve nada = firewall/servicio caído |
| `sudo firewall-cmd --list-all` / `--get-active-zones` | Firewall | ¿Está permitido el servicio/puerto? | — |
| `sudo journalctl -u NetworkManager -n 50` | Log de NM | Errores de perfil | — |

## 5. Cómo distinguir la causa por el síntoma de una conexión TCP
| Lo que ves | Causa probable |
|---|---|
| `Connection refused` (inmediato) | Nadie escucha en ese puerto (servicio parado) o regla REJECT explícita |
| `No route to host` (inmediato) | ICMP *host prohibited* de firewalld (rechazo por defecto) o sin ruta/ARP |
| *Timeout* (espera larga) | Paquetes descartados (DROP) o ruta/gateway incorrectos |
| Conecta pero falla la aplicación | Servicio, autenticación, SELinux o permisos |
| Funciona por IP, no por nombre | DNS (resolv.conf, servidor, zona) |
| Funciona con `setenforce 0` (temporal) | SELinux; **restaura** con `setenforce 1` y arregla con contexto/booleano |

## 6. Troubleshooting de ejemplo (recetas)
- **¿DNS?** `ping 1.1.1.1` OK y `ping redhat.com` falla → DNS. `dig @10.10.10.20 x` vs `dig @10.10.10.1 x` aísla el servidor.
- **¿Firewall?** El servicio aparece en `ss -ltn` y aun así no se llega → `firewall-cmd --list-services`; `tcpdump` en el servidor: SYN entrante sin respuesta.
- **¿Servicio?** `systemctl status`, `ss -ltnp | grep :PUERTO`.
- **¿SELinux?** `ausearch -m avc -ts recent`; `semanage port -l | grep http_port_t` para puertos no estándar.

## 7. Errores comunes
Cambiar varias cosas a la vez; confiar solo en `ping` (ICMP puede estar filtrado aunque TCP funcione); usar `dig` para "probar el sistema" (no pasa por nsswitch); desactivar firewall/SELinux "para probar" y olvidarlo.

## 8. Diferencias RHEL 7 / 8 / 9 / 10
`net-tools` (`ifconfig`, `netstat`, `route`) en RHEL 7; usa `ip`/`ss` en todas ◦. firewalld: backend iptables (7 ◦) → nftables (8+ ◦; el backend iptables está en desuso en 9 ◦). Los mensajes de rechazo de firewalld son iguales.

## 9. Automatización
`tests/test_network.sh` y `tests/test_dns.sh`.

## 10. Ejercicio
Resuelve los 6 casos: `09-wrong-ip`, `10-wrong-gateway`, `11-wrong-dns`, `02-firewall-block`, `03-service-down`, `12-wrong-route` — cada uno con un snapshot previo y anotando hipótesis y evidencias.

## 11. Criterios de aceptación
Dado un síntoma, nombras la capa y el comando que lo confirma, sin adivinar.
