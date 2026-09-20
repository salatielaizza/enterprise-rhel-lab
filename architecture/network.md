# Diseño de red

| Elemento | Valor |
|---|---|
| Red libvirt | `lab-net`, modo **NAT**, bridge `virbr-lab` |
| Subred / máscara | 10.10.10.0/24 (255.255.255.0) |
| Gateway (host KVM) | 10.10.10.1 |
| DNS del laboratorio | 10.10.10.20 (dns01, BIND) |
| DNS de arranque | 10.10.10.1 (dnsmasq de libvirt) hasta que dns01 exista |
| NTP | 10.10.10.20 (dns01, chrony) |
| Dominio | `lab.local` |
| DHCP | Ninguno: IP estática para todas las VMs |
| IPv6 | Desactivado en las VMs (`ipv6.method ignore`) |

## Flujo de resolución de nombres
`cliente → 10.10.10.20 (BIND, zona lab.local y su inversa) → forwarder 10.10.10.1 (dnsmasq) → DNS del host → Internet`.

## Flujo de hora
`pool público → dns01 (stratum n+1, sirve a 10.10.10.0/24, "local stratum 10" como respaldo) → resto de VMs`.

## Puntos de atención
- **`.local` y mDNS (RFC 6762)**: `.local` está reservado a mDNS. En Mint (avahi + nss-mdns) `ssh x.lab.local` puede fallar
  aunque `dig @10.10.10.20 x.lab.local` funcione, porque `mdns4_minimal [NOTFOUND=return]` corta antes de consultar DNS.
  Por eso `~/.ssh/lab_config` define alias por IP. `lab.sh host-dns` enruta `~lab.local` a dns01 con `resolvectl` (no persistente).
- **Firewall del host**: libvirt inserta sus reglas NAT. Si usas `ufw`: `sudo ufw allow in on virbr-lab` y `sudo ufw route allow in on virbr-lab`.
- **Colisión de rangos**: `01-create-network.sh` aborta si ya existe una ruta 10.10.10.0/24 (VPN, otra red).
- **Wi-Fi**: NAT evita el problema de los bridges sobre interfaces inalámbricas.
