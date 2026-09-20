# 08 — Cliente sin sincronizar con dns01

**Objetivo**: diagnosticar problemas de chrony cliente/servidor.
**Preparación**: Etapa 4 aplicada; snapshots de dns01 y rhel9-app01.

## Cómo provocar
En dns01 (elige una): `sudo systemctl stop chronyd`  **o**  `sudo firewall-cmd --remove-service=ntp` (runtime). En el cliente, si quieres desfase visible: `sudo systemctl stop chronyd; sudo date -s '+90 seconds'; sudo systemctl start chronyd`.

## Síntoma
En rhel9-app01: `chronyc sources` → `10.10.10.20` con `^?` y `Reach 0`; con el tiempo `Leap status : Not synchronised`; `timedatectl` indica que no está sincronizado.

## Hipótesis
Servidor parado, UDP/123 filtrado, cliente apunta a otra IP, red caída.

## Diagnóstico
```bash
chronyc sources -v ; chronyc tracking ; chronyc sourcestats
ping -c2 10.10.10.20                                   # red OK
sudo tcpdump -ni any udp port 123                      # salen peticiones, no vuelven respuestas
# En dns01: systemctl status chronyd ; firewall-cmd --list-services ; chronyc clients
```

## Causa raíz
dns01 no responde a NTP (servicio parado o 123/udp bloqueado).

## Solución
`sudo systemctl start chronyd` / `sudo firewall-cmd --add-service=ntp` (+ `--permanent`); en el cliente `sudo chronyc makestep` para corregir el desfase.

## Validación
`chronyc tracking` → `Leap status : Normal`; `^*` sobre 10.10.10.20; `scripts/lab.sh test test_time.sh all`.

## Prevención
Servicio habilitado, puerto documentado, alertas de "no sincronizado" (Etapa 11), y `makestep` tras restaurar snapshots.
