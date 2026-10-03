# 🔐 Troubleshooting y guía de estudio — Etapa 4 (BIND, chrony, SSH/SFTP)

Ver formato y regla general en [`troubleshooting/README.md`](../README.md).

Este documento tiene dos usos:

1. **Índice de los casos reales** de troubleshooting de la Etapa 4.
2. **Base de estudio**: todos los comandos que usan los scripts y los tests de esta etapa, con
   una explicación sencilla de qué hace cada uno y para qué sirve al diagnosticar.

> Regla del proyecto: *manual → documentado → repetible → automatizado*. Cada comando de esta
> guía se puede lanzar a mano dentro de una VM; los scripts solo los encadenan.

---

## 1. Casos documentados

| Caso | Tema |
|---|---|
| [01 dns-failure](01-dns-failure.md) | `dns01` caído: clientes sin resolución |
| [02 ssh-failure](02-ssh-failure.md) | `Permission denied (publickey)` |
| [03 time-sync-failure](03-time-sync-failure.md) | Cliente sin sincronizar con `dns01` |
| [04 dns-wrong-record](04-dns-wrong-record.md) | Registro A erróneo en la zona |
| [05 dns-wrong-zone](05-dns-wrong-zone.md) | Zona que no carga |
| [06 dns-cambiado-en-perfil-pero-no-en-resolv-rhel8](06-dns-cambiado-en-perfil-pero-no-en-resolv-rhel8.md) 🔎 | DNS actualizado en nmcli pero no en `resolv.conf` (solo RHEL 8) |
| [07 sftpdemo-falsos-positivos-pwck-y-test-ssh](07-sftpdemo-falsos-positivos-pwck-y-test-ssh.md) 🔎 | `sftpdemo` con chroot: `pwck` y test de `ChrootDirectory` con falsos positivos |

🔎 = encontrado de forma orgánica al ejecutar contra las VMs reales.

---

## 2. Flujo de la etapa (orden exacto)

| # | Comando | Scripts que ejecuta | Dónde corre |
|---|---|---|---|
| 1 | `scripts/lab.sh stage4-dns` | `stage4/01-setup-dns.sh` → `stage3/01-configure-network.sh --dns 10.10.10.20` → `stage4/02-setup-chrony.sh --role server` | `dns01` |
| 2 | `scripts/lab.sh stage4-clients <host\|all>` | `stage3/01-configure-network.sh --dns 10.10.10.20` → `stage4/02-setup-chrony.sh --role client` (`server` en dns01) → `stage4/03-ssh-hardening.sh` → **nueva sesión SSH de prueba** | Cada VM |
| 3 | `scripts/lab.sh host-dns` (opcional) | `resolvectl` en el host | Host |
| 4 | `scripts/lab.sh test all <host\|all>` | `run_all.sh` → añade `test_dns`, `test_time`, `test_ssh` | VM |
| 5 | `scripts/lab.sh snapshot create <host> 4` | `scripts/03-snapshot.sh` | Host |

El orden importa: primero el servidor DNS y de hora (`dns01`), después los clientes. Tras endurecer
SSH, `lab.sh` abre **una sesión nueva** para comprobar que todavía se puede entrar; si falla, avisa de
cómo recuperar por consola con la copia de seguridad.

---

## 3. Comandos de los scripts, explicados

### 3.1 `01-setup-dns.sh` — BIND en `dns01`

| Comando | Qué hace | Por qué |
|---|---|---|
| `rpm -q bind` | ¿Está instalado el paquete? | Idempotencia |
| `dnf -y install bind bind-utils` | Instala el servidor (`bind`) y las herramientas (`dig`, `host`, `nslookup`) | Necesita repositorios: VM registrada o ISO como repo |
| `cp -a /etc/named.conf /etc/named.conf.lab-orig` | Copia del original, solo la primera vez | Siempre poder volver atrás |
| `date +%y%m%d%H%M` | Genera el **serial** de la zona (AAMMDDhhmm) | El serial debe **subir** en cada cambio: es como los secundarios saben que la zona cambió |
| `install -m 0640 -o root -g named named.conf /etc/named.conf` | Instala el fichero con permisos y propietario | `named` corre como usuario `named`: necesita poder leerlo |
| `sed "s/@@SERIAL@@/$SERIAL/" plantilla > /var/named/lab.local.zone` | Genera la zona a partir de la plantilla | |
| `restorecon -R /etc/named.conf /var/named` | Etiquetas SELinux (`named_conf_t`, `named_zone_t`) | Sin ellas, `named` no puede leer las zonas aunque los permisos sean correctos |
| `named-checkconf -z /etc/named.conf` | Valida `named.conf` y, con `-z`, **carga de prueba** todas las zonas | Si falla, el script se para **antes** de reiniciar `named` |
| `named-checkzone lab.local /var/named/lab.local.zone` | Valida una zona concreta | Detecta errores típicos: falta el punto final, registros duplicados, serial |
| `firewall-cmd --permanent --add-service=dns` + `--reload` | Abre 53/udp y 53/tcp de forma persistente | DNS usa UDP normalmente y TCP para respuestas grandes y transferencias |
| `systemctl enable named` / `restart named` | Habilita y reinicia | |
| `dig +short @127.0.0.1 dns01.lab.local` | Consulta A al propio servidor | Prueba local, sin depender de la red |
| `dig +short @127.0.0.1 -x 10.10.10.13` | Consulta inversa (PTR) | `-x` construye solo el nombre `13.10.10.10.in-addr.arpa` |

**Puntos clave de `named.conf`:**

- `listen-on port 53 { 127.0.0.1; 10.10.10.20; };` — dónde escucha.
- `allow-query` / `allow-recursion { localhost; 10.10.10.0/24; };` — solo responde al laboratorio
  (un DNS abierto a todo el mundo se usa para ataques de amplificación).
- `forwarders { 10.10.10.1; }; forward first;` — lo que no es `lab.local` se pregunta al dnsmasq de
  libvirt; si no responde, intenta resolverlo él mismo.
- `zone "lab.local" { type master; file "lab.local.zone"; };` — zona directa (nombre → IP).
- `zone "10.10.10.in-addr.arpa" ...` — zona inversa (IP → nombre).

**Puntos clave de las zonas:**

- `SOA`: servidor primario, contacto (`hostmaster.lab.local.` = `hostmaster@lab.local`), serial y tiempos.
- Los nombres completos terminan en **punto** (`dns01.lab.local.`). Sin el punto, BIND añade el
  nombre de la zona: `dns01.lab.local.lab.local.` (caso 05).
- `A` = nombre → IPv4. `PTR` = IP → nombre. `NS` = servidor de la zona.

### 3.2 `02-setup-chrony.sh` — hora jerárquica

| Comando | Qué hace | Por qué |
|---|---|---|
| `cp -a /etc/chrony.conf /etc/chrony.conf.lab-orig` | Copia del original | |
| `sed -i '/^# BEGIN lab-chrony/,/^# END lab-chrony/d'` | Borra el bloque propio de una ejecución anterior | Idempotencia: ejecutar dos veces no duplica líneas |
| `sed -i -E 's/^(pool\|server)[[:space:]]+/#lab-disabled# \1 /'` | (Cliente) comenta las fuentes originales | Reversible: se sabe qué líneas comentó el script |
| `server 10.10.10.20 iburst` | (Cliente) única fuente: `dns01` | `iburst` = varias consultas rápidas al arrancar para sincronizar antes |
| `allow 10.10.10.0/24` | (Servidor) permite que la red del lab le pida la hora | Por defecto chrony **no** sirve hora a nadie |
| `local stratum 10` | (Servidor) sigue sirviendo hora aunque pierda Internet | Stratum alto = "fuente poco fiable", pero mantiene el lab coherente |
| `firewall-cmd --permanent --add-service=ntp` + `--reload` | (Servidor) abre 123/udp | |
| `systemctl restart chronyd` | Aplica la configuración | |
| `chronyc -a makestep` | Corrige el reloj **de golpe** si el desfase es grande | Por defecto chrony corrige poco a poco (slew) |
| `chronyc tracking` | Estado de la sincronización: fuente, stratum, desfase, `Leap status` | `Leap status : Normal` = sincronizado |
| `chronyc sources` | Fuentes y su estado | `^*` = fuente seleccionada; `^?` = sin respuesta |
| `timedatectl` | Resumen: zona horaria, NTP activo, reloj sincronizado | |

### 3.3 `03-ssh-hardening.sh` — endurecimiento de SSH y SFTP enjaulado

| Comando | Qué hace | Por qué |
|---|---|---|
| `id -nG adminlab \| grep -qw sysadmins` | ¿adminlab está en `sysadmins`? | `AllowGroups` lo exigirá: si no, te quedarías fuera |
| `[[ -s /home/adminlab/.ssh/authorized_keys ]]` | ¿Tiene clave pública? | Se va a desactivar la contraseña |
| `cp -a sshd_config sshd_config.lab-bak.<fecha>` | Copia con marca de tiempo | Vía de recuperación por consola |
| `groupadd -g 2005 sftponly` / `useradd -M -u 1005 -g sftponly -d /upload -s /sbin/nologin sftpdemo` | Usuario solo-SFTP | `-M` sin home real; `-d /upload` es relativo a la jaula; `nologin` impide shell |
| `install -d -m 0755 -o root -g root /srv/sftp/sftpdemo` | Raíz de la jaula | `ChrootDirectory` exige que la jaula y sus padres sean de **root** y **no escribibles** por otros |
| `install -d -m 0770 -o sftpdemo -g sftponly .../upload` | Subdirectorio donde sí puede escribir | |
| `install -m 0644 ... /etc/ssh/lab-keys/sftpdemo` | Clave pública fuera de la jaula | `AuthorizedKeysFile /etc/ssh/lab-keys/%u` |
| `semanage fcontext -a -t user_home_t '/srv/sftp/[^/]+/upload(/.*)?'` | Regla SELinux **persistente** para esa ruta | `chcon` se perdería con el próximo `restorecon` |
| `restorecon -R /srv/sftp` | Aplica la regla | |
| `setsebool -P ssh_chroot_rw_homedirs on` | Booleano SELinux persistente (`-P`) | Permite escribir dentro de un chroot de SFTP |
| Directivas globales | `PermitRootLogin no`, `PasswordAuthentication no`, `MaxAuthTries 3`, `LoginGraceTime 30`, `X11Forwarding no`, `ClientAliveInterval 300`, `AllowGroups ...`, `UseDNS no` | Solo claves, sin root, pocos intentos, sesiones inactivas cerradas, solo grupos autorizados |
| `Match Group sftponly` + `ChrootDirectory /srv/sftp/%u` + `ForceCommand internal-sftp` | Bloque solo para ese grupo | `Match` va **al final**: todo lo que sigue pertenece al bloque |
| `grep -Eq '^[[:space:]]*Include' sshd_config` | ¿Soporta drop-ins? | RHEL 9/10 sí → `sshd_config.d/00-lab-hardening.conf`; RHEL 7/8 no → bloque en el fichero principal |
| `sshd -t` | Valida la configuración **sin aplicarla** | Si falla, el script restaura la copia y no recarga |
| `systemctl reload sshd` | Relee la configuración | `reload`, no `restart`: las sesiones abiertas siguen vivas |
| `sshd -T` | Muestra la configuración **efectiva** (todos los valores, ya resueltos) | La verdad final, tras drop-ins y valores por defecto |

**Por qué el drop-in se llama `00-...`:** sshd se queda con el **primer** valor que encuentra para
cada directiva. Con `00-` se lee antes que `50-redhat.conf` y `01-permitrootlogin.conf`.

### 3.4 `lab.sh host-dns` — resolver `*.lab.local` desde el host (no persistente)

| Comando | Qué hace |
|---|---|
| `resolvectl dns virbr-lab 10.10.10.20` | Usa `dns01` como DNS de esa interfaz |
| `resolvectl domain virbr-lab '~lab.local'` | Solo para el dominio `lab.local` (`~` = dominio de enrutado, no de búsqueda) |
| `resolvectl mdns virbr-lab no` / `llmnr virbr-lab no` | Desactiva mDNS y LLMNR en ese bridge |
| `resolvectl query dns01.lab.local` | Prueba la resolución |

---

## 4. Comandos de los tests, explicados

Se lanzan con `scripts/lab.sh test all <host|all>`. `run_all.sh` los añade a partir de `LAB_STAGE=4`.
Todos son de **solo lectura**.

### 4.1 `test_dns.sh`

| Comprobación | Comando manual equivalente | Qué demuestra |
|---|---|---|
| (dns01) `named` activo y habilitado | `systemctl is-active named; systemctl is-enabled named` | |
| (dns01) Configuración válida | `named-checkconf -z /etc/named.conf` | Config y zonas cargan |
| (dns01) Escucha en 53 UDP y TCP | `ss -lun \| grep :53`, `ss -ltn \| grep :53` | |
| (dns01) firewalld permite `dns` | `firewall-cmd --list-services` | |
| Registro A de cada host | `dig +short +time=2 +tries=1 @10.10.10.20 rhel9-app01.lab.local` | `+time`/`+tries` evitan esperas largas si falla |
| Registro PTR de cada IP | `dig +short @10.10.10.20 -x 10.10.10.13` | La inversa coincide con la directa |
| `kvm-host.lab.local` → `.1` | `dig +short @10.10.10.20 kvm-host.lab.local` | |
| Resolución externa | `dig +short @10.10.10.20 redhat.com` | El forwarder funciona |
| El sistema usa `dns01` | `getent hosts dns01` | El cliente resuelve igual que las aplicaciones |

### 4.2 `test_time.sh`

| Comprobación | Comando manual equivalente | Qué demuestra |
|---|---|---|
| `chronyd` activo y habilitado | `systemctl is-active chronyd` | |
| `Leap status : Normal` | `chronyc tracking` | Sincronizado |
| Reloj sincronizado | `timedatectl` | El texto varía según versión: `NTP synchronized` (RHEL 7) o `System clock synchronized` |
| Desfase < 1 s | `chronyc tracking` (línea `System time`) | |
| Zona horaria configurada | `timedatectl` (`Time zone: Europe/Madrid`) | |
| (dns01) `allow 10.10.10.0/24` | `grep allow /etc/chrony.conf` | Sirve hora al lab |
| (dns01) firewalld permite `ntp` | `firewall-cmd --list-services` | |
| (cliente) Única fuente = `10.10.10.20` | `grep -E '^(pool\|server)' /etc/chrony.conf` | No hay otras fuentes activas |
| (cliente) `^*` en `10.10.10.20` | `chronyc -n sources` | `-n` = sin resolver nombres; `^*` = fuente elegida |

### 4.3 `test_ssh.sh`

| Comprobación | Comando manual equivalente | Qué demuestra |
|---|---|---|
| Configuración válida | `sshd -t` | |
| Escucha en 22/tcp | `ss -ltn \| grep ':22 '` | |
| Clave de host ed25519 | `ls -l /etc/ssh/ssh_host_ed25519_key` | |
| `.ssh` 700 y `authorized_keys` 600 | `stat -c %a ~adminlab/.ssh ~adminlab/.ssh/authorized_keys` | `StrictModes` rechaza permisos más abiertos (caso 02) |
| Etiqueta `ssh_home_t` | `ls -Z ~adminlab/.ssh/authorized_keys` | SELinux deja a `sshd` leerla |
| Valores efectivos (×5) | `sshd -T \| grep -E '^(permitrootlogin\|passwordauthentication\|pubkeyauthentication\|maxauthtries\|x11forwarding) '` | Lo **aplicado**, no lo escrito |
| `AllowGroups` incluye `sysadmins` | `sshd -T \| grep -i allowgroups` | |
| `sftpdemo` UID 1005, grupo `sftponly` | `id sftpdemo` | |
| Jaula `root:755` | `stat -c %U:%a /srv/sftp/sftpdemo` | |
| `Match` aplicado a `sftpdemo` | `sshd -T -C user=sftpdemo,host=lab,addr=10.10.10.1 \| grep -Ei 'forcecommand\|chrootdirectory'` | `-C` simula una conexión concreta para evaluar los `Match` (caso 07) |

---

## 5. Comandos de diagnóstico de los casos reales

| Comando | Qué hace | Caso |
|---|---|---|
| `dig @10.10.10.20 <nombre>` | Pregunta directamente a `dns01` | 01 — `connection refused` o timeout = servidor caído |
| `nc -zvu 10.10.10.20 53` | Prueba el puerto 53/udp | 01 |
| `ss -lun \| grep :53` (en dns01) | ¿Algo escucha en el 53? | 01 — vacío = `named` parado |
| `systemctl status named` / `journalctl -u named -n 30` | Estado y log del servidor | 01/05 |
| `ssh -vvv -i <clave> usuario@ip` | Cliente detallado: qué claves ofrece y qué responde el servidor | 02 |
| `tail -n 20 /var/log/secure` | Log de autenticación en el servidor | 02 — `bad ownership or modes for directory` |
| `namei -l ~/.ssh/authorized_keys` | Permisos de cada componente de la ruta | 02 — home escribible por otros |
| `restorecon -Rv ~/.ssh` | Repone etiquetas SELinux mostrando qué cambia (`-v`) | 02 (variante SELinux) |
| `chronyc sources -v` / `sourcestats` | Fuentes con leyenda explicada (`-v`) y estadísticas | 03 |
| `tcpdump -ni any udp port 123` | Tráfico NTP | 03 — salen peticiones, no vuelven respuestas |
| `chronyc clients` (en dns01) | Qué clientes le han pedido la hora | 03 |
| `chronyc makestep` | Corrige el desfase de golpe | 03 |
| `rndc reload` | Recarga zonas sin reiniciar `named` | 04/05 |
| `grep <host> /var/named/*.zone /var/named/*.rev` | Comparar directa e inversa | 04 |
| `ls -lZ /var/named/` | Propietario `root:named` y tipo `named_zone_t` | 05 |
| `nmcli -f ipv4.dns con show lab0` frente a `cat /etc/resolv.conf` | Lo **configurado** frente a lo **aplicado** | 06 — distintos en RHEL 8 tras `reapply` |
| `nmcli con up lab0` | Reactivar el perfil para aplicar el DNS | 06 — solución |
| `sshd -T -C user=...,host=...,addr=...` | Configuración efectiva para un usuario concreto | 07 |

---

## 6. Chuleta: síntoma → primeros comandos

| Síntoma | Primeros comandos |
|---|---|
| Nada resuelve nombres del lab | `cat /etc/resolv.conf`, `dig @10.10.10.20 dns01.lab.local`, en dns01 `systemctl status named` |
| Un nombre resuelve a una IP incorrecta | `dig @10.10.10.20 <nombre> +short`, `grep <nombre> /var/named/lab.local.zone` |
| He editado la zona y no cambia nada | ¿Subiste el serial? `named-checkzone ...` y `rndc reload` |
| `named` no arranca | `named-checkconf -z /etc/named.conf`, `journalctl -u named -n 50`, `ls -lZ /var/named` |
| `nmcli` dice un DNS y `resolv.conf` otro | `nmcli con up lab0` |
| La hora no se sincroniza | `chronyc sources -v`, `chronyc tracking`, en dns01 `firewall-cmd --list-services` |
| `Permission denied (publickey)` | `ssh -vvv`, `/var/log/secure`, `namei -l ~/.ssh/authorized_keys`, `ls -Z` |
| Me he quedado fuera tras tocar sshd | `virsh console <vm>`, restaurar `sshd_config.lab-bak.*`, `sshd -t`, `systemctl reload sshd` |
| Un cambio en `sshd_config` no tiene efecto | `sshd -T` (¿otro fichero lo define antes?), ¿se hizo `reload`? |

---

## 7. Preguntas de repaso

1. ¿Qué diferencia hay entre una zona directa y una inversa?
2. ¿Para qué sirve el serial del SOA y qué pasa si no se sube?
3. ¿Qué ocurre si falta el punto final en `dns01.lab.local.`?
4. ¿Qué diferencia hay entre `named-checkconf -z` y `named-checkzone`?
5. ¿Por qué se limita `allow-recursion` a la red del laboratorio?
6. ¿Qué significan `^*` y `^?` en `chronyc sources`?
7. ¿Qué diferencia hay entre `chronyc makestep` y la corrección normal de chrony?
8. ¿Por qué `systemctl reload sshd` y no `restart` al endurecer SSH?
9. ¿Por qué sshd se queda con el primer valor y qué implica para los drop-ins?
10. ¿Por qué la jaula de `ChrootDirectory` debe ser de root y no escribible?
11. ¿Qué diferencia hay entre `semanage fcontext` + `restorecon` y `chcon`?
12. ¿Qué diferencia hay entre `sshd -t` y `sshd -T`?
