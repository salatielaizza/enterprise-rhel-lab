# 02 — Puerto bloqueado por firewalld

**Objetivo**: distinguir "el servicio no escucha" de "el firewall lo bloquea".
**Preparación**: snapshots de rhel9-app01 (servidor) y rhel8-app01 (cliente); `nmap-ncat` instalado (viene en el kickstart).

## Cómo provocar
En rhel9-app01: `sudo nc -lk 8080 &` (escucha en 8080, **no** abierto en firewalld).

## Síntoma
Desde rhel8-app01: `nc -zv 10.10.10.13 8080` → `No route to host` (rechazo inmediato). `ping` funciona.

## Hipótesis
Servicio caído (daría `Connection refused`), firewall (rechazo ICMP *host prohibited* → "No route to host"), ruta (daría *timeout*/unreachable local).

## Diagnóstico
```bash
# servidor
ss -ltnp | grep 8080                       # escucha en *:8080  → el servicio está vivo
sudo firewall-cmd --get-active-zones ; sudo firewall-cmd --list-all   # 8080/tcp ausente
sudo tcpdump -ni any tcp port 8080         # llega el SYN y sale un ICMP "admin prohibited"
```

## Causa raíz
El puerto 8080/tcp no está permitido en la zona activa (`public`).

## Solución
Prueba: `sudo firewall-cmd --add-port=8080/tcp` (runtime). Definitivo: `--permanent --add-port=8080/tcp` + `--reload` (o mejor, un `--add-service` con nombre).

## Validación
`nc -zv 10.10.10.13 8080` → `Connected`. Limpieza: `sudo pkill nc`; `sudo firewall-cmd --remove-port=8080/tcp`.

## Prevención
Documentar cada puerto abierto; preferir servicios (`firewall-cmd --get-services`); `--permanent` + `--reload` y comprobar `--list-all`.
