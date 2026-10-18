# 📡 Troubleshooting y guía de estudio — Etapa N2 (SIEM: Graylog, OpenSearch, Syslog, NXLog, Docker, k3s y VMware)

Ver formato y regla general en [`troubleshooting/README.md`](../README.md).

Este documento tiene dos usos:

1. **Índice de los casos reales** de troubleshooting de la Etapa N2 (se añaden al ejecutarla en las VMs).
2. **Base de estudio**: los comandos que usan los scripts y el test de esta etapa, con una explicación sencilla
   de qué hace cada uno y por qué, más los comandos de diagnóstico de un SIEM.

> Regla del proyecto: *manual → documentado → repetible → automatizado*. Cada bloque de la guía
> [`siem/etapaN2-siem.md`](../../siem/etapaN2-siem.md) se hace primero a mano y después con `lab.sh`.

---

## 1. Casos documentados

| Caso | Tema |
|---|---|
| [01 test-siem-falla-antes-de-desplegar](01-test-siem-falla-antes-de-desplegar.md) 🔎 | `test_siem.sh` daba 20 FAIL (y 4 PASS vacíos) en `siem01` antes de desplegar el SIEM: ahora comprueba por fases |
| [02 preflight-dns-getent-hosts-ipv6](02-preflight-dns-getent-hosts-ipv6.md) 🔎 | Preflight: "`siem01.lab.local` no resuelve" con la zona correcta: `getent hosts` devolvía primero la `fe80::` de `nss-myhostname` |
| [03 docker-containerd-image-store-llena-var](03-docker-containerd-image-store-llena-var.md) 🔎 | `siem-stack`: "no space left on device" con `lv_docker` vacío: Docker 29 guardaba las imágenes en `/var/lib/containerd` (en `/var`, 4 GB) |

🔎 = encontrado de forma orgánica al ejecutar contra las VMs reales. Cada fallo real nuevo se documenta aquí
como `NN-slug.md` con la plantilla del proyecto.

**Averías provocadas** (ejercicios de la guía, con snapshot `siem01-stage5-complete` como red de seguridad):

| Bloque | Avería | Qué se aprende |
|---|---|---|
| 1 | `/var/lib/docker` con etiqueta SELinux incorrecta | `chcon` frente a `restorecon`/`semanage fcontext`; AVC con `ausearch` |
| 2 | `vm.max_map_count` bajo · OpenSearch parado | *Bootstrap checks*; el *journal* de Graylog evita perder mensajes |
| 3 | Entrada parada · `POST` sin `X-Requested-By` · GELF sin `short_message` | UDP no confirma la entrega; CSRF en la API; validación del formato |
| 4 | Puerto 5140 sin `syslogd_port_t` · SIEM apagado · *rollback* | SELinux y puertos; colas en disco; cambios reversibles |
| 5 | Permisos de `audit.log` · comentario al final de una directiva de NXLog | `log_group` de auditd; sintaxis de NXLog |
| 6 | Umbral de alerta mal afinado | Falsos negativos/positivos; afinar con datos |
| 7 | Puerto de Graylog incorrecto en Fluent Bit · DaemonSet sin `spc_t` · Pod Security | *Buffering* en disco; SELinux en Kubernetes; perfiles de seguridad |
| 8 | Exportar sin preparar (`--no-prep`) · API de ESXi gratuito · IP duplicada | initramfs *hostonly*; licencias de vSphere; identidad de las copias |

Relacionados de otras etapas: [etapa2/04](../etapa2/04-selinux-denial.md) (etiqueta SELinux),
[etapa2/06](../etapa2/06-ausearch-colgado-timeout.md) (`ausearch` con `timeout`),
[etapa3/01](../etapa3/01-firewall-block.md) (firewalld), [etapa4/03](../etapa4/03-time-sync-failure.md) (hora),
[etapa6/01](../etapa6/01-log-verbose-set-e-lab-healthcheck.md) (`set -e`),
[etapa7/03](../etapa7/03-group-vars-ubicacion-incorrecta.md) (fuente de verdad del proyecto Ansible),
[etapa8/01](../etapa8/01-preflight-pipefail-sigpipe.md) (`| grep -q` con `pipefail`).

---

## 2. Flujo de la etapa (orden exacto)

| # | Comando | Script que ejecuta | Dónde corre |
|---|---|---|---|
| 1 | `scripts/lab.sh stage4-dns` | `stage4/01-setup-dns.sh` (plantillas con `siem01` y `graylog`) | `dns01` |
| 2 | `scripts/lab.sh vm-create siem01` · `stage2/3/4-clients/5 siem01` | Etapas 1-5 | Host / `siem01` |
| 3 | `scripts/lab.sh siem-preflight` | `stageN2/00-preflight.sh` | `siem01` (solo lectura) |
| 4 | `scripts/lab.sh siem-docker` | `stageN2/01-docker-host.sh` | `siem01` (root) |
| 5 | `scripts/lab.sh siem-stack [--with-elastic]` | `stageN2/02-graylog-stack.sh` → `docker compose` | `siem01` |
| 6 | `scripts/lab.sh siem-inputs` | `stageN2/03-graylog-inputs.sh` → `graylog_inputs.py`, `gelf_send.py`, `os_search.py` | `siem01` |
| 7 | `scripts/lab.sh siem-forward [args]` | `stageN2/20-siem-forward.sh` → `playbooks/siem-forwarding.yml` | `ansible01` → grupo `lab` |
| 8 | `scripts/lab.sh siem-nxlog <host> <rpm>` | `scp` del RPM + `stageN2/10-nxlog-agent.sh` | VM agente |
| 9 | `scripts/lab.sh siem-k8s` | `stageN2/04-k3s-fluentbit.sh` → `kubectl apply` | `siem01` |
| 10 | `scripts/lab.sh vm-convert export\|import\|inspect ...` | `stageN2/30-vm-convert.sh` | Host |
| 11 | `scripts/lab.sh test test_siem.sh <host\|all>` | `tests/test_siem.sh` (también desde `run_all.sh` según el papel) | VMs |

---

## 3. Comandos de los scripts, explicados

### 3.1 `00-preflight.sh` — auditoría de solo lectura

| Comando | Qué hace | Por qué |
|---|---|---|
| `set -uo pipefail` (sin `-e`) | No se para en el primer fallo | Un preflight debe enseñar **todas** las comprobaciones |
| `awk '/MemTotal/ {print $2}' /proc/meminfo` | RAM total en kB | OpenSearch + Graylog + MongoDB necesitan ~5-6 GB reales |
| `vgs --noheadings --units g --nosuffix -o vg_free vg_system` | Espacio libre del VG | Hacen falta 45 GB para los LVs de Docker y k3s |
| `df --output=pcent /var` | % de uso de `/var` | Los logs de pods de k3s van a `/var/log/pods` |
| `chronyc tracking` (`Leap status : Normal`) | ¿Hora sincronizada? | Sin hora correcta no se pueden ordenar ni correlacionar eventos |
| `dig +short siem01.lab.local A @10.10.10.20` | DNS directo en `dns01` | Lo que publica la zona, sin cachés ni `/etc/hosts` |
| `getent ahostsv4 siem01.lab.local` | DNS directo del sistema (NSS), solo IPv4 | No `getent hosts`: en el propio host devuelve antes la `fe80::` de `nss-myhostname` (caso 02) |
| `dig +short -x 10.10.10.55 @10.10.10.20` | DNS inverso | El PTR hace que los eventos muestren nombres y no IPs |
| `curl -s -o /dev/null -w '%{http_code}' <url>` | Código HTTP sin descargar | Comprueba la salida a `download.docker.com`, Docker Hub (401 = accesible) y `get.k3s.io` |
| `ss -ltnu \| grep -Eq ':(9000\|5140\|12201) '` | ¿Puertos ya ocupados? | Evita un `bind: address already in use` a mitad del despliegue |

### 3.2 `01-docker-host.sh` — almacenamiento y Docker

| Comando | Qué hace | Por qué |
|---|---|---|
| `lvcreate -y -n lv_docker -L 35G vg_system` | LV nuevo en el VG del sistema | `/var` del kickstart tiene 4 GB |
| `mkfs.xfs -q /dev/vg_system/lv_docker` | Formatea en XFS | `ftype=1` por defecto en RHEL 9: lo exige el driver `overlay2` |
| `blkid -s UUID -o value <dev>` + línea en `fstab` | Montaje por UUID | Un nombre de dispositivo puede cambiar; el UUID no (caso etapa2/02) |
| `systemctl daemon-reload` · `mount <punto>` | systemd regenera las unidades `.mount` y monta | Sin el *reload*, systemd avisa de que `fstab` cambió |
| `restorecon -R /var/lib/docker` (antes **y** después de instalar) | Aplica las etiquetas SELinux de la política | Las reglas de `/var/lib/docker` las trae `container-selinux`, que llega con `docker-ce` |
| `stat -c %C /var/lib/docker` | Contexto SELinux | Debe ser `container_var_lib_t` |
| `dnf remove -y podman runc` | Retira paquetes en conflicto | `containerd.io` choca con `runc` de RHEL |
| `dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo` | Repositorio oficial de Docker | Docker CE no está en los repos de Red Hat |
| `dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin` | Motor, cliente, *runtime*, buildx y `docker compose` | |
| `daemon.json`: `log-opts max-size/max-file` | Rota los logs de los contenedores | Sin esto, `json-file` crece sin límite |
| `daemon.json`: `"selinux-enabled": true` | Etiqueta SELinux por contenedor (`container_t` + MCS) | Confinamiento: un contenedor no lee los ficheros de otro |
| `daemon.json`: `"live-restore": true` | Los contenedores siguen vivos si se reinicia `dockerd` | Actualizar Docker sin cortar la ingesta |
| `daemon.json`: `"features": { "containerd-snapshotter": false }` | Driver clásico `overlay2` en `/var/lib/docker` | Desde Docker 29 el *containerd image store* guarda las capas en `/var/lib/containerd`, fuera de `lv_docker` (caso 03) |
| `docker info --format '{{.Driver}} {{.DockerRootDir}}'` | Driver de almacenamiento y raíz de Docker | `overlay2` = clásico; `overlayfs` = *snapshotter* de containerd (las imágenes no van a la raíz que se muestra) |
| `du -sh /var/lib/containerd /var/lib/docker` | Dónde está ocupando espacio de verdad | `df` del LV vacío y `/var` lleno delatan que se escribe en otro sitio |
| `python3 -m json.tool <fichero>` | Valida el JSON antes de instalarlo | Un `daemon.json` roto impide arrancar Docker |
| `usermod -aG docker adminlab` | Docker sin `sudo` | Grupo `docker` = root en ese host: decisión de laboratorio |
| `/etc/sysctl.d/90-siem.conf`: `vm.max_map_count = 262144` + `sysctl -p` | Más áreas de memoria mapeada por proceso | Requisito de OpenSearch/Elasticsearch (si no, no arrancan) |

### 3.3 `02-graylog-stack.sh` — despliegue con Compose

| Comando | Qué hace | Por qué |
|---|---|---|
| `install -d -m 0750 /opt/siem` · `install -d -m 0700 /root/.siem` | Directorios con permisos en un paso | Proyecto Compose y secretos solo para root |
| `head -c 512 /dev/urandom \| tr -dc 'A-Za-z0-9'` (`randpw`) | Contraseña aleatoria alfanumérica | Sin símbolos para no romper el `.env` con comillas |
| `printf '%s' "$pw" \| sha256sum \| cut -d' ' -f1` | SHA-256 de la contraseña de admin | Graylog guarda el *hash*, no la contraseña (`GRAYLOG_ROOT_PASSWORD_SHA2`) |
| `umask 077` | Ficheros nuevos 0600 | El `.env` nace protegido, sin ventana de tiempo |
| `[[ ! -f .env ]]` | Solo genera secretos la primera vez | Cambiar `GRAYLOG_PASSWORD_SECRET` invalida lo cifrado en MongoDB |
| `grep ... 8c6976e5...a918` | Se niega a usar el *hash* de `admin` | Credencial por defecto de la documentación |
| `docker compose config --quiet` | Valida el compose y el `.env` | `${VAR:?}` hace fallar aquí si falta un secreto |
| `docker compose pull --quiet` · `up -d` · `ps` | Descarga, arranca en segundo plano, estado | Versiones fijadas: nada de `latest` |
| `docker compose --profile elastic ...` | Activa el servicio opcional | Los perfiles encienden servicios solo cuando se piden |
| `curl -s http://127.0.0.1:9000/api/system/lbstatus` | `ALIVE` si el nodo está listo | Comprobación de balanceador: sin autenticación |
| `curl -u admin:... /api/system` | Versión y ciclo de vida del nodo | Primera llamada autenticada a la API |
| `firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.10.10.0/24" port port="5140" protocol="tcp" accept'` | Abre el puerto solo para el lab | Mínima exposición (ver el ejercicio Docker y firewalld) |

Claves del `docker-compose.yml`:

| Clave | Qué hace |
|---|---|
| `ports: "127.0.0.1:9200:9200"` | Publica solo en *loopback*: OpenSearch sin seguridad nunca queda expuesto a la red |
| `ports: "${SIEM_IP}:5140:5140/udp"` | Publica en una IP concreta, no en 0.0.0.0 |
| `depends_on: {condition: service_healthy}` | Graylog espera a que MongoDB y OpenSearch pasen su *healthcheck* |
| `healthcheck: test: [...]` | Comando que decide si el contenedor está sano (`docker inspect -f '{{.State.Health.Status}}'`) |
| `ulimits: memlock -1` + `bootstrap.memory_lock: "true"` | Bloquea el *heap* en RAM: OpenSearch nunca va a *swap* |
| `action.auto_create_index: "false"` | Solo Graylog crea índices (evita índices basura) |
| `--wiredTigerCacheSizeGB 0.5` | Limita la caché de MongoDB (por defecto, ~50 % de la RAM) |
| `restart: unless-stopped` | Arranca con Docker salvo que se haya parado a mano |

### 3.4 `03-graylog-inputs.sh` y las herramientas en Python

| Comando / código | Qué hace | Por qué |
|---|---|---|
| `GET /api/system/inputs` · `GET /api/system/inputstates` | Lista entradas y su estado en el nodo | Idempotencia: se busca por título antes de crear |
| `POST /api/system/inputs` (`global: true`) | Crea la entrada en todos los nodos | Cabecera `X-Requested-By` obligatoria |
| `PUT /api/system/inputstates/<id>` | Arranca la entrada | Una entrada creada puede quedar parada |
| `use_null_delimiter: true` (GELF TCP) | Mensajes separados por `\0` | Así delimita GELF por TCP; Syslog TCP usa salto de línea |
| `zlib.compress()` + cabecera `\x1e\x0f` + id + nº de trozo | GELF por UDP comprimido y troceado | Un datagrama > MTU se fragmenta o se pierde |
| `ss -ltn \| grep "10.10.10.55:12201 "` | Puerto publicado por Docker en la IP del lab | `docker-proxy` o NAT, según la configuración |
| `os_search.py count --query "lab_marker:<m>"` | Cuenta documentos en OpenSearch | Prueba de extremo a extremo: entrada → proceso → índice |
| `POST /<índice>/_search` con `query_string` + `range now-15m` | Búsqueda Lucene en una ventana de tiempo | La misma sintaxis que la barra de búsqueda de Graylog |
| `aggs: terms: field: source` | Agregación: cuántos por valor | Base de cualquier "top N" o regla de umbral |
| `POST /_bulk` (NDJSON) | Inserción masiva | Una línea de acción + una de documento |
| `detect_bruteforce.py`: regex sobre `message` + `terms` sobre `audit_addr` | Correlación sobre dos fuentes | Normalizar fuentes distintas en una sola regla |

### 3.5 `20-siem-forward.sh` y `siem-forwarding.yml`

| Comando / tarea | Qué hace | Por qué |
|---|---|---|
| `cp -a files/siem-lab/. ~adminlab/siem-lab/` | Recopia el proyecto en cada ejecución | La fuente de verdad es git (caso etapa7/03) |
| `runuser -l adminlab -c "cd ~/siem-lab && ansible-playbook ..."` | Ejecuta como `adminlab` | Su clave SSH, su `ansible.cfg` y su Vault |
| `inventory = /home/adminlab/ansible-lab/inventory/hosts.ini` | Reutiliza el inventario de la Etapa 7 | Las `group_vars` junto al inventario se cargan igual |
| `semanage port -l \| awk '... END { exit !f }'` | ¿5140 ya es `syslogd_port_t`? | Un solo `awk` lee toda la entrada: sin SIGPIPE con `pipefail` (etapa8/01) |
| `semanage port -a -t syslogd_port_t -p tcp 5140` (o `-m`) | Permite a rsyslog conectar a ese puerto | Sin esto, AVC `name_connect` y no se reenvía nada |
| `omfwd` + `RSYSLOG_SyslogProtocol23Format` | Reenvío en RFC 5424 | Graylog separa host, aplicación, PID y nivel |
| `queue.type="LinkedList"` + `queue.filename` + `queue.saveOnShutdown` | Cola en memoria con desbordamiento a disco | No se pierde nada si el SIEM cae |
| `action.resumeRetryCount="-1"` | Reintentos infinitos | La acción nunca se da por perdida |
| *Handlers* `rsyslogd -N1` → `service: restarted` (mismo `listen`) | Valida antes de reiniciar | Una configuración rota no llega a aplicarse |
| `meta: flush_handlers` | Ejecuta los *handlers* en ese punto | La prueba posterior usa ya la configuración nueva |
| `wait_for: host port timeout` | ¿Se abre el TCP? | Aviso, no fallo: el SIEM puede estar apagado a propósito |
| `logger -p authpriv.notice -t siem-test` | Mensaje de prueba | Misma *facility* que sshd |
| `-e siem_state=absent` | *Rollback* | Cambio reversible y probado |

### 3.6 `10-nxlog-agent.sh`

| Comando | Qué hace | Por qué |
|---|---|---|
| `dnf install -y ./nxlog-ce-*.rpm` | Instala un RPM local resolviendo dependencias de los repos | `rpm -i` no resuelve dependencias |
| `rpm -E %rhel` | Versión mayor de RHEL | Avisar si el RPM no es de esta versión |
| `log_group = nxlog` en `/etc/audit/auditd.conf` | auditd crea sus ficheros 0640 con ese grupo | Lectura sin dar root al agente |
| `chgrp nxlog /var/log/audit && chmod 0750 /var/log/audit` | Acceso al directorio | |
| `service auditd restart` | Reinicia auditd | `systemctl restart auditd` está bloqueado (`RefuseManualStop`) |
| `runuser -u nxlog -- test -r /var/log/audit/audit.log` | Comprueba el permiso **como** el usuario del agente | Probar como quien lo va a usar, no como root |
| `nxlog -v -c /etc/nxlog.conf` | Valida la configuración | Si falla, se restaura la copia y no se reinicia |
| `auditctl -m "siem-test <marca>"` | Escribe un evento propio en `audit.log` | Prueba de extremo a extremo sin tocar nada del sistema |
| `timeout 3 bash -c "</dev/tcp/IP/12201"` | ¿Abre el TCP? | Sin `nc`: funciona en cualquier RHEL |

### 3.7 `04-k3s-fluentbit.sh`

| Comando | Qué hace | Por qué |
|---|---|---|
| `curl -sfL https://get.k3s.io -o <fichero>` + `sha256sum` | Descarga y registra el instalador | Nada de `curl \| sh` sin ver qué se ejecuta |
| `INSTALL_K3S_EXEC="server --selinux --disable traefik --write-kubeconfig-mode 0600"` | Opciones del servidor | SELinux en containerd, sin ingress (RAM), kubeconfig protegido |
| `firewall-cmd --zone=trusted --add-source=10.42.0.0/16` (y `10.43.0.0/16`) | Redes de pods y servicios de confianza | firewalld no debe filtrar el tráfico interno del clúster |
| `kubectl get nodes` | Estado del nodo | `Ready` = kubelet, red y *runtime* OK |
| `sed "s/__SIEM_IP__/.../"` + `kubectl apply -f` | Aplica los manifiestos | Declarativo: `apply` crea o actualiza |
| `kubectl rollout restart ds/fluent-bit` · `rollout status` | Reinicia los pods y espera | Un cambio en el ConfigMap no reinicia los pods por sí solo |
| `multiline.parser: cri` | Interpreta `<hora> stdout F <texto>` | containerd no escribe el JSON de Docker |
| filtro `kubernetes` + `nest lift` (prefijo `k8s_`) | Añade metadatos y los aplana | GELF necesita campos planos |
| `storage.type: filesystem` | *Buffer* en disco | Si Graylog cae, los logs esperan |
| `seLinuxOptions: type: spc_t` | Contenedor sin confinar (solo este) | `container_t` no puede leer `/var/log` del nodo |

### 3.8 `30-vm-convert.sh` (host)

| Comando | Qué hace | Por qué |
|---|---|---|
| `virsh domstate <vm>` | Exige `shut off` | Copiar un disco en uso da una copia inconsistente |
| `virsh domblklist <vm> --details` | Ruta del disco | |
| `sudo qemu-img convert -p -O qcow2 <src> <copia>` | Copia de trabajo | El original no se toca nunca |
| `virt-customize -a <copia> --run-command 'dracut -f --no-hostonly --regenerate-all'` | initramfs con todos los drivers | El *hostonly* de KVM solo trae virtio |
| `--run-command 'sed -i "/^interface-name=/d" ...nmconnection'` | Perfil de red no atado al nombre de la NIC | virtio `enp1s0` ≠ vmxnet3 `ens192` |
| `--selinux-relabel` | Reetiqueta tras modificar ficheros | Si no, el invitado puede no arrancar servicios |
| `virt-sysprep --operations machine-id,ssh-hostkeys,net-hwaddr,...` | Identidad nueva | Dos VMs con el mismo machine-id/claves = conflictos |
| `qemu-img convert -O vmdk -o subformat=monolithicSparse,adapter_type=lsilogic` | VMDK para `vmkfstools -i` | Formato *hosted* que ESXi sabe importar |
| `-o subformat=streamOptimized` | VMDK compacto | El de los OVA; lo acepta `govc import.vmdk` |
| `qemu-img info` · `sha256sum` / `sha256sum -c` | Formato, tamaño virtual e integridad | Detecta copias dañadas entre sistemas |
| `virt-v2v -i disk\|ova <fichero> -o libvirt -os lab-images -on <nombre>` | Convierte e importa en libvirt | Cambia drivers del invitado a virtio |
| `virt-xml <vm> --remove-device --network all` | Quita las NIC | Evita IP duplicada con el original |
| `virt-inspector -a <fichero>` | SO, paquetes y discos de una imagen | Inspección sin arrancarla |

---

## 4. Comandos del test (`tests/test_siem.sh`), explicados

Se lanza con `scripts/lab.sh test test_siem.sh <host|all>`; `run_all.sh` lo añade en `siem01` y en las VMs con agente.

| Comprobación | Comando manual equivalente | Qué demuestra |
|---|---|---|
| LV propio y etiqueta | `mountpoint /var/lib/docker` · `ls -Zd /var/lib/docker` | Almacenamiento separado y bien etiquetado |
| Docker activo, SELinux, rotación | `systemctl is-active docker` · `docker info` · `cat /etc/docker/daemon.json` | Host de contenedores configurado |
| `vm.max_map_count` | `sysctl vm.max_map_count` | Requisito de OpenSearch |
| Contenedores en ejecución / *healthy* | `docker compose ps` · `docker inspect -f '{{.State.Health.Status}}' siem-opensearch` | El stack está sano, no solo arrancado |
| Sin `:latest` | `docker ps --format '{{.Image}}'` | Versiones controladas |
| `.env` y contraseña 0600 · sin `admin` | `stat -c %a /opt/siem/.env` | Secretos protegidos y sin credenciales por defecto |
| OpenSearch solo en 127.0.0.1 · MongoDB sin puerto · nada en 0.0.0.0 | `ss -ltnp` · `docker ps --format '{{.Ports}}'` | Mínima exposición |
| `lbstatus` ALIVE · clúster green/yellow | `curl 127.0.0.1:9000/api/system/lbstatus` · `curl 127.0.0.1:9200/_cluster/health` | Servicio operativo |
| Entradas escuchando y 4 en RUNNING | `ss -ltnu` · `graylog_inputs.py --list` | Ingesta disponible |
| GELF de prueba indexado en < 60 s | `gelf_send.py` + `os_search.py count` | La cadena completa funciona **ahora** |
| k3s Ready · Fluent Bit listo · logs de `demo` | `kubectl get nodes` · `kubectl -n logging get ds` · búsqueda `k8s_namespace_name:demo` | Kubernetes integrado en el SIEM |
| Agente rsyslog: activo, `-N1`, destino, cola, puerto SELinux | `rsyslogd -N1` · `cat /etc/rsyslog.d/90-siem-forward.conf` · `semanage port -l` | Reenvío correcto y resistente |
| Agente NXLog: servicio, `-v`, destino, usuario `nxlog`, `log_group`, lectura | `systemctl status nxlog` · `nxlog -v -c` · `ps -o user= -C nxlog` | Agente correcto y sin privilegios |
| Conectividad con el SIEM (INFO si no hay) | `timeout 3 bash -c '</dev/tcp/10.10.10.55/5140'` | Separa "mal configurado" (FAIL) de "SIEM apagado" (INFO) |

---

## 5. Comandos de diagnóstico de un SIEM

| Comando | Qué hace | Uso |
|---|---|---|
| `docker compose ps` · `docker compose logs --tail 50 <servicio>` | Estado y logs de cada pieza | Primer paso siempre |
| `docker stats --no-stream` | CPU y RAM reales | ¿OOM? ¿JVM al límite? |
| `docker inspect <c> --format '{{json .State}}'` | Estado, código de salida, `OOMKilled` | Contenedor que se reinicia |
| `curl -s 127.0.0.1:9200/_cluster/health?pretty` · `_cat/indices?v` · `_cat/shards?v` · `_cluster/allocation/explain?pretty` | Salud y por qué un shard no se asigna | Estado `red` o `yellow` |
| **System > Nodes** (journal, *buffers*) · **System > Inputs** · **System > Overview** (avisos) | Estado interno de Graylog | Mensajes que no se indexan |
| `ss -ltnup` · `ss -tnp \| grep 5140` | Puertos y conexiones | ¿Escucha? ¿Está conectado el agente? |
| `sudo tcpdump -ni any port 5140 -A -c 5` | Paquetes reales | ¿Sale del origen? ¿Llega al destino? |
| `sudo nft list ruleset \| grep -B2 -A6 DOCKER` | Reglas NAT de Docker | Puertos publicados que "saltan" firewalld |
| `sudo timeout 20 ausearch -m AVC -ts recent` · `sealert -a /var/log/audit/audit.log` | Denegaciones SELinux | rsyslog, k3s, Fluent Bit |
| `rsyslogd -N1` · `journalctl -u rsyslog -n 30` · `ls -l /var/lib/rsyslog/` | Configuración, errores y cola en disco | Reenvío que no llega |
| `nxlog -v -c /etc/nxlog.conf` · `tail /var/log/nxlog/nxlog.log` | Configuración y errores del agente | |
| `kubectl get pods -A` · `kubectl describe pod <p>` · `kubectl logs <p> --previous` · `kubectl get events -A --sort-by=.lastTimestamp` | Estado y eventos del clúster | Pods en `CrashLoopBackOff` o `Pending` |
| `chronyc tracking` · `timedatectl` | Hora | Eventos "en el futuro" o desordenados |
| `qemu-img info` · `qemu-img check` · `virt-inspector` | Imagen de disco | Conversión de VMs que no arrancan |

---

## 6. Chuleta: síntoma → primeros comandos

| Síntoma | Primeros comandos |
|---|---|
| La web de Graylog no carga | `docker compose ps`, `curl 127.0.0.1:9000/api/system/lbstatus`, `ss -ltn \| grep 9000`, `docker compose logs graylog` |
| Graylog pide una configuración inicial (*preflight*) en vez del login | `docker compose config \| grep ELASTICSEARCH_HOSTS` (debe ser `http://opensearch:9200`), `docker compose logs graylog \| grep -i preflight` |
| OpenSearch sale (`Exited`) | `docker compose logs opensearch \| tail` (¿`max_map_count`? ¿`memlock`? ¿disco?), `sysctl vm.max_map_count`, `df -h /var/lib/docker` |
| No llegan logs de una VM | En la VM: `rsyslogd -N1`, `ss -tnp \| grep 5140`, `ausearch -m AVC -c rsyslogd`; en `siem01`: `tcpdump -ni any port 5140`; Graylog: entrada RUNNING |
| Llegan con la hora mal | `chronyc tracking` en origen y en `siem01`; zona del usuario en Graylog; ¿RFC 3164 sin zona? |
| Mensajes en el *journal* de Graylog que no bajan | OpenSearch sano (`_cluster/health`), disco (`df`), índice en solo lectura (`_cat/indices` + `index.blocks.read_only_allow_delete`) |
| NXLog activo pero no envía | `tail /var/log/nxlog/nxlog.log`, `runuser -u nxlog -- test -r /var/log/audit/audit.log`, `nxlog -v` |
| Fluent Bit en `CrashLoopBackOff` | `kubectl -n logging logs ds/fluent-bit --previous`, sintaxis del ConfigMap |
| Fluent Bit arranca pero no lee | `ausearch -m AVC \| grep fluent` (¿`spc_t`?), `kubectl -n logging exec ds/fluent-bit -- ls /var/log/containers` |
| VM convertida no arranca en ESXi | Consola: ¿*dracut emergency shell*? → exportar sin `--no-prep`; ¿controladora correcta? |
| VM convertida arranca sin red | `nmcli dev`, `nmcli con show` (¿`interface-name` antiguo?), ¿NIC conectada en el hipervisor? |
| `govc`/PowerCLI fallan al importar en `esxi01` | Licencia gratuita = API de solo lectura: SSH + `vmkfstools` o un host en evaluación |

---

## 7. Preguntas de repaso

1. ¿Qué diferencia hay entre lo que guarda MongoDB y lo que guarda OpenSearch en Graylog?
2. ¿Por qué Graylog 7 no puede usar Elasticsearch 9 como almacén, y qué tienen en común sus APIs?
3. Syslog por UDP frente a TCP frente a TCP con TLS: ¿qué ganas y qué pierdes en cada caso?
4. ¿Qué es GELF y por qué su versión UDP comprime y trocea los mensajes?
5. Si `siem01` se apaga una hora, ¿qué pasa con los logs de las VMs? ¿Y con los de Kubernetes? ¿Dónde esperan?
6. ¿Por qué rsyslog necesita una etiqueta SELinux para enviar al puerto 5140 y no para escribir en `/var/log/messages`?
7. ¿Por qué NXLog no corre como root y cómo lee entonces `audit.log`?
8. ¿Qué es un stream, una regla de pipeline y una Event Definition, y en qué orden actúan?
9. Diseña una regla de fuerza bruta: ¿qué consulta, qué agrupación, qué umbral y qué ventana? ¿Cómo reduces los falsos positivos?
10. ¿Por qué los puertos que publica Docker no obedecen a las zonas de firewalld, y cómo se limita entonces la exposición?
11. ¿Por qué el agente de logs de Kubernetes es un DaemonSet y no un Deployment?
12. ¿Qué cambia en los logs de contenedores entre Docker (`json-file`) y containerd (CRI)?
13. ¿Por qué una VM de KVM puede no arrancar en ESXi y cómo se prepara antes de convertirla?
14. ¿Qué es un OVA por dentro? ¿Qué diferencia hay entre un VMDK *monolithicSparse*, *streamOptimized* y el `-flat.vmdk` de VMFS?
15. ¿Qué limita la licencia gratuita de ESXi y qué caminos de importación/exportación siguen funcionando?
16. Calcula el disco para 30 días de retención con 20 VMs que generan 50 mensajes/s de 400 bytes cada una.
17. ¿Qué cinco cosas revisas, en orden, cuando "no llegan los logs de un servidor"?
