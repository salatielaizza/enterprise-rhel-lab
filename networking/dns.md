# DNS con BIND (dns01)

## 1. Objetivo
Montar un DNS autoritativo para `lab.local` (y su inversa) con recursión limitada a la LAN, y saber diagnosticarlo.

## 2. Prerrequisitos
`dns01` (RHEL 9) con IP 10.10.10.20, repositorios (suscripción o ISO local) y snapshot previo.

## 3. Arquitectura
`named` escucha en 127.0.0.1 y 10.10.10.20; zonas `lab.local` (`/var/named/lab.local.zone`) y `10.10.10.in-addr.arpa` (`/var/named/10.10.10.rev`);
`allow-query`/`allow-recursion` = localhost + 10.10.10.0/24; `forwarders { 10.10.10.1; }; forward first;`; `dnssec-validation no` (decisión de laboratorio). Ficheros fuente: `scripts/stage4/dns/`.
Registros: kvm-host .1, rhel7/8/9/10-app01 .11-.14, dns01 .20, ansible01 .30 (.40 y .50 reservados, comentados).

## 4. Procedimiento manual y comandos
| Comando | Qué hace | Por qué | Salida / fallo |
|---|---|---|---|
| `sudo dnf install -y bind bind-utils` | Instala servidor y `dig/host/nslookup` | — | Sin repos → ver `packages.md` |
| Copiar `named.conf` a `/etc/named.conf` (root:named, 0640) | Configuración | Permisos: `named` debe poder leerla | — |
| Crear zonas en `/var/named/` (root:named, 0640) con `SOA`, `NS`, `A`, `PTR` | Datos | El **serial** debe aumentar en cada cambio (AAMMDDhhmm) | Serial no aumentado = los esclavos/caché no ven el cambio |
| `named-checkconf -z /etc/named.conf` | Valida sintaxis **y carga zonas** | Antes de reiniciar | Sin salida o "zone … loaded serial N" |
| `named-checkzone lab.local /var/named/lab.local.zone` | Valida una zona | Detecta errores típicos (falta punto final, CNAME junto a otros registros) | `OK` |
| `sudo firewall-cmd --permanent --add-service=dns && sudo firewall-cmd --reload` | Abre 53/tcp+udp | Si no, los clientes hacen *timeout* | — |
| `sudo systemctl enable --now named` | Arranca | — | `journalctl -u named` si falla |
| `dig @10.10.10.20 rhel9-app01.lab.local +short` | Consulta A | Prueba directa | `10.10.10.13` |
| `dig @10.10.10.20 -x 10.10.10.13 +short` | Consulta PTR | Prueba inversa | `rhel9-app01.lab.local.` |
| `dig @10.10.10.20 redhat.com` | Recursión/forwarder | Salida a Internet | `status: NOERROR` |
| `sudo rndc reload` / `rndc flush` | Recargar zonas / vaciar caché | Sin reiniciar | — |
| `sudo rndc querylog on` → `journalctl -u named -f` | Log de consultas | Depuración | Desactiva después |

Errores clásicos de zona: falta el **punto final** en un FQDN (`dns01.lab.local` se expande a `dns01.lab.local.lab.local.`), serial sin subir, registros PTR con la subred mal escrita, `NS` sin `A`.

## 5. Resultado esperado y validación
`scripts/lab.sh stage4-dns` y `scripts/lab.sh stage4-clients all`; `scripts/lab.sh test test_dns.sh all` → todos los A/PTR correctos desde cada VM.
Desde el host: `dig @10.10.10.20 rhel9-app01.lab.local +short` (y `lab.sh host-dns` para enrutar `~lab.local`).

## 6. Troubleshooting
`troubleshooting/01-dns-failure.md`, `11-wrong-dns.md`, `13-dns-wrong-record.md`, `14-dns-wrong-zone.md`. SELinux: ficheros de zona fuera de `/var/named` necesitan `named_zone_t`.

## 7. Errores comunes
Olvidar el firewall; `listen-on` sin la IP de la LAN; permitir recursión a todo Internet (resolver abierto); editar la zona sin subir el serial; `.local` reservado a mDNS (ver `architecture/network.md`).

## 8. Diferencias RHEL 7 / 8 / 9 / 10
El lab usa BIND de RHEL 9 en dns01; los clientes 7/8/9/10 usan el mismo DNS. En RHEL 8+ `named.conf` incluye `/etc/crypto-policies/back-ends/bind.config` ◦ (no existe en 7). Modo *chroot* (`named-chroot`/`bind-chroot`): opcional según versión ◦. El soporte de DNS cifrado (DoT/DoH) en RHEL 10 queda pendiente de verificar en las etapas de seguridad ◦.

## 9. Automatización
`scripts/stage4/01-setup-dns.sh` (valida antes de arrancar; serial = fecha/hora).

## 10. Ejercicio
Añade `rhel9-web01` (.40) con A y PTR **subiendo el serial**; rompe la zona (falta un punto final), observa `named-checkzone`; apaga `named` y observa el comportamiento de un cliente (tiempos de espera).

## 11. Criterios de aceptación
`test_dns.sh` PASS; resuelves los casos 01, 11, 13 y 14.
