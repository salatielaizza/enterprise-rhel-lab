# Etapa N — DevOps: Docker, Kubernetes, Jenkins y monitorización

> **Prueba práctica y adelanto de tecnologías** del perfil *Linux Administrator DevOps*. Es teoría + práctica manual en una VM. Nada de esto se ha ejecutado todavía en el lab real: validación de cada bloque en la VM y anotación de lo que falle.

## Objetivo

Practicar a mano lo que se pide hoy en un perfil *Linux Administrator DevOps*: **Docker y Kubernetes**,
**Jenkins** (CI/CD), **monitorización** (Prometheus + Grafana), el vocabulario **ITIL** (incidencias,
cambios, PIR) y el día a día de **APS** (*Application Production Support*) con **ServiceNow**.

## Arquitectura

```text
rhel9-monitor01  10.10.10.50  (RHEL 9 · 4 vCPU · 8 GB RAM · 60 GB)
 ├─ Docker CE
 │   ├─ Prometheus  :9090   métricas y alertas
 │   ├─ Grafana     :3000   dashboards
 │   ├─ node-exporter :9100 métricas de esta VM
 │   └─ Jenkins     :8080   pipelines
 └─ k3s (Kubernetes de un nodo) :6443, NodePorts 30000-32767

Resto del lab: node_exporter (:9100) instalado con Ansible desde ansible01 → Prometheus los recoge
Fuera del lab: instancia gratuita de ServiceNow (PDI) → incidencias, cambios y KB; se le habla por API desde la VM
```

## Día 0 — Preparar la VM (≈1 h)

```bash
# hosts.conf solo tiene rhel9-monitor01 como comentario de reserva. Añade esta línea activa,
# con el mismo formato que las demás (NAME VER IP VCPUS MEM_MB DISK_GB DATA_GB):
#   rhel9-monitor01 9    10.10.10.50   4      8192    60       0
grep -n rhel9-monitor01 scripts/hosts.conf   # comprueba que aparece la línea activa (no solo el comentario)
scripts/lab.sh vm-create rhel9-monitor01 --dry-run
scripts/lab.sh vm-create rhel9-monitor01
scripts/lab.sh register rhel9-monitor01 <usuario-RH>
scripts/lab.sh stage4-clients rhel9-monitor01    # DNS del lab + chrony + SSH endurecido
scripts/lab.sh snapshot create rhel9-monitor01 1 # punto de retorno antes de empezar
```

No marques `LAB_STAGE` en esta VM: los tests de las etapas normales no aplican aquí.

---

## Bloque 1 — Docker (día 1)

### Teoría mínima

- **Imagen**: plantilla de solo lectura, formada por **capas**. **Contenedor**: una imagen en ejecución,
  con una capa de escritura encima. Borrar el contenedor borra esa capa.
- **Registro**: dónde viven las imágenes (Docker Hub, Quay, Harbor, un registro privado del banco).
- **Volumen**: datos que sobreviven al contenedor. **Red**: los contenedores de la misma red se ven por nombre.
- Un contenedor **no es una VM**: comparte el kernel del host. Se aísla con *namespaces* y se limita con *cgroups*.
- **Docker vs Podman** (pregunta típica en entornos Red Hat): Docker usa un demonio (`dockerd`) que corre
  como root; Podman no tiene demonio y funciona *rootless*. Los comandos son casi idénticos.

### Instalación en RHEL 9

```bash
sudo dnf remove -y podman runc 2>/dev/null       # chocan con los paquetes de Docker
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker adminlab                 # sal y vuelve a entrar para usar docker sin sudo
docker run --rm hello-world
```

### Práctica

```bash
docker run -d --name web -p 8081:80 nginx        # contenedor en segundo plano
docker ps; docker logs web; docker exec -it web bash; docker inspect web | less
curl -s localhost:8081 | head -5
docker stop web && docker rm web

mkdir -p ~/devops/miweb && cd ~/devops/miweb
echo '<h1>Hola desde el lab</h1>' > index.html
cat > Dockerfile <<'EOF'
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
EOF
docker build -t miweb:1.0 .
docker run -d --name miweb -p 8082:80 miweb:1.0 && curl -s localhost:8082
docker images; docker history miweb:1.0         # las capas de la imagen
```

Desde tu host, abre `http://10.10.10.50:8082`. **Detalle importante:** los puertos publicados con
`-p` suelen ser accesibles aunque `firewalld` no los tenga abiertos, porque Docker escribe sus propias
reglas de red. Compruébalo con `sudo firewall-cmd --list-all` y anota lo que veas.

---

## Bloque 2 — Monitorización con Prometheus y Grafana (día 2)

### Teoría mínima

- **Métricas** (números en el tiempo), **logs** (eventos en texto) y **trazas** (el recorrido de una
  petición). Son los tres pilares de la *observabilidad*.
- Prometheus funciona en modo **pull**: cada X segundos *rasca* (`scrape`) un endpoint `/metrics` de cada
  **exporter**. `node_exporter` expone CPU, RAM, disco y red de un Linux.
- **PromQL** es su lenguaje de consultas. Una **regla de alerta** es una consulta que, si se cumple durante
  un tiempo (`for:`), dispara la alerta. **Alertmanager** la envía por correo, Teams, etc.
- **Grafana** no guarda datos: dibuja lo que le da Prometheus.
- Las **4 señales doradas** (SRE): latencia, tráfico, errores y saturación.

### Montaje con Docker Compose

```bash
mkdir -p ~/devops/monitoring && cd ~/devops/monitoring
cat > prometheus.yml <<'EOF'
global:
  scrape_interval: 15s
rule_files:
  - /etc/prometheus/alerts.yml
scrape_configs:
  - job_name: node
    static_configs:
      - targets: ['10.10.10.50:9100']
EOF

cat > alerts.yml <<'EOF'
groups:
  - name: lab
    rules:
      - alert: HostDown
        expr: up == 0
        for: 1m
        labels: { severity: critical }
        annotations: { summary: "{{ $labels.instance }} no responde" }
      - alert: DiskAlmostFull
        expr: (1 - node_filesystem_avail_bytes{fstype=~"xfs|ext4"} / node_filesystem_size_bytes{fstype=~"xfs|ext4"}) * 100 > 80
        for: 5m
        labels: { severity: warning }
        annotations: { summary: "{{ $labels.instance }} {{ $labels.mountpoint }} por encima del 80 %" }
EOF

cat > compose.yml <<'EOF'
services:
  prometheus:
    image: prom/prometheus
    network_mode: host
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro,Z
      - ./alerts.yml:/etc/prometheus/alerts.yml:ro,Z
    restart: unless-stopped
  grafana:
    image: grafana/grafana
    network_mode: host
    restart: unless-stopped
  node-exporter:
    image: prom/node-exporter
    network_mode: host
    pid: host
    command: ['--path.rootfs=/host']
    volumes:
      - /:/host:ro,rslave
    restart: unless-stopped
EOF

docker compose up -d && docker compose ps
sudo firewall-cmd --permanent --add-port={9090,3000,9100}/tcp && sudo firewall-cmd --reload
```

Con `network_mode: host` los contenedores usan la red de la VM. Por eso aquí **sí** manda `firewalld`, a
diferencia de los puertos publicados con `-p`. El sufijo `:Z` ajusta la etiqueta SELinux de los ficheros montados.

- Prometheus: `http://10.10.10.50:9090` → *Status → Targets* (debe salir `UP`) y *Alerts*.
- Grafana: `http://10.10.10.50:3000` (usuario `admin` / `admin`, pide cambiarla) → *Connections → Data sources →
  Prometheus* con URL `http://localhost:9090` → *Dashboards → Import* → ID **1860** (*Node Exporter Full*).

### node_exporter en el resto del lab, con Ansible (desde ansible01)

Requiere la colección `ansible.posix` (`ansible-galaxy collection list | grep posix`; si falta:
`ansible-galaxy collection install ansible.posix`). Comprueba la última versión en
github.com/prometheus/node_exporter/releases y ajusta la variable.

```yaml
# ~/ansible-lab/playbooks/node_exporter.yml
- hosts: lab
  become: true
  vars:
    ne_version: "1.8.2"
  tasks:
    - name: Descargar node_exporter
      ansible.builtin.unarchive:
        src: "https://github.com/prometheus/node_exporter/releases/download/v{{ ne_version }}/node_exporter-{{ ne_version }}.linux-amd64.tar.gz"
        dest: /opt
        remote_src: true
        creates: "/opt/node_exporter-{{ ne_version }}.linux-amd64/node_exporter"
    - name: Binario en /usr/local/bin
      ansible.builtin.copy:
        src: "/opt/node_exporter-{{ ne_version }}.linux-amd64/node_exporter"
        dest: /usr/local/bin/node_exporter
        remote_src: true
        mode: "0755"
      notify: restart node_exporter
    - name: Usuario de sistema
      ansible.builtin.user: { name: node_exporter, system: true, shell: /sbin/nologin, create_home: false }
    - name: Unidad systemd
      ansible.builtin.copy:
        dest: /etc/systemd/system/node_exporter.service
        content: |
          [Unit]
          Description=Prometheus node_exporter
          After=network-online.target
          [Service]
          User=node_exporter
          ExecStart=/usr/local/bin/node_exporter
          Restart=on-failure
          [Install]
          WantedBy=multi-user.target
      notify: restart node_exporter
    - name: Servicio activo
      ansible.builtin.systemd: { name: node_exporter, enabled: true, state: started, daemon_reload: true }
    - name: Puerto 9100 en firewalld
      ansible.posix.firewalld: { port: 9100/tcp, permanent: true, immediate: true, state: enabled }
  handlers:
    - name: restart node_exporter
      ansible.builtin.systemd: { name: node_exporter, state: restarted, daemon_reload: true }
```

Ejecútalo dos veces: la segunda debe dar `changed=0` (idempotencia, igual que en la Etapa 7). Después añade
las IPs `.11 .12 .13 .14 .20 .30` (puerto 9100) a `targets` en `prometheus.yml` y `docker compose restart prometheus`.

### Ejercicio: incidencia simulada

1. En `rhel8-app01`: `sudo systemctl stop node_exporter`.
2. En Prometheus → *Alerts*: `HostDown` pasa a *Pending* y, tras 1 minuto, a *Firing*.
3. Diagnostica (`systemctl status`, `journalctl -u node_exporter`), restaura y comprueba que la alerta se resuelve.
4. Escribe el **PIR** con la plantilla del bloque 5.

---

## Bloque 3 — Kubernetes con k3s (día 3)

### Teoría mínima

| Objeto | Qué es |
|---|---|
| **Pod** | La unidad mínima: uno o varios contenedores que comparten red y almacenamiento |
| **Deployment** | Mantiene N réplicas de un pod y gestiona las actualizaciones (*rolling update*) y el *rollback* |
| **ReplicaSet** | Lo crea el Deployment; garantiza el número de réplicas |
| **Service** | IP y nombre estables delante de pods que cambian. Tipos: `ClusterIP`, `NodePort`, `LoadBalancer` |
| **Namespace** | Separación lógica (equipos, entornos) |
| **ConfigMap / Secret** | Configuración y datos sensibles fuera de la imagen |

Arquitectura: el **control plane** (API server, scheduler, controller manager, etcd) decide; en cada nodo,
el **kubelet** arranca los contenedores. **k3s** es un Kubernetes completo y certificado, empaquetado en un
solo binario: ideal para un lab. La filosofía es **declarativa**: describes el estado deseado en YAML y
Kubernetes lo mantiene.

### Instalación

```bash
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=30000-32767/tcp                 # NodePorts
sudo firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16    # red de pods
sudo firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16    # red de services
sudo firewall-cmd --reload
curl -sfL https://get.k3s.io | sudo sh -s - --write-kubeconfig-mode 644   # 644: solo laboratorio
kubectl get nodes -o wide            # Ready
kubectl get pods -A                  # componentes del sistema
```

En RHEL, el instalador añade también el paquete `k3s-selinux`, porque SELinux sigue en `enforcing`.

### Práctica

```bash
kubectl create deployment web --image=nginx:1.27 --replicas=2
kubectl get deploy,rs,pods -o wide
kubectl expose deployment web --port=80 --type=NodePort
kubectl get svc web                  # anota el puerto 3xxxx → http://10.10.10.50:3xxxx
kubectl scale deployment web --replicas=4
kubectl delete pod <uno-de-los-pods> && kubectl get pods -w   # se recrea solo (autorreparación)

kubectl set image deployment/web nginx=nginx:1.27-alpine      # "release"
kubectl rollout status deployment/web
kubectl rollout history deployment/web
kubectl rollout undo deployment/web                           # "rollback"

kubectl create deployment web2 --image=nginx --dry-run=client -o yaml > web2.yaml
kubectl apply -f web2.yaml           # lo mismo, de forma declarativa (así se trabaja de verdad)

kubectl create deployment roto --image=busybox -- sh -c 'echo arrancando; exit 1'
kubectl get pods                     # CrashLoopBackOff
kubectl describe pod <pod-roto>      # eventos al final
kubectl logs <pod-roto> --previous   # logs del intento anterior
kubectl delete deployment roto
```

---

## Bloque 4 — Jenkins (día 4)

### Teoría mínima

- **CI** (*Continuous Integration*): cada cambio en el repositorio se compila y prueba automáticamente.
- **CD**: *Continuous Delivery* (el despliegue queda listo y requiere aprobación) o *Continuous Deployment*
  (se despliega solo). En banca, casi siempre *Delivery* con aprobación: encaja con el Change Management de ITIL.
- **Pipeline**: etapas (*stages*) con pasos (*steps*), definidas en un `Jenkinsfile` versionado en Git.
- **Agente**: dónde se ejecutan los pasos. **Credenciales**: se guardan en Jenkins, nunca en el `Jenkinsfile`.

### Instalación en Docker

```bash
docker run -d --name jenkins --restart unless-stopped \
  -p 8080:8080 -v jenkins_home:/var/jenkins_home jenkins/jenkins:lts-jdk17
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Abre `http://10.10.10.50:8080`, pega la contraseña, instala los *plugins sugeridos* y crea tu usuario.

### Primer pipeline sobre tu propio repositorio

*New Item → Pipeline* → en *Pipeline script*, pega:

```groovy
pipeline {
  agent any
  stages {
    stage('Checkout') {
      steps { git url: 'https://github.com/salatielaizza/enterprise-rhel-lab.git', branch: 'main' }
    }
    stage('Lint de bash') {
      steps { sh 'find scripts tests -name "*.sh" -print0 | xargs -0 -n1 bash -n && echo "Sintaxis OK"' }
    }
    stage('Aprobación del cambio') {
      steps { input message: '¿Apruebas el despliegue? (Change Management)' }
    }
    stage('Despliegue') {
      steps { echo 'Aquí iría ansible-playbook o kubectl apply' }
    }
  }
  post {
    success { echo 'Pipeline OK' }
    failure { echo 'Pipeline FALLIDO: revisa la consola' }
  }
}
```

*Build Now* → en *Stage View* verás cada etapa. En "Aprobación" se queda esperando tu clic: eso es el
*approval gate* de un cambio. Prueba también a romper un script a propósito en una rama tuya y ver cómo
falla el lint.

**Ampliación (si sobra tiempo):** que el paso de despliegue haga un `kubectl apply` real contra k3s. Hace
falta dar al contenedor de Jenkins el binario `kubectl` y el *kubeconfig*, y SELinux puede bloquearlo: es un
buen ejercicio de troubleshooting, pero no imprescindible para esta etapa.

---

## Bloque 5 — ITIL para operación (día 5)

### Teoría mínima

| Proceso | Objetivo | Ejemplo en el lab |
|---|---|---|
| **Incident Management** | Restaurar el servicio **lo antes posible** | La alerta `HostDown` del bloque 2 |
| **Problem Management** | Encontrar la **causa raíz** para que no se repita | Tus casos de `troubleshooting/` |
| **Known Error / Knowledge Base** | Documentar la solución o el *workaround* | Las guías `README_troubleshooting_etapaN.md` |
| **Change Management** | Evaluar, aprobar y registrar cambios. Tipos: **estándar** (preaprobado), **normal** (CAB) y **de emergencia** | El `input` del pipeline de Jenkins; snapshot antes del cambio |
| **Release Management** | Poner en producción versiones de forma controlada, con *rollback* | `kubectl rollout` / `rollout undo` |

Métricas básicas de operación: **SLA** (acuerdo con el cliente), **SLO** (objetivo interno),
**MTTR** (tiempo medio de restauración) y **prioridad = impacto × urgencia**.

### Plantilla de PIR (Post Incident Review)

```markdown
# PIR — <título breve>
- Fecha / duración: inicio HH:MM, detección HH:MM, restauración HH:MM (MTTR: X min)
- Impacto: qué servicio, qué usuarios, severidad
- Detección: alerta / usuario / monitorización
- Cronología: hechos con hora, sin culpables
- Causa raíz: el porqué real (técnica de los 5 porqués)
- Resolución: qué se hizo para restaurar
- Acciones preventivas: responsable y fecha de cada una
- Lecciones aprendidas
```

Rellénala con la incidencia simulada del bloque 2. Es un documento que sirve de ejemplo de trabajo real.

---

## Bloque 6 — APS y ServiceNow (día 6)

### Teoría mínima

**APS (*Application Production Support*)** es el equipo que mantiene vivas las aplicaciones en producción.
Su trabajo no es construir infraestructura, sino que el servicio funcione: incidencias de nivel 2/3,
análisis de logs, vigilancia de procesos batch y transferencias de ficheros, releases, accesos y
documentación. Casi todas las responsabilidades del anuncio son de APS.

**ServiceNow** es la plataforma ITSM donde vive ese trabajo: cada incidencia, problema, cambio o artículo
de conocimiento es un registro con estados, prioridad, grupo asignado y notas.

| Registro | Estados típicos | Campos clave |
|---|---|---|
| **Incident** | New → In Progress → On Hold → Resolved → Closed | *Impact*, *Urgency* → **Priority** (calculada), *Assignment group*, *Work notes* (internas) vs *Additional comments* (visibles al usuario) |
| **Problem** | New → Assess → Root Cause Analysis → Fix in Progress → Resolved | Incidencias relacionadas, causa raíz, *workaround* |
| **Change Request** | New → Assess → Authorize → Scheduled → Implement → Review → Closed | Tipo (estándar/normal/emergencia), plan de implementación, **plan de backout**, ventana, aprobación |
| **Knowledge Article** | Draft → Review → Published | Síntoma, causa, solución |

### Práctica en una instancia gratuita

ServiceNow ofrece una **instancia personal de desarrollador (PDI)** gratuita en
developer.servicenow.com. Comprueba sus condiciones al registrarte (se suspende si no la usas un tiempo).

1. **Incident:** crea una para la caída de `node_exporter` del bloque 2. Pon *Impact* 2 y *Urgency* 2 y mira
   qué *Priority* calcula. Asígnala a un grupo, escribe *work notes* con tu diagnóstico y llévala a *Resolved*
   con un *resolution code*.
2. **Problem:** créalo desde la incidencia (*Create Problem*) y documenta la causa raíz.
3. **Change Request:** un cambio normal "Actualizar nginx en k3s" con plan de implementación
   (`kubectl set image`), plan de backout (`kubectl rollout undo`) y ventana de cambio.
4. **Knowledge:** un artículo con el síntoma y la solución.

### Crear una incidencia desde el lab (Table API)

```bash
SN=https://devXXXXX.service-now.com            # tu instancia
read -rsp "Contraseña de admin de la PDI: " SNPASS; echo
curl -s -u "admin:$SNPASS" -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -X POST "$SN/api/now/table/incident" \
  -d '{"short_description":"HostDown: rhel8-app01 no responde","impact":"2","urgency":"2"}' \
  | python3 -m json.tool | grep -E '"number"|"priority"'
```

La respuesta trae el número (`INC00…`). Es el mismo mecanismo con el que, en un banco, una alerta de
monitorización abre la incidencia sola (Alertmanager → *webhook* → ServiceNow). La contraseña se pide por
teclado para que no quede en el historial de la shell.

### Análisis de logs: los comandos de cada día

```bash
journalctl -u nginx --since "1 hour ago" -p err      # errores de un servicio en la última hora
journalctl -b -1 -p warning                          # avisos del arranque anterior
tail -f /var/log/messages | grep -i --line-buffered error   # seguir un log en directo
less +F /var/log/app.log                             # como tail -f, pero con Ctrl+C puedes buscar
grep -c ERROR app.log                                # cuántos errores
grep -B3 -A10 'OutOfMemory' app.log                  # contexto antes y después de un error
awk '{print $9}' access.log | sort | uniq -c | sort -rn   # códigos HTTP más frecuentes (log de nginx/httpd)
zgrep ERROR app.log.*.gz                             # buscar en logs rotados y comprimidos
docker logs --since 10m <contenedor>                 # logs de un contenedor
kubectl logs deploy/web --tail=100 -f                # logs de un Deployment en k8s
```

### Ejercicio: un batch nocturno que falla

1. En `rhel9-monitor01`, crea un "batch" que falle a propósito:
   ```bash
   sudo tee /usr/local/bin/batch-cierre.sh >/dev/null <<'EOF'
   #!/usr/bin/env bash
   set -euo pipefail
   echo "Inicio cierre diario"
   test -f /srv/entrada/fichero_del_dia.csv     # el fichero de entrada no ha llegado
   echo "Cierre OK"
   EOF
   sudo chmod 755 /usr/local/bin/batch-cierre.sh
   sudo tee /etc/systemd/system/batch-cierre.service >/dev/null <<'EOF'
   [Unit]
   Description=Batch de cierre diario (laboratorio)
   [Service]
   Type=oneshot
   ExecStart=/usr/local/bin/batch-cierre.sh
   EOF
   sudo tee /etc/systemd/system/batch-cierre.timer >/dev/null <<'EOF'
   [Unit]
   Description=Lanza el cierre diario
   [Timer]
   OnCalendar=*-*-* 02:00
   Persistent=true
   [Install]
   WantedBy=timers.target
   EOF
   sudo systemctl daemon-reload && sudo systemctl enable --now batch-cierre.timer
   sudo systemctl start batch-cierre.service       # lanzarlo ahora, como un relanzamiento manual
   ```
2. **Detecta:** `systemctl list-timers batch-cierre*`, `systemctl status batch-cierre.service`
   (`status=1/FAILURE`), `journalctl -u batch-cierre.service -n 20`.
3. **Registra** la incidencia en ServiceNow con el `curl` de arriba.
4. **Resuelve:** `sudo mkdir -p /srv/entrada && sudo touch /srv/entrada/fichero_del_dia.csv` (simula que
   llega el fichero) y **relanza** con `sudo systemctl start batch-cierre.service`.
5. **Cierra** la incidencia con la causa ("no llegó el fichero de entrada de la interfaz") y una acción
   preventiva (alerta si el fichero no ha llegado a las 01:30).

En banca, la planificación de batch suele hacerse con **Control-M**; el concepto es el mismo: dependencias,
ventanas horarias, códigos de retorno, relanzamientos y escalado si falla.

---

## Día 7 — Repaso

Preguntas para responder en voz alta, en español y en inglés:

1. ¿Qué diferencia hay entre una imagen y un contenedor? ¿Y entre un contenedor y una VM?
2. ¿Docker o Podman? ¿Por qué Red Hat prefiere Podman?
3. ¿Qué pasa si borras un pod de un Deployment? ¿Y si borras el Deployment?
4. ¿Cómo harías un rollback de una release en Kubernetes?
5. Un pod está en `CrashLoopBackOff`: ¿qué tres comandos ejecutas primero?
6. ¿Qué diferencia hay entre Continuous Delivery y Continuous Deployment?
7. ¿Por qué Prometheus es *pull*? ¿Qué es un exporter?
8. ¿Cómo crearías una alerta de disco lleno?
9. Diferencia entre incidencia y problema en ITIL.
10. ¿Qué incluye un PIR y por qué se hace sin buscar culpables?
11. ¿Qué hace un equipo de APS? ¿Qué diferencia hay entre *work notes* y *additional comments* en ServiceNow?
12. Un batch nocturno ha fallado: ¿cómo lo detectas, qué miras primero y cómo lo relanzas?

### Vocabulario técnico en inglés

| Español | Inglés |
|---|---|
| Restaurar el servicio | *Restore service* |
| Causa raíz | *Root cause* |
| Revisión posterior a la incidencia | *Post-incident review (PIR) / postmortem* |
| Gestión de cambios | *Change management* (*CAB*: *Change Advisory Board*) |
| Marcha atrás | *Rollback* |
| Procesos por lotes | *Batch jobs* |
| Guardia | *On-call* |
| Base de conocimiento | *Knowledge base (KB) article* |
| Plan de marcha atrás de un cambio | *Backout plan* |
| Grupo resolutor | *Assignment group* |

## Criterios de aceptación

- [ ] Imagen propia construida y ejecutada con Docker
- [ ] Prometheus con todos los nodos del lab en `UP` y dashboard 1860 en Grafana
- [ ] Alerta `HostDown` disparada y resuelta, con su PIR escrito
- [ ] Deployment en k3s escalado, actualizado y revertido con `rollout undo`
- [ ] Pipeline de Jenkins con lint, aprobación y despliegue (simulado)
- [ ] Incidencia, problema, cambio y artículo de conocimiento creados en la PDI de ServiceNow
- [ ] Incidencia creada por API (`curl` a la Table API) desde el lab
- [ ] Batch fallido detectado, relanzado y cerrado con su causa
- [ ] Las 12 preguntas de repaso respondidas sin mirar
- [ ] Snapshot de `rhel9-monitor01` al terminar
