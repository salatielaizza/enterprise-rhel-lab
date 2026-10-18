# Etapa N2 — SIEM: Graylog, OpenSearch/Elasticsearch, Syslog, NXLog, contenedores y VMware

> **Prueba práctica y adelanto de tecnologías.** Monta en el lab un SIEM completo sobre entornos virtualizados
> y contenedores, alimentado por las VMs que ya existen (Etapas 1-8), y practica su operación, su
> troubleshooting y su documentación. Adelanta parte de las Etapas 12 (migraciones VMware → KVM),
> 16 (monitorización), 17 (Docker) y 18 (Kubernetes), que mantienen su planificación completa.
>
> **Estado: 📝 Planificada.** Automatización, tests y guía escritos y validados en estático (sintaxis,
> `shellcheck`, `yamllint`, `ansible-lint`, `docker compose config`, `kubeconform` y pruebas de las
> herramientas en Python contra un servidor simulado). Pendiente de ejecutar en las VMs reales: cada fallo
> real que aparezca se documenta como caso en `troubleshooting/etapaN2/`.

## Objetivo

Operar un SIEM de punta a punta como se hace en un equipo de infraestructura:

| Área | Qué se practica |
|---|---|
| SIEM | Graylog 7 (entradas, streams, *pipelines*, alertas, retención), OpenSearch como almacén y Elasticsearch 9 por su API |
| Ingesta | **Syslog** (rsyslog, RFC 5424, TCP con cola en disco), **GELF**, **NXLog CE** (auditd), **Fluent Bit** (Kubernetes) |
| Contenedores | **Docker** y Docker Compose en RHEL 9 con SELinux; **Kubernetes** (k3s) con un DaemonSet de logs |
| Automatización | **Bash** (scripts idempotentes con `lab.sh`), **Python** (API REST, GELF, detección), **Ansible** (rsyslog en todo el lab, con *rollback*) |
| Virtualización | **VMware ESXi/vCenter**: exportar, importar y convertir VMs (VMDK, OVF/OVA, `vmkfstools`, `virt-v2v`, `govc`) |
| Infraestructura | Física (RAM, disco, CPU del host), virtual (KVM, redes libvirt, ESXi anidado) y de conectividad (puertos, NAT, MTU, DNS, hora) |
| Ciberseguridad | Sin credenciales por defecto, secretos fuera del repo, mínima exposición, SELinux, mínimo privilegio, hora fiable, retención |

## Arquitectura

```text
                     Host KVM (Linux Mint) 10.10.10.1 ── navegador: http://10.10.10.55:9000
                                   │ lab-net 10.10.10.0/24
   ┌───────────────┬───────────────┼───────────────┬──────────────┬──────────────────────────────┐
 rhel7/8/10-app01   rhel9-app01     dns01           ansible01      siem01 10.10.10.55 (RHEL 9 · 4 vCPU · 10 GB · 80 GB)
 rsyslog ──┐        rsyslog ──┐     rsyslog ──┐     Ansible:       ├─ Docker CE (LV propio /var/lib/docker)
           │        NXLog CE ─┼─┐             │     siem-lab       │   ├─ graylog     :9000 web/API · 5140 Syslog · 12201 GELF
           │        (auditd)  │ │             │     (rsyslog del   │   ├─ opensearch  127.0.0.1:9200  (almacén)
           │                  │ │             │      lab entero)   │   ├─ mongodb     sin puerto en el host (configuración)
           └── Syslog TCP 5140┴─┼─────────────┴───────────────────►│   └─ elasticsearch 127.0.0.1:9201 (perfil opcional)
                                └──── GELF TCP 12201 ─────────────►└─ k3s (LV propio /var/lib/rancher)
                                                                       ├─ logging/fluent-bit (DaemonSet) ── GELF TCP ──► graylog
                                                                       └─ demo/pagos-demo (app que genera logs)
 VMware (Etapa 8): esxi01 .60 (gratuito) · esxi02/03 + vcsa01 (evaluación) ◄── VMDK / OVA / virt-v2v ──► KVM (host)
```

| Flujo | Origen → destino | Protocolo | Para qué |
|---|---|---|---|
| Syslog | rsyslog de las VMs → `siem01:5140/tcp` | RFC 5424 sobre TCP, cola en disco | Logs del sistema (sshd, sudo, systemd...) |
| GELF | NXLog (`rhel9-app01`) → `siem01:12201/tcp` | JSON terminado en byte nulo | Eventos de auditd con campos extraídos |
| GELF | Fluent Bit (k3s) → `siem01:12201/tcp` | Ídem | Logs de pods con namespace, pod y nodo |
| GELF | `gelf_send.py` → `siem01:12201/udp` | JSON comprimido y troceado | Pruebas y alertas generadas por scripts |
| REST | scripts → Graylog `127.0.0.1:9000/api` | HTTP + JSON | Entradas, estado, automatización |
| REST | scripts → OpenSearch `127.0.0.1:9200` | HTTP + JSON (API de Elasticsearch) | Consultas, agregaciones, comprobaciones |

## Recursos y orden de trabajo

| Recurso | Valor | Comentario |
|---|---|---|
| `siem01` | 4 vCPU · 10 GB RAM · 80 GB (qcow2 *thin*) | OpenSearch 1 GB de *heap*, Graylog ~1,5 GB, MongoDB 0,5 GB de caché, k3s ~0,7 GB |
| VMs encendidas | `dns01`, `ansible01`, `siem01`, `rhel9-app01` (+ el resto de `app01` si hay margen) | ≈ 18-26 GB de los 31 GB del host |
| Disco real estimado | 12-20 GB | Imágenes ~3 GB + índices; crece con la retención |
| Etapa 8 (VMware) | Solo para la parte B del bloque 8 | Fase A (`esxi01`) basta; la fase B nunca a la vez que `siem01` (RAM) |

Orden recomendado (cada bloque deja algo funcionando y verificable): 0 → 1 → 2 → 3 → 4 → 6 → 5 → 7 → 8 → 9 → 10.
Los bloques 0-4 y 6 son el núcleo; 5, 7 y 8 amplían; 9 y 10 se repasan sobre lo ya montado.

**Regla de trabajo de toda la etapa:** cada bloque se hace primero **a mano** (para entenderlo) y después con
su comando de `lab.sh` (para repetirlo igual). Lo que falle de verdad se documenta como caso en
`troubleshooting/etapaN2/` con la plantilla del proyecto.

---

## Bloque 0 — VM `siem01`

`siem01` está en `scripts/hosts.conf` como host **opcional** (8.ª columna): `lab.sh … all` no la incluye
(así `test all all` o `up all` no fallan si está apagada), pero funciona por nombre en cualquier comando.

```bash
# 1. DNS: las plantillas ya traen siem01 (A + PTR) y el alias graylog.lab.local
scripts/lab.sh stage4-dns
dig @10.10.10.20 siem01.lab.local +short ; dig @10.10.10.20 -x 10.10.10.55 +short

# 2. Alias SSH (lab_config se generó en la Etapa 1, antes de existir siem01)
grep -q '^Host siem01$' ~/.ssh/lab_config || printf 'Host siem01\n  HostName 10.10.10.55\n  User adminlab\n  IdentityFile ~/.ssh/lab_ed25519\n  IdentitiesOnly yes\n  UserKnownHostsFile ~/.ssh/known_hosts_lab\n  StrictHostKeyChecking accept-new\n\n' >> ~/.ssh/lab_config

# 3. Crear e integrar la VM con la MISMA base que el resto del lab (usuarios, red, DNS, hora, SSH, SELinux)
scripts/lab.sh vm-create siem01 --dry-run
scripts/lab.sh vm-create siem01
scripts/lab.sh register siem01 <usuario-RH>
scripts/lab.sh stage2 siem01 && scripts/lab.sh stage3 siem01 && scripts/lab.sh stage4-clients siem01 && scripts/lab.sh stage5 siem01
scripts/lab.sh test all siem01                 # base del lab en 0 FAIL antes de añadir nada
scripts/lab.sh snapshot create siem01 5        # punto de retorno: siem01-stage5-complete
scripts/lab.sh siem-preflight                  # auditoría de solo lectura para esta etapa
```

**Por qué la base de seguridad primero:** un SIEM concentra los logs de todo el entorno; es uno de los
sistemas que más protección necesita. Entra en servicio ya endurecido (SELinux Enforcing, SSH solo con
clave, auditd, `pwquality`), no se endurece después.

---

## Bloque 1 — Docker en RHEL 9

### Teoría mínima

- **Imagen** (plantilla de solo lectura, por capas) · **contenedor** (imagen en ejecución + capa de escritura) ·
  **volumen** (datos que sobreviven al contenedor) · **red** (los contenedores de una red se ven por nombre).
- Un contenedor **comparte el kernel** del host: se aísla con *namespaces*, se limita con *cgroups* y, en RHEL,
  se confina con **SELinux** (tipo `container_t`, etiquetas MCS distintas por contenedor).
- **Docker** usa un demonio (`dockerd`) como root; **Podman** (el de Red Hat) no tiene demonio y funciona *rootless*.
  Los comandos son casi iguales; en RHEL, Docker CE viene del repositorio de Docker, no de Red Hat.
- **Compose** describe varios contenedores, redes y volúmenes en un YAML: es la forma de desplegar el SIEM.
- Pertenecer al grupo `docker` **equivale a ser root** en ese host (se puede montar `/` en un contenedor).

### Práctica

A mano, para entender cada paso (es lo que hace `01-docker-host.sh`):

```bash
ssh siem01
sudo vgs vg_system                                  # espacio libre del VG (el kickstart deja /var en 4 GB)
sudo lvcreate -n lv_docker -L 35G vg_system && sudo mkfs.xfs /dev/vg_system/lv_docker
sudo blkid /dev/vg_system/lv_docker                 # UUID para fstab (nunca /dev/dm-N)
# ... fstab por UUID, mount, y:
sudo restorecon -Rv /var/lib/docker ; ls -Zd /var/lib/docker
```

Con el script (idempotente, con copias de seguridad):

```bash
scripts/lab.sh siem-docker
ssh siem01 'docker info --format "{{.ServerVersion}} {{.Driver}} {{.SecurityOptions}}"; df -h /var/lib/docker /var/lib/rancher'
```

Ejercicio de contenedores básico (en `siem01`, como `adminlab`, tras volver a entrar para que cuente el grupo):

```bash
docker run --rm hello-world
docker run -d --name web -p 127.0.0.1:8081:80 nginx:1.27 && curl -s 127.0.0.1:8081 | head -3
docker exec web cat /etc/os-release ; docker logs web ; docker inspect -f '{{.ProcessLabel}}' web   # etiqueta SELinux
docker rm -f web
```

### Verificación

`scripts/lab.sh test test_siem.sh siem01` (sección de host: LV propio, etiqueta SELinux, Docker activo,
`selinux-enabled`, rotación de logs, `vm.max_map_count`).

### Avería provocada (troubleshooting)

1. **Etiqueta SELinux incorrecta.** Hazla **antes** de `siem-stack` (o con snapshot `siem01-stage5-complete`).
   `sudo chcon -R -t var_lib_t /var/lib/docker && sudo systemctl restart docker`
   → observa el fallo (`journalctl -u docker -n 30`, `sudo timeout 20 ausearch -m AVC -ts recent`), arréglalo con
   `restorecon -R /var/lib/docker` y explica por qué `chcon` no sobrevive a un *relabel* y `semanage fcontext` sí.
   **Si el stack ya está desplegado**, `restorecon` no basta: los volúmenes y la capa escribible de cada
   contenedor llevan `container_file_t` con categorías MCS que pone **Docker** al crearlos, no la política.
   Hay que recrearlos (borra los datos del SIEM; el `.env` se conserva):
   `sudo docker compose --project-directory /opt/siem down -v && sudo restorecon -R /var/lib/docker && scripts/lab.sh siem-stack`
   (caso [`etapaN2/04`](../troubleshooting/etapaN2/04-chcon-con-stack-desplegado-restorecon-no-basta.md)).
2. **Disco lleno.** Calcula cuánto tardaría en llenarse un `/var` de 4 GB a 1.000 mensajes/s de 500 bytes y
   anota por qué el script separa `/var/lib/docker` en su propio LV (y cómo crecería: `lvextend -r -L +10G`).

---

## Bloque 2 — Graylog + OpenSearch + MongoDB (y Elasticsearch)

### Teoría mínima

- **SIEM** (*Security Information and Event Management*): recoge eventos de muchas fuentes, los **normaliza**,
  los guarda con **retención**, permite **buscar** y **correlacionar**, y **alerta**. Graylog cubre la gestión
  de logs y la parte de seguridad (streams, *pipelines*, Event Definitions); en otras empresas el papel lo
  hacen Splunk, Elastic Security, QRadar, Wazuh o Microsoft Sentinel.
- **Piezas de Graylog**: *inputs* (reciben) → *extractors/pipelines* (procesan) → *streams* (clasifican) →
  *index sets* (guardan, rotan y borran) → búsquedas, dashboards y alertas.
- **MongoDB** guarda la **configuración** (usuarios, entradas, streams); **OpenSearch** guarda los **mensajes**.
- **OpenSearch** nace en 2021 como *fork* de Elasticsearch 7.10 y mantiene su API REST (`_search`, `_cat`,
  `_bulk`...). **Graylog 7 solo admite OpenSearch** (o su Data Node, que lo empaqueta) como almacén; por eso
  Elasticsearch 9 va aparte, en un perfil opcional, para practicar su API directamente.
- **Índices y shards**: un índice se reparte en *shards*; con un solo nodo, las réplicas no se pueden asignar
  (estado `yellow`, normal en el lab). Graylog escribe siempre en el índice activo (`graylog_deflector`) y
  **rota** (por tiempo o tamaño) y **borra** según la retención: así se controla el disco.
- **JVM heap**: OpenSearch y Elasticsearch, como mucho el 50 % de la RAM que se les quiera dar (el resto es
  caché de ficheros del sistema), y nunca más de ~31 GB.

### Práctica

```bash
scripts/lab.sh siem-stack                  # o: siem-stack --with-elastic (≈ +1,5 GB de RAM)
ssh siem01 'sudo cat /root/.siem/graylog-admin.txt'     # contraseña de admin, generada (nunca "admin")
# Navegador del host: http://10.10.10.55:9000  (o http://graylog.lab.local:9000 si el host resuelve lab.local)
```

Lo que hace `02-graylog-stack.sh`, para poder repetirlo a mano: copia `files/graylog/docker-compose.yml` a
`/opt/siem`, genera `/opt/siem/.env` (0600) con secretos aleatorios **solo si no existe**, valida con
`docker compose config`, descarga las imágenes con versión fijada, arranca y espera a que
`/api/system/lbstatus` responda `ALIVE`.

Operación diaria del stack (en `siem01`, `cd /opt/siem` con `sudo -i`; `/opt/siem` es `root` 0750 porque guarda
el `.env`. Sin entrar: `sudo docker compose --project-directory /opt/siem ps`):

```bash
docker compose ps                          # estado y healthchecks
docker compose logs -f --tail 50 graylog   # logs de un servicio
docker stats --no-stream                   # CPU y RAM reales de cada contenedor
docker compose restart graylog             # reinicio de un servicio
docker compose pull && docker compose up -d   # actualización controlada (tras cambiar la versión en el compose)
curl -s 127.0.0.1:9200/_cluster/health?pretty
curl -s '127.0.0.1:9200/_cat/indices?v&s=index'
curl -s '127.0.0.1:9200/_cat/shards?v' | head
/opt/siem/tools/os_search.py health ; /opt/siem/tools/os_search.py indices
```

Elasticsearch (si se arrancó con `--with-elastic`):

```bash
P=/root/.siem/elastic.txt; T=/opt/siem/tools/os_search.py
sudo $T --url http://127.0.0.1:9201 --user elastic --password-file $P health
sudo $T --url http://127.0.0.1:9201 --user elastic --password-file $P ingest-demo --count 200
sudo $T --url http://127.0.0.1:9201 --user elastic --password-file $P --index lab-demo top --field level --minutes 60
sudo $T --url http://127.0.0.1:9201 --user elastic --password-file $P --index lab-demo search --query 'level:ERROR' --fields timestamp,host,message
curl -s -u "elastic:$(sudo cat $P)" '127.0.0.1:9201/_cat/indices?v'     # misma API que OpenSearch
```

Configuración en la web (anótala en el checklist):

- **System > Indices > Default index set**: rotación diaria (`P1D`), retención 7 índices, 1 shard, 0 réplicas
  (un nodo). Calcula: mensajes/día × tamaño medio × días = disco necesario.
- **System > Users and Teams**: un usuario `analista` con rol *Reader* (mínimo privilegio) y crea un **token** de API
  para scripts en lugar de usar la contraseña de admin.

### Avería provocada

1. **`vm.max_map_count` bajo.** `sudo sysctl -w vm.max_map_count=65530 && docker compose restart opensearch`
   → `docker compose logs opensearch` muestra el error del *bootstrap check*. Restaura con `sysctl --system`.
2. **Graylog sin OpenSearch.** `docker compose stop opensearch` → observa la web (aviso de índices), el
   *journal* de Graylog creciendo (**System > Nodes**) y que **no se pierden** los mensajes: al arrancar
   OpenSearch se vacía el *journal*. Explica por qué existe.
3. **Disco del índice.** Rellena con `gelf_send.py --count 50000` y mira `_cat/indices`; fuerza una rotación desde
   **System > Indices > Maintenance** y comprueba qué índice pasa a ser el activo.

---

## Bloque 3 — Entradas de Graylog y Python

### Teoría mínima

- **Entrada (*input*)** = puerto + protocolo + formato. Puertos > 1024 porque Graylog no corre como root.
- **Syslog**: RFC 3164 (antiguo, sin año ni zona) y RFC 5424 (estructurado, con zona horaria). UDP 514 es el
  clásico (rápido, **sin garantía de entrega**); TCP permite colas y reintentos; TLS (6514) cifra.
- **GELF**: JSON con `version`, `host`, `short_message`, `timestamp`, `level` y campos propios con `_`.
  Por UDP se comprime (zlib) y se **trocea** (máx. 128 trozos); por TCP va sin comprimir y cada mensaje termina en `\0`.
- **API REST de Graylog**: autenticación básica (usuario o *token*), cabecera `X-Requested-By` en toda petición
  que cambia algo (protección CSRF), documentación interactiva en **System > Nodes > API browser**.

### Práctica

```bash
scripts/lab.sh siem-inputs        # crea/arranca las 4 entradas y hace una prueba de extremo a extremo
```

En `siem01` (`sudo -i`; herramientas en `/opt/siem/tools`, solo biblioteca estándar de Python):

```bash
cd /opt/siem/tools
./graylog_inputs.py --password-file /root/.siem/graylog-admin.txt --list
./gelf_send.py --host 10.10.10.55 --proto udp --message "hola GELF" --field app=pagos --level 3
./gelf_send.py --host 10.10.10.55 --proto udp --big 20000          # fuerza el troceado UDP
./gelf_send.py --host 10.10.10.55 --proto tcp --count 100 --field app=lote
./os_search.py search --query 'app:pagos' --minutes 15 --fields timestamp,source,level,message
./os_search.py top --field app --minutes 60
logger --server 10.10.10.55 --port 5140 --udp --rfc5424 "syslog por UDP desde $(hostname -s)"
```

Lee los cuatro scripts (`graylog_inputs.py`, `gelf_send.py`, `os_search.py`, `detect_bruteforce.py`): están
comentados para estudiar cómo se habla con una API REST con `urllib`, cómo se construye un protocolo binario
sencillo (cabecera GELF de trozos) y cómo se hace una agregación `terms` en OpenSearch.

### Avería provocada

1. **Entrada parada.** Para `lab-gelf-tcp-12201` en **System > Inputs** y lanza `gelf_send.py --proto tcp`:
   conexión rechazada. Con `--proto udp` el script dice "enviado"... y el mensaje no llega. Explica la diferencia.
2. **Sin `X-Requested-By`.** Repite con `curl` un `POST /api/system/inputs` sin esa cabecera y anota el error.
3. **Mensaje sin campo obligatorio.** Envía con `nc` un JSON sin `short_message` al 12201/tcp
   (`printf '{"version":"1.1","host":"x"}\0' | nc 10.10.10.55 12201`) y búscalo en **System > Nodes > Metrics / logs del servidor**.

---

## Bloque 4 — Syslog de todo el lab con rsyslog y Ansible

### Teoría mínima

- En RHEL, `journald` recoge los logs y **rsyslog** los escribe en `/var/log` y los **reenvía** (`omfwd`).
- **Cola de acción** (`queue.type="LinkedList"` + `queue.filename`): si el SIEM no responde, los mensajes
  esperan en memoria y en disco y se envían al volver; sin cola, se pierden o bloquean.
- **SELinux** solo deja a rsyslog (`syslogd_t`) conectar a puertos `syslogd_port_t`: el 5140 hay que etiquetarlo
  (`semanage port -a -t syslogd_port_t -p tcp 5140`). Es el fallo clásico de "en una VM con SELinux no reenvía".
- Ansible aplica lo mismo a RHEL 7, 8, 9 y 10, de forma **idempotente** y **reversible** (`siem_state=absent`).

### Práctica

```bash
scripts/lab.sh siem-forward --check --diff     # qué cambiaría, sin cambiar nada
scripts/lab.sh siem-forward                    # aplicar en el grupo "lab" (app01 x4 + dns01)
scripts/lab.sh siem-forward                    # 2.º pase: changed=0 (idempotencia)
scripts/lab.sh test test_siem.sh all           # agentes: config, SELinux, cola, conectividad
```

A mano en una VM, para ver cada pieza:

```bash
ssh rhel9-app01
cat /etc/rsyslog.d/90-siem-forward.conf
sudo rsyslogd -N1                                   # validar la configuración completa
sudo semanage port -l | grep syslogd_port_t
logger -p authpriv.warning -t prueba "mensaje de prueba $(date +%s)"
sudo ss -tnp | grep 5140                            # conexión establecida de rsyslogd
```

En Graylog: `application_name:siem-test`, `source:dns01`, `application_name:sshd`.

### Avería provocada

1. **SELinux bloquea el reenvío.** En una VM: `sudo semanage port -d -t syslogd_port_t -p tcp 5140 && sudo systemctl restart rsyslog`.
   Genera un `logger` y verás que no llega. Diagnóstico: `sudo timeout 20 ausearch -m AVC -ts recent -c rsyslogd`
   (`name_connect` denegado a `unreserved_port_t`), `sudo journalctl -u rsyslog -n 20`. Arreglo: relanzar el playbook.
2. **SIEM caído y cola.** Apaga `siem01` (`lab.sh down siem01`), genera 50 mensajes en una VM, mira la cola en
   `/var/lib/rsyslog/siem_fwd*`, enciende `siem01` y comprueba en Graylog que llegan los 50 con su hora original.
3. **Rollback.** `scripts/lab.sh siem-forward --limit rhel8-app01 -e siem_state=absent` y comprueba con el test que
   en esa VM ya no aplica; vuelve a aplicarlo.

---

## Bloque 5 — NXLog Community Edition (auditd → GELF)

### Teoría mínima

- **NXLog** es un agente multiplataforma muy usado en **Windows** (lee el Visor de eventos con `im_msvistalog`)
  y también en Linux. Modelo: **Input → Exec (procesado) → Output**, unidos por una **Route**.
- **Community Edition** (gratuita, 3.x) frente a **Enterprise/NXLog Platform** (más módulos: `im_linuxaudit`,
  `im_systemd`, gestión central). Aquí se usa CE con `im_file` y expresiones regulares.
- **Mínimo privilegio**: el agente corre como `nxlog`, no como root; para leer `audit.log` se usa
  `log_group = nxlog` en `auditd.conf` (auditd crea el fichero 0640 con ese grupo), en vez de dar root al agente.

### Práctica

1. Descarga en el host el RPM de NXLog CE para RHEL 9 desde `https://nxlog.co/downloads` (no hace falta cuenta:
   opción de descarga directa). Guárdalo, por ejemplo, en `~/Descargas/rhel-lab/nxlog/`.
2. Despliega el agente:

```bash
scripts/lab.sh siem-nxlog rhel9-app01 ~/Descargas/rhel-lab/nxlog/nxlog-ce-<versión>_rhel9.x86_64.rpm
scripts/lab.sh test test_siem.sh rhel9-app01
```

3. Genera eventos de auditoría que ya vigilan las reglas de la Etapa 5 y búscalos:

```bash
ssh rhel9-app01 'sudo touch /etc/passwd; sudo -l >/dev/null; sudo auditctl -m "marca manual"'
# Graylog: audit_key:lab-identity   ·   audit_type:USER_CMD   ·   SourceName:auditd AND audit_res:failed
```

Configuración: `scripts/stageN2/files/nxlog/nxlog.conf.tpl` (comentada). Comandos útiles en la VM:
`sudo nxlog -v -c /etc/nxlog.conf` (validar), `sudo tail -f /var/log/nxlog/nxlog.log`, `systemctl status nxlog`.

### Avería provocada

1. **Permisos.** Quita el grupo: `sudo chgrp root /var/log/audit/audit.log` → `nxlog.log` muestra el error de
   lectura; `service auditd restart` lo vuelve a corregir (por `log_group`). Explica por qué la solución
   duradera es `log_group` y no un `chmod`.
2. **Configuración inválida.** Pon un comentario al final de una directiva (`Port 12201 # gelf`) y valida con
   `nxlog -v`: verás por qué la plantilla los pone siempre en su propia línea.
3. **Dependencias del RPM.** Si `dnf` no encuentra una dependencia, el script indica habilitar CodeReady Builder:
   documenta qué paquete faltaba y de qué repositorio salió.

---

## Bloque 6 — Detección: streams, pipelines, alertas y correlación

### Teoría mínima

- **Stream**: clasifica mensajes por reglas (p. ej. "todo lo de sshd y sudo") y permite permisos y alertas por stream.
- **Pipeline**: reglas en el lenguaje de Graylog que **normalizan** (extraen campos, renombran, enriquecen).
  Normalizar es lo que permite que una misma regla funcione con logs de orígenes distintos.
- **Event Definition**: búsqueda + agregación + umbral en una ventana de tiempo → evento/alerta → notificación.
- **Caso de uso** típico: fuerza bruta (N fallos de autenticación desde una IP en X minutos), uso de sudo fuera
  de horario, cambios en `/etc/passwd` (regla `lab-identity` de la Etapa 5), errores repetidos de una aplicación.
- **Falsos positivos** y **afinado** (umbral, ventana, listas de exclusión) son la mitad del trabajo de un SIEM.

### Práctica

1. **Stream** "Autenticación": regla `application_name` coincide con la expresión `^(sshd|sudo)$`; marca
   *Remove matches from Default Stream* solo si entiendes el efecto.
2. **Pipeline** "Normalización SSH" conectado al stream *Default Stream*, con esta regla:

```text
rule "sshd: usuario e IP de los fallos"
when
  has_field("application_name") && to_string($message.application_name) == "sshd" &&
  regex("Invalid user (\\S+) from (\\d+\\.\\d+\\.\\d+\\.\\d+)", to_string($message.message)).matches == true
then
  let m = regex("Invalid user (\\S+) from (\\d+\\.\\d+\\.\\d+\\.\\d+)", to_string($message.message));
  set_field("ssh_user", m["0"]);
  set_field("src_ip", m["1"]);
  set_field("event_type", "ssh_auth_failure");
end
```

3. **Simulación de ataque** desde otra VM del lab (usuarios inexistentes; el SSH del lab solo admite claves):

```bash
ssh rhel7-app01 'for i in $(seq 1 8); do ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no noexiste$i@10.10.10.13 true; done; true'
```

4. **Event Definition** "Fuerza bruta SSH": *Filter & Aggregation*, consulta `event_type:ssh_auth_failure`,
   agrupar por `src_ip`, condición `count() >= 5`, ventana 5 min, ejecutar cada 1 min. Revisa **Alerts & Events**.
5. **La misma correlación en Python** (lo que hace el motor del SIEM por dentro, sobre Syslog **y** auditd):

```bash
ssh siem01 'sudo /opt/siem/tools/detect_bruteforce.py --minutes 15 --threshold 5 --notify'
# Graylog: alert_rule:ssh-bruteforce   (level 2 = crítico)
```

6. **Dashboard** "SIEM del lab": mensajes por `source` (barras), fallos SSH por `src_ip` (tabla),
   eventos `audit_key:lab-identity` (contador), logs `level` ERROR de `k8s_namespace_name:demo` (línea temporal).

### Avería provocada

Cambia el umbral a 50 y repite la simulación: la alerta no salta. Documenta cómo afinarías el umbral con datos
reales (cuántos fallos "normales" hay al día) en vez de a ojo.

---

## Bloque 7 — Kubernetes (k3s) y Fluent Bit

### Teoría mínima

- **Pod** (uno o más contenedores), **Deployment** (réplicas y actualizaciones), **DaemonSet** (un pod por nodo:
  justo lo que necesita un agente de logs), **Namespace**, **ConfigMap**, **ServiceAccount + RBAC**.
- **k3s**: Kubernetes certificado en un solo binario, con **containerd** (no Docker) como *runtime*: sus logs están en
  `/var/log/containers/*.log` en **formato CRI** (`<hora> stdout F <texto>`), no en el JSON de Docker.
- **Fluent Bit**: agente ligero; *input* `tail` + *parser* `cri` + *filter* `kubernetes` (añade namespace, pod,
  contenedor y nodo consultando la API) + *output* `gelf`.
- **SELinux con Kubernetes**: un pod normal (`container_t`) no puede leer `/var/log` del nodo; el DaemonSet de logs
  usa `spc_t` (excepción documentada y limitada a ese pod). La app de ejemplo cumple el perfil **restricted** de
  Pod Security (sin root, sin escalada, sin capacidades, sistema de ficheros de solo lectura).

### Práctica

```bash
scripts/lab.sh siem-k8s                         # k3s (--selinux, sin Traefik) + Fluent Bit + pagos-demo
ssh siem01
kubectl get nodes -o wide ; kubectl get pods -A
kubectl -n logging logs ds/fluent-bit --tail 20
kubectl -n demo logs deploy/pagos-demo --tail 5
kubectl -n logging port-forward ds/fluent-bit 2020:2020 &  curl -s 127.0.0.1:2020/api/v1/metrics | head; kill %1
# Graylog: k8s_namespace_name:demo AND "level=ERROR"     ·     k8s_pod_name:pagos-demo*
kubectl -n demo scale deploy/pagos-demo --replicas=3    # 3 pods: 3 fuentes con su k8s_pod_name
```

### Avería provocada

1. **Destino incorrecto.** `kubectl -n logging edit configmap fluent-bit-config` (pon `port: 12202`),
   `kubectl -n logging rollout restart ds/fluent-bit` → `kubectl -n logging logs ds/fluent-bit` muestra los
   reintentos; los logs **esperan en disco** (`storage.type: filesystem`) y llegan al corregirlo.
2. **Sin `spc_t`.** Quita el bloque `seLinuxOptions` del DaemonSet: el pod arranca pero no lee nada.
   Diagnóstico: `sudo timeout 20 ausearch -m AVC -ts recent | grep fluent`. Restaura con `lab.sh siem-k8s`.
3. **Pod Security.** Intenta `kubectl -n demo run root --image=busybox:1.37 --restart=Never -- id` y lee el
   rechazo del perfil *restricted*.

---

## Bloque 8 — VMware: importación, exportación y conversión de VMs

### Teoría mínima

| Concepto | Qué es |
|---|---|
| `.vmx` | Configuración de la VM en ESXi (hardware virtual, discos, red) |
| `.vmdk` | Disco virtual: un **descriptor** de texto + datos (`-flat.vmdk` en VMFS). Formatos *hosted* (sparse, streamOptimized) para mover entre sistemas |
| *Thin* / *thick* | Reserva bajo demanda frente a reserva completa (*lazy* o *eager zeroed*) |
| OVF / OVA | Estándar de empaquetado: descriptor XML `.ovf` + manifiesto `.mf` (SHA) + discos; **OVA** = todo en un `tar` (el `.ovf` primero) |
| Hardware virtual | Controladora (LSI Logic, **PVSCSI**), NIC (**VMXNET 3**, E1000E), versión de hardware (compatibilidad con ESXi) |
| `open-vm-tools` | Herramientas del invitado en Linux (apagado ordenado, IP visible en vCenter, *quiesce* de snapshots) |
| Herramientas | Host Client / vSphere Client (asistentes *Deploy OVF* y *Export*), `ovftool`, `govc` (CLI de govmomi), `vmkfstools`, PowerCLI, **vCenter Converter** (P2V/V2V), `virt-v2v` (VMware → KVM) |

Por qué una VM no arranca al cambiar de hipervisor: el **initramfs** se generó en modo *hostonly* (solo con
los drivers `virtio` de KVM) y no encuentra el disco en la controladora de VMware; la **NIC cambia de nombre**
(virtio `enp1s0` → vmxnet3 `ens192`) y el perfil de red no se aplica; y la copia hereda **machine-id, claves
SSH y MAC** del original. `30-vm-convert.sh` resuelve las tres cosas sobre una copia (`dracut --no-hostonly`,
perfil de NetworkManager sin `interface-name`, `virt-sysprep`).

### Práctica — parte A (solo KVM, sin ESXi)

Herramientas en el host: `sudo apt install qemu-utils libguestfs-tools virt-v2v`.

```bash
scripts/lab.sh down rhel9-app01                                   # el original, apagado (nunca se modifica)
scripts/lab.sh vm-convert export rhel9-app01 --dry-run            # ver los comandos
scripts/lab.sh vm-convert export rhel9-app01                      # -> ~/lab-export/rhel9-app01/rhel9-app01-sparse.vmdk
scripts/lab.sh vm-convert export rhel9-app01 --format stream      # -> ...-stream.vmdk (formato OVA)
scripts/lab.sh up rhel9-app01
qemu-img info ~/lab-export/rhel9-app01/rhel9-app01-sparse.vmdk
scripts/lab.sh vm-convert inspect ~/lab-export/rhel9-app01/rhel9-app01-sparse.vmdk
# Vuelta a KVM con virt-v2v (la VM nueva queda SIN red para no duplicar la IP del original)
scripts/lab.sh vm-convert import ~/lab-export/rhel9-app01/rhel9-app01-sparse.vmdk rhel9-conv01
virsh start rhel9-conv01 && virsh console rhel9-conv01           # login por consola: hostname, ip a, machine-id
```

### Práctica — parte B (con `esxi01` de la Etapa 8, fase A)

**KVM → ESXi** (por SSH y `vmkfstools`; funciona con el ESXi gratuito):

```bash
scp -i ~/.ssh/lab_esxi_rsa ~/lab-export/rhel9-app01/rhel9-app01-sparse.vmdk root@10.10.10.60:/vmfs/volumes/datastore1/
ssh -i ~/.ssh/lab_esxi_rsa root@10.10.10.60
  mkdir -p /vmfs/volumes/datastore1/rhel9-conv02
  vmkfstools -i /vmfs/volumes/datastore1/rhel9-app01-sparse.vmdk -d thin /vmfs/volumes/datastore1/rhel9-conv02/rhel9-conv02.vmdk
  rm /vmfs/volumes/datastore1/rhel9-app01-sparse.vmdk
# Host Client (https://10.10.10.60/ui): Crear VM > Linux / RHEL 9 > quitar el disco nuevo > "Disco existente"
#   rhel9-conv02.vmdk · controladora LSI Logic SAS o PVSCSI · NIC VMXNET 3 · red SIN conectar al arrancar
# Consola de la VM: arranca, dnf install -y open-vm-tools, systemctl enable --now vmtoolsd
```

**ESXi → KVM** (`virt-v2v` lee el `.vmx` por SSH; también vale con el ESXi gratuito; la VM origen, apagada):

```bash
eval "$(ssh-agent)"; ssh-add ~/.ssh/lab_esxi_rsa
virt-v2v -i vmx -it ssh "ssh://root@10.10.10.60/vmfs/volumes/datastore1/rhel9-vm01/rhel9-vm01.vmx" \
  -o libvirt -oc qemu:///system -os lab-images -on rhel9-vm01-kvm
virt-xml rhel9-vm01-kvm --remove-device --network all      # misma regla: sin IP duplicada
```

**Exportar a OVF/OVA**: en el Host Client, *Exportar* la VM (descarga `.ovf` + `.vmdk` + `.mf`) y empaqueta un
OVA a mano (`tar -cvf rhel9-vm01.ova rhel9-vm01.ovf rhel9-vm01.mf rhel9-vm01-disk1.vmdk`: el orden importa) o con
`ovftool` (descarga gratuita de Broadcom). Importar un OVA en KVM: `scripts/lab.sh vm-convert import <fichero>.ova rhel9-ova01`.

**Con vCenter** (fase B de la Etapa 8, API de escritura disponible): `govc import.ova`, `govc import.vmdk`,
`govc export.ovf`, *Deploy OVF Template* y *Export OVF Template* en el vSphere Client, y bibliotecas de contenido.

### Avería provocada

1. **Initramfs *hostonly*.** Exporta con `--no-prep` y arranca la copia en ESXi: el arranque se queda en el
   *dracut emergency shell* sin encontrar `vg_system`. Explica la causa y arréglalo con la exportación normal.
2. **API de solo lectura.** Con la licencia gratuita aplicada, `govc import.vmdk` contra `esxi01` falla
   ("*Current license or ESXi version prohibits execution of the requested operation*"). Explica por qué el
   camino SSH + `vmkfstools` sí funciona y qué licencia necesitaría la automatización por API.
3. **IP duplicada.** Arranca `rhel9-conv01` con red (`virt-xml rhel9-conv01 --add-device --network network=lab-net`)
   con `rhel9-app01` encendida y diagnostica con `sudo arping -D -I <nic> 10.10.10.13` y `ip neigh`.

---

## Bloque 9 — Buenas prácticas de ciberseguridad aplicadas (y dónde están en el lab)

| Práctica | Dónde se ve | Cómo se comprueba |
|---|---|---|
| Sin credenciales por defecto | Contraseña de Graylog aleatoria; el script se niega a usar `admin` | `test_siem.sh` |
| Secretos fuera del repositorio | `/opt/siem/.env` y `/root/.siem/*` (0600); `env.example` con `CAMBIAR` | `stat -c %a`, `.gitignore` |
| Mínima exposición | OpenSearch/Elasticsearch solo en 127.0.0.1; MongoDB sin puerto; nada en 0.0.0.0 | `ss -ltnp`, `test_siem.sh` |
| Defensa en profundidad | firewalld (solo 10.10.10.0/24) **y** puertos de Docker ligados a IPs concretas | Ejercicio: Docker y firewalld (abajo) |
| Mínimo privilegio | NXLog como `nxlog` + `log_group`; usuario `analista` *Reader*; *token* de API para scripts | `ps -o user= -C nxlog`, web |
| Confinamiento | SELinux Enforcing en el host, en los contenedores (`selinux-enabled`) y en k3s (`--selinux`); `spc_t` solo para el agente de logs | `getenforce`, `docker inspect`, `ausearch` |
| Integridad y trazabilidad | auditd (Etapa 5) enviado al SIEM; SHA-256 de las imágenes de VM exportadas; versiones fijadas | `audit_key:lab-identity`, `sha256sum -c` |
| Hora fiable | chrony contra `dns01` en todas las VMs: sin hora correcta no hay correlación | `chronyc tracking` |
| Disponibilidad de los logs | Colas en disco (rsyslog, Fluent Bit), *journal* de Graylog, retención calculada | Averías de los bloques 2, 4 y 7 |
| Cambios controlados | `--check --diff`, *rollback* (`siem_state=absent`), copias `*.lab-bak.<fecha>` | Bloque 4 |
| Ampliaciones | TLS en las entradas (Syslog 6514, GELF TLS), HTTPS en la web con proxy inverso, copias (`mongodump` + *snapshots* de OpenSearch) | `checklists/etapaN2.md` |

**Ejercicio: Docker y firewalld.** Los puertos que publica Docker se resuelven con reglas NAT propias, **antes**
de las zonas de firewalld. Compruébalo: quita temporalmente la regla rica del 9000
(`firewall-cmd --remove-rich-rule=...` sin `--permanent`) y abre `http://10.10.10.55:9000` desde el host: sigue
funcionando. Conclusión documentada: en un host con Docker, el control de exposición se hace al **publicar**
(IP concreta) o en la cadena `DOCKER-USER`, no solo con firewalld. Restaura con `firewall-cmd --reload`.

---

## Bloque 10 — Infraestructura física, virtual y de conectividad

Diagnóstico por capas de "no llegan logs de X", de abajo arriba:

| Capa | Pregunta | Comandos |
|---|---|---|
| Física (host) | ¿Hay RAM, CPU y disco? ¿El host hace *swap*? | `free -h`, `vmstat 2 5`, `df -h /var/lib/libvirt`, `iostat -x 2 3`, `virsh nodememstats` |
| Virtual | ¿VM encendida, con sus vCPU/RAM? ¿Red libvirt activa? | `virsh list --all`, `virsh dominfo siem01`, `virsh domstats siem01`, `virsh net-info lab-net`, `ip -br link show virbr-lab` |
| Red (L2/L3) | ¿Llega por IP? ¿MAC correcta? | `ping -c2 10.10.10.55`, `ip neigh`, `sudo arping -c2 -I virbr-lab 10.10.10.55`, `tracepath 10.10.10.55` (MTU) |
| Transporte (L4) | ¿El puerto escucha y es accesible? | `ss -ltnup` (en siem01), `timeout 3 bash -c '</dev/tcp/10.10.10.55/5140'`, `nc -vz 10.10.10.55 12201` |
| Filtrado | ¿firewalld, NAT de Docker, SELinux? | `firewall-cmd --list-all`, `sudo nft list ruleset | grep -A3 DOCKER`, `ausearch -m AVC -ts recent` |
| Captura | ¿Salen/entran los paquetes? | `sudo tcpdump -ni any port 5140 -c 5 -A` (en origen y en destino) |
| Nombres y hora | ¿Resuelve? ¿Hora sincronizada? | `dig siem01.lab.local`, `chronyc tracking`, comparar `timestamp` y hora del origen |
| Aplicación | ¿Entrada RUNNING? ¿Errores al procesar? | **System > Inputs**, **System > Nodes**, `docker compose logs graylog`, `os_search.py count` |

Ejercicio de capacidad: con `docker stats` y `virsh domstats siem01 --balloon` anota el consumo real de cada
componente con 1, 100 y 1.000 mensajes/s (`gelf_send.py --count`), y deduce el tamaño de `siem01` para el doble de VMs.

---

## Documentación que deja la etapa

- `checklists/etapaN2.md` rellenado con los resultados **obtenidos** (salidas reales en `results/etapaN2/`).
- Casos reales en `troubleshooting/etapaN2/NN-*.md` y la guía de estudio
  [`troubleshooting/etapaN2/README_troubleshooting_etapaN2.md`](../troubleshooting/etapaN2/README_troubleshooting_etapaN2.md).
- Capturas de la web de Graylog (entradas, stream, pipeline, alerta, dashboard) en `prints/etapaN2/`.
- Scripts: [`scripts/stageN2/README_stageN2.md`](../scripts/stageN2/README_stageN2.md).

## Glosario técnico (ES / EN)

| Español | Inglés | Nota |
|---|---|---|
| Ingesta | Ingestion / log shipping | Llevar los logs desde el origen al SIEM |
| Entrada | Input | Puerto + protocolo + formato en Graylog |
| Normalización | Normalization / parsing | Convertir texto en campos comunes |
| Correlación | Correlation | Relacionar eventos (de varias fuentes) en una ventana de tiempo |
| Regla de detección | Detection rule / use case | Consulta + umbral + ventana → alerta |
| Falso positivo | False positive | Alerta sin incidente real; se reduce afinando |
| Retención | Retention | Cuánto tiempo se guardan los datos (y qué cuesta en disco) |
| Rotación de índices | Index rotation | Cerrar el índice activo y abrir otro |
| Cola en disco | Disk-assisted queue / buffering | No perder eventos si el destino cae |
| Agente | Agent / forwarder / shipper | NXLog, rsyslog, Fluent Bit, Beats |
| Contenedor confinado | Confined container | SELinux `container_t` |
| Conversión V2V | V2V conversion | De un hipervisor a otro (`virt-v2v`, Converter) |
| Plantilla OVF | OVF template | Paquete portable de VM |
| Disco ligero / completo | Thin / thick provisioning | Reserva bajo demanda o completa |
| Endurecimiento | Hardening | Reducir superficie de ataque |
| Mínimo privilegio | Least privilege | Solo los permisos imprescindibles |
| Análisis post-incidente | Post-incident review | Qué pasó, causa raíz, prevención |

## Fuentes

- Graylog — [Docker con OpenSearch propio](https://go2docs.graylog.org/current/downloading_and_installing_graylog/docker_installation_os.htm) ·
  [Matriz de compatibilidad](https://go2docs.graylog.org/current/downloading_and_installing_graylog/compatibility_matrix.htm)
- [Fluent Bit — salida GELF](https://docs.fluentbit.io/manual/pipeline/outputs/gelf) · [NXLog — descargas](https://nxlog.co/downloads)
- Etiquetas de imagen consultadas en Docker Hub: `graylog/graylog`, `opensearchproject/opensearch`, `mongo`, `elasticsearch`, `fluent/fluent-bit`
