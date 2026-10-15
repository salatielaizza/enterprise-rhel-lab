# 🌐 Etapa 3 — Networking (`scripts/stage3/`)

## Qué hace esta etapa

Configura la red de cada VM con **NetworkManager** de forma homogénea en RHEL 7/8/9/10: IP estática,
gateway, DNS, dominio de búsqueda y hostname FQDN, en una conexión que siempre se llama `lab0`.
En esta etapa el DNS es **de arranque** (`10.10.10.1`, el dnsmasq de libvirt); la Etapa 4 lo cambia a
`dns01` (`10.10.10.20`) reutilizando este mismo script.

## Cómo se lanza

```bash
scripts/lab.sh stage3 <host|all>              # DNS de arranque 10.10.10.1
scripts/lab.sh stage3 <host|all> --lab-dns    # DNS del lab 10.10.10.20 (lo usa la Etapa 4)
```

`lab.sh` saca la IP de cada VM de `scripts/hosts.conf`; nunca se escribe a mano.

## Scripts

| Script | Qué hace | Qué modifica | Idempotencia y seguridad |
|---|---|---|---|
| `01-configure-network.sh --ip --gw --dns --hostname [--domain]` | Localiza la interfaz ethernet, renombra (o crea) la conexión a `lab0`, fija `ipv4.method manual`, IP/24, gateway, DNS, `dns-search lab.local`, `ignore-auto-dns`, IPv6 `ignore` y el hostname | Perfil de NetworkManager (`ifcfg` en RHEL 7, keyfile en 8/9/10), `/etc/hostname` y, de forma indirecta, `/etc/resolv.conf` | Aplica con `nmcli device reapply` para **no cortar la sesión SSH** (si no puede, `connection up`); repetirlo deja el mismo estado. Termina con `set_stage 3` |

## Requisitos previos

- Etapa 1 completa (NetworkManager activo; `nmcli` instalado).
- Para `--lab-dns`: `dns01` con BIND funcionando (Etapa 4).

## Ejecución manual (sin `lab.sh`)

```bash
ssh rhel9-app01
sudo bash ~/lab-scripts/stage3/01-configure-network.sh --ip 10.10.10.13 --gw 10.10.10.1 \
     --dns 10.10.10.1 --hostname rhel9-app01.lab.local --domain lab.local
```

## Cómo se verifica

```bash
scripts/lab.sh test test_network.sh <host|all>    # IP, gateway, lab0, DNS esperado según la etapa, pings
TEST_PEERS=all scripts/lab.sh test test_network.sh all   # + ping entre todas las VMs
```

## Documentación relacionada

- Checklist: [`checklists/etapa3.md`](../../checklists/etapa3.md)
- Tema: [`networking/networkmanager.md`](../../networking/networkmanager.md) · [`networking/troubleshooting.md`](../../networking/troubleshooting.md)
- Comandos explicados, método por capas y 8 casos reales: [`troubleshooting/etapa3/README_troubleshooting_etapa3.md`](../../troubleshooting/etapa3/README_troubleshooting_etapa3.md)
