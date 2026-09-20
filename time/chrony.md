# Sincronización horaria con chrony

## 1. Objetivo
Mantener todas las VMs sincronizadas contra una fuente definida (dns01) y diagnosticar desfases.

## 2. Prerrequisitos
`dns01` con red (para el pool público) y firewalld; clientes con DNS/gateway funcionando.

## 3. Arquitectura
`pool público → dns01 (servidor: allow 10.10.10.0/24, local stratum 10) → clientes (server 10.10.10.20 iburst)`.
`local stratum 10` mantiene la coherencia interna si se pierde Internet. Los cambios van entre `# BEGIN/END lab-chrony`; las líneas originales `pool/server` se comentan con `#lab-disabled#` (reversible; copia en `/etc/chrony.conf.lab-orig`).

## 4. Procedimiento manual y comandos
| Comando | Qué hace | Por qué | Salida / fallo |
|---|---|---|---|
| `systemctl status chronyd` | Estado | — | `active (running)` |
| `chronyc sources -v` | Fuentes y estado (`^*` = seleccionada, `^+` combinable, `^?` inalcanzable) | Ver si sincroniza y con quién | Cliente: `^* 10.10.10.20` |
| `chronyc tracking` | Desfase, stratum, *Leap status* | `Leap status : Normal` = sincronizado; `Not synchronised` = no | `System time` = desfase actual |
| `chronyc sourcestats`, `chronyc clients` (en dns01) | Estadísticas / clientes atendidos | Comprobar que dns01 sirve | — |
| `sudo chronyc makestep` | Salta el reloj ya | Corrige desfases grandes tras suspender la VM | — |
| `timedatectl` | Hora, zona, sincronización | RHEL 7: `NTP synchronized: yes`; 8+: `System clock synchronized: yes` | — |
| `sudo timedatectl set-timezone Europe/Madrid`, `set-ntp true` | Zona / activar NTP | — | — |
| `sudo firewall-cmd --permanent --add-service=ntp && sudo firewall-cmd --reload` (dns01) | Abre 123/udp | Sin esto los clientes no sincronizan | — |
| `sudo tcpdump -ni any udp port 123` | Ver el tráfico NTP | Diagnóstico | Petición sin respuesta = firewall/servicio |

Directivas clave: `pool`/`server` (fuentes), `allow` (quién puede consultar), `local stratum` (reloj propio de respaldo), `makestep 1.0 3` (permite saltos en las 3 primeras actualizaciones), `driftfile`, `rtcsync`.

## 5. Resultado esperado y validación
`scripts/lab.sh stage4-dns` (server) + `stage4-clients` (clients); `scripts/lab.sh test test_time.sh all` → Leap Normal, desfase < 1 s, cliente sincronizado con 10.10.10.20.

## 6. Troubleshooting
`troubleshooting/08-time-sync-failure.md`: `^?` en el cliente → dns01 no responde (chronyd parado, firewall, `allow` ausente); `Not synchronised` en dns01 → sin Internet y sin `local`; reloj tras restaurar snapshot: `makestep`.

## 7. Errores comunes
Dejar fuentes públicas en los clientes; olvidar `allow`; confiar en `date` en vez de `chronyc tracking`; restaurar un snapshot y no forzar `makestep`.

## 8. Diferencias RHEL 7 / 8 / 9 / 10
En RHEL 7 conviven `ntpd` (paquete `ntp`) y chrony; en RHEL 8+ **`ntpd` desaparece y solo hay chrony** ◦. Versiones de chrony distintas (3.x en 7, 4.x en 8+ ◦): `confdir` solo en versiones recientes, por eso se edita el fichero principal con marcas. Registrado por `collect-facts.sh` (`TIMESYNC`, `NTPD_INSTALLED`).

## 9. Automatización
`scripts/stage4/02-setup-chrony.sh --role server|client`.

## 10. Ejercicio
Desfasa el reloj (`date -s '+2 min'` con chrony parado), arranca chrony y mide cuánto tarda; para `chronyd` en dns01 y observa `chronyc sources` en un cliente; restaura un snapshot y corrige con `makestep`.

## 11. Criterios de aceptación
`test_time.sh` PASS en 6 VMs; explicas stratum, `^*` y `Leap status`.
