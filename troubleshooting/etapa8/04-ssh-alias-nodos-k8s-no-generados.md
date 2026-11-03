# Etapa 8 · Caso 04 — `ssh k8s-cp01`: "Could not resolve hostname" con la VM en marcha 🔎

**Objetivo**: entender por qué un nodo nuevo responde a `lab.sh` pero no a `ssh <nombre>` desde el host, y cómo los
ficheros generados a partir de un inventario se quedan desfasados cuando el inventario cambia.

**Preparación**: host Linux Mint 22; nodos `k8s-cp01`, `k8s-w01` y `k8s-w02` recién creados con `lab.sh vm-create` y
pasados por las etapas 2-5 (172 PASS / 0 FAIL en los tres, 2026-11-03). Paso 8.2.2 (entrar en `k8s-cp01`). Encontrado
al ejecutar, no provocado.

## Cómo se produjo

```bash
ssh adminlab@k8s-cp01
```

## Síntoma

```text
ssh: Could not resolve hostname k8s-cp01: Name or service not known
```

`ssh rhel9-app01`, `ssh dns01` o `ssh ansible01` sí funcionan, y `lab.sh stage2`...`stage5`, `test` y `snapshot` sobre
los tres nodos acababan de ir bien.

## Hipótesis descartadas

- **La VM no está encendida o no tiene red**: descartada. `lab.sh test all k8s-cp01` acababa de dar 172 PASS, y
  `lab.sh` entra por SSH.
- **Falta el registro en el DNS del lab**: descartada. `dig +short k8s-api.lab.local @10.10.10.20` → `10.10.10.100`, y
  `k8s-cp01` está en la plantilla de zona de la Etapa 4.

## Diagnóstico

```bash
grep '^Host ' ~/.ssh/lab_config            # alias de las VMs base; ninguno k8s-*
grep -n 'lab_config' scripts/00-host-setup.sh
ssh adminlab@10.10.10.100 hostname          # por IP sí entra: k8s-cp01.lab.local
```

## Causa raíz

Dos causas que se suman:

1. **Alias SSH generados con un inventario antiguo.** `ssh <nombre>` funciona en el lab gracias a los bloques `Host` de
   `~/.ssh/lab_config` (IP, usuario `adminlab`, clave `~/.ssh/lab_ed25519` y `known_hosts_lab`). Ese fichero lo genera
   `lab.sh host-setup` (Etapa 1) **una vez**, recorriendo `scripts/hosts.conf`. Los nodos `k8s-*` se añadieron a
   `hosts.conf` después, así que no tienen alias. `lab.sh` no lo necesita: lee la IP de `hosts.conf` cada vez.
2. **El nombre corto no se resuelve por DNS en el host.** `lab.sh host-dns` solo envía a `dns01` los nombres
   `*.lab.local`; `k8s-cp01` sin dominio no lo resuelve nadie.

## Solución aplicada

Añadir a `~/.ssh/lab_config` los tres alias, con el mismo formato que genera `host-setup`, sin volver a ejecutarlo
(instala paquetes y reescribiría el fichero):

```bash
cp -a ~/.ssh/lab_config ~/.ssh/lab_config.antes-8.2
for h in k8s-cp01 k8s-w01 k8s-w02; do
  grep -q "^Host $h\$" ~/.ssh/lab_config && continue
  ip=$(awk -v n="$h" '$1==n {print $3}' scripts/hosts.conf)
  printf 'Host %s\n  HostName %s\n  User adminlab\n  IdentityFile ~/.ssh/lab_ed25519\n  IdentitiesOnly yes\n  UserKnownHostsFile ~/.ssh/known_hosts_lab\n  StrictHostKeyChecking accept-new\n\n' "$h" "$ip" >> ~/.ssh/lab_config
done
```

El `grep -q ... && continue` lo hace idempotente (no duplica alias) y la IP sale de `hosts.conf`, la fuente de verdad.
Vuelta atrás: `cp -a ~/.ssh/lab_config.antes-8.2 ~/.ssh/lab_config`.

## Validación

```bash
grep -A2 '^Host k8s' ~/.ssh/lab_config
for h in k8s-cp01 k8s-w01 k8s-w02; do ssh "$h" hostname; done
```

Salida real (2026-11-03):

```text
Host k8s-cp01
  HostName 10.10.10.100
  User adminlab
--
Host k8s-w01
  HostName 10.10.10.101
  User adminlab
--
Host k8s-w02
  HostName 10.10.10.102
  User adminlab
k8s-cp01.lab.local
k8s-w01.lab.local
k8s-w02.lab.local
```

## Prevención

- Al añadir un host a `hosts.conf`, regenerar **todo** lo que se deriva de él: aquí, los alias de `lab_config` (lo hace
  ahora el paso 8.2.1 de la guía).
- Desde el host, usar los alias (`ssh k8s-cp01`, `scp fichero k8s-cp01:`); desde `ansible01`, los nombres DNS
  (`k8s-cp01.lab.local`), que resuelve `dns01`.
- En el mercado es un fallo muy habitual: un inventario (CMDB, `hosts.conf`, inventario de Ansible) y sus ficheros
  derivados (`/etc/hosts`, `~/.ssh/config`, reglas de firewall) desincronizados; unas máquinas responden y otras no, y
  se culpa a la red o al DNS.
