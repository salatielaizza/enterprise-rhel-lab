# Etapa 8 — Kubernetes y OpenShift, con Prometheus/Grafana y Terraform: práctica manual paso a paso

> **Estado: 🚧 En curso** (8.1 empezada el 2026-10-29). Todo **a mano**; la automatización (Ansible, Terraform, GitOps)
> llega al final y solo para lo ya hecho a mano.
> Primero los **enunciados** K1-K13 (secciones 0-5); las **soluciones**, al final (sección 6), con cada comando
> explicado, la salida esperada y qué hacer si sale otra cosa. Intenta cada ejercicio antes de mirarlas.
> Checklist: [`checklists/etapa8.md`](../checklists/etapa8.md) · Ficheros: [`scripts/stage8/`](../scripts/stage8/README_stage8.md) ·
> Casos reales: [`troubleshooting/etapa8/`](../troubleshooting/etapa8/README_troubleshooting_etapa8.md) ·
> Guías de la 8.8 y la 8.9: [Prometheus/Grafana](monitorizacion-prometheus-grafana.md) · [Terraform](terraform-iac.md)

---

## 0. Reglas de la práctica

- **Todo a mano**, sin `lab.sh stage8-*` (no existen). `lab.sh` solo para crear las VMs, pasarlas por las etapas 2-5,
  tests y snapshots.
- **Dónde se ejecuta cada cosa** (en las soluciones va en la primera línea de cada bloque):

  | Etiqueta | Significa |
  |---|---|
  | `# [host]` | Linux Mint, en la raíz del repo |
  | `# [ansible01 · adminlab]` | `ssh adminlab@ansible01`; aquí se usan `kubectl`, `helm` y `terraform` |
  | `# [k8s-cp01 · root]` | `ssh adminlab@k8s-cp01` y `sudo -i` |
  | `# [nodos · root]` | Lo mismo en los tres nodos (`k8s-cp01`, `k8s-w01`, `k8s-w02`) |
  | `# [workers · root]` | Solo en `k8s-w01` y `k8s-w02` |

- **Antes de aplicar, simula:** `kubectl apply --dry-run=server`, `helm template`, `terraform plan`.
- **Nombres completos** de imagen (`registro/ruta:etiqueta`), nunca nombres cortos ni `latest` (lo aprendiste en K1).
- **Si algo no sale como dice la solución, para.** No encadenes comandos: pega la salida y conviértelo en un caso de
  `troubleshooting/etapa8/`.
- **Snapshots** con los nodos **apagados** (un clúster encendido no da un snapshot consistente):
  `*-stage5-complete` antes de K2, `*-cluster-vacio` al acabar K2, `*-antes-8.6`, `*-antes-8.9` y `*-antes-8.12`.
  Procedimiento en la solución de K2 (paso 8.2.7).
- **Orden recomendado:** K1 → K2 → K3 → K4 → K5 → K6 → K7 → K8 → K9 → K11 → K12 → K13 → **K10 al final** (OpenShift
  Local necesita el clúster apagado y toca el host).
- **Ningún secreto** en el repo: contraseñas, `kubeconfig`, claves privadas y `tfstate` se quedan en las VMs.

---

## 1. La arquitectura en una mirada

```
 TU LINUX MINT (host)  ── repo git · lab.sh (VMs, snapshots) · OpenShift Local en K10
        │
 red lab-net 10.10.10.0/24 · DNS dns01 (.20)
        │
 ansible01 (.30) · ESTACIÓN DE CONTROL ── podman (K1) · kubectl · helm · terraform · argocd · ansible
        │  API de Kubernetes https://k8s-api.lab.local:6443
        ▼
 k8s-cp01 (.100)              k8s-w01 (.101)             k8s-w02 (.102)
 plano de control             worker                     worker
 apiserver · etcd             kubelet · containerd       kubelet · containerd
 scheduler · controller-mgr   kube-proxy · calico-node   kube-proxy · calico-node
        │
 Pods 10.244.0.0/16 (Calico) · Services 10.96.0.0/12 · LoadBalancer (MetalLB) .110-.119
   ingress .110 · grafana .111 · prometheus .112 · alertmanager .113 · podinfo .114
   gitea .115 · argocd .116 · tienda .117
```

**Qué pasa en `kubectl apply -f app.yaml`:** `kubectl` envía el objeto a la **API** → la API lo valida (esquema, RBAC,
Pod Security) y lo guarda en **etcd** → el **controlador** del Deployment crea un ReplicaSet y este, los Pods → el
**scheduler** elige un nodo para cada Pod → el **kubelet** de ese nodo pide a **containerd** que descargue la imagen y
arranque los contenedores → **Calico** le da una IP de pod → **kube-proxy** añade el pod al Service.

| Herramienta | Responde a… |
|---|---|
| `podman` | "Ejecuta un contenedor **aquí**, sin clúster" |
| `kubeadm` | "**Crea** el clúster / une un nodo / actualízalo" |
| `kubectl` | "¿**Qué hay** en el clúster? Cámbialo" |
| `crictl` | "¿Qué contenedores hay en **este nodo**?" (sin pasar por la API) |
| `helm` | "Instala un **paquete** (chart) con estos valores" |
| `terraform` | "Deja la plataforma **como dice el código**, y enséñame antes el plan" |
| Argo CD | "Deja el clúster **como dice Git**, siempre" |
| `oc` | `kubectl` de OpenShift, con extras (`new-project`, `expose`, `new-app`) |

---

## 2. Conceptos que vas a usar en todos los ejercicios

| Concepto | En una frase |
|---|---|
| **Estado deseado** | Declaras qué quieres (`replicas: 2`) y los controladores trabajan sin parar para que la realidad coincida |
| **Pod** | Uno o más contenedores que comparten red (misma IP, `localhost`) y volúmenes |
| **Deployment → ReplicaSet → Pod** | El Deployment gestiona versiones; cada versión es un ReplicaSet; el ReplicaSet mantiene N pods |
| **Service** | IP y nombre DNS estables delante de pods que cambian; los elige por **etiquetas** |
| **Namespace** | Espacio de nombres: separa equipos, permisos (RBAC), cuotas y nivel de Pod Security |
| **Pod estático** | Pod que el kubelet arranca leyendo un fichero (`/etc/kubernetes/manifests/`), sin API: así arranca la propia API |
| **CNI** | El plugin de red de pods (Calico). Sin él, los nodos están `NotReady` |
| **PV / PVC / StorageClass** | Volumen real / petición de volumen / quién lo crea y cómo |
| **RBAC** | Quién (usuario, grupo, ServiceAccount) puede hacer qué verbo sobre qué recurso, y dónde |
| **Chart / release** | Paquete de Helm / una instalación concreta con su historial |
| **Estado de Terraform** | Lo que Terraform cree que existe; el `plan` compara código, estado y realidad |
| **GitOps** | Un agente dentro del clúster lo mantiene igual que un repositorio Git |

Las preguntas de diagnóstico que sirven siempre: `kubectl get` (¿qué hay?), `kubectl describe` + **Events** (¿qué ha
pasado?), `kubectl logs [--previous]` (¿qué dice la aplicación?) y, en el nodo, `journalctl -u kubelet -u containerd`
y `crictl ps -a`.

---

## 3. Ejercicios (enunciados)

### K1 — Contenedores con Podman, sin clúster (ansible01)

> ✅ Hecho hasta el punto 4 (2026-10-29/30). La solución 6.1 lleva tus resultados reales.

1. Instala Podman **de la forma soportada** en RHEL 9 y comprueba versión, modo rootless, backend de red, dónde
   guarda las imágenes y tu rango de subuid/subgid.
2. Arranca podinfo 6.15.0 publicando el puerto 9898 en el 8080. Comprueba que responde y demuestra, con dos comandos,
   que el contenedor es **un proceso del host** y con qué UID corre dentro y fuera.
3. Construye una imagen propia `localhost/lab/saludo:1.0` desde UBI 9 minimal (etiqueta fija, no `latest`) con un
   script de bash al estilo de la Etapa 6 y `USER 1001`. Ejecútala y muestra sus capas, su usuario y su comando.
4. Monta `~/datos` en un contenedor **sin** `:Z` y **con** `:Z`. Demuestra quién bloquea el primer intento y qué
   cambia en el disco con el segundo.
5. Crea un **pod** de Podman con dos contenedores (podinfo y un cliente que lo llame por `localhost` cada 10 s). Genera
   su YAML de Kubernetes, bórralo y recréalo desde ese YAML.
6. Haz que un contenedor de `saludo` arranque **solo** al reiniciar `ansible01`, sin Kubernetes (Quadlet).
7. (Opcional) Compara entre RHEL 7/8/9/10 si Podman viene instalado y qué versión de cgroups usa cada uno.

**Comprueba:** `podman ps --pod` (¿cuántos contenedores y por qué?), `ls -laZ ~/datos`, `podman ps` tras el reboot.

**Preguntas:** (a) ¿por qué `podman build` desde `~` es mala idea aunque funcione? (b) ¿qué pasa al ejecutar
`podman run lab/saludo:1.0` si la imagen no existe en local? (c) ¿por qué el contenedor rootless no puede leer
`~/datos` si `adminlab` es el dueño? (d) ¿qué UID tiene en el host un proceso que dentro es el 1001?

### K2 — Un clúster de 3 nodos con kubeadm

1. Crea `k8s-cp01`, `k8s-w01` y `k8s-w02` con `lab.sh`, regístralas y pásalas por las etapas 2-5. Comprueba que la base
   del lab sigue en 0 FAIL y que `k8s-api.lab.local` resuelve. Snapshot `stage5`.
2. Prepara **cada nodo** a mano:
   - LVs de 16, 6 y 8 GiB en `vg_data` para `/var/lib/containerd`, `/var/lib/kubelet` y `/var/lib/local-path`
     (validando `fstab` antes de montar);
   - swap desactivada de forma persistente;
   - módulos `overlay` y `br_netfilter` y los tres sysctl de la red de pods, persistentes;
   - NetworkManager sin gestionar las interfaces de Calico;
   - una zona `k8s` de firewalld para el lab y las redes del clúster, **sin perder el SSH**, con los puertos de cada
     tipo de nodo;
   - containerd desde el repositorio de Docker, con el plugin CRI activo y `SystemdCgroup = true`;
   - kubeadm, kubelet y kubectl **1.36.5**, protegidos contra un `dnf update` rutinario.
3. Inicializa el plano de control con `scripts/stage8/files/cluster/kubeadm-config.yaml` (léelo antes) y explica las
   fases de la salida. Configura `kubectl` para `adminlab`.
4. ¿Por qué el nodo sale `NotReady` y CoreDNS `Pending`? Arréglalo instalando Calico con su operador y
   `calico-custom-resources.yaml`.
5. Une los dos workers con un token **nuevo**.
6. Administra el clúster desde `ansible01`: `kubectl` (con autocompletado), Helm 4 verificado con su suma y una copia del
   repo.
7. Comprueba la salud del clúster y de sus certificados, y haz el snapshot `*-cluster-vacio` con los nodos apagados.

**Comprueba:** `kubectl get nodes -o wide` (3 Ready, v1.36.5, containerd), `kubectl get pods -A`,
`kubectl get --raw='/readyz?verbose'`, `kubeadm certs check-expiration`, `lab.sh test all k8s-cp01`.

**Preguntas:** (a) ¿qué hace cada componente del plano de control y de cada nodo? (b) ¿cómo arranca el kubelet la API
si la API es un pod? (c) ¿por qué `NotReady` justo después del `init`? (d) ¿para qué sirve el `exclude=` del
repositorio? (e) ¿por qué `SystemdCgroup = true`?

### K3 — Objetos de Kubernetes (namespace `demo`)

1. Despliega `apps/podinfo.yaml` y explica la cadena Deployment → ReplicaSet → Pod con la salida de un solo `get`.
2. Borra un pod y observa qué pasa. Escala a 4 y vuelve a 2. ¿Por qué ninguno va a `k8s-cp01`?
3. Haz un *rolling update* (cambia una variable de entorno), mira el historial y vuelve atrás.
4. Pasa configuración con un ConfigMap y crea un Secret. Demuestra que el Secret **no** está cifrado.
5. Quita a un pod la etiqueta del selector. ¿Qué hacen el ReplicaSet y el Service?
6. Crea un Job con `kubectl create job` en `demo`. Lee por qué falla y corrígelo con un YAML.
7. Encuentra los DaemonSets del clúster y explica por qué hay uno por nodo.
8. Usa los eventos y `describe` para contar lo que acabas de hacer. Deja `demo` como estaba (sin restos de `set env`).

**Preguntas:** (a) ¿por qué no se crean Pods sueltos? (b) ¿qué pasa al quitar a un pod la etiqueta del selector?
(c) ¿un Secret está cifrado? (d) ¿por qué ningún pod de podinfo va a `k8s-cp01`?

### K4 — Red: Services, DNS, MetalLB, Ingress/Gateway y NetworkPolicies

1. Demuestra las tres capas de un Service: ClusterIP (por DNS interno), NodePort y LoadBalancer.
2. Comprueba que un pod resuelve `podinfo.demo.svc.cluster.local` **y** `dns01.lab.local`, y explica por qué el segundo.
3. Instala MetalLB (0.16.1) con Helm y su pool `.110-.119`. Haz que podinfo responda en `http://podinfo.lab.local` y
   averigua **qué nodo** anuncia la IP. ¿Qué cambia `externalTrafficPolicy: Local`?
4. Instala Traefik con Gateway API. Publica podinfo con un `Ingress` en `ingress.lab.local` y con un `HTTPRoute` con
   otro nombre, en la **misma IP**.
5. Aplica `apps/loadgen.yaml` y `apps/networkpolicies.yaml`. Demuestra qué entra y qué no (desde `loadgen`, desde otro
   namespace y desde la red del lab). Algo que funcionaba en el punto 4 deja de funcionar: encuéntralo y arréglalo con
   una política mínima.

**Preguntas:** (a) ¿qué añade cada tipo de Service? (b) ¿por qué el pod bloqueado da timeout y no "connection
refused"? (c) ¿por qué se rompió el Ingress? (d) ¿qué ventaja tiene Gateway API sobre Ingress?

### K5 — Almacenamiento con local-path

1. Instala local-path-provisioner v0.0.37, haz que use `/var/lib/local-path` (el LV de K2) y que sea la StorageClass
   por defecto.
2. Crea un PVC de 1 Gi **solo** y explica su estado. Después, un Deployment (que cumpla `restricted`) que escriba la
   fecha cada 10 s en el volumen.
3. Borra el pod: demuestra que los datos sobreviven y en qué nodo están.
4. Encuentra el volumen en el disco del nodo y su contexto SELinux.
5. Borra el PVC y comprueba qué pasa con los datos.

**Preguntas:** (a) ¿por qué el PVC se queda en `Pending` sin pod? (b) ¿qué significa `ReadWriteOnce`? (c) ¿qué pasa
con los datos al borrar el PVC?

### K6 — Seguridad: RBAC, ServiceAccounts, Pod Security, Secrets y SELinux

1. Crea el usuario `dev-tienda` (grupo `equipo-tienda`) con un certificado firmado por el clúster, válido 30 días, con
   permiso de edición **solo** en el namespace `tienda`. Demuéstralo con `auth can-i` y con un `Forbidden` real.
2. Crea una ServiceAccount en `demo` que solo pueda listar pods. Desde un pod que la use, llama a la API con su token:
   listar (sí), borrar (no), secrets (no).
3. Muestra los niveles de Pod Security de cada namespace. Averigua, **sin cambiar nada**, qué pasaría si
   `metallb-system` fuera `restricted`.
4. Demuestra que un Secret se lee en claro con permisos de `edit` y que en etcd está en claro.
5. Activa SELinux en containerd en **un** worker. Compara el contexto de los procesos de los pods en los dos workers.
   Busca qué se rompe con un volumen de local-path y arréglalo **sin** `setenforce 0`.

**Preguntas:** (a) ¿dónde están los usuarios de Kubernetes? (b) `Role` + `RoleBinding` frente a `ClusterRole` +
`RoleBinding`. (c) ¿por qué `metallb-system` no puede ser `restricted`? (d) ¿está cifrado un Secret? (e) ¿qué añade
`enable_selinux = true`?

### K7 — Helm (Gitea)

1. Inspecciona las releases que ya tienes (MetalLB, Traefik): historial, valores tuyos frente a efectivos y qué
   objetos crearía el chart, sin aplicarlo.
2. Instala Gitea con `apps/gitea-values.yaml`: contraseña de administrador en un Secret, versión de chart fijada, y
   comprobación previa de que tus claves de valores existen en el chart.
3. Entra en http://gitea.lab.local y crea la organización `lab` y el repo público `k8s-apps` (lo usa K11).
4. Haz un `upgrade` cambiando un valor, mira el historial, haz `rollback` a la revisión 1 y explica la revisión que
   aparece.

**Preguntas:** (a) ¿dónde guarda Helm el historial? (b) ¿qué pasa si escribes mal una clave de valores? (c) ¿un
`rollback` borra la revisión mala?

### K8 — Prometheus y Grafana

Sigue la guía del repo `kubernetes/monitorizacion-prometheus-grafana.md`:

1. Instala kube-prometheus-stack 88.6.2 con la contraseña de Grafana en un Secret. Comprueba *Targets* todo `UP`, solo
   la alerta `Watchdog` y el dashboard "Lab · podinfo (RED)".
2. Prueba las reglas sin clúster con `promtool test rules`.
3. Haz los escenarios **E00-E12**. En cada uno, apunta: cuánto tarda la alerta, qué consulta PromQL lo demuestra y qué
   comando de `kubectl` da la causa.
4. Grafana: dashboard 1860, un panel nuevo **como código** que sobreviva a recargar, una variable `namespace` y un
   usuario *Viewer*.

**Antes de K9:** snapshot `*-antes-8.9`.

### K9 — Terraform

Sigue la guía del repo `kubernetes/terraform-iac.md`, escenarios **T1-T8**:

1. `init` y `plan` **sin aplicar**: ¿qué quiere crear y por qué fallaría?
2. Adopta con `import` lo hecho a mano (0 to destroy, innegociable) y llega a `No changes`.
3. Crea `tienda-web` con el módulo, provoca *drift*, el bloqueo del estado, el error de CRD inexistente y prueba
   `prevent_destroy` y `moved`.
4. Escribe tu tabla de quién hace qué: Terraform, Ansible o Argo CD.

### K10 — OpenShift Local (al final de la etapa, en el host)

1. Revisa el host **en solo lectura** (CPU, RAM, disco, redes de libvirt, DNS del lab) y guarda el "antes".
2. Apaga el clúster, descarga `crc` y el *pull secret*, y configura 11 GiB y 4 CPU. Averigua **qué cambiaría**
   `crc setup` sin ejecutarlo y decide.
3. (Si decides seguir) arranca OpenShift y comprueba que el DNS del lab sigue funcionando.
4. Despliega podinfo en un proyecto `tienda`: ¿por qué falla con el mismo YAML que en Kubernetes y cómo se arregla?
   Publícalo con una Route.
5. Compara con lo que hiciste a mano: proyectos, SCC, Routes, S2I, monitorización integrada y operadores.
6. Deja el host como estaba y compara con el "antes".

### K11 — CI y GitOps (Gitea + Argo CD)

1. Instala `yamllint`, `kubeconform` y `promtool` (con suma de verificación) y ejecuta
   `scripts/stage8/files/ci/validar.sh` hasta `RESULTADO: OK`.
2. En una **copia**, rompe una regla de alerta, un YAML y un manifiesto, y comprueba que el CI lo caza.
3. Instala Argo CD v3.5.2 en `.116`.
4. Sube a `lab/k8s-apps` (Gitea) un Deployment y un Service de podinfo y crea una `Application` con sincronización
   automática, `prune` y `selfHeal` hacia el namespace `gitops`.
5. Escala a mano y mira qué pasa. Cambia las réplicas con un commit. Vuelve atrás con `git revert`.

**Preguntas:** (a) `kubectl apply` desde un pipeline frente a GitOps. (b) ¿cómo se vuelve atrás en GitOps? (c) ¿qué
hace `selfHeal`?

### K12 — Operación: mantenimiento, etcd y upgrade

1. Saca un worker para "parchearlo" (drain, `dnf update`, reboot, uncordon) sin cortar podinfo.
2. Con un PodDisruptionBudget `minAvailable: 1` y una sola réplica, intenta el mismo `drain`. Explica y arréglalo.
3. Haz una copia de etcd, compruébala y llévala **fuera** del nodo.
4. Crea un namespace `borrame`, haz una copia, bórralo y **restaura** etcd hasta que vuelva.
5. Actualiza el clúster de 1.36 a 1.37 (plano de control primero, workers de uno en uno) con un bucle de `curl` contra
   podinfo que demuestre que no hay corte. Actualiza también `kubectl` en `ansible01`.

**Antes:** snapshot `*-antes-8.12`.

### K13 — Automatizar con Ansible lo que hiciste a mano

En un proyecto **separado** `ansible01:~/k8s-ansible` (nunca en `~/ansible-lab`):

1. Inventario con `control_plane`, `workers` y el padre `k8s`; colecciones con versión fijada dentro del proyecto.
2. Rol `k8s_node` con **todo** el punto 2 de K2. Criterio: `--check` válido y `changed=0` la segunda vez.
3. Playbook `k8s-cluster.yml`: `init` solo si no hay clúster, Calico, y `join` de los workers con un token generado al
   vuelo (`delegate_to`).
4. **Prueba de fuego:** saca `k8s-w02` del clúster, devuélvelo al snapshot `stage5` y reconstrúyelo **solo con Ansible**
   hasta `Ready`.
5. (Ampliación) Rol `node_exporter` para las VMs del lab.

---

## 4. Ideas para seguir practicando

- Repite K3 escribiendo tú el YAML de podinfo desde cero, con `kubectl create deployment --dry-run=client -o yaml`
  como punto de partida y `kubectl explain` como documentación.
- Añade un `HorizontalPodAutoscaler` a podinfo (necesita `metrics-server`) y provócalo con el `loadgen`.
- Cifrado en reposo de los Secrets (`EncryptionConfiguration`) y comprobación con `etcdctl` (ampliación de K6).
- Un *runner* de Gitea Actions que ejecute `validar.sh` en cada `push` (ampliación de K11).
- Velero con MinIO para copias de objetos y volúmenes (ampliación de K12).
- Preguntas tipo CKA: "un nodo `NotReady`", "un pod en `Pending`", "un Service sin endpoints". Diagnostica cada una
  solo con `get`, `describe`, `logs` y `journalctl`.

---

## 5. Limpieza

- **Por ejercicio:** cada solución termina con su limpieza (los `delete -f`, los `set env VAR-`, `helm uninstall`).
- **El clúster entero:** vuelve al snapshot `*-cluster-vacio` (apaga los tres nodos y `virsh snapshot-revert <nodo>
  <nodo>-cluster-vacio`) o, para quitar Kubernetes, a `*-stage5-complete` (`scripts/lab.sh snapshot revert k8s-cp01 5`,
  ídem workers).
- **ansible01:** el contenedor `saludo` y el *linger* de K1 (reversión en la solución 6.1, paso 8.1.5); los binarios
  de `~/.local/bin` y `/usr/local/bin` (helm, kubeconform, promtool) se pueden quedar.
- **Host:** `crc cleanup` deshace `crc setup` (K10).

---

## 6. Soluciones

> Los resultados marcados **✅ Resultado real** son de tu lab. El resto son la salida **esperada**: compárala con la
> tuya y, si difiere, es un caso de troubleshooting. Los números de paso (8.1.2, 8.2.2 f…) corresponden a las subetapas 8.1-8.13. Los manifiestos de `apps/`, `cluster/` y `monitoring/` están en `scripts/stage8/files/`.

### 6.1 Solución K1 — Contenedores con Podman (en ansible01)

**Objetivo:** entender los contenedores **sin orquestador** antes de montar Kubernetes: imagen frente a contenedor,
capas, rootless y subuid, SELinux con `:Z`, pods y systemd. Todo lo de esta subetapa reaparece en la 8.2 con containerd.

**Dónde:** `ansible01`, como `adminlab`. `dns01` encendida (es su DNS). El host no se toca.

**Vuelta atrás:** nada de esta subetapa es destructivo. La reversión está al final de cada ejercicio y, si todo falla,
`scripts/lab.sh snapshot revert ansible01 7`.

| Paso | Qué | Estado |
|---|---|---|
| 8.1.0 | Instalar y comprobar Podman | ✅ 2026-10-29 |
| 8.1.1 | Primer contenedor: proceso dentro y fuera | ✅ 2026-10-29 |
| 8.1.2 | Imagen propia con un `Containerfile` | ✅ 2026-10-29 (caso 01) |
| 8.1.3 | Volúmenes y SELinux (`:Z`) | ✅ 2026-10-30 |
| 8.1.4 | Pod de Podman y YAML de Kubernetes | ⏳ |
| 8.1.5 | Servicio systemd con Quadlet | ⏳ |
| 8.1.6 | Comparación entre versiones de RHEL (opcional) | ⏳ |

#### 8.1.0 Instalar y comprobar Podman

El kickstart del lab instala un sistema **mínimo**: Podman está en AppStream, pero **no viene instalado**. Sale
`podman: command not found` hasta que lo instalas.

**1. ¿Responden los repos?**

```bash
# [ansible01 · adminlab]
sudo subscription-manager repos --list-enabled | grep 'Repo ID'
dnf info podman container-tools 2>&1 | grep -E '^(Name|Version|Release|Repository)|Error|error'
```

| Comando | Qué hace | Qué esperas | Si sale otra cosa |
|---|---|---|---|
| `repos --list-enabled` | Lista los repos **configurados** | `rhel-9-for-x86_64-baseos-rpms` y `...-appstream-rpms` | Vacío o error → la suscripción no da repos. Para y revísala (`subscription-manager status`) |
| `dnf info ...` | **Descarga** los metadatos y busca los paquetes: prueba que el certificado sigue siendo válido | Dos bloques, `container-tools` y `podman`, con `Repository : rhel-9-for-x86_64-appstream-rpms` | `Failed to download metadata` o `403` → certificado caducado. `No matching packages` → AppStream no está habilitado |

> ✅ **Resultado real (2026-10-29):** los dos repos habilitados; `container-tools-1-15.el9` y `podman-5.8.2-8.el9_8`
> en AppStream. El sufijo `el9_8` es la build de RHEL 9.8, la misma versión menor que `ansible01`.

**2. Instalar.** No elijas una versión a mano: se instala **la de AppStream de tu versión menor**, que Red Hat prueba
junto con `container-selinux`, `crun`, `netavark` y el kernel de esa versión.

```bash
# [ansible01 · adminlab]
sudo dnf install -y container-tools
```

- **Qué hace:** instala el metapaquete `container-tools`: `podman`, `buildah` (lo que hay debajo de `podman build`),
  `skopeo` (inspeccionar y copiar imágenes sin descargarlas) y sus dependencias (`container-selinux`, `crun`, `conmon`,
  `netavark`, `passt`).
- **Qué esperas:** `Complete!` al final.
- **Diferencia con RHEL 8:** allí es un **módulo** (`dnf module install container-tools:rhel8`). En RHEL 9 los
  módulos de contenedores desaparecen y es un paquete normal.

**3. Comprobar.** Como `adminlab`, sin `sudo`:

```bash
# [ansible01 · adminlab]
podman --version
podman info --format '{{.Host.Security.Rootless}} {{.Host.NetworkBackend}} {{.Store.GraphRoot}}'
grep adminlab /etc/subuid /etc/subgid
getenforce; free -h | head -2; df -h ~ | tail -1
```

| Comando | Qué esperas | Qué significa | Si sale otra cosa |
|---|---|---|---|
| `podman --version` | `podman version 5.8.2` | La de AppStream 9.8 | — |
| `podman info --format` | `true netavark /home/adminlab/.local/share/containers/storage` | Rootless (sin root); backend de red actual (CNI está retirado en Podman 5); las imágenes cuentan en `/home`, no en `/var` | `false` → estás como root |
| `grep /etc/subuid /etc/subgid` | `adminlab:100000:65536` en los dos | El UID 0 del contenedor es `adminlab`; del 1 en adelante, los UIDs 100000-165535 del host | Sin línea → rootless falla con `cannot find mappings` |
| `getenforce` / `free` / `df` | `Enforcing`, ≥ 1 GiB libre, ≥ 2 GB libres en `/home` | Sin `Enforcing`, el ejercicio de `:Z` no tiene sentido | — |

> ✅ **Resultado real (2026-10-29):** `podman version 5.8.2`; `true netavark /home/adminlab/.local/share/containers/storage`;
> `adminlab:100000:65536` en `/etc/subuid` y `/etc/subgid`.

**Anota en el checklist (fila 1):** versión de Podman y de dónde sale.

#### 8.1.1 Primer contenedor: un proceso aislado, no una máquina

```bash
# [ansible01 · adminlab]
timeout 30 skopeo inspect docker://ghcr.io/stefanprodan/podinfo:6.15.0 | grep -E '"(Digest|Created)"'
podman run -d --name web -p 8080:9898 ghcr.io/stefanprodan/podinfo:6.15.0
```

| Comando | Qué hace | Qué esperas | Si sale otra cosa |
|---|---|---|---|
| `skopeo inspect` | Lee los metadatos de la imagen en el registro **sin descargarla** | Un `"Digest": "sha256:..."` | `manifest unknown` → esa versión no existe. Timeout → DNS o NAT |
| `podman run -d --name web -p 8080:9898` | Descarga la imagen y arranca un contenedor en segundo plano (`-d`). Publica el 9898 del contenedor en el 8080 de `ansible01` | Líneas `Copying blob ...` y al final un ID largo | `address already in use` → algo usa el 8080 (`ss -tlnp \| grep 8080`) |

```bash
# [ansible01 · adminlab]
curl -s localhost:8080 | head -5
podman ps
podman logs web | tail -3
```

Deberías ver un JSON con `"hostname"` y `"version": "6.15.0"`, la línea de `web` con `0.0.0.0:8080->9898/tcp` y la
línea de arranque del servidor en los logs.

**Lo que más importa de la 8.1:** un contenedor es un **proceso del host aislado con namespaces**, no una VM.

```bash
# [ansible01 · adminlab]
podman exec web ps
ps -ef | grep [p]odinfo
podman top web user huser pid hpid
```

| Comando | Qué esperas | Qué demuestra |
|---|---|---|
| `podman exec web ps` | Uno o dos procesos: podinfo con PID 1 y el propio `ps` | El contenedor tiene su propio espacio de PIDs |
| `ps -ef \| grep [p]odinfo` | `podinfo` como un proceso más del host, con un UID numérico grande (100000 y algo). Los corchetes evitan que `grep` se encuentre a sí mismo | Desde fuera es un proceso normal |
| `podman top ... user huser pid hpid` | `user` = el usuario dentro de la imagen; `huser` = ese mismo usuario visto desde el host; `pid` frente a `hpid` | El mapeo de `/etc/subuid` y los dos espacios de PIDs |

```bash
# [ansible01 · adminlab]
podman rm -f web
```

**Anota en el checklist (fila 1):** la salida de `podman top`.

#### 8.1.2 Imagen propia con un `Containerfile`

**Regla:** cada imagen en **su propio directorio** (el *contexto* del build) y con **nombre completo**
(`localhost/...`). Las dos cosas fallaron la primera vez: caso
etapa8/01 (pendiente de documentar).

**1. La etiqueta de la imagen base.** Nunca `latest`:

```bash
# [ansible01 · adminlab]
skopeo list-tags docker://registry.access.redhat.com/ubi9/ubi-minimal | grep -E '"9\.[0-9]+"' | tail -3
```

Lo esperado es una lista como `"9.6"`, `"9.7"`, `"9.8"`. Usa la más alta en el `FROM`.

> ✅ **Resultado real:** `9.8`.

**2. El directorio y el script.** Estilo de la Etapa 6: `set -euo pipefail`, una función y un argumento. Tiene dos
modos: una sola vez, o `--bucle` para el servicio de la 8.1.5.

```bash
# [ansible01 · adminlab]
mkdir -p ~/podman-lab/saludo && cd ~/podman-lab/saludo && pwd

cat > saludo.sh <<'EOF'
#!/bin/bash
# saludo.sh - Etapa 8.1: script de prueba para la imagen lab/saludo
set -euo pipefail

saludar() {
  printf '%s  Hola desde %s (uid=%s)\n' \
    "$(date '+%F %T')" "$(cat /proc/sys/kernel/hostname)" "$(id -u)"
}

if [[ "${1:-}" == "--bucle" ]]; then
  while true; do saludar; sleep 30; done   # modo servicio (8.1.5)
else
  saludar                                  # modo una sola vez
fi
EOF
```

`pwd` **tiene** que decir `/home/adminlab/podman-lab/saludo` antes de seguir. El `cat > ... <<'EOF'` crea el fichero en
el directorio **actual**: si el `cd` no se hizo, el fichero acaba en otro sitio (eso pasó en el caso 01).

**3. El `Containerfile`.**

```bash
# [ansible01 · adminlab]  (en ~/podman-lab/saludo)
cat > Containerfile <<'EOF'
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.8
LABEL description="Etapa 8.1 - imagen de prueba" maintainer="adminlab"
COPY saludo.sh /usr/local/bin/saludo.sh
RUN chmod 0755 /usr/local/bin/saludo.sh
USER 1001
CMD ["/usr/local/bin/saludo.sh"]
EOF
ls -la
```

| Instrucción | Qué hace | ¿Crea capa? |
|---|---|---|
| `FROM` | Imagen base | Usa las de la base |
| `LABEL` | Metadatos (autor, descripción) | No |
| `COPY` | Copia un fichero del **contexto** a la imagen | Sí |
| `RUN` | Ejecuta un comando durante el build | Sí |
| `USER 1001` | El contenedor no corre como root dentro | No |
| `CMD` | Qué se ejecuta al arrancar | No |

`ls -la` debe mostrar `Containerfile` y `saludo.sh`, los dos con más de 0 bytes.

**4. Construir y ejecutar.**

```bash
# [ansible01 · adminlab]  (en ~/podman-lab/saludo)
podman build -t localhost/lab/saludo:1.0 .
podman images
podman run --rm localhost/lab/saludo:1.0
```

| Comando | Qué hace | Qué esperas | Si sale otra cosa |
|---|---|---|---|
| `podman build -t ... .` | Construye la imagen. El `.` es el **contexto**: el directorio donde busca el `Containerfile` y los ficheros del `COPY` | `STEP 1/6` ... `STEP 6/6` y `Successfully tagged localhost/lab/saludo:1.0` | `no Containerfile or Dockerfile` → no estás en el directorio. Se para en `COPY` → el fichero no está en el contexto |
| `podman images` | Lista las imágenes locales | `localhost/lab/saludo  1.0` | Una imagen `<none> <none>` → un build que se quedó a medias |
| `podman run --rm` | Ejecuta y borra el contenedor al terminar | `2026-10-29 23:58:01  Hola desde a1b2c3d4e5f6 (uid=1001)`. El "hostname" es el ID corto del contenedor | `Trying to pull registry.access.redhat.com/lab/saludo...` → nombre corto y la imagen local no existe (caso 01) |

**5. Capas y metadatos.**

```bash
# [ansible01 · adminlab]
podman image inspect localhost/lab/saludo:1.0 --format 'User={{.Config.User}}  Cmd={{.Config.Cmd}}'
podman history localhost/lab/saludo:1.0 | head -6
podman image inspect localhost/lab/saludo:1.0 --format 'Capas={{len .RootFS.Layers}}'
podman images localhost/lab/saludo
```

> ✅ **Resultado real (2026-10-30):**
>
> ```text
> User=1001  Cmd=[/usr/local/bin/saludo.sh]
> ID            CREATED         CREATED BY                                     SIZE
> cab93738abae  4 minutes ago   /bin/sh -c #(nop) CMD ["/usr/local/bin/sal...  0B
> <missing>     4 minutes ago   /bin/sh -c #(nop) USER 1001                    0B
> <missing>     4 minutes ago   /bin/sh -c chmod 0755 /usr/local/bin/salud...  3.58kB
> 0e799578a795  4 minutes ago   /bin/sh -c #(nop) COPY file:42e140c19583a4...  3.58kB
> e15848b7a7e3  17 minutes ago  /bin/sh -c #(nop) LABEL description="Etapa...  0B
> Capas=3
> localhost/lab/saludo  1.0  38202e4c3e82  5 minutes ago  109 MB
> ```

Cómo se lee:

| Dato | Qué significa |
|---|---|
| `Capas=3` | 1 de UBI (sus capas vienen aplanadas en una de 109 MB) + 1 del `COPY` + 1 del `RUN chmod` |
| `USER`, `CMD`, `LABEL` con `0B` | Son metadatos de la configuración, no capas |
| `RUN chmod` ocupa lo mismo que el `COPY` | Las capas son **copy-on-write**: cambiar solo los permisos guarda **el fichero entero** otra vez. Con 406 bytes da igual; con un binario de 200 MB serían 400 MB. Por eso, en un `Containerfile` real se escribe `COPY --chmod=0755 saludo.sh /usr/local/bin/` |
| `SIZE 109 MB` | La imagen completa. En disco solo añade unos 7 kB: la capa de UBI se **comparte** con `ubi9/ubi-minimal:9.8` |

**Anota en el checklist (fila 2):** etiqueta de UBI, `User`/`Cmd`, número de capas y tamaño.

#### 8.1.3 Volúmenes y SELinux

Un contenedor rootless corre como `adminlab` en el host, así que los **permisos Unix** de tu home le dejan leer. Lo que
lo bloquea es **SELinux**: el proceso corre con el tipo `container_t` y no puede leer ficheros `user_home_t`.

**1. Datos de prueba.**

```bash
# [ansible01 · adminlab]
mkdir -p ~/datos
echo "hola desde el host" > ~/datos/hola.txt
ls -laZ ~/datos
```

Lo esperado: propietario `adminlab` y contexto `unconfined_u:object_r:user_home_t:s0`.

**2. Sin `:Z`: falla.**

```bash
# [ansible01 · adminlab]
podman run --rm -v ~/datos:/datos registry.access.redhat.com/ubi9/ubi-minimal:9.8 cat /datos/hola.txt
sudo timeout 20 ausearch -m avc -ts recent | grep denied | tail -2
```

| Comando | Qué esperas | Qué demuestra |
|---|---|---|
| `podman run -v ~/datos:/datos` | `cat: /datos/hola.txt: Permission denied` | Los permisos Unix están bien (eres el dueño), pero algo bloquea |
| `ausearch -m avc -ts recent` | `avc: denied { read } ... scontext=...container_t... tcontext=...user_home_t` | Quien bloquea es SELinux. `timeout` por la lección del caso [etapa2/06](../troubleshooting/etapa2/06-ausearch-colgado-timeout.md) |

**3. Con `:Z`: funciona.**

```bash
# [ansible01 · adminlab]
podman run --rm -v ~/datos:/datos:Z registry.access.redhat.com/ubi9/ubi-minimal:9.8 cat /datos/hola.txt
ls -laZ ~/datos
```

> ✅ **Resultado real (2026-10-30):**
>
> ```text
> hola desde el host
> drwxr-xr-x.  2 adminlab adminlab system_u:object_r:container_file_t:s0:c87,c584   22 Oct 30 00:19 .
> drwx------. 11 adminlab adminlab unconfined_u:object_r:user_home_dir_t:s0       4096 Oct 30 00:19 ..
> -rw-r--r--.  1 adminlab adminlab system_u:object_r:container_file_t:s0:c87,c584   19 Oct 30 00:19 hola.txt
> ```

Qué demuestra la salida:

- **`:Z` solo reetiqueta lo que se monta.** `~/datos` y `hola.txt` pasaron a `container_file_t`; `..` (tu home) sigue
  en `user_home_dir_t`.
- **`s0:c87,c584` son las categorías MCS** que Podman asignó a **ese** contenedor. `:Z` (mayúscula) es una etiqueta
  privada: otro contenedor con `:Z` sobre el mismo directorio lo reetiquetaría y el primero perdería el acceso. `:z`
  (minúscula) es una etiqueta compartida entre contenedores.
- **Los permisos Unix no cambiaron** (`adminlab`, 644). Solo cambió la etiqueta SELinux.

> ⚠️ **Nunca** `:Z` sobre `~` entero, `/home`, `/etc` o `/var`: reetiqueta todo lo que monta y te puedes quedar sin login.
> Solo directorios dedicados como `~/datos`. Para volver a la etiqueta original: `restorecon -Rv ~/datos`.

**Opcional (rootless y subuid):** `podman run --rm -v ~/datos:/datos:Z localhost/lab/saludo:1.0 touch /datos/prueba`
falla, ahora por **permisos Unix**: la imagen corre como UID 1001, que en el host es 100000 + 1000 = **101000**, y
ese UID no es dueño de `~/datos`. `podman unshare chown 1001:1001 ~/datos` lo arregla (dentro de `unshare`, los UIDs
son los del contenedor) y `ls -ln ~/datos` muestra `101000`. Se deshace con `podman unshare chown 0:0 ~/datos`.

**Anota en el checklist (fila 3):** la línea del AVC y el `ls -laZ` de antes y de después.

#### 8.1.4 Pod de Podman y YAML de Kubernetes

En Kubernetes no se ejecutan contenedores sueltos, sino **Pods**: grupos de uno o más contenedores que **comparten la
red** (misma IP; se hablan por `localhost`). Podman también crea Pods, así que se puede ver aquí antes de tener el
clúster. Y Podman sabe escribir el YAML de Kubernetes de ese Pod: es el puente a la 8.3.

**1. El pod y sus dos contenedores.**

```bash
# [ansible01 · adminlab]
podman pod create --name saludo-pod -p 8081:9898
podman run -d --pod saludo-pod --name web ghcr.io/stefanprodan/podinfo:6.15.0
podman run -d --pod saludo-pod --name cliente registry.access.redhat.com/ubi9/ubi-minimal:9.8 \
  bash -c 'while true; do curl -s localhost:9898/version; echo; sleep 10; done'
```

| Comando | Qué hace | Si sale otra cosa |
|---|---|---|
| `podman pod create -p 8081:9898` | Crea el pod. El puerto se publica en el **pod**, no en cada contenedor | `address already in use` → otro proceso en el 8081 |
| `podman run --pod saludo-pod --name web` | Mete podinfo en el pod | `name "web" is already in use` → no borraste el de la 8.1.1: `podman rm -f web` |
| `podman run --pod ... --name cliente` | Un segundo contenedor que llama a `localhost:9898` cada 10 s | `curl: command not found` → la imagen no trae `curl` (UBI minimal sí lo trae) |

**2. ¿Comparten la red?**

```bash
# [ansible01 · adminlab]
podman pod ps
podman ps --pod
podman logs cliente | tail -2
curl -s localhost:8081/version
```

| Comando | Qué esperas | Qué demuestra |
|---|---|---|
| `podman pod ps` | `saludo-pod` en `Running`, con `# OF CONTAINERS` = 3 | — |
| `podman ps --pod` | **Tres** contenedores: `web`, `cliente` y `xxxxxxxx-infra` | El `-infra` mantiene vivos los namespaces compartidos. En Kubernetes es el contenedor *pause* |
| `podman logs cliente` | El JSON de la versión, con `"version": "6.15.0"` | `cliente` llega a podinfo por **`localhost`**, aunque son contenedores distintos |
| `curl localhost:8081/version` | El mismo JSON | El puerto del pod llega a `web` |

**3. El YAML de Kubernetes, y la ida y vuelta.**

```bash
# [ansible01 · adminlab]
podman kube generate saludo-pod > ~/podman-lab/saludo-pod.yaml
grep -E 'apiVersion|kind|^  name|- name|image:' ~/podman-lab/saludo-pod.yaml
podman pod rm -f saludo-pod
podman kube play ~/podman-lab/saludo-pod.yaml
podman pod ps
podman kube down ~/podman-lab/saludo-pod.yaml
```

| Comando | Qué hace | Qué esperas |
|---|---|---|
| `podman kube generate` | Escribe el manifiesto de Kubernetes del pod | — |
| `grep` | Muestra las líneas clave | `apiVersion: v1`, `kind: Pod`, los contenedores `web` y `cliente` con sus imágenes |
| `podman pod rm -f` | Borra el pod y sus contenedores | El nombre del pod |
| `podman kube play` | **Recrea** el pod a partir del YAML | `Pod: <id>` y los dos contenedores |
| `podman kube down` | Borra lo que creó `kube play` | — |

Guarda `~/podman-lab/saludo-pod.yaml`: en la 8.3 lo miras al lado de `apps/podinfo.yaml` y ves qué añade un
Deployment.

**Anota en el checklist (fila 4):** la salida de `podman ps --pod` y del `grep`.

#### 8.1.5 Servicio systemd con Quadlet

Sin Kubernetes, ¿quién arranca un contenedor cuando la VM se reinicia? **systemd**. Quadlet convierte un fichero
`.container` en una unidad systemd normal; no escribes el `.service`: lo genera Podman.

**1. El fichero Quadlet.**

```bash
# [ansible01 · adminlab]
mkdir -p ~/.config/containers/systemd
cat > ~/.config/containers/systemd/saludo.container <<'EOF'
[Unit]
Description=Saludo (Etapa 8.1, Quadlet)

[Container]
Image=localhost/lab/saludo:1.0
ContainerName=saludo
Exec=/usr/local/bin/saludo.sh --bucle

[Service]
Restart=always

[Install]
WantedBy=default.target
EOF
```

`Image=` usa el **nombre completo**: con el nombre corto, systemd intentaría descargarlo de un registro remoto (caso 01).

**2. Revisar la unidad que generará.**

```bash
# [ansible01 · adminlab]
/usr/libexec/podman/quadlet -dryrun -user
```

Muestra el `.service` generado, con su `ExecStart=/usr/bin/podman run ... --name saludo ... localhost/lab/saludo:1.0
/usr/local/bin/saludo.sh --bucle`. Si hay un error de sintaxis en el `.container`, sale aquí y no se genera nada.

**3. Arrancar.**

```bash
# [ansible01 · adminlab]
systemctl --user daemon-reload
systemctl --user start saludo
systemctl --user status saludo --no-pager
journalctl --user -u saludo -n 5 --no-pager
```

| Comando | Qué hace | Qué esperas | Si sale otra cosa |
|---|---|---|---|
| `daemon-reload` | Ejecuta el generador de Quadlet y recarga las unidades | Nada | — |
| `start saludo` | Arranca la unidad generada `saludo.service` | Nada | `Unit saludo.service not found` → el generador no la creó: vuelve al paso 2 |
| `status` | Estado | `active (running)` | `failed` → `journalctl --user -u saludo` |
| `journalctl --user -u saludo` | Log de la unidad | Una línea de saludo cada 30 s | — |

Las unidades de Quadlet **no** se activan con `systemctl enable` (son generadas): lo que las hace arrancar en el boot
es el `[Install]` del fichero.

**4. Que sobreviva al reinicio.**

```bash
# [ansible01 · adminlab]
loginctl show-user adminlab -p Linger
sudo loginctl enable-linger adminlab
loginctl show-user adminlab -p Linger
```

Primero anota el estado previo (para poder revertir). Después debe salir `Linger=yes`. Sin *linger*, los servicios
`--user` solo existen mientras `adminlab` tiene una sesión abierta; con *linger*, systemd arranca tu "usuario" al
iniciar la VM.

**5. Prueba de reinicio.**

```bash
# [ansible01 · adminlab]
sudo reboot
# [host]  (espera ~30 s y vuelve a entrar)
ssh adminlab@ansible01
# [ansible01 · adminlab]
podman ps
journalctl --user -u saludo -n 3 --no-pager
```

Lo esperado: `saludo` en estado `Up` sin que hayas hecho nada.

**6. Reversión (si quieres dejarlo limpio).**

```bash
# [ansible01 · adminlab]
systemctl --user stop saludo
rm ~/.config/containers/systemd/saludo.container
systemctl --user daemon-reload
sudo loginctl disable-linger adminlab        # solo si antes estaba en Linger=no
```

**Anota en el checklist (fila 4):** `Linger=yes` y `podman ps` tras el reboot.

#### 8.1.6 Comparación entre versiones de RHEL (opcional)

La regla del proyecto pide comparar lo que cambia entre versiones. Dos datos que importan para la etapa: si Podman
viene instalado y qué versión de **cgroups** usa cada sistema. Kubernetes moderno necesita cgroup v2. Se hace desde el
proyecto de la Etapa 7, sin tocar nada:

```bash
# [ansible01 · adminlab]
cd ~/ansible-lab
ansible app -m command -a 'rpm -q podman' -o
ansible app -m command -a 'stat -fc %T /sys/fs/cgroup' -o
```

| Comando | Qué esperas | Cómo se lee |
|---|---|---|
| `rpm -q podman` | `package podman is not installed` (`FAILED`, `rc=1`) en las que no lo tengan | `rc=1` de `rpm -q` es la respuesta "no instalado", no un fallo |
| `stat -fc %T /sys/fs/cgroup` | `cgroup2fs` = cgroup v2; `tmpfs` = cgroup v1 | Anota lo que salga en cada versión |

Anota los resultados en "Diferencias RHEL 7/8/9/10" (al final de la guía) y en
`migration/rhel7-rhel8-rhel9-rhel10.md`, solo con lo medido.

### Qué documentar de la 8.1

- Imagen frente a contenedor; capas y copy-on-write; caché de capas.
- Rootless y subuid (`/etc/subuid`, `podman top ... huser`, `podman unshare`).
- Por qué `:Z`, qué es MCS, y la diferencia entre `:Z` y `:z`.
- Pod = contenedores que comparten red; el contenedor infra/*pause*.
- **Qué aporta Kubernetes que Podman + systemd no tiene:** varios nodos, reprogramación si un nodo cae, Services con
  balanceo, escalado declarativo (`replicas: 3`) y *rolling updates*.

**Respuestas a las preguntas de K1:**

1. **¿Por qué `podman build` desde `~` es mala idea aunque funcione?** Porque `~` pasa a ser el contexto: Podman
   empaqueta todo tu home (incluidos `.ssh/` y `.vault_pass.txt`) para el build. Un directorio por imagen, o un
   `.containerignore`.
2. **¿Qué pasa al ejecutar `podman run lab/saludo:1.0` si la imagen local se llama `localhost/lab/saludo:1.0`?** Si
   existe en local, Podman la encuentra igualmente. Si **no** existe, la busca en los
   `unqualified-search-registries` de `/etc/containers/registries.conf` (`registry.access.redhat.com`,
   `registry.redhat.io`, `docker.io`). Con un nombre corto podrías ejecutar la imagen de otra persona que se llame igual.
3. **¿Por qué el contenedor rootless no pudo leer `~/datos` si `adminlab` es el dueño?** Por SELinux: `container_t` no
   puede leer `user_home_t`. `:Z` lo reetiqueta a `container_file_t` con las categorías MCS de ese contenedor.
4. **¿Qué UID tiene en el host un proceso que dentro del contenedor rootless es el 1001?** 101000: el 0 es `adminlab` y
   del 1 en adelante se usa el rango de `/etc/subuid` (100000 + 1001 − 1).


---

### 6.2 Solución K2 — Clúster con kubeadm

**Objetivo:** un clúster de 3 nodos (1 plano de control + 2 workers) montado a mano, entendiendo cada pieza: el
almacenamiento propio, por qué fuera la swap, la red de pods, firewalld, el runtime (containerd), los paquetes
fijados y qué hace `kubeadm init` por dentro.

**Dónde:** el host (crear las VMs), los tres nodos como root y `ansible01` (administración).

**Vuelta atrás:** snapshot `*-stage5-complete` antes de empezar (paso 8.2.1) y `*-cluster-vacio` al terminar
(paso 8.2.7). Si un nodo queda mal a mitad de la 8.2: `kubeadm reset -f` en ese nodo o volver a `stage5`.

| Paso | Qué | Dónde |
|---|---|---|
| 8.2.1 | Crear las VMs y pasarlas por las etapas 2-5 | host |
| 8.2.2 | Preparar cada nodo: LVs, swap, módulos, NetworkManager, firewalld, containerd, paquetes | nodos |
| 8.2.3 | `kubeadm init` y red de pods (Calico) | `k8s-cp01` |
| 8.2.4 | Unir los workers | workers + `k8s-cp01` |
| 8.2.5 | Administrar desde `ansible01`: kubectl, Helm y copia del repo | `ansible01` |
| 8.2.6 | Comprobación de salud | `ansible01` + `k8s-cp01` |
| 8.2.7 | Snapshot del clúster vacío | host |

#### 8.2.1 Las VMs (desde el host, con lab.sh)

**1. Antes de crear nada: ¿cabe?** (solo lectura)

```bash
# [host]
free -h
df -h /var/lib/libvirt
grep '^k8s' scripts/hosts.conf
virsh list --all | grep k8s
```

| Comando | Qué esperas | Si sale otra cosa |
|---|---|---|
| `free -h` | `available` ≥ 19 GiB con `dns01` y `ansible01` encendidas | Apaga las `app01` que no necesites (`scripts/lab.sh down rhel7-app01`, etc.) |
| `df -h /var/lib/libvirt` | ≥ 130 GB libres | Libera espacio antes (por ejemplo, ISOs duplicadas) |
| `grep '^k8s' hosts.conf` | 3 líneas: RHEL 9, `.100/.101/.102`, RAM 4096/5120, discos 20 y 40, `opcional` | — |
| `virsh list --all \| grep k8s` | Nada: las VMs aún no existen | Si ya existen, no las recrees: sigue en el punto 3 |

**2. Crear las VMs.**

```bash
# [host]
scripts/lab.sh vm-create k8s-cp01
scripts/lab.sh vm-create k8s-w01
scripts/lab.sh vm-create k8s-w02
scripts/lab.sh status
```

| Comando | Qué hace | Qué esperas | Si sale otra cosa |
|---|---|---|---|
| `vm-create <nodo>` | Instala RHEL 9 con el kickstart del lab, en lab-net, con IP fija. Pide la contraseña de `adminlab` una vez | Termina con la VM encendida y SSH respondiendo | Revisa la consola: `virsh console k8s-cp01` (salir con `Ctrl+]`) |
| `status` | Estado de todas las VMs y del SSH | Las tres `k8s-*` con `SSH OK` | `--` en SSH → la VM aún arranca, o la IP no es la de `hosts.conf` |

**3. Registrar y aplicar las etapas base.**

```bash
# [host]
for h in k8s-cp01 k8s-w01 k8s-w02; do scripts/lab.sh register "$h" TU_USUARIO_DE_RED_HAT; done
scripts/lab.sh stage4-dns
for h in k8s-cp01 k8s-w01 k8s-w02; do
  scripts/lab.sh stage2 "$h" && scripts/lab.sh stage3 "$h" --lab-dns && \
  scripts/lab.sh stage4-clients "$h" && scripts/lab.sh stage5 "$h"
done
```

| Comando | Qué hace | Por qué |
|---|---|---|
| `register <nodo> <usuario>` | `subscription-manager register` en la VM (la contraseña se pide allí). Cambia `TU_USUARIO_DE_RED_HAT` por tu usuario | Sin repos no hay `dnf` |
| `stage4-dns` | Recarga la zona de `dns01` | La zona ya trae `k8s-*`, `k8s-api`, `ingress`, `grafana`... |
| `stage2` | Usuarios, `vg_data` en el disco de 40 GB, sudo, servicio de ejemplo | La 8.2.2 crea sus LVs en `vg_data` |
| `stage3 --lab-dns` | Red con `nmcli`, DNS = `dns01` | kubeadm necesita resolver `k8s-api.lab.local` |
| `stage4-clients` | chrony y endurecimiento de SSH | **Hora sincronizada**: los certificados del clúster fallan con relojes desfasados |
| `stage5` | SELinux *enforcing*, auditd, hardening | Kubernetes se monta sin desactivar SELinux |

**4. Comprobar la base y el DNS.**

```bash
# [host]
for h in k8s-cp01 k8s-w01 k8s-w02; do scripts/lab.sh test all "$h"; done
dig +short k8s-api.lab.local @10.10.10.20
dig +short -x 10.10.10.101 @10.10.10.20
```

Lo esperado: 0 FAIL en los tres nodos; `10.10.10.100`; `k8s-w01.lab.local.`. Si un test falla aquí, arréglalo
**antes** de montar Kubernetes: después es imposible saber de dónde viene.

**5. Snapshot de partida.**

```bash
# [host]
for h in k8s-cp01 k8s-w01 k8s-w02; do scripts/lab.sh snapshot create "$h" 5; done
scripts/lab.sh snapshot list k8s-cp01
```

Apaga cada nodo, crea `<nodo>-stage5-complete` y lo vuelve a encender. Si la 8.2 sale mal:
`scripts/lab.sh snapshot revert k8s-cp01 5` (ídem workers).

**Anota en el checklist (fila 5):** resultado de `test all` y los tres snapshots.

#### 8.2.2 Preparar cada nodo (los tres, como root)

Haz **todo este paso completo en `k8s-cp01`** primero, entendiendo cada bloque, y después repítelo en `k8s-w01` y
`k8s-w02` (ahí ya puedes pegar los bloques seguidos). Hay dos diferencias entre nodos, marcadas en el apartado e.

```bash
# [host]
ssh adminlab@k8s-cp01
# [k8s-cp01]
sudo -i
```

##### a. Almacenamiento propio para contenedores, kubelet y volúmenes

```bash
# [nodos · root]
vgs vg_data
lvs vg_data
```

Lo esperado: `vg_data` de ~40 GiB con unos 32 GiB en `VFree`, y los LVs de la Etapa 2 (`lv_application`, `lv_logs`,
`lv_backup`). Si `VFree` es menor de 30 GiB, **para**: los tres LVs de abajo no caben.

```bash
# [nodos · root]
lvcreate -y -n lv_containerd -L 16G vg_data
lvcreate -y -n lv_kubelet    -L 6G  vg_data
lvcreate -y -n lv_localpath  -L 8G  vg_data
for lv in containerd kubelet localpath; do mkfs.xfs -q /dev/vg_data/lv_$lv; done
mkdir -p /var/lib/containerd /var/lib/kubelet /var/lib/local-path
cp -a /etc/fstab /etc/fstab.antes-8.2
cat >> /etc/fstab <<'EOF'
/dev/vg_data/lv_containerd  /var/lib/containerd  xfs  defaults  0 0
/dev/vg_data/lv_kubelet     /var/lib/kubelet     xfs  defaults  0 0
/dev/vg_data/lv_localpath   /var/lib/local-path  xfs  defaults  0 0
EOF
findmnt --verify
systemctl daemon-reload && mount -a
df -h /var/lib/containerd /var/lib/kubelet /var/lib/local-path
```

| Comando | Qué hace | Qué esperas | Si sale otra cosa |
|---|---|---|---|
| `lvcreate -L 16G` | Crea el LV (en GiB) | `Logical volume "lv_containerd" created.` | `Insufficient free space` → `VFree` no alcanza |
| `mkfs.xfs -q` | Formatea en XFS, sin salida | Nada | — |
| `cp -a /etc/fstab ...` | **Copia de seguridad** antes de tocar `fstab` | — | — |
| `findmnt --verify` | Valida `fstab` **antes** de montar o reiniciar | `Success, no errors or warnings detected` (o solo avisos) | Un error aquí es el modo emergencia en el próximo arranque (caso [etapa2/02](../troubleshooting/etapa2/02-bad-fstab.md)). Restaura la copia |
| `mount -a` + `df -h` | Monta los tres LVs | 16G, 6G y 8G montados en sus rutas | `mount point does not exist` → falta un `mkdir` |

¿Por qué separar? Las imágenes (`/var/lib/containerd`), los volúmenes `emptyDir` y los logs del kubelet
(`/var/lib/kubelet`) y los volúmenes persistentes (`/var/lib/local-path`) crecen sin control. Sin LVs propios
llenarían `/var` (4 GB) y el nodo entero se caería (caso [etapa2/11](../troubleshooting/etapa2/README_troubleshooting_etapa2.md)).
El kubelet, además, mide por separado `nodefs` y `imagefs` para decidir cuándo desaloja pods (E10 de la 8.8).

El contexto SELinux de estos directorios se restaura en el apartado f, cuando ya esté instalada la política de
`container-selinux`.

##### b. Swap fuera

```bash
# [nodos · root]
swapon --show
swapoff -a
sed -i.antes-swap '/lv_swap/ s/^/#/' /etc/fstab
grep -n lv_swap /etc/fstab
systemctl daemon-reload && swapon --show
free -h | grep -i swap
```

| Comando | Qué hace | Qué esperas |
|---|---|---|
| `swapon --show` | Muestra la swap activa | `/dev/dm-N partition 2G` (el `lv_swap` del kickstart) |
| `swapoff -a` | La desactiva **ahora** | Nada |
| `sed -i.antes-swap '/lv_swap/ s/^/#/'` | Comenta la línea de swap de `fstab` (para que no vuelva en el arranque) y guarda copia en `fstab.antes-swap` | — |
| `grep -n lv_swap` | Comprueba el cambio | La línea empieza por `#` |
| `swapon --show` / `free` | Comprobación final | Vacío; `Swap: 0B` |

**Por qué:** el kubelet, por defecto, no arranca con swap activa (`failSwapOn: true`). El *scheduler* reparte pods
según la memoria que piden; con swap, un nodo "lleno" seguiría aceptando trabajo y degradándose en silencio. Las
versiones recientes admiten swap de forma controlada (`NodeSwap`), pero hay que configurarlo a propósito: en el lab,
fuera.

##### c. Módulos del kernel y sysctl

```bash
# [nodos · root]
cat > /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay && modprobe br_netfilter
lsmod | grep -E '^(overlay|br_netfilter)'
cat > /etc/sysctl.d/90-k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system | grep -E 'bridge-nf-call-iptables|ip_forward'
```

| Pieza | Para qué |
|---|---|
| `overlay` | Sistema de ficheros de las capas de las imágenes (el copy-on-write de la 8.1) |
| `br_netfilter` | Que el tráfico que pasa por un *bridge* atraviese las reglas de iptables/nftables (kube-proxy depende de ello) |
| `ip_forward = 1` | El nodo **reenvía** paquetes entre la red del lab y la de pods: hace de router |
| `/etc/modules-load.d/`, `/etc/sysctl.d/` | Que se mantenga tras un reinicio |

Lo esperado: las dos líneas de `lsmod` y las tres claves con `= 1`. Si `sysctl` dice `cannot stat
/proc/sys/net/bridge/...`, falta cargar `br_netfilter`.

##### d. NetworkManager no debe gestionar las interfaces de Calico

```bash
# [nodos · root]
cat > /etc/NetworkManager/conf.d/calico.conf <<'EOF'
[keyfile]
unmanaged-devices=interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico;interface-name:vxlan-v6.calico;interface-name:wireguard.cali;interface-name:wg-v6.cali
EOF
systemctl reload NetworkManager
nmcli general status
```

Calico crea una interfaz `cali...` por cada pod y otra `vxlan.calico`. Si NetworkManager intenta gestionarlas, puede
reconfigurarlas o borrar sus rutas, y los pods pierden la red de forma intermitente. Lo esperado tras el `reload`:
`nmcli general status` con `connected`; tu sesión SSH no se corta.

##### e. firewalld: una zona `k8s` en lugar de apagarlo

Muchas guías desactivan firewalld. Aquí no: se crea una zona `k8s` para la red del lab y las redes del clúster. Si el
**origen** de un paquete es de esas redes, firewalld usa la zona `k8s`; el resto sigue en `public`.

> ⚠️ **Riesgo de quedarte sin SSH.** Al poner `10.10.10.0/24` como origen de la zona `k8s`, el SSH que viene del host
> (10.10.10.1) deja de pasar por `public`. Si la zona nueva no permite `ssh`, la sesión se corta al hacer `--reload`.
> Mantén **dos** sesiones abiertas y aplica en este orden.

**1. Qué hay ahora en `public`** (para copiarlo a la zona nueva):

```bash
# [nodos · root]
firewall-cmd --get-default-zone
firewall-cmd --zone=public --list-services
firewall-cmd --zone=public --list-ports
```

Lo normal es `cockpit dhcpv6-client ssh` (más lo que añadieran las Etapas 4-5). Anótalo.

**2. La zona `k8s`, común a los tres nodos:**

```bash
# [nodos · root]
firewall-cmd --permanent --new-zone=k8s
for src in 10.10.10.0/24 10.244.0.0/16 10.96.0.0/12; do firewall-cmd --permanent --zone=k8s --add-source=$src; done
firewall-cmd --permanent --zone=k8s --add-service=ssh
firewall-cmd --permanent --zone=k8s --add-port={10250/tcp,10249/tcp,9100/tcp,4789/udp,5473/tcp,7946/tcp,7946/udp,9091/tcp}
```

Si en el punto 1 había otros servicios en `public` además de `ssh`, `cockpit` y `dhcpv6-client`, añádelos también a
`k8s` (`--add-service=<nombre>`).

**3. Lo específico de cada nodo:**

```bash
# [k8s-cp01 · root]  API, etcd y métricas del plano de control
firewall-cmd --permanent --zone=k8s --add-port={6443/tcp,2379-2380/tcp,2381/tcp,10257/tcp,10259/tcp}
```

```bash
# [workers · root]  NodePort
firewall-cmd --permanent --zone=k8s --add-port=30000-32767/tcp
```

**4. Aplicar y comprobar (con la segunda sesión abierta):**

```bash
# [nodos · root]
firewall-cmd --reload
firewall-cmd --get-active-zones
firewall-cmd --zone=k8s --list-all
```

```bash
# [host]  en una TERCERA terminal, antes de cerrar nada
ssh adminlab@k8s-cp01 hostname
```

| Comando | Qué esperas | Si sale otra cosa |
|---|---|---|
| `--get-active-zones` | `k8s` con `sources: 10.10.10.0/24 10.244.0.0/16 10.96.0.0/12`, y `public` con la interfaz | Sin `k8s` → no se aplicó el `--permanent`: repite y `--reload` |
| `--zone=k8s --list-all` | `services: ssh` y los puertos de arriba | — |
| `ssh ... hostname` desde el host | El nombre del nodo | Falla → en la sesión que sigue abierta: `firewall-cmd --zone=k8s --add-service=ssh` (en caliente) y revisa |

| Puerto | Para qué |
|---|---|
| 6443 | API de Kubernetes |
| 2379-2380 / 2381 | etcd (clientes y pares) / métricas de etcd |
| 10250 | API del kubelet (logs, exec, métricas) |
| 10257 / 10259 / 10249 | Métricas de controller-manager / scheduler / kube-proxy |
| 4789/udp, 5473 | VXLAN de Calico, Typha |
| 7946 tcp+udp | memberlist de MetalLB (elige qué nodo anuncia cada IP) |
| 9100, 9091 | node-exporter, métricas de Calico (felix) |
| 30000-32767 | NodePort (workers) |

> Si después algo de la red de pods falla (CoreDNS no llega a la API, pods que no se ven entre nodos), **firewalld es el
> primer sospechoso**: `firewall-cmd --get-active-zones`, `journalctl -k --since -10min | grep -i -E 'reject|drop'` y un
> caso de troubleshooting. Para confirmar la sospecha **un momento**: `systemctl stop firewalld`, prueba, y
> `systemctl start firewalld` enseguida. Nunca se deja apagado.

##### f. containerd (el runtime)

RHEL no trae containerd: el paquete `containerd.io` viene del repositorio de Docker para RHEL. Solo se instala
containerd, **no** Docker.

**1. Repositorio e instalación:**

```bash
# [nodos · root]
dnf install -y dnf-plugins-core
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf install -y containerd.io
rpm -q containerd.io container-selinux
containerd --version
```

Lo esperado: los dos paquetes instalados y la versión de containerd (anótala en el checklist). `container-selinux`
viene como dependencia y trae la política SELinux de los contenedores.

**2. Contexto SELinux de los LVs** (ahora que existe la política):

```bash
# [nodos · root]
restorecon -Rv /var/lib/containerd /var/lib/kubelet /var/lib/local-path
ls -dZ /var/lib/containerd /var/lib/kubelet /var/lib/local-path
```

Lo esperado: `container_var_lib_t` en `/var/lib/containerd` y `container_var_lib_t` o `var_lib_t` en los otros. Un
directorio recién montado sale con `unlabeled_t` o con la etiqueta del punto de montaje; `restorecon` aplica la que
dice la política (lección de la Etapa 5).

**3. Configuración:**

```bash
# [nodos · root]
cp -a /etc/containerd/config.toml /etc/containerd/config.toml.paquete
grep -n disabled_plugins /etc/containerd/config.toml.paquete
containerd config default > /etc/containerd/config.toml
grep -n 'SystemdCgroup' /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
grep -n 'SystemdCgroup\|enable_selinux\|sandbox' /etc/containerd/config.toml
```

| Comando | Qué hace | Qué esperas |
|---|---|---|
| `grep disabled_plugins ...paquete` | Mira el fichero que trae el paquete | `disabled_plugins = ["cri"]`: el plugin que usa Kubernetes viene **apagado** (el paquete está pensado para Docker) |
| `containerd config default >` | Genera la configuración completa por defecto, con el plugin CRI activo | Nada |
| `grep SystemdCgroup` (antes) | Busca el driver de cgroups de runc | Una línea `SystemdCgroup = false` |
| `sed ... = true` | Lo cambia a `true` | — |
| `grep ...` (después) | Comprobación | `SystemdCgroup = true`, `enable_selinux = false` y la imagen *sandbox* (`pause`) |

**Por qué `SystemdCgroup = true`:** el kubelet usa el driver `systemd` (en `kubeadm-config.yaml`, `cgroupDriver:
systemd`). Si containerd usara otro (`cgroupfs`), habría dos gestores de cgroups para los mismos procesos y el nodo se
volvería inestable bajo carga.

**containerd 1.7 frente a 2.x:** las secciones del fichero cambian de nombre (en 2.x,
`[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]`), pero la línea `SystemdCgroup` existe en
las dos y el `sed` funciona igual. Anota en el checklist qué versión tienes.

**4. Arrancar y comprobar:**

```bash
# [nodos · root]
systemctl enable --now containerd
systemctl is-active containerd
ctr version | head -8
```

Lo esperado: `active` y la versión de cliente y servidor. Si sale `failed`: `journalctl -u containerd -n 30` (lo
habitual es un error de sintaxis en `config.toml`; vuelve a generarlo).

> `enable_selinux = false` (por defecto) hace que los contenedores corran con el contexto del propio containerd.
> SELinux sigue en *enforcing* en el sistema (la Etapa 5 no se rompe), pero no aísla los contenedores entre sí. En la
> 8.6 lo activas en un worker y ves qué se rompe: es un ejercicio, no un descuido.

##### g. kubeadm, kubelet y kubectl v1.36

```bash
# [nodos · root]
cat > /etc/yum.repos.d/kubernetes.repo <<'EOF'
[kubernetes]
name=Kubernetes v1.36
baseurl=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
dnf list --showduplicates kubeadm --disableexcludes=kubernetes | tail -5
dnf install -y kubelet-1.36.5 kubeadm-1.36.5 kubectl-1.36.5 --disableexcludes=kubernetes
systemctl enable kubelet
kubeadm version -o short
```

| Línea o comando | Qué hace | Qué esperas | Si sale otra cosa |
|---|---|---|---|
| `baseurl=.../v1.36/rpm/` | Un repositorio **por versión menor**: este solo tiene 1.36.x | — | — |
| `exclude=kubelet kubeadm ...` | Un `dnf update` rutinario **no** toca Kubernetes. Las actualizaciones del clúster se hacen a propósito (8.12) | — | — |
| `dnf list --showduplicates` | Versiones disponibles | Varias `1.36.z`, entre ellas `1.36.5` | Si `1.36.5` ya no está, usa la última 1.36 y cámbiala también en `kubeadm-config.yaml` |
| `--disableexcludes=kubernetes` | Salta el `exclude` **solo** en este comando | `Complete!` | — |
| `systemctl enable kubelet` | Que arranque en el boot | Nada | — |
| `kubeadm version -o short` | Versión instalada | `v1.36.5` | — |

El kubelet se queda **reiniciándose en bucle** (`systemctl status kubelet` → `activating (auto-restart)`) hasta el
`init` o el `join`: todavía no tiene configuración. Es normal; no lo "arregles".

```bash
# [nodos · root]
crictl --runtime-endpoint unix:///run/containerd/containerd.sock info | head -20
```

`crictl` (paquete `cri-tools`) habla con containerd igual que lo hará el kubelet. Lo esperado: un JSON con
`"RuntimeReady"` y `"status": true`. `NetworkReady` saldrá `false` hasta que haya Calico.

##### h. Comprobación del nodo

Antes de pasar al siguiente nodo, todo en verde:

```bash
# [nodos · root]
swapon --show | wc -l                                   # 0
lsmod | grep -c -E '^(overlay|br_netfilter)'            # 2
sysctl -n net.ipv4.ip_forward                           # 1
firewall-cmd --get-active-zones | grep -c k8s           # 1
systemctl is-active containerd                          # active
grep -c 'SystemdCgroup = true' /etc/containerd/config.toml   # 1
rpm -q kubelet kubeadm kubectl                          # las tres 1.36.5
df -h --output=target,size /var/lib/containerd /var/lib/kubelet /var/lib/local-path
```

**Anota en el checklist (filas 6-9):** los LVs, swap, sysctl, zona `k8s`, versión de containerd y `SystemdCgroup`.

#### 8.2.3 Inicializar el plano de control (k8s-cp01)

**1. Subir la configuración y leerla.**

```bash
# [host]
scp scripts/stage8/files/cluster/kubeadm-config.yaml scripts/stage8/files/cluster/calico-custom-resources.yaml \
    adminlab@k8s-cp01.lab.local:
```

```bash
# [k8s-cp01 · root]
less ~adminlab/kubeadm-config.yaml
```

Cada decisión está comentada en el fichero. Las importantes:

| Clave | Valor | Por qué |
|---|---|---|
| `controlPlaneEndpoint` | `k8s-api.lab.local:6443` | Un nombre DNS, no una IP: un segundo nodo de control más adelante solo cambia el registro DNS, no los certificados |
| `podSubnet` / `serviceSubnet` | `10.244.0.0/16` / `10.96.0.0/12` | No chocan con `10.10.10.0/24` (lab), `192.168.122.0/24` (libvirt) ni con la red de casa |
| `bind-address: 0.0.0.0` (controller-manager, scheduler), `listen-metrics-urls` (etcd), `metricsBindAddress` (kube-proxy) | Métricas fuera de `127.0.0.1` | Si no, Prometheus los da por caídos (E00 de la 8.8). firewalld solo deja llegar desde el lab |
| `cgroupDriver: systemd` | El mismo que containerd | Apartado 8.2.2 f |
| `containerLogMaxSize: 10Mi`, `containerLogMaxFiles: 3` | Logs de pods acotados | `/var` tiene 4 GB |

**2. Validar y preparar.**

```bash
# [k8s-cp01 · root]
kubeadm config validate --config ~adminlab/kubeadm-config.yaml
kubeadm config images list --config ~adminlab/kubeadm-config.yaml
kubeadm config images pull --config ~adminlab/kubeadm-config.yaml
```

| Comando | Qué hace | Qué esperas | Si sale otra cosa |
|---|---|---|---|
| `config validate` | Comprueba la sintaxis y las claves del fichero | `ok` | `unknown field` → una clave mal escrita o de otra versión de la API |
| `config images list` | Qué imágenes usará: apiserver, controller-manager, scheduler, proxy, coredns, **pause**, etcd | 7 líneas de `registry.k8s.io/...:v1.36.5` y otras | — |
| `config images pull` | Las descarga antes del `init` (el `init` va más rápido y los fallos de red salen aquí) | `[config/images] Pulled ...` × 7 | Timeout → DNS o NAT del lab |

Compara la versión de `pause` de `images list` con la de `sandbox` en `/etc/containerd/config.toml`. Si son distintas,
el `init` avisará (`detected that the sandbox image ... is inconsistent`). No es grave, pero arréglalo para que el
kubelet y containerd usen la misma: cambia la versión en `config.toml` y `systemctl restart containerd`.

**3. `kubeadm init`.**

```bash
# [k8s-cp01 · root]
kubeadm init --config ~adminlab/kubeadm-config.yaml --upload-certs | tee /root/kubeadm-init.log
```

Tarda 1-3 minutos. Lee la salida: son **fases**, y cada una es un subcomando que podrías lanzar por separado
(`kubeadm init phase ...`):

| Fase | Qué hace |
|---|---|
| `preflight` | Comprueba el nodo: swap, puertos, módulos, runtime. Aquí fallan los olvidos de la 8.2.2 |
| `certs` | Crea la CA del clúster y todos los certificados en `/etc/kubernetes/pki/` |
| `kubeconfig` | Ficheros de acceso para admin, kubelet, controller-manager y scheduler |
| `kubelet-start` | Escribe la configuración del kubelet y lo arranca |
| `control-plane`, `etcd` | Escribe los manifiestos de los **pods estáticos** en `/etc/kubernetes/manifests/` |
| `upload-config`, `upload-certs` | Guarda la configuración en el clúster (ConfigMap `kubeadm-config`) y los certificados cifrados (para unir más nodos de control) |
| `mark-control-plane` | Etiqueta y *taint* del nodo: los pods normales no se ejecutan en el plano de control |
| `bootstrap-token` | Token para que los workers se unan |
| `addons` | CoreDNS y kube-proxy |

Al final: `Your Kubernetes control-plane has initialized successfully!` y **dos** comandos `kubeadm join` (uno para
otro nodo de control, con `--control-plane`, y otro para workers). Están en `/root/kubeadm-init.log`.

Si falla en `preflight`, el mensaje dice qué falta (`[ERROR Swap]`, `[ERROR FileContent--proc-sys-net-ipv4-ip_forward]`...):
arréglalo y repite. Si falla más adelante, `kubeadm reset -f` deja el nodo como antes del `init` (no deshace la 8.2.2).

**4. kubectl para `adminlab` en `k8s-cp01`.**

```bash
# [k8s-cp01 · root]
mkdir -p ~adminlab/.kube
cp /etc/kubernetes/admin.conf ~adminlab/.kube/config
chown -R adminlab: ~adminlab/.kube && chmod 600 ~adminlab/.kube/config
exit
# [k8s-cp01 · adminlab]
kubectl get nodes
kubectl -n kube-system get pods -o wide
ls /etc/kubernetes/manifests/
```

| Comando | Qué esperas | Por qué |
|---|---|---|
| `kubectl get nodes` | `k8s-cp01   NotReady   control-plane` | Falta la red de pods (CNI) |
| `get pods -n kube-system` | `etcd-`, `kube-apiserver-`, `kube-controller-manager-`, `kube-scheduler-` y `kube-proxy-` en `Running`; `coredns-` en **`Pending`** | CoreDNS es un pod normal: necesita red de pods |
| `ls /etc/kubernetes/manifests/` | `etcd.yaml`, `kube-apiserver.yaml`, `kube-controller-manager.yaml`, `kube-scheduler.yaml` | Pods **estáticos**: el kubelet los arranca leyendo estos ficheros, **sin** API (la API es uno de ellos) |

> `admin.conf` es **cluster-admin** con un certificado que dura un año: trátalo como la contraseña de root. En la 8.6
> creas un usuario con permisos limitados.

**5. Red de pods: Calico con su operador.**

```bash
# [k8s-cp01 · adminlab]
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/tigera-operator.yaml
kubectl -n tigera-operator rollout status deploy/tigera-operator --timeout=3m
kubectl create -f ~/calico-custom-resources.yaml
watch kubectl get tigerastatus
```

| Comando | Qué hace | Qué esperas | Si sale otra cosa |
|---|---|---|---|
| `create -f tigera-operator.yaml` | Instala el **operador** de Calico y sus CRDs. Se usa `create` y no `apply` porque los CRDs son tan grandes que no caben en la anotación que guarda `apply` | Una lista de `created` | `already exists` → ya estaba instalado |
| `rollout status` | Espera a que el operador esté listo | `successfully rolled out` | — |
| `create -f calico-custom-resources.yaml` | Le dice al operador **qué** instalar: un `Installation` con el pool `10.244.0.0/16` (el `podSubnet` de kubeadm) y VXLAN | `installation.operator.tigera.io/default created` | — |
| `watch kubectl get tigerastatus` | Estado de cada componente. Sal con `Ctrl+C` | Al cabo de 2-4 min, `apiserver`, `calico` (y los que traiga tu versión) con `AVAILABLE True` | Atascado en `PROGRESSING` → `kubectl -n calico-system get pods` y `describe` del que no arranque |

```bash
# [k8s-cp01 · adminlab]
kubectl get nodes
kubectl -n calico-system get pods -o wide
kubectl -n kube-system get pods -l k8s-app=kube-dns
```

Lo esperado: `k8s-cp01 Ready`, pods de `calico-system` en `Running` y los dos `coredns` en `Running`. Así se ve que
"el nodo no está Ready" era "no hay CNI".

**Anota en el checklist (filas 10-11):** las fases del `init`, el aviso de `sandbox` si salió y `tigerastatus`.

#### 8.2.4 Unir los workers

```bash
# [k8s-cp01 · root]
kubeadm token list
kubeadm token create --print-join-command
```

El token del `init` caduca a las 24 h; `token create --print-join-command` genera uno nuevo y escribe el comando
completo. Cópialo tal cual.

```bash
# [workers · root]  (pega el comando que imprimió k8s-cp01; tiene esta forma)
kubeadm join k8s-api.lab.local:6443 --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:0123...cdef
```

| Parte | Qué es |
|---|---|
| `k8s-api.lab.local:6443` | La API (por el nombre DNS de `controlPlaneEndpoint`) |
| `--token` | Credencial temporal para que el nodo se presente |
| `--discovery-token-ca-cert-hash` | El hash de la CA del clúster: el worker comprueba que habla con **tu** clúster y no con un impostor |

Lo esperado: `This node has joined the cluster`. Si sale `connection refused` o un timeout, comprueba desde el worker
`curl -k https://k8s-api.lab.local:6443/livez` (debe responder `ok`) y el puerto 6443 en la zona `k8s` de `k8s-cp01`.

```bash
# [k8s-cp01 · adminlab]
kubectl get nodes -o wide
kubectl label node k8s-w01 k8s-w02 node-role.kubernetes.io/worker=
kubectl get nodes
```

Lo esperado: 3 nodos `Ready`, `VERSION v1.36.5`, `CONTAINER-RUNTIME containerd://...`, IPs `.100`, `.101`, `.102`.
La etiqueta `node-role.kubernetes.io/worker=` solo sirve para que la columna `ROLES` diga `worker`.

**Anota en el checklist (fila 12).**

#### 8.2.5 Administrar desde ansible01

`ansible01` es la estación de control del lab: desde aquí se opera el clúster (como en una empresa, nadie trabaja
conectado al plano de control).

**1. kubectl** (mismo repositorio de la 8.2.2 g):

```bash
# [ansible01 · adminlab]
sudo tee /etc/yum.repos.d/kubernetes.repo >/dev/null <<'EOF'
[kubernetes]
name=Kubernetes v1.36
baseurl=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
sudo dnf install -y kubectl-1.36.5 --disableexcludes=kubernetes
mkdir -p ~/.kube && scp adminlab@k8s-cp01.lab.local:.kube/config ~/.kube/config && chmod 600 ~/.kube/config
kubectl get nodes
kubectl config get-contexts
```

Lo esperado: los 3 nodos y un contexto `kubernetes-admin@lab-k8s` marcado con `*`. Si el `scp` pide contraseña, la
clave de `ansible01` no está en `k8s-cp01`: cópiala desde el host
(`ssh adminlab@ansible01 cat .ssh/id_ed25519.pub | ssh adminlab@k8s-cp01 'cat >> .ssh/authorized_keys'`) y repite.

**2. Autocompletado:**

```bash
# [ansible01 · adminlab]
rpm -q bash-completion || sudo dnf install -y bash-completion
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl; complete -o default -F __start_kubectl k' >> ~/.bashrc
source ~/.bashrc
```

Con el tabulador, `kubectl get po<TAB>` completa tipos, nombres y *namespaces*. En entrevistas prácticas
(CKA/CKAD) es lo primero que se configura.

**3. Helm** (lo usan la 8.4, la 8.7 y la 8.8). Binario oficial con suma de verificación:

```bash
# [ansible01 · adminlab]
HELM_VERSION=v4.0.0       # cámbialo por la última 4.x estable de https://github.com/helm/helm/releases
curl -fsSLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum" | sha256sum -c
tar xzf "helm-${HELM_VERSION}-linux-amd64.tar.gz" && sudo install -m 0755 linux-amd64/helm /usr/local/bin/helm
rm -rf linux-amd64 "helm-${HELM_VERSION}-linux-amd64.tar.gz"
helm version
```

| Comando | Qué hace | Qué esperas | Si sale otra cosa |
|---|---|---|---|
| `curl -fsSLO` | Descarga el tarball (`-f`: falla si el servidor devuelve un error) | Nada | `404` → esa versión no existe: revisa `HELM_VERSION` |
| `... sha256sum -c` | Compara la suma publicada con la del fichero descargado | `helm-v4...tar.gz: OK` | `FAILED` → **no** lo instales: descarga corrupta o manipulada |
| `install -m 0755` | Copia el binario con los permisos correctos | — | — |
| `helm version` | Versión instalada | `version.BuildInfo{Version:"v4...` | — |

**4. Copia del repositorio** (los manifiestos de `scripts/stage8/files/` se aplican desde aquí):

```bash
# [ansible01 · adminlab]
rpm -q git || sudo dnf install -y git
git clone https://github.com/salatielaizza/enterprise-rhel-lab.git ~/enterprise-rhel-lab
ls ~/enterprise-rhel-lab/scripts/stage8/files
```

Para traer cambios más adelante: `git -C ~/enterprise-rhel-lab pull`. Es una copia de **lectura**: los cambios se
hacen en el repo del host y se suben a GitHub.

**Anota en el checklist (fila 13):** versiones de kubectl y Helm.

#### 8.2.6 Comprobación de salud

```bash
# [ansible01 · adminlab]
kubectl get nodes
kubectl get pods -A | grep -v -E 'Running|Completed'
kubectl get --raw='/readyz?verbose' | tail -3
kubectl -n kube-system get cm kubeadm-config -o yaml | grep -E 'podSubnet|serviceSubnet|controlPlaneEndpoint|kubernetesVersion'
```

```bash
# [k8s-cp01 · root]
kubeadm certs check-expiration
```

```bash
# [host]
for h in k8s-cp01 k8s-w01 k8s-w02; do scripts/lab.sh test all "$h"; done
```

| Comando | Qué esperas |
|---|---|
| `get nodes` | 3 `Ready` |
| `get pods -A \| grep -v ...` | Solo la línea de cabecera: nada fuera de `Running` |
| `/readyz?verbose` | Una lista de `[+]... ok` y al final `readyz check passed` |
| `get cm kubeadm-config` | Tu configuración, guardada en el clúster |
| `certs check-expiration` | Todos los certificados con ~364 días restantes; la CA, 10 años |
| `lab.sh test all <nodo>` | Sigue en 0 FAIL: montar Kubernetes no rompe la base del lab |

**Anota en el checklist (fila 14).**

#### 8.2.7 Snapshot del clúster vacío (desde el host)

Es el punto de vuelta más valioso de toda la etapa: si algo de la 8.3-8.8 deja el clúster inservible, vuelves aquí en
dos minutos en lugar de repetir la 8.2.

Un snapshot de un clúster **encendido** no es consistente (etcd escribiendo a mitad), así que se apaga primero. El
orden importa: workers primero, plano de control al final; al encender, al revés.

```bash
# [host]
scripts/lab.sh down k8s-w02; scripts/lab.sh down k8s-w01; scripts/lab.sh down k8s-cp01
watch 'virsh list --all | grep k8s'          # espera a que los tres digan "apagado"/"shut off"; Ctrl+C
for h in k8s-cp01 k8s-w01 k8s-w02; do
  virsh snapshot-create-as "$h" --name "$h-cluster-vacio" --description "Etapa 8.2: clúster recién creado, sin apps"
done
virsh snapshot-list k8s-cp01
scripts/lab.sh up k8s-cp01; sleep 60; scripts/lab.sh up k8s-w01; scripts/lab.sh up k8s-w02
```

| Comando | Qué hace | Qué esperas |
|---|---|---|
| `lab.sh down` | Apagado ACPI ordenado | `apagado ACPI solicitado` |
| `watch virsh list --all` | Espera al apagado real | `shut off` en los tres |
| `virsh snapshot-create-as` | Snapshot interno del qcow2 (los dos discos) con nombre y descripción | `Domain snapshot k8s-cp01-cluster-vacio created` |
| `lab.sh up` | Enciende; `k8s-cp01` primero para que la API esté lista cuando lleguen los workers | Al cabo de ~2 min, `kubectl get nodes` con 3 `Ready` |

Para volver aquí: apaga los tres y `virsh snapshot-revert <nodo> <nodo>-cluster-vacio` en cada uno. El mismo
procedimiento, con otro nombre, sirve para `*-antes-8.6`, `*-antes-8.9` y `*-antes-8.12`.

**Respuestas a las preguntas de K2:**

1. **¿Qué componentes tiene el plano de control y qué hace cada uno?** `kube-apiserver` (la única puerta: todo pasa
   por la API), `etcd` (la base de datos con todo el estado), `kube-scheduler` (decide en qué nodo va cada pod) y
   `kube-controller-manager` (los bucles que llevan el estado real al deseado: ReplicaSets, nodos, endpoints...). En
   cada nodo: `kubelet` (arranca los pods del nodo), el runtime (containerd) y `kube-proxy` (reglas de los Services).
2. **¿Cómo arranca el kubelet la API si la API es un pod?** Con **pods estáticos**: lee los manifiestos de
   `/etc/kubernetes/manifests/` y los arranca sin preguntar a nadie.
3. **¿Por qué el nodo sale `NotReady` justo después del `init`?** Porque no hay CNI: el kubelet informa
   `NetworkReady=false` hasta que Calico configura la red de pods.
4. **¿Para qué sirve el `exclude=` del repositorio de Kubernetes?** Para que un `dnf update` de parches no actualice
   Kubernetes sin querer. El orden del upgrade (plano de control primero, una versión menor cada vez) se hace a mano
   (8.12).
5. **¿Por qué `SystemdCgroup = true`?** El kubelet y containerd tienen que usar el mismo gestor de cgroups (`systemd`).


---

### 6.3 Solución K3 — Objetos de Kubernetes

**Objetivo:** el vocabulario de cualquier entrevista de plataforma, visto en vivo: Pod, ReplicaSet, Deployment,
Service, ConfigMap, Secret, Job, DaemonSet, namespace y etiquetas. La idea central es el **estado deseado**: tú
declaras qué quieres y los controladores trabajan sin parar para que la realidad coincida.

**Dónde:** `ansible01`, como `adminlab`, desde la copia del repo.

**Vuelta atrás:** `kubectl delete -f apps/podinfo.yaml` borra el namespace `demo` entero.

#### 8.3.1 Desplegar podinfo y leer lo que se ha creado

```bash
# [ansible01 · adminlab]
cd ~/enterprise-rhel-lab/scripts/stage8/files
less apps/podinfo.yaml
kubectl apply -f apps/podinfo.yaml
kubectl -n demo get deploy,rs,pods,svc -o wide --show-labels
```

| Objeto en `apps/podinfo.yaml` | Qué es |
|---|---|
| `Namespace demo` con `pod-security.kubernetes.io/enforce: restricted` | Un espacio de nombres donde **solo** entran pods que cumplen buenas prácticas de seguridad (sin root, sin privilegios, con seccomp) |
| `Deployment podinfo` (2 réplicas) | Describe la aplicación: imagen, puertos, *probes*, recursos y seguridad |
| `Service podinfo` (LoadBalancer) | Una IP y un nombre estables delante de los pods, que cambian |

Lo esperado tras el `apply`: `namespace/demo created`, `deployment.apps/podinfo created`, `service/podinfo created`.
En el `get`:

| Línea | Qué esperas | Cómo se relaciona |
|---|---|---|
| `deployment.apps/podinfo` | `READY 2/2` | El Deployment crea un ReplicaSet... |
| `replicaset.apps/podinfo-<hash>` | `DESIRED 2 CURRENT 2 READY 2` | ...el ReplicaSet crea los pods... |
| `pod/podinfo-<hash>-<id>` × 2 | `Running`, uno en cada worker (columna `NODE`) | ...y los pods llevan la etiqueta `pod-template-hash` de su ReplicaSet |
| `service/podinfo` | `TYPE LoadBalancer`, `EXTERNAL-IP <pending>` | Sin MetalLB aún (8.4) |

Compáralo con el `saludo-pod.yaml` de la 8.1.4: un Pod suelto frente a un Deployment que **mantiene** N copias, las
actualiza y vuelve atrás.

```bash
# [ansible01 · adminlab]
kubectl explain deployment.spec.strategy
kubectl explain pod.spec.containers.readinessProbe --recursive | head -20
```

`kubectl explain` es la documentación de la API **del propio clúster** (de tu versión exacta). Sirve sin Internet y en
los exámenes.

#### 8.3.2 Ejercicios

Haz cada uno, observa y anota lo que veas.

**1. Estado deseado: borrar un pod.**

```bash
# [ansible01 · adminlab]
kubectl -n demo get pods -o name
kubectl -n demo delete pod "$(kubectl -n demo get pods -o name | head -1 | cut -d/ -f2)"
kubectl -n demo get pods -w
```

Lo esperado: el pod borrado pasa a `Terminating` y **a la vez** aparece uno nuevo en `ContainerCreating` → `Running`.
El ReplicaSet ve 1 de 2 y crea otro. Sal del `-w` (*watch*) con `Ctrl+C`.

**2. Escalar.**

```bash
# [ansible01 · adminlab]
kubectl -n demo scale deploy/podinfo --replicas=4
kubectl -n demo get pods -o wide
kubectl -n demo scale deploy/podinfo --replicas=2
```

Lo esperado: 4 pods repartidos entre `k8s-w01` y `k8s-w02` (el scheduler los reparte), y después vuelta a 2.
Ninguno va a `k8s-cp01`: tiene el *taint* `node-role.kubernetes.io/control-plane:NoSchedule`
(`kubectl describe node k8s-cp01 | grep Taints`).

**3. Actualización progresiva (*rolling update*).**

```bash
# [ansible01 · adminlab]
kubectl -n demo set env deploy/podinfo PODINFO_UI_MESSAGE="version 2"
kubectl -n demo rollout status deploy/podinfo
kubectl -n demo get rs
kubectl -n demo rollout history deploy/podinfo
```

| Comando | Qué esperas | Qué demuestra |
|---|---|---|
| `set env` | `deployment.apps/podinfo env updated` | Cambiar la plantilla del pod = una **revisión** nueva |
| `rollout status` | `Waiting for ... 1 of 2 updated replicas...` y `successfully rolled out` | Los pods se sustituyen de uno en uno: nunca se queda sin servicio |
| `get rs` | **Dos** ReplicaSets: el nuevo con `2/2` y el viejo con `0/0` | El viejo se guarda para poder volver atrás |
| `rollout history` | Revisiones 1 y 2, con `CHANGE-CAUSE <none>` | Para que diga algo: `kubectl -n demo annotate deploy/podinfo kubernetes.io/change-cause="mensaje version 2"` |

**4. Vuelta atrás.**

```bash
# [ansible01 · adminlab]
kubectl -n demo rollout undo deploy/podinfo
kubectl -n demo rollout status deploy/podinfo
kubectl -n demo get rs
kubectl -n demo exec deploy/podinfo -- env | grep PODINFO_UI_MESSAGE || echo "sin PODINFO_UI_MESSAGE: vuelta a la revisión 1"
```

Lo esperado: el ReplicaSet viejo vuelve a `2/2` y el nuevo baja a `0/0`; la variable ya no está.

**5. ConfigMap y Secret.**

```bash
# [ansible01 · adminlab]
kubectl -n demo create configmap podinfo-cfg --from-literal=PODINFO_UI_COLOR=#34577c
kubectl -n demo set env deploy/podinfo --from=configmap/podinfo-cfg
kubectl -n demo exec deploy/podinfo -- env | grep PODINFO_UI_COLOR
kubectl -n demo create secret generic podinfo-token --from-literal=token=NoEsSecreto123
kubectl -n demo get secret podinfo-token -o yaml | grep -A1 '^data'
kubectl -n demo get secret podinfo-token -o jsonpath='{.data.token}' | base64 -d; echo
```

| Comando | Qué esperas | Qué demuestra |
|---|---|---|
| `set env --from=configmap/...` | Un *rollout* nuevo; la variable dentro del pod | La configuración vive fuera de la imagen |
| `get secret -o yaml` | `token: Tm9Fc1NlY3JldG8xMjM=` | Los Secrets van en **base64** |
| `... \| base64 -d` | `NoEsSecreto123` | **base64 no es cifrado**: cualquiera con permiso `get secrets` lo lee. En la 8.6 se ve cómo protegerlos |

**6. Etiquetas y selectores.**

```bash
# [ansible01 · adminlab]
kubectl -n demo get pods -l 'app.kubernetes.io/name in (podinfo)' --show-labels
POD=$(kubectl -n demo get pods -l app.kubernetes.io/name=podinfo -o name | head -1)
kubectl -n demo label "$POD" app.kubernetes.io/name-
kubectl -n demo get pods --show-labels
kubectl -n demo get endpointslices -l kubernetes.io/service-name=podinfo -o wide
kubectl -n demo delete "$POD"
```

| Paso | Qué esperas | Qué demuestra |
|---|---|---|
| `label ... app.kubernetes.io/name-` (el `-` final **quita** la etiqueta) | `pod/... unlabeled` | — |
| `get pods --show-labels` | **Tres** pods: el que perdió la etiqueta sigue `Running`, y hay uno nuevo | El ReplicaSet solo cuenta los pods que **coinciden con su selector**: vio 1 de 2 y creó otro |
| `get endpointslices` | Solo dos IPs: la del pod huérfano ya no está | El Service también selecciona por etiquetas: el huérfano no recibe tráfico |
| `delete "$POD"` | Borra el huérfano | Nadie lo gestiona: hay que borrarlo a mano |

**7. Job: rechazado por Pod Security, y corregido.**

```bash
# [ansible01 · adminlab]
kubectl -n demo create job pi --image=busybox:1.37 -- sh -c 'echo hola'
```

Lo esperado: **error**, con un mensaje como `violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false
..., unrestricted capabilities ..., runAsNonRoot != true ..., seccompProfile ...`. Lee el mensaje entero: dice
exactamente qué falta. Corrección con un YAML que cumpla `restricted`:

```bash
# [ansible01 · adminlab]
cat > ~/job-hola.yaml <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: hola
  namespace: demo
spec:
  backoffLimit: 2
  ttlSecondsAfterFinished: 600          # se borra solo 10 min después de terminar
  template:
    spec:
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534                # nobody
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: hola
          image: busybox:1.37
          command: ["sh", "-c", "echo hola desde un Job; date"]
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: {drop: ["ALL"]}
          resources:
            requests: {cpu: 10m, memory: 8Mi}
            limits: {cpu: 100m, memory: 32Mi}
EOF
kubectl apply -f ~/job-hola.yaml
kubectl -n demo get job hola -w            # COMPLETIONS 1/1; Ctrl+C
kubectl -n demo logs job/hola
```

Lo esperado: `COMPLETIONS 1/1` y en los logs `hola desde un Job` y la fecha. Un Job ejecuta algo **hasta que termina**
(no lo reinicia como un Deployment); un CronJob crea Jobs según un horario (`kubectl create cronjob --help`).

**8. DaemonSet: uno por nodo.**

```bash
# [ansible01 · adminlab]
kubectl get ds -A
kubectl -n calico-system get pods -l k8s-app=calico-node -o wide
```

Lo esperado: `kube-proxy` (en `kube-system`) y `calico-node` (en `calico-system`) con `DESIRED 3`: un pod por nodo,
**incluido** `k8s-cp01`. Un DaemonSet es para agentes de nodo (red, logs, métricas): en la 8.8 aparece otro,
`node-exporter`.

**9. Eventos y `describe`: la primera fuente de diagnóstico.**

```bash
# [ansible01 · adminlab]
kubectl -n demo get events --sort-by=.lastTimestamp | tail -15
kubectl -n demo describe deploy/podinfo | tail -15
kubectl -n demo describe pod "$(kubectl -n demo get pods -l app.kubernetes.io/name=podinfo -o name | head -1 | cut -d/ -f2)" | sed -n '/Events/,$p'
```

Los eventos cuentan la historia de lo que acabas de hacer: `Scheduled`, `Pulled`, `Created`, `Started`, `Killing`,
`ScalingReplicaSet`... Ante cualquier problema de un pod, `describe` + `Events` es **siempre** lo primero.

**Limpieza:**

```bash
# [ansible01 · adminlab]
kubectl -n demo delete job hola --ignore-not-found
kubectl -n demo set env deploy/podinfo PODINFO_UI_COLOR-     # el "-" final quita la variable
kubectl -n demo delete configmap podinfo-cfg
kubectl -n demo delete secret podinfo-token
kubectl -n demo get deploy podinfo -o jsonpath='{.spec.template.spec.containers[0].env}'; echo   # vacío
```

¿Por qué no basta con `kubectl apply -f apps/podinfo.yaml`? `apply` solo quita lo que **él** puso antes (lo guarda en
la anotación `last-applied-configuration`). Lo añadido con `set env` no está ahí y sobreviviría. Es una fuente típica
de *drift* (la 8.9 y la 8.11 vuelven sobre ello).

**Anota en el checklist (filas 15-16).**

**Qué documentar:** la tabla con lo observado y, en una frase, cada objeto: Pod, ReplicaSet, Deployment, Service,
ConfigMap, Secret, Job, CronJob, DaemonSet, namespace, etiqueta y selector.

**Respuestas a las preguntas de K3:**

1. **¿Por qué no se crean Pods sueltos?** Un Pod suelto no se recrea si muere ni se reprograma si cae el nodo. Un
   Deployment (vía ReplicaSet) mantiene N réplicas, hace *rolling updates* y vuelve atrás.
2. **¿Qué pasa al quitar a un pod la etiqueta del selector?** Sale del ReplicaSet (que crea otro para mantener N) y
   del Service (deja de recibir tráfico). Sigue vivo y huérfano.
3. **¿Un Secret está cifrado?** No: va en base64. Se protege con RBAC, cifrado en reposo de etcd o gestores externos
   (8.6).
4. **¿Por qué ningún pod de podinfo va a `k8s-cp01`?** Por su *taint* `NoSchedule`. Los DaemonSets de red sí van,
   porque llevan la *toleration*.


---

### 6.4 Solución K4 — Red: Services, DNS, MetalLB, Ingress y NetworkPolicies

**Objetivo:** cómo llega el tráfico a un pod, desde dentro y desde fuera del clúster: ClusterIP, NodePort y
LoadBalancer; el DNS interno; MetalLB para tener IPs reales en un lab sin nube; Ingress/Gateway API para muchos
servicios detrás de una IP; y NetworkPolicies para cortar el tráfico que no toca.

**Dónde:** `ansible01` y, para mirar ARP, el host (solo lectura).

**Vuelta atrás:** `helm uninstall` de MetalLB y Traefik, `kubectl delete -f` de las políticas.

#### 8.4.1 Services y DNS interno

```bash
# [ansible01 · adminlab]
kubectl -n demo get svc podinfo -o wide
kubectl -n demo get endpointslices -l kubernetes.io/service-name=podinfo -o wide
kubectl run dnstest -it --rm --image=busybox:1.37 --restart=Never -- nslookup podinfo.demo.svc.cluster.local
kubectl run dnstest -it --rm --image=busybox:1.37 --restart=Never -- nslookup dns01.lab.local
kubectl -n kube-system get cm coredns -o yaml | grep -A2 forward
```

| Comando | Qué esperas | Qué demuestra |
|---|---|---|
| `get svc` | `CLUSTER-IP 10.96.x.x`, `PORT(S) 80:3xxxx/TCP` | Un Service tiene IP virtual **y** un NodePort (el `3xxxx`) |
| `get endpointslices` | Las IPs `10.244.x.x` de los dos pods, puerto 9898 | Lo que hay de verdad detrás de la IP virtual |
| `nslookup podinfo.demo.svc.cluster.local` | `Address: 10.96.x.x` (la del Service) | Nombre = `<servicio>.<namespace>.svc.cluster.local` |
| `nslookup dns01.lab.local` | `10.10.10.20` | CoreDNS **reenvía** lo que no es del clúster al DNS del nodo, que es `dns01` |
| `get cm coredns` | `forward . /etc/resolv.conf` | Por eso: usa el `resolv.conf` del nodo (Etapa 3) |

`kubectl run` funciona en `default` porque ese namespace no tiene Pod Security `restricted`. En `demo` sería rechazado.

**NodePort** (sin MetalLB):

```bash
# [ansible01 · adminlab]
NP=$(kubectl -n demo get svc podinfo -o jsonpath='{.spec.ports[0].nodePort}'); echo "NodePort: $NP"
curl -s "http://k8s-w01.lab.local:$NP" | head -5
```

Lo esperado: el JSON de podinfo. Así quedan las tres capas: **ClusterIP** (solo dentro), **NodePort** (un puerto en
cada nodo) y **LoadBalancer** (una IP externa, que necesita algo que la asigne: MetalLB).

#### 8.4.2 MetalLB: IPs del lab para los Services LoadBalancer

En la nube, `type: LoadBalancer` crea un balanceador del proveedor. En un lab no hay nadie que lo haga: MetalLB asigna
IPs de un rango (`.110-.119`) y las anuncia por **ARP** (modo L2) desde uno de los nodos.

```bash
# [ansible01 · adminlab]
kubectl create namespace metallb-system
kubectl label namespace metallb-system pod-security.kubernetes.io/enforce=privileged
helm repo add metallb https://metallb.github.io/metallb && helm repo update
helm search repo metallb/metallb --versions | head -5
helm install metallb metallb/metallb --version 0.16.1 -n metallb-system --wait
kubectl -n metallb-system get pods -o wide
```

| Comando | Qué hace | Qué esperas | Si sale otra cosa |
|---|---|---|---|
| `label ... enforce=privileged` | El *speaker* de MetalLB usa `hostNetwork` (necesita responder ARP en la red del nodo): no cumple `baseline` | `namespace/metallb-system labeled` | Sin la etiqueta, los pods del *speaker* se rechazan |
| `helm repo add` + `update` | Añade el repositorio de charts | `"metallb" has been added` | — |
| `helm search --versions` | Comprueba que la versión fijada existe | `0.16.1` en la lista | No está → usa la que haya y anótala |
| `helm install ... --wait` | Instala y espera a que todo esté listo | `STATUS: deployed` | Timeout → `kubectl -n metallb-system describe pod` |
| `get pods` | `controller` (1) y `speaker` (uno por nodo) | Todos `Running` | — |

```bash
# [ansible01 · adminlab]
cat cluster/metallb-pool.yaml
kubectl apply -f cluster/metallb-pool.yaml
kubectl -n demo get svc podinfo
curl -s http://podinfo.lab.local | head -5
```

Lo esperado: `EXTERNAL-IP 10.10.10.114` (la que pide la anotación `metallb.io/loadBalancerIPs` de `apps/podinfo.yaml`)
y el JSON de podinfo por el nombre del DNS del lab.

**¿Quién responde a esa IP?** Desde el host, solo lectura:

```bash
# [host]
curl -s -o /dev/null -w '%{http_code}\n' http://10.10.10.114
ip neigh show 10.10.10.114
virsh domiflist k8s-w01; virsh domiflist k8s-w02
```

Lo esperado: `200`, una MAC en `ip neigh`, y esa MAC es la de **un** nodo (compárala con `virsh domiflist`). MetalLB
L2 no reparte carga entre nodos: un nodo "tiene" la IP y kube-proxy reparte desde ahí. Si ese nodo cae, otro la anuncia.

**`externalTrafficPolicy: Local`** (en `apps/podinfo.yaml`): el tráfico solo entra por nodos que tienen un pod de
podinfo y conserva la IP real del cliente (sin SNAT). Con `Cluster`, cualquier nodo acepta el tráfico y lo reenvía,
cambiando el origen por su propia IP. Se ve con una sola réplica:

```bash
# [ansible01 · adminlab]
kubectl -n demo scale deploy/podinfo --replicas=1
kubectl -n demo get pods -l app.kubernetes.io/name=podinfo -o wide      # ¿en qué nodo está?
kubectl -n demo get events --field-selector involvedObject.name=podinfo --sort-by=.lastTimestamp | tail -3
```

```bash
# [host]
ip neigh flush 10.10.10.114 dev virbr-lab 2>/dev/null; curl -s -o /dev/null http://10.10.10.114; ip neigh show 10.10.10.114
```

Lo esperado: en los eventos del Service, `nodeAssigned ... announcing from node "k8s-w0X"` con el nodo **donde está el
pod**, y la MAC de `ip neigh` es la de ese nodo. Con `Local`, MetalLB solo anuncia la IP desde nodos con un pod listo.
(`ip neigh flush` necesita root: si no quieres usar `sudo` en el host, omítelo y basta con los eventos.)

```bash
# [ansible01 · adminlab]
kubectl -n demo scale deploy/podinfo --replicas=2
```

Las NetworkPolicies de la 8.4.4 usan la IP de origen; con `Local` es la del cliente de verdad (`10.10.10.30` si pruebas
desde `ansible01`).

#### 8.4.3 Ingress y Gateway API con Traefik

Un LoadBalancer gasta **una IP por servicio**. Un controlador de entrada usa **una IP para muchos** servicios y elige el
destino por el nombre (`Host`) o la ruta. `ingress-nginx` se ha retirado (anuncio en noviembre de 2025, sin
mantenimiento desde marzo de 2026); las alternativas habituales son Traefik y los controladores de **Gateway API**, su
sucesora. Traefik hace las dos cosas.

**1. CRDs de Gateway API** (Traefik no los instala):

```bash
# [ansible01 · adminlab]
GWAPI=v1.6.3     # la que indique la documentación de tu versión de Traefik ("Kubernetes Gateway API")
kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GWAPI}/standard-install.yaml"
kubectl get crd | grep gateway.networking.k8s.io
```

Lo esperado: los CRDs `gatewayclasses`, `gateways`, `httproutes`, `referencegrants`, `grpcroutes`.

**2. Traefik:**

```bash
# [ansible01 · adminlab]
kubectl create namespace traefik
helm repo add traefik https://traefik.github.io/charts && helm repo update
helm search repo traefik/traefik | head -3          # fija la versión y anótala en el checklist
TRAEFIK_CHART=<versión-de-helm-search>
helm install traefik traefik/traefik -n traefik --version "$TRAEFIK_CHART" \
  --set service.annotations."metallb\.io/loadBalancerIPs"=10.10.10.110 \
  --set providers.kubernetesGateway.enabled=true \
  --set gateway.listeners.web.namespacePolicy.from=All \
  --wait
kubectl -n traefik get pods,svc
kubectl get gatewayclass; kubectl get gateway -A
```

| Parte | Qué hace |
|---|---|
| `TRAEFIK_CHART=` | Cambia `<versión-de-helm-search>` por la de la columna `CHART VERSION` |
| `service.annotations...=10.10.10.110` | Pide a MetalLB la IP de `ingress.lab.local` |
| `providers.kubernetesGateway.enabled=true` | Además de `Ingress`, entiende Gateway API; crea una `GatewayClass` y un `Gateway` por defecto |
| `gateway.listeners.web.namespacePolicy.from=All` | Que rutas de **otros** namespaces (`demo`) puedan colgarse de ese Gateway |

Lo esperado: el Service `traefik` con `EXTERNAL-IP 10.10.10.110`, una `GatewayClass traefik` con `ACCEPTED True` y un
`Gateway` (por ejemplo `traefik-gateway`) en `traefik` con `PROGRAMMED True`. **Anota su nombre**: lo usa el
`HTTPRoute`.

**3. Un `Ingress` para podinfo:**

```bash
# [ansible01 · adminlab]
cat > ~/podinfo-ingress.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: podinfo
  namespace: demo
spec:
  ingressClassName: traefik
  rules:
    - host: ingress.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: podinfo
                port: {number: 80}
EOF
kubectl apply -f ~/podinfo-ingress.yaml
kubectl -n demo get ingress
curl -s http://ingress.lab.local | head -3
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: otro.lab.local' http://10.10.10.110/
```

Lo esperado: `ADDRESS 10.10.10.110`, el JSON de podinfo y `404` con otro `Host`. Traefik decide por la cabecera
`Host`, no por la IP.

**4. Lo mismo con Gateway API (`HTTPRoute`):**

```bash
# [ansible01 · adminlab]
GW=$(kubectl -n traefik get gateway -o jsonpath='{.items[0].metadata.name}'); echo "Gateway: $GW"
cat > ~/podinfo-httproute.yaml <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: podinfo
  namespace: demo
spec:
  parentRefs:
    - name: $GW
      namespace: traefik
  hostnames: ["podinfo-gw.lab.local"]
  rules:
    - backendRefs:
        - name: podinfo
          port: 80
EOF
kubectl apply -f ~/podinfo-httproute.yaml
kubectl -n demo get httproute podinfo -o jsonpath='{.status.parents[0].conditions[*].type}{"\n"}'
curl -s -H 'Host: podinfo-gw.lab.local' http://10.10.10.110/ | head -3
```

Lo esperado: `Accepted ResolvedRefs` y el JSON de podinfo. `podinfo-gw.lab.local` no existe en el DNS: la cabecera
`Host` basta para demostrar el enrutado por nombre.

| | Ingress | Gateway API |
|---|---|---|
| Objetos | Uno: `Ingress` | Separados por rol: `GatewayClass` (proveedor), `Gateway` (plataforma), `HTTPRoute` (equipo de la app) |
| Estado | Congelado; las funciones avanzadas van en anotaciones propias de cada controlador | Activo; cabeceras, pesos y TLS en el propio estándar |

#### 8.4.4 NetworkPolicies

Sin políticas, **cualquier pod habla con cualquier pod** de cualquier namespace. Calico aplica las NetworkPolicies.

```bash
# [ansible01 · adminlab]
less apps/networkpolicies.yaml
kubectl apply -f apps/loadgen.yaml
kubectl -n demo rollout status deploy/loadgen
kubectl apply -f apps/networkpolicies.yaml
kubectl -n demo get networkpolicy
```

| Política | Qué hace |
|---|---|
| `denegar-entrada-por-defecto` | `podSelector: {}` sin reglas de entrada: **nadie** entra a ningún pod de `demo` |
| `podinfo-desde-loadgen` | Abre podinfo:9898 a los pods `loadgen` |
| `podinfo-desde-monitoring` | Abre podinfo:9898 al namespace `monitoring` (Prometheus, 8.8) |
| `podinfo-desde-red-del-lab` | Abre podinfo:9898 a `10.10.10.0/24` (el navegador por MetalLB) |

**Pruebas:**

```bash
# [ansible01 · adminlab]
kubectl -n demo exec deploy/loadgen -- wget -qO- -T3 http://podinfo | head -3
kubectl run intruso -it --rm --image=busybox:1.37 --restart=Never -- wget -qO- -T3 http://podinfo.demo
curl -s -m3 http://podinfo.lab.local | head -3
curl -s -m3 -o /dev/null -w '%{http_code}\n' http://ingress.lab.local
```

| Prueba | Qué esperas | Por qué |
|---|---|---|
| Desde `loadgen` | El JSON | Permitido por `podinfo-desde-loadgen` |
| `intruso` desde `default` | `wget: download timed out` | Ninguna política lo permite: el paquete se descarta, no se rechaza (por eso es un timeout) |
| Desde `ansible01` por MetalLB | El JSON | El `ipBlock` y `externalTrafficPolicy: Local`, que conserva el origen `10.10.10.30` |
| Por el Ingress | **Falla** (`000`, `502` o `504`) | ¡Sorpresa prevista! El tráfico llega desde el **pod de Traefik** (`10.244.x.x`), que no está en ninguna regla |

**Arreglo del Ingress** (abrir solo Traefik → podinfo:9898):

```bash
# [ansible01 · adminlab]
cat > ~/np-podinfo-desde-traefik.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: podinfo-desde-traefik
  namespace: demo
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: podinfo
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: traefik
      ports:
        - {protocol: TCP, port: 9898}
EOF
kubectl apply -f ~/np-podinfo-desde-traefik.yaml
curl -s -m3 http://ingress.lab.local | head -3
```

Lo esperado: vuelve el JSON. Fíjate en el `port: 9898`: la política se evalúa en el **pod**, así que el puerto es el del
contenedor, no el 80 del Service. Este caso, el de Ingress roto por una política, es un buen caso de troubleshooting.

Anota qué pasaría si borraras `podinfo-desde-monitoring` (spoiler: escenario E08 de la 8.8).

**Anota en el checklist (filas 17-20).**

**Respuestas a las preguntas de K4:**

1. **ClusterIP, NodePort y LoadBalancer: ¿qué añade cada uno?** ClusterIP: IP virtual interna. NodePort: además, un
   puerto en todos los nodos. LoadBalancer: además, una IP externa que asigna un proveedor (aquí, MetalLB).
2. **¿Por qué el `intruso` da timeout y no "connection refused"?** La política descarta (*drop*) el paquete; nadie
   responde.
3. **¿Por qué se rompió el Ingress al aplicar las políticas?** El origen real es el pod de Traefik, no el cliente:
   hay que permitir el namespace `traefik`.
4. **¿Qué ventaja tiene Gateway API sobre Ingress?** Separa responsabilidades (plataforma frente a equipos) y estandariza
   lo que en Ingress eran anotaciones propias de cada controlador.


---

### 6.5 Solución K5 — Almacenamiento: PV, PVC y StorageClass

**Objetivo:** datos que sobreviven al pod. **PVC** = "necesito 1 Gi"; **PV** = el volumen real; **StorageClass** = quién
lo crea y cómo. Sin almacenamiento compartido, el lab usa **local-path-provisioner**: cada volumen es un directorio en
el nodo donde arranca el pod, dentro del LV `lv_localpath` de la 8.2.

**Dónde:** `ansible01` y un worker (para ver el directorio).

#### 8.5.1 Instalar local-path y hacerlo la StorageClass por defecto

```bash
# [ansible01 · adminlab]
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.37/deploy/local-path-storage.yaml
kubectl -n local-path-storage rollout status deploy/local-path-provisioner
kubectl -n local-path-storage get cm local-path-config -o jsonpath='{.data.config\.json}'; echo
```

Lo esperado: el provisionador `Running` y un JSON con `"paths":["/opt/local-path-provisioner"]`. Esa es la ruta por
defecto, en el disco del sistema. Cámbiala por la del LV:

```bash
# [ansible01 · adminlab]
kubectl -n local-path-storage edit configmap local-path-config
```

En el editor (vim), dentro de `config.json`, cambia `/opt/local-path-provisioner` por `/var/lib/local-path`. Guarda con
`:wq`. Después:

```bash
# [ansible01 · adminlab]
kubectl -n local-path-storage get cm local-path-config -o jsonpath='{.data.config\.json}'; echo
kubectl -n local-path-storage rollout restart deploy/local-path-provisioner
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get storageclass
```

| Comando | Qué esperas | Si sale otra cosa |
|---|---|---|
| `get cm ... config.json` | `"paths":["/var/lib/local-path"]` | La ruta vieja → el `edit` no se guardó |
| `patch storageclass` | `storageclass.storage.k8s.io/local-path patched` | — |
| `get storageclass` | `local-path (default)`, `PROVISIONER rancher.io/local-path`, `RECLAIMPOLICY Delete`, `VOLUMEBINDINGMODE WaitForFirstConsumer` | Sin `(default)`, los PVC sin `storageClassName` se quedan en `Pending` para siempre |

#### 8.5.2 Ejercicios

**1. Un PVC y un pod que escribe en él.** Dos ficheros, para crearlos por separado y ver qué hace el PVC solo:

```bash
# [ansible01 · adminlab]
cat > ~/fechas-pvc.yaml <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fechas
  namespace: demo
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
EOF
kubectl apply -f ~/fechas-pvc.yaml
kubectl -n demo get pvc fechas
kubectl -n demo describe pvc fechas | tail -3
```

Lo esperado: `STATUS Pending`, y en los eventos `waiting for first consumer to be created before binding`. **No es un
error**: local-path espera a saber en qué nodo arrancará el pod para crear el volumen ahí (*WaitForFirstConsumer*).

El Deployment cumple `restricted` (el namespace `demo` lo exige):

```bash
# [ansible01 · adminlab]
cat > ~/fechas-deploy.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fechas
  namespace: demo
  labels: {app.kubernetes.io/name: fechas}
spec:
  replicas: 1
  strategy: {type: Recreate}            # ReadWriteOnce: dos pods a la vez no pueden montarlo
  selector:
    matchLabels: {app.kubernetes.io/name: fechas}
  template:
    metadata:
      labels: {app.kubernetes.io/name: fechas}
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: escritor
          image: busybox:1.37
          command: ["sh", "-c", "while true; do date >> /datos/fechas.log; sleep 10; done"]
          volumeMounts:
            - {name: datos, mountPath: /datos}
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: {drop: ["ALL"]}
          resources:
            requests: {cpu: 10m, memory: 8Mi}
            limits: {cpu: 50m, memory: 32Mi}
      volumes:
        - name: datos
          persistentVolumeClaim: {claimName: fechas}
EOF
kubectl apply -f ~/fechas-deploy.yaml --dry-run=server
```

El `--dry-run=server` envía el YAML a la API **sin crear nada**: valida esquema, Pod Security y cuotas. Lo esperado:
`deployment.apps/fechas created (server dry run)`. Si sale `violates PodSecurity`, revisa el `securityContext`.

```bash
# [ansible01 · adminlab]
kubectl apply -f ~/fechas-deploy.yaml
kubectl -n demo get pvc fechas -w          # Pending -> Bound; Ctrl+C
kubectl get pv
kubectl -n demo get pods -l app.kubernetes.io/name=fechas -o wide
```

Lo esperado: `Bound`; un PV `pvc-<uuid>` de 1Gi con `RECLAIM POLICY Delete`; el pod `Running` en un worker (anota
cuál).

**2. Los datos sobreviven al pod.**

```bash
# [ansible01 · adminlab]
sleep 30; kubectl -n demo exec deploy/fechas -- wc -l /datos/fechas.log
kubectl -n demo delete pod -l app.kubernetes.io/name=fechas
kubectl -n demo rollout status deploy/fechas
kubectl -n demo exec deploy/fechas -- head -3 /datos/fechas.log
kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}{"\n"}{end}'
```

Lo esperado: el pod nuevo lee las fechas **anteriores** a su creación, y el PV tiene una *nodeAffinity* hacia un nodo
concreto: el pod nuevo **tiene** que ir a ese nodo.

**3. El volumen es un directorio del nodo.**

```bash
# [k8s-w0X · root]  (el nodo del ejercicio 2)
ls -l /var/lib/local-path/
ls -lZ /var/lib/local-path/*/
tail -3 /var/lib/local-path/*/fechas.log
```

Lo esperado: un directorio `pvc-<uuid>_demo_fechas` con `fechas.log` dentro, y su contexto SELinux (anótalo: lo
necesitarás en la 8.6.5).

**4. ¿Y si cae ese nodo?** Piénsalo ahora y compruébalo en el E07 de la 8.8: el pod **no** puede ir a otro nodo
(el PV está atado al disco de ese nodo) y se queda `Pending` hasta que el nodo vuelve.

**5. `reclaimPolicy: Delete`.**

```bash
# [ansible01 · adminlab]
kubectl delete -f ~/fechas-deploy.yaml -f ~/fechas-pvc.yaml
kubectl get pv
```

```bash
# [k8s-w0X · root]
ls /var/lib/local-path/
```

Lo esperado: el PV desaparece y, a los pocos segundos, también el directorio (un pod auxiliar de local-path lo borra).
Con `Retain`, el PV quedaría `Released` y los datos seguirían en el disco.

**Anota en el checklist (fila 21).**

**Qué documentar:** PV/PVC/StorageClass, `WaitForFirstConsumer`, `ReadWriteOnce`, `reclaimPolicy`, por qué en
producción se usa almacenamiento de red (NFS, Ceph, cabinas con CSI; la Etapa 15 monta NFS) y que `local-path` **no
publica métricas de volumen** (`kubelet_volume_stats_*` sale vacío: lo verás en la 8.8).

**Respuestas a las preguntas de K5:**

1. **¿Por qué el PVC se queda en `Pending` sin pod?** `WaitForFirstConsumer`: el volumen se crea en el nodo donde se
   programe el pod, así que espera a que exista.
2. **¿Qué significa `ReadWriteOnce`?** Montable en lectura y escritura por **un nodo** a la vez. Por eso la
   estrategia `Recreate`: en un *rolling update*, el pod nuevo no podría montarlo mientras viva el viejo en otro nodo.
3. **¿Qué pasa con los datos si borro el PVC?** Con `Delete`, se borran. Con `Retain`, se quedan y hay que
   limpiarlos a mano.


---

### 6.6 Solución K6 — Seguridad: RBAC, ServiceAccounts, Pod Security, Secrets y SELinux

**Objetivo:** quién puede hacer qué en el clúster (RBAC), con qué identidad corren los pods (ServiceAccounts), qué
pods se admiten (Pod Security), qué tan protegidos están los Secrets y cómo aísla SELinux los contenedores.

**Dónde:** `ansible01` y, en la 8.6.5, `k8s-w02`.

**Antes de empezar:** snapshot `*-antes-8.6` (procedimiento del paso 8.2.7
con el nombre `<nodo>-antes-8.6`). La 8.6.5 toca containerd en un worker.

#### 8.6.1 Un usuario que no es administrador (`dev-tienda`)

Kubernetes **no tiene usuarios**: confía en quien presente un certificado firmado por su CA (o un token de un
proveedor de identidad). El `CN` del certificado es el usuario y el `O`, el grupo. Se crea `dev-tienda`, del grupo
`equipo-tienda`, con permisos de edición solo en el namespace `tienda`.

```bash
# [ansible01 · adminlab]
mkdir -p ~/rbac && cd ~/rbac
kubectl create namespace tienda
openssl genrsa -out dev-tienda.key 3072
openssl req -new -key dev-tienda.key -subj "/CN=dev-tienda/O=equipo-tienda" -out dev-tienda.csr
chmod 600 dev-tienda.key
```

| Comando | Qué hace |
|---|---|
| `openssl genrsa` | La clave privada del usuario: **nunca** sale de su equipo |
| `openssl req -subj "/CN=.../O=..."` | La petición de certificado: usuario `dev-tienda`, grupo `equipo-tienda` |

```bash
# [ansible01 · adminlab]  (en ~/rbac)
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: dev-tienda
spec:
  request: $(base64 -w0 < dev-tienda.csr)
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 2592000          # 30 días
  usages: [client auth]
EOF
kubectl get csr dev-tienda
kubectl certificate approve dev-tienda
kubectl get csr dev-tienda
kubectl get csr dev-tienda -o jsonpath='{.status.certificate}' | base64 -d > dev-tienda.crt
openssl x509 -in dev-tienda.crt -noout -subject -enddate
```

| Comando | Qué esperas | Qué significa |
|---|---|---|
| `get csr` (antes) | `CONDITION Pending` | La petición está en el clúster, pendiente de que un administrador la apruebe |
| `certificate approve` | `approved` | La CA del clúster la firma |
| `get csr` (después) | `Approved,Issued` | Ya hay certificado |
| `openssl x509 -subject -enddate` | `subject=O=equipo-tienda, CN=dev-tienda` y una fecha a 30 días | — |

**Darle permisos** con un `RoleBinding` al `ClusterRole` `edit` (crear y cambiar casi todo, salvo roles y permisos),
solo en `tienda`:

```bash
# [ansible01 · adminlab]
kubectl create rolebinding equipo-tienda-edit --clusterrole=edit --group=equipo-tienda -n tienda
```

**Probarlo** con un contexto propio:

```bash
# [ansible01 · adminlab]  (en ~/rbac)
kubectl config set-credentials dev-tienda --client-certificate=dev-tienda.crt --client-key=dev-tienda.key --embed-certs
kubectl config set-context dev-tienda --cluster=lab-k8s --user=dev-tienda --namespace=tienda
kubectl --context dev-tienda auth can-i create deployments
kubectl --context dev-tienda auth can-i get pods -n demo
kubectl --context dev-tienda auth can-i get nodes
kubectl --context dev-tienda get pods -n demo
kubectl auth can-i --list --as=dev-tienda --as-group=equipo-tienda -n tienda | head -15
```

| Prueba | Qué esperas | Por qué |
|---|---|---|
| `can-i create deployments` (en `tienda`) | `yes` | El `RoleBinding` le da `edit` en `tienda` |
| `can-i get pods -n demo` | `no` | Un `RoleBinding` solo vale en **su** namespace |
| `can-i get nodes` | `no` | Los nodos no pertenecen a ningún namespace: harían falta un `ClusterRole` y un `ClusterRoleBinding` |
| `get pods -n demo` | `Error from server (Forbidden): ... User "dev-tienda" cannot list resource "pods" ... in the namespace "demo"` | El error dice usuario, verbo, recurso y namespace: es todo lo que necesitas para diagnosticar |
| `can-i --list --as=...` | Lo que puede hacer, como lo ve el administrador | `--as` es **suplantación**: el administrador prueba sin tener la clave del usuario |

| Objeto | Ámbito |
|---|---|
| `Role` / `RoleBinding` | Un namespace |
| `ClusterRole` / `ClusterRoleBinding` | Todo el clúster (o un `ClusterRole` reutilizado con un `RoleBinding` en un namespace, como aquí) |

La clave `dev-tienda.key` y el contexto quedan en tu `~/.kube/config`. Es un ejercicio; en una empresa, cada persona
tiene su propio kubeconfig (y normalmente un proveedor de identidad con OIDC en lugar de certificados).

#### 8.6.2 ServiceAccounts: los pods también tienen identidad

Cada pod corre con una ServiceAccount (por defecto, `default` de su namespace), y su token se monta en
`/var/run/secrets/kubernetes.io/serviceaccount/`. Se crea una que **solo** pueda listar pods en `demo`:

```bash
# [ansible01 · adminlab]
cat > ~/rbac/sa-lector.yaml <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: lector-pods
  namespace: demo
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: leer-pods
  namespace: demo
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: lector-pods-leer-pods
  namespace: demo
subjects:
  - kind: ServiceAccount
    name: lector-pods
    namespace: demo
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: leer-pods
---
apiVersion: v1
kind: Pod
metadata:
  name: cliente-api
  namespace: demo
spec:
  serviceAccountName: lector-pods
  securityContext:
    runAsNonRoot: true
    runAsUser: 100
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: cliente
      image: ghcr.io/stefanprodan/podinfo:6.15.0     # trae curl
      command: ["sleep", "3600"]
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: {drop: ["ALL"]}
      resources:
        requests: {cpu: 10m, memory: 16Mi}
        limits: {cpu: 100m, memory: 64Mi}
EOF
kubectl apply -f ~/rbac/sa-lector.yaml
kubectl -n demo wait --for=condition=Ready pod/cliente-api --timeout=60s
```

Desde dentro del pod, hablando con la API con su token:

```bash
# [ansible01 · adminlab]
kubectl -n demo exec cliente-api -- sh -c '
  SA=/var/run/secrets/kubernetes.io/serviceaccount
  API=https://kubernetes.default.svc
  echo "== listar pods de demo:";   curl -s --cacert $SA/ca.crt -H "Authorization: Bearer $(cat $SA/token)" $API/api/v1/namespaces/demo/pods -o /dev/null -w "%{http_code}\n"
  echo "== borrar un pod de demo:"; curl -s --cacert $SA/ca.crt -H "Authorization: Bearer $(cat $SA/token)" -X DELETE $API/api/v1/namespaces/demo/pods/cliente-api -o /dev/null -w "%{http_code}\n"
  echo "== listar secrets:";        curl -s --cacert $SA/ca.crt -H "Authorization: Bearer $(cat $SA/token)" $API/api/v1/namespaces/demo/secrets -o /dev/null -w "%{http_code}\n"'
kubectl auth can-i delete pods -n demo --as=system:serviceaccount:demo:lector-pods
```

| Prueba | Qué esperas | Por qué |
|---|---|---|
| Listar pods | `200` | El `Role` lo permite |
| Borrar un pod | `403` | El `Role` no tiene `delete` |
| Listar secrets | `403` | Ni siquiera `get` |
| `auth can-i --as=system:serviceaccount:demo:lector-pods` | `no` | El nombre completo de una ServiceAccount como usuario |

Si un pod **no** necesita hablar con la API (la mayoría), `automountServiceAccountToken: false` en su `spec` evita
que tenga un token que se pueda robar.

```bash
# [ansible01 · adminlab]
kubectl delete -f ~/rbac/sa-lector.yaml
```

#### 8.6.3 Pod Security Admission

Tres **niveles** (`privileged` → sin restricciones; `baseline` → impide lo claramente peligroso: `hostNetwork`,
`privileged`, `hostPath`; `restricted` → buenas prácticas obligatorias: no root, sin capacidades, seccomp) y tres
**modos** por namespace (`enforce` rechaza; `audit` lo anota en el log de auditoría; `warn` avisa al usuario).

```bash
# [ansible01 · adminlab]
kubectl get ns -L pod-security.kubernetes.io/enforce
kubectl -n demo run root --image=busybox:1.37 --restart=Never -- sleep 60
kubectl label --dry-run=server --overwrite ns metallb-system pod-security.kubernetes.io/enforce=restricted
kubectl label --dry-run=server --overwrite ns default pod-security.kubernetes.io/enforce=baseline
```

| Comando | Qué esperas | Qué demuestra |
|---|---|---|
| `get ns -L ...` | `demo restricted`, `metallb-system privileged`; el resto, vacío (= `privileged`) | El nivel de cada namespace, de un vistazo |
| `run root` en `demo` | `Error from server (Forbidden): pods "root" is forbidden: violates PodSecurity "restricted:latest": ...` | Lee la lista entera: es la receta de un `securityContext` correcto (el Job de la 8.3) |
| `label --dry-run=server` en `metallb-system` | `Warning: existing pods in namespace "metallb-system" violate the new PodSecurity enforce level ... host namespaces (hostNetwork=true) ...` | Antes de endurecer un namespace, el `dry-run` dice qué pods ya en marcha lo incumplen |
| Ídem en `default` | Sin avisos (no hay pods) o avisos de restos de pruebas | — |

¿Por qué `monitoring` y `metallb-system` son `privileged`? Porque node-exporter y el *speaker* de MetalLB necesitan la
red y los procesos **del nodo** (`hostNetwork`, `hostPID`): son agentes de nodo, no aplicaciones.

#### 8.6.4 Secrets: qué protege y qué no

```bash
# [ansible01 · adminlab]
kubectl -n tienda create secret generic bd --from-literal=password='Tienda.2026!'
kubectl -n tienda get secret bd -o jsonpath='{.data.password}' | base64 -d; echo
kubectl --context dev-tienda -n tienda get secret bd -o jsonpath='{.data.password}' | base64 -d; echo
```

Lo esperado: la contraseña en claro las dos veces. **Cualquiera con `get secrets` en el namespace los lee** (el
ClusterRole `edit` lo incluye). La protección real es RBAC: quién tiene `get/list secrets`.

**¿Y en etcd?** Están **en claro**, salvo que se configure cifrado en reposo:

```bash
# [k8s-cp01 · root]
kubectl --kubeconfig /etc/kubernetes/admin.conf -n kube-system exec etcd-k8s-cp01 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
  get /registry/secrets/tienda/bd --print-value-only | grep -a -o 'Tienda.2026!'
```

Lo esperado: `Tienda.2026!`. Quien tenga una copia de etcd (o del disco de `k8s-cp01`) tiene todos los Secrets.

**Ampliación (opcional, con el snapshot `antes-8.6` hecho):** cifrado en reposo con una `EncryptionConfiguration`
(proveedor `aescbc` o `secretbox`) referenciada con `--encryption-provider-config` en
`/etc/kubernetes/manifests/kube-apiserver.yaml`. Después, `kubectl get secrets -A -o json | kubectl replace -f -`
reescribe los existentes, y el `etcdctl get` de arriba ya no encuentra la contraseña. Procedimiento:
[Encrypting Confidential Data at Rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/) en la
documentación oficial. Antes de editar el manifiesto, cópialo **fuera** de `/etc/kubernetes/manifests/` (una copia
dentro se arrancaría como otro pod estático).

```bash
# [ansible01 · adminlab]
kubectl -n tienda delete secret bd
```

#### 8.6.5 SELinux en los contenedores

En la 8.2.2 f, containerd quedó con `enable_selinux = false`: los contenedores corren con el contexto de containerd y
SELinux no los aísla entre sí. Aquí se activa en **un** worker (`k8s-w02`) y se ve qué se rompe.

**1. Sacar el trabajo del nodo** (lo explica a fondo la 8.12):

```bash
# [ansible01 · adminlab]
kubectl drain k8s-w02 --ignore-daemonsets --delete-emptydir-data
kubectl get nodes
```

Lo esperado: `node/k8s-w02 drained` y `k8s-w02 Ready,SchedulingDisabled`. Los pods de `k8s-w02` se recrean en
`k8s-w01` (salvo los DaemonSets, que se quedan).

**2. Activar SELinux en containerd:**

```bash
# [k8s-w02 · root]
cp -a /etc/containerd/config.toml /etc/containerd/config.toml.antes-8.6
grep -n 'enable_selinux' /etc/containerd/config.toml
sed -i 's/enable_selinux = false/enable_selinux = true/' /etc/containerd/config.toml
grep -n 'enable_selinux' /etc/containerd/config.toml
systemctl restart containerd && systemctl is-active containerd
```

Lo esperado: la línea pasa a `enable_selinux = true` y containerd `active`.

**3. Volver a programar pods en `k8s-w02`:**

```bash
# [ansible01 · adminlab]
kubectl uncordon k8s-w02
kubectl -n demo rollout restart deploy/podinfo
kubectl -n demo get pods -o wide
```

Si los dos pods de podinfo caen en `k8s-w01`, repite el `rollout restart` o escala a 4 réplicas para que alguno vaya a
`k8s-w02`.

**4. Mirar los contextos:**

```bash
# [k8s-w02 · root]
ps -eZ | grep -E 'podinfo|calico-node' | grep -v grep
```

| Proceso | Qué esperas | Qué significa |
|---|---|---|
| `podinfo` | `system_u:system_r:container_t:s0:c123,c456` (categorías distintas en cada pod) | Igual que el `:Z` de la 8.1.3: cada pod con sus categorías MCS. Un pod comprometido no puede leer los ficheros de otro |
| `calico-node` | `spc_t` (*super privileged container*) | Los contenedores `privileged` quedan fuera del confinamiento: es su naturaleza |

En `k8s-w01` (sin el cambio), `ps -eZ | grep podinfo` muestra el mismo contexto para todos los pods, el que hereda de
containerd (normalmente `container_runtime_t`): esa es la diferencia. Anota lo que salga en cada worker.

**5. Buscar lo que se rompe.** Lo habitual son los volúmenes `hostPath` y `local-path`, que no tienen la etiqueta
`container_file_t`. Pruébalo con el ejercicio de la 8.5 en `k8s-w02`:

```bash
# [ansible01 · adminlab]
sed -i '/^    spec:$/a\      nodeSelector: {kubernetes.io/hostname: k8s-w02}' ~/fechas-deploy.yaml
grep -n -B1 nodeSelector ~/fechas-deploy.yaml
kubectl apply -f ~/fechas-pvc.yaml -f ~/fechas-deploy.yaml
kubectl -n demo logs deploy/fechas --tail=5
kubectl -n demo get pods -l app.kubernetes.io/name=fechas
```

```bash
# [k8s-w02 · root]
timeout 20 ausearch -m AVC -ts recent | grep denied | tail -3
ls -dZ /var/lib/local-path/*/
```

El `grep` debe mostrar `nodeSelector` justo debajo del `spec:` de la plantilla (6 espacios de sangría). Se usa
`nodeSelector` y no `nodeName`: con `nodeName` el pod se salta el *scheduler*, y entonces nadie le dice a local-path en
qué nodo crear el volumen (`WaitForFirstConsumer`) y el PVC se queda `Pending` para siempre.

Lo esperado (y lo que hay que **comprobar**, no suponer): `sh: can't create /datos/fechas.log: Permission denied` en el
log o el pod reiniciándose, y un AVC con `scontext=...container_t:s0:cX,cY` y `tcontext=...` la etiqueta del directorio
que viste en la 8.5.2 ejercicio 3. Si **no** falla, anota por qué (qué etiqueta tenía el directorio): también es un
resultado.

**6. Arreglo correcto** (nunca `setenforce 0`):

```bash
# [k8s-w02 · root]
semanage fcontext -a -t container_file_t '/var/lib/local-path(/.*)?'
restorecon -Rv /var/lib/local-path
ls -dZ /var/lib/local-path /var/lib/local-path/*/
```

```bash
# [ansible01 · adminlab]
kubectl -n demo rollout restart deploy/fechas
sleep 20; kubectl -n demo logs deploy/fechas --tail=3; kubectl -n demo exec deploy/fechas -- tail -2 /datos/fechas.log
```

| Comando | Qué hace | Por qué así |
|---|---|---|
| `semanage fcontext -a -t container_file_t '...(/.*)?'` | Añade una **regla** a la política: todo bajo `/var/lib/local-path` es `container_file_t` | Persiste: sobrevive a un `restorecon` o a un reetiquetado completo del sistema. Un `chcon` se perdería |
| `restorecon -Rv` | Aplica la regla a lo que ya existe | — |

Si el AVC persiste por las categorías MCS (`s0` frente a `s0:cX,cY`), anótalo: es el motivo por el que los
provisionadores de almacenamiento "de verdad" (CSI) reetiquetan cada volumen al montarlo. Documenta el caso completo en
`troubleshooting/etapa8/`.

**7. Dejarlo como estaba (o no):**

```bash
# [ansible01 · adminlab]
kubectl delete -f ~/fechas-deploy.yaml -f ~/fechas-pvc.yaml
sed -i '/nodeSelector: {kubernetes.io\/hostname: k8s-w02}/d' ~/fechas-deploy.yaml
```

Decide si `k8s-w02` se queda con `enable_selinux = true` (más seguro, y el resto de la etapa pasa a ser una prueba de
que todo funciona con él) o vuelve a `false` (`cp -a /etc/containerd/config.toml.antes-8.6 /etc/containerd/config.toml`,
`systemctl restart containerd`, con `drain`/`uncordon`). **Anota la decisión** en el checklist: si los dos workers
difieren, cualquier fallo posterior de un volumen en uno solo de ellos tiene aquí su explicación.

**Anota en el checklist (filas 22-23).**

**Respuestas a las preguntas de K6:**

1. **¿Dónde están los usuarios de Kubernetes?** En ningún sitio: se autentican con certificados firmados por la CA del
   clúster (CN = usuario, O = grupo), tokens o un proveedor OIDC. RBAC autoriza.
2. **`Role` con `RoleBinding` frente a `ClusterRole` con `RoleBinding`:** en los dos casos los permisos valen en un
   namespace; el segundo reutiliza un rol definido para todo el clúster (`edit`, `view`, `admin`).
3. **¿Por qué `metallb-system` no puede ser `restricted`?** Su *speaker* usa `hostNetwork` para responder ARP.
4. **¿Está cifrado un Secret?** En la API, solo base64. En etcd, en claro, salvo `EncryptionConfiguration`.
5. **¿Qué añade `enable_selinux = true`?** Que cada pod corra como `container_t` con categorías MCS propias: aislamiento
   entre pods y con el nodo, además de los namespaces.


---

### 6.7 Solución K7 — Helm: charts, valores y releases

**Objetivo:** Helm es el gestor de paquetes de Kubernetes. Un **chart** es una plantilla de manifiestos; los
**valores** la personalizan; cada instalación es una **release** con historial de **revisiones**.

**Dónde:** `ansible01`.

#### 8.7.1 Leer lo que ya hay (MetalLB y Traefik)

```bash
# [ansible01 · adminlab]
helm list -A
helm -n metallb-system history metallb
helm -n metallb-system get values metallb
helm -n metallb-system get values metallb --all | head -20
helm show chart metallb/metallb --version 0.16.1
helm template metallb metallb/metallb --version 0.16.1 | grep -E '^kind:' | sort | uniq -c
```

| Comando | Qué esperas | Para qué sirve |
|---|---|---|
| `helm list -A` | `metallb` y `traefik`, `STATUS deployed`, `REVISION 1` | Inventario de lo instalado con Helm |
| `history` | Una revisión: `Install complete` | Cada `upgrade` añade una |
| `get values` | `null` o vacío | Lo que **tú** cambiaste (nada) |
| `get values --all` | Todos los valores efectivos | Lo que de verdad usa la release |
| `show chart` | Metadatos: versión del chart, `appVersion`, dependencias | — |
| `helm template ... \| grep kind` | Recuento de objetos: `Deployment`, `DaemonSet`, `ServiceAccount`, `ClusterRole`... | Lo que Helm **aplicaría**, sin aplicarlo: la herramienta de revisión antes de instalar nada |

#### 8.7.2 Gitea con Helm

Gitea es un servidor Git; la 8.11 lo usa como repositorio de GitOps. El chart trae PostgreSQL y Valkey activados por
defecto (varios GB de RAM); `apps/gitea-values.yaml` los apaga y usa SQLite en una sola réplica.

**1. Namespace y contraseña del administrador** (en un Secret, nunca en el repo):

```bash
# [ansible01 · adminlab]
cd ~/enterprise-rhel-lab/scripts/stage8/files
kubectl create namespace gitea
kubectl label namespace gitea pod-security.kubernetes.io/enforce=baseline
GITEA_PW="$(openssl rand -base64 18)"; echo "Gitea gitea-admin: $GITEA_PW"
kubectl -n gitea create secret generic gitea-admin --from-literal=username=gitea-admin --from-literal=password="$GITEA_PW"
```

Apunta la contraseña en tu gestor de contraseñas **ahora**. Si la pierdes:
`kubectl -n gitea get secret gitea-admin -o jsonpath='{.data.password}' | base64 -d`. `baseline` y no `restricted`:
los contenedores de inicialización del chart no cumplen `restricted`.

**2. Elegir versión y comparar los valores:**

```bash
# [ansible01 · adminlab]
helm repo add gitea-charts https://dl.gitea.com/charts/ && helm repo update
helm search repo gitea-charts/gitea --versions | head -5
GITEA_CHART=<versión-de-helm-search>
helm show values gitea-charts/gitea --version "$GITEA_CHART" > /tmp/gitea-defaults.yaml
diff <(grep -E '^[a-z]' /tmp/gitea-defaults.yaml | cut -d: -f1 | sort) <(grep -E '^[a-z]' apps/gitea-values.yaml | cut -d: -f1 | sort)
grep -n -E '^(postgresql|postgresql-ha|valkey|valkey-cluster):' -A2 /tmp/gitea-defaults.yaml
```

| Comando | Qué buscas |
|---|---|
| `GITEA_CHART=` | La `CHART VERSION` más reciente; anótala en el checklist |
| `diff` de las claves de primer nivel | Las líneas con `>` son claves de **nuestro** fichero: tienen que existir también en los valores del chart. Si una clave nuestra no existe en el chart, Helm la **ignora en silencio** |
| `grep ... postgresql ...` | Que los subcharts se llaman igual que en `gitea-values.yaml` (si cambiaron de nombre, nuestro `enabled: false` no tendría efecto) |

**3. Ver qué se instalaría y después instalar:**

```bash
# [ansible01 · adminlab]
helm template gitea gitea-charts/gitea -n gitea --version "$GITEA_CHART" -f apps/gitea-values.yaml | grep -E '^kind:' | sort | uniq -c
helm install gitea gitea-charts/gitea -n gitea --version "$GITEA_CHART" -f apps/gitea-values.yaml --wait --timeout 10m
kubectl -n gitea get pods,pvc,svc
```

| Comando | Qué esperas | Si sale otra cosa |
|---|---|---|
| `helm template ... \| uniq -c` | Un `Deployment`, Services, un `PersistentVolumeClaim`; **ningún** `StatefulSet` de PostgreSQL ni de Valkey | Si salen, los subcharts no se apagaron: revisa el `grep` del punto 2 |
| `helm install --wait` | `STATUS: deployed` en unos minutos | Timeout → `kubectl -n gitea describe pod` y `logs` |
| `get pods,pvc,svc` | Pod `Running`; PVC `Bound` de 5Gi en `local-path`; Service `gitea-http` con `EXTERNAL-IP 10.10.10.115` | PVC `Pending` → la StorageClass por defecto (8.5) |

**4. Primer uso:** entra en http://gitea.lab.local desde el navegador del host, con `gitea-admin` y la contraseña.
Crea la organización `lab` y, dentro, el repositorio **público** `k8s-apps` (con un README para que exista la rama
`main`). Lo usa la 8.11.

#### 8.7.3 `upgrade`, `history` y `rollback`

```bash
# [ansible01 · adminlab]
helm -n gitea upgrade gitea gitea-charts/gitea --version "$GITEA_CHART" -f apps/gitea-values.yaml \
  --set resources.limits.memory=768Mi --wait
helm -n gitea history gitea
helm -n gitea get values gitea | grep -A3 resources
kubectl -n gitea get deploy gitea -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}'; echo
helm -n gitea rollback gitea 1 --wait
helm -n gitea history gitea
kubectl -n gitea get deploy gitea -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}'; echo
```

| Paso | Qué esperas | Qué demuestra |
|---|---|---|
| `upgrade --set ...` | `REVISION: 2` | Un cambio de valores = revisión nueva |
| `history` | Revisiones 1 (`superseded`) y 2 (`deployed`) | — |
| `get deploy ... limits.memory` | `768Mi` | El valor llegó al Deployment |
| `rollback gitea 1` | `Rollback was a success!` | — |
| `history` | **Revisión 3**: `Rollback to 1` | Un *rollback* no borra historia: crea una revisión nueva con el contenido de la 1 |
| `limits.memory` | `512Mi` (el de `gitea-values.yaml`) | — |

¡Cuidado con `--set` en el día a día! Lo que pongas con `--set` y no esté en el fichero de valores se **pierde** en el
siguiente `upgrade -f`. En el lab, todo cambio va al fichero del repo.

**Anota en el checklist (fila 24):** versión del chart, PVC, IP y el historial.

**Qué documentar:** chart, valores, release, revisión; `helm template` como herramienta de revisión; por qué todos los
`helm install` del lab fijan `--version` (sin ella, la misma orden instala cosas distintas cada mes).

**Respuestas a las preguntas de K7:**

1. **¿Dónde guarda Helm el historial?** En Secrets del namespace de la release (`kubectl -n gitea get secrets -l
   owner=helm`), uno por revisión.
2. **¿Qué pasa si escribes mal una clave en el fichero de valores?** Nada: Helm la ignora. Por eso se compara con
   `helm show values` y se revisa con `helm template` o `helm get values --all`.
3. **¿Un `rollback` borra la revisión mala?** No: crea una revisión nueva con el contenido de la elegida.


---

### 6.8 Solución K8 — Monitorización con Prometheus y Grafana

Sigue la guía del repo: **[kubernetes/monitorizacion-prometheus-grafana.md](monitorizacion-prometheus-grafana.md)**.

| Parte | Contenido |
|---|---|
| Conceptos | Prometheus (pull), exporters, reglas, Alertmanager, Grafana, Prometheus Operator; PromQL en cinco minutos |
| 1. Instalación | kube-prometheus-stack 88.6.2 paso a paso, con la salida esperada de cada comando; receptor de alertas ("móvil de guardia"), ServiceMonitor de podinfo, reglas y dashboard como código |
| 2. Escenarios | **13 averías reales**: E00 falsos `TargetDown`, E01 CrashLoopBackOff, E02 OOMKilled, E03 CPU throttling, E04 errores 5xx, E05 latencia, E06 readiness, E07 nodo caído, E08 ServiceMonitor ignorado, E09 imagen inexistente, E10 disco lleno, E11 silencios e inhibición, E12 VMs fuera del clúster |
| 3. Grafana | Explore, dashboards de serie, importar el 1860, dashboard como código, variables, usuario Viewer |

**Requisitos:** 8.2 (clúster), 8.4 (MetalLB y NetworkPolicies), 8.5 (local-path) y 8.7 (Helm).

**Antes de la 8.9:** snapshot `*-antes-8.9` (el primer `apply` de Terraform adopta con `import` lo hecho a mano).

### 6.9 Solución K9 — Infraestructura como código con Terraform

Sigue la guía del repo: **[kubernetes/terraform-iac.md](terraform-iac.md)**.

| Parte | Contenido |
|---|---|
| Preparación | Terraform 1.16 desde el repositorio de HashiCorp, paso a paso; namespace `tfstate` para el estado remoto |
| T1-T8 | `init` y `plan` sin aplicar, `import` de lo hecho a mano, módulos, drift, bloqueo del estado, CRDs, `prevent_destroy`/`moved`, Terraform frente a Ansible |

**Requisitos:** 8.4 (MetalLB y su pool), 8.6 (namespace `tienda`) y 8.8 (kube-prometheus-stack y el Secret
`grafana-admin`), todo instalado a mano tal como dicen esas subetapas.

---

### 6.10 Solución K10 — OpenShift: Red Hat OpenShift Local (CRC) en el host

> **Orden:** se hace **al final de la etapa** (ver la sección 0). Necesita el
> clúster kubeadm apagado y es la única subetapa que toca el host.

**Objetivo:** OpenShift es Kubernetes con todo lo que en la 8.2-8.9 has montado a mano ya integrado (red, registro de
imágenes, monitorización, rutas, consola web, actualizaciones gestionadas) y con seguridad más estricta por defecto.
Se ve qué cambia trabajando con él.

**Dónde:** el host (Linux Mint), como tu usuario.

**Requisitos de CRC:** 4 vCPU físicas, ~10,5-11 GiB de RAM libres y 35 GB de disco **en el host**; cuenta gratuita de
Red Hat Developer para descargar `crc` y el *pull secret* (console.redhat.com → OpenShift → Local).

> ⚠️ **Linux Mint no es una plataforma soportada por CRC** (lo es RHEL/Fedora; en Ubuntu y derivados suele funcionar
> si se usa NetworkManager, como en Mint). Y `crc setup` **modifica el host**: configura libvirt y su red `crc`, un
> `dnsmasq` de NetworkManager para `*.crc.testing` y `*.apps-crc.testing`, y añade tu usuario a grupos. En el lab,
> además, el host ya enruta `*.lab.local` hacia `dns01` (`lab.sh host-dns`, Etapa 4): un cambio en el DNS del host puede
> romperlo. Por eso, primero solo lectura y una decisión con la lista delante. Si algo preocupa, se queda en teoría y
> se practica en el **Developer Sandbox** de Red Hat (OpenShift en la nube, gratuito y temporal).

#### 8.10.1 Revisión de solo lectura del host

```bash
# [host]
nproc; free -h; df -h ~
virsh net-list --all
resolvectl status | grep -A3 -E 'virbr-lab|Link'
resolvectl query dns01.lab.local
systemctl is-active NetworkManager
```

Anota todo: es el "antes". Lo esperado: ≥ 4 CPU, ≥ 11 GiB disponibles **con el clúster apagado**, ≥ 35 GB libres,
las redes `default` y `lab-net`, `dns01.lab.local` resolviendo a `10.10.10.20` y NetworkManager `active`.

#### 8.10.2 Apagar el clúster y descargar `crc`

```bash
# [host]
scripts/lab.sh down k8s-w02; scripts/lab.sh down k8s-w01; scripts/lab.sh down k8s-cp01
free -h
```

Descarga desde console.redhat.com (OpenShift → Local) el tarball de `crc` para Linux y el *pull secret*
(`pull-secret.txt`) en `~/Descargas`. Después, sin `sudo`:

```bash
# [host]
mkdir -p ~/bin ~/crc && tar xJf ~/Descargas/crc-linux-amd64.tar.xz -C ~/crc --strip-components=1
install -m 0755 ~/crc/crc ~/bin/crc
crc version
```

Lo esperado: la versión de CRC y la de OpenShift que trae (anótalas en el checklist). Si `crc: command not found`,
`~/bin` no está en tu `PATH`: abre una terminal nueva o usa `~/bin/crc`.

#### 8.10.3 Configurar y revisar qué cambiaría

```bash
# [host]
crc config set memory 11264
crc config set cpus 4
crc config set consent-telemetry no
crc config view
crc setup --check-only
```

| Comando | Qué hace | Qué esperas |
|---|---|---|
| `config set memory 11264` | RAM de la VM de OpenShift, en MiB (11 GiB) | — |
| `config set cpus 4` | vCPU de la VM | — |
| `config set consent-telemetry no` | No enviar telemetría | — |
| `config view` | Configuración actual | Las tres claves |
| `setup --check-only` | **Solo comprueba**: lista lo que `crc setup` cambiaría, sin cambiarlo | Una lista de comprobaciones con las que fallan (las que `setup` arreglaría) |

Si tu versión no tiene `--check-only`, `crc setup --help` dice qué opciones hay; **no** lances `crc setup` sin saber qué
va a hacer. Copia la salida al checklist (fila 49) y decide.

#### 8.10.4 (Tras decidirlo) instalar y arrancar

```bash
# [host]
crc setup
crc start -p ~/Descargas/pull-secret.txt
eval "$(crc oc-env)"
crc console --credentials
oc login -u developer -p developer https://api.crc.testing:6443
oc whoami; oc get nodes
resolvectl query dns01.lab.local
```

| Comando | Qué esperas | Si sale otra cosa |
|---|---|---|
| `crc setup` | `Your system is correctly setup for using CRC` | Un error de una comprobación → léelo, no lo fuerces |
| `crc start` | 10-20 minutos; al final, la URL de la consola y las credenciales | Falta de memoria → ¿el clúster kubeadm sigue encendido? |
| `oc login`, `oc get nodes` | `developer` y un nodo `crc` `Ready` | — |
| `resolvectl query dns01.lab.local` | Sigue resolviendo `10.10.10.20` | Si no, el `dnsmasq` de CRC ha pisado el DNS del lab: es un caso de troubleshooting y `crc cleanup` lo deshace |

#### 8.10.5 Ejercicios comparando con Kubernetes "a pelo"

```bash
# [host]
oc new-project tienda
oc apply -f scripts/stage8/files/apps/podinfo.yaml
```

Este `apply` trae el namespace `demo` (un `developer` no puede crearlo) y los recursos. Para el ejercicio, aplica solo
el Deployment y el Service en `tienda`:

```bash
# [host]
sed -e '/^kind: Namespace/,/^---/d' -e 's/namespace: demo/namespace: tienda/' scripts/stage8/files/apps/podinfo.yaml > /tmp/podinfo-oc.yaml
oc apply -f /tmp/podinfo-oc.yaml
oc get pods; oc get events --sort-by=.lastTimestamp | tail -5
```

| Ejercicio | Comando | Qué esperas | Lo equivalente en el lab |
|---|---|---|---|
| Proyecto | `oc new-project tienda`; `oc get project tienda -o yaml` | Proyecto = namespace con RBAC, cuotas y SCC listos | 8.6 a mano |
| podinfo sin tocar | `oc apply -f /tmp/podinfo-oc.yaml` | **Falla**: el SCC `restricted-v2` no admite `runAsUser: 100` (OpenShift asigna un UID del rango del proyecto) | Pod Security `restricted` (aquí sí valía) |
| Corregirlo | Quita las líneas `runAsUser: 100` de `/tmp/podinfo-oc.yaml` y repite | Pods `Running` con un UID alto (`oc exec deploy/podinfo -- id`) | — |
| Route | `oc expose svc/podinfo`; `oc get route` y `curl` a la URL | Nombre `podinfo-tienda.apps-crc.testing` | Ingress + Traefik + DNS (8.4) |
| S2I | `oc new-app` con un repo de GitHub o de Gitea (si lo enciendes) | Construye la imagen **dentro** del clúster | No hay: Podman fuera del clúster (8.1) |
| Consola web: *Observe* | `crc console` | Prometheus/Alertmanager integrados (en CRC, apagados por defecto: `crc config set enable-cluster-monitoring true`, pide 14 GiB) | 8.8 entero |
| Operadores | `oc get clusteroperators`; `oc get clusterversion` (como `kubeadmin`) | El clúster se gestiona con operadores y versiones del propio OpenShift | `kubeadm upgrade` (8.12) |

**OpenShift Virtualization** (KubeVirt) ejecuta VMs como objetos de Kubernetes y es la alternativa de Red Hat a vSphere
tras la compra de VMware por Broadcom. CRC no la soporta (no hay virtualización anidada suficiente): se estudia en
teoría y se relaciona con la Etapa 10 (VMware) y la 14 (migraciones). Anota sus conceptos: `VirtualMachine`,
`DataVolume`, migración en vivo, Migration Toolkit for Virtualization.

#### 8.10.6 Dejar el host como estaba

```bash
# [host]
crc stop
crc delete            # si necesitas liberar el disco (~35 GB)
crc cleanup           # deshace lo que hizo crc setup en el host
resolvectl query dns01.lab.local
virsh net-list --all
```

Compara con el "antes" de la 8.10.1. Lo esperado: el DNS del lab resolviendo y solo las redes `default` y `lab-net`.

**Anota en el checklist (filas 49-50).**

---

### 6.11 Solución K11 — CI/CD y GitOps (Gitea + Argo CD)

**Objetivo:** **CI** = comprobar cada cambio antes de aplicarlo; **CD con GitOps** = el clúster se sincroniza solo con
lo que dice Git.

**Dónde:** `ansible01`.

#### 8.11.1 CI: `validar.sh` y sus herramientas

`scripts/stage8/files/ci/validar.sh` hace lo que haría un pipeline con cada cambio de la etapa: `yamllint`,
`kubeconform` (manifiestos frente al esquema de la API 1.36), `promtool` (reglas y pruebas unitarias de alertas) y
`terraform fmt`/`validate`. **Sin clúster y sin tocar nada.** Si falta una herramienta, la salta y lo dice.

**1. Instalar lo que falte** (Terraform viene de la 8.9):

```bash
# [ansible01 · adminlab]
sudo dnf install -y python3-pip python3-pyyaml
pip3 install --user yamllint
yamllint --version
```

```bash
# [ansible01 · adminlab]  kubeconform: binario de GitHub con suma de verificación
KC_VERSION=v0.7.0        # cámbialo por la última de https://github.com/yannh/kubeconform/releases
cd /tmp
curl -fsSLO "https://github.com/yannh/kubeconform/releases/download/${KC_VERSION}/kubeconform-linux-amd64.tar.gz"
curl -fsSL "https://github.com/yannh/kubeconform/releases/download/${KC_VERSION}/CHECKSUMS" | grep 'kubeconform-linux-amd64.tar.gz' | sha256sum -c
tar xzf kubeconform-linux-amd64.tar.gz kubeconform && install -m 0755 kubeconform ~/.local/bin/
kubeconform -v
```

```bash
# [ansible01 · adminlab]  promtool: viene en el tarball de Prometheus
PROM_VERSION=3.x.y       # la última 3.x de https://github.com/prometheus/prometheus/releases (sin la "v")
cd /tmp
curl -fsSLO "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
curl -fsSL "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/sha256sums.txt" | grep "prometheus-${PROM_VERSION}.linux-amd64.tar.gz" | sha256sum -c
tar xzf "prometheus-${PROM_VERSION}.linux-amd64.tar.gz" "prometheus-${PROM_VERSION}.linux-amd64/promtool"
install -m 0755 "prometheus-${PROM_VERSION}.linux-amd64/promtool" ~/.local/bin/
promtool --version
```

| Comprobación | Qué esperas | Si sale otra cosa |
|---|---|---|
| `sha256sum -c` | `...tar.gz: OK` | `FAILED` → no lo instales. Si el `grep` no devuelve nada, el nombre del fichero de sumas cambió: míralo en la página de la versión |
| `kubeconform -v` / `promtool --version` | La versión | `command not found` → `~/.local/bin` no está en el `PATH` (abre otra sesión) |

**2. Ejecutar:**

```bash
# [ansible01 · adminlab]
git -C ~/enterprise-rhel-lab pull
~/enterprise-rhel-lab/scripts/stage8/files/ci/validar.sh
```

Lo esperado: cuatro bloques (`== 1. yamllint`, `== 2. kubeconform`, `== 3. promtool`, `== 4. terraform`) con `OK` y
`RESULTADO: OK` al final. Lo `OMITIDO` (por ejemplo, `terraform validate` sin red) no cuenta como fallo.

**3. Romper a propósito** (en una copia, no en el repo):

```bash
# [ansible01 · adminlab]
rm -rf /tmp/ci-prueba && cp -r ~/enterprise-rhel-lab/scripts/stage8/files /tmp/ci-prueba
sed -i 's/> 0.05/> 0.10/' /tmp/ci-prueba/monitoring/rules/podinfo-slo.yaml
/tmp/ci-prueba/ci/validar.sh | grep -E 'FALLO|RESULTADO'
```

Lo esperado: `FALLO tests/podinfo-slo.rules.yaml desfasado` (la copia que usan las pruebas ya no coincide con la regla)
y `RESULTADO: 1 FALLO(S)`. Prueba también una sangría rota en un YAML (lo caza `yamllint`) y un `replicas: "dos"` en
`apps/podinfo.yaml` (lo caza `kubeconform`). Así funciona un pipeline: el cambio no entra si no pasa.

**Ampliación:** un *runner* de Gitea Actions que ejecute `validar.sh` en cada `push` al repositorio `lab/k8s-apps`.

#### 8.11.2 Instalar Argo CD

```bash
# [ansible01 · adminlab]
kubectl create namespace argocd
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.2/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=5m
kubectl -n argocd patch svc argocd-server -p '{"spec":{"type":"LoadBalancer"},"metadata":{"annotations":{"metallb.io/loadBalancerIPs":"10.10.10.116"}}}'
kubectl -n argocd get svc argocd-server
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

| Comando | Qué esperas | Si sale otra cosa |
|---|---|---|
| `apply --server-side` | Muchos `serverside-applied` | Sin `--server-side`, los CRDs grandes fallan con `metadata.annotations: Too long` |
| `rollout status` | `successfully rolled out` | — |
| `patch svc` | `EXTERNAL-IP 10.10.10.116` | `<pending>` → la IP está ocupada o fuera del pool |
| `initial-admin-secret` | La contraseña inicial de `admin` | Apúntala; después de cambiarla, borra ese Secret |

Entra en https://argocd.lab.local (certificado autofirmado: acéptalo) con `admin` y esa contraseña.

#### 8.11.3 Un repositorio GitOps en Gitea

```bash
# [ansible01 · adminlab]
cd ~ && git clone http://gitea.lab.local/lab/k8s-apps.git && cd k8s-apps
mkdir -p podinfo-gitops
cat > podinfo-gitops/podinfo.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: podinfo
  labels: {app.kubernetes.io/name: podinfo}
spec:
  replicas: 2
  selector:
    matchLabels: {app.kubernetes.io/name: podinfo}
  template:
    metadata:
      labels: {app.kubernetes.io/name: podinfo}
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 100
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: podinfo
          image: ghcr.io/stefanprodan/podinfo:6.15.0
          ports: [{name: http, containerPort: 9898}]
          env: [{name: PODINFO_UI_MESSAGE, value: "desplegado por Argo CD"}]
          resources:
            requests: {cpu: 20m, memory: 32Mi}
            limits: {cpu: 200m, memory: 128Mi}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: ["ALL"]}
---
apiVersion: v1
kind: Service
metadata:
  name: podinfo
spec:
  selector: {app.kubernetes.io/name: podinfo}
  ports: [{name: http, port: 80, targetPort: http}]
EOF
git add podinfo-gitops && git -c user.name=adminlab -c user.email=adminlab@lab.local commit -m "podinfo gestionado por GitOps"
git push origin main
```

`git push` pide usuario y contraseña: `gitea-admin` y la de la 8.7.2. Los manifiestos **no** llevan `namespace`: lo
pone la `Application`.

#### 8.11.4 La `Application` de Argo CD

```bash
# [ansible01 · adminlab]
cat > ~/app-podinfo-gitops.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: podinfo-gitops
  namespace: argocd
spec:
  project: default
  source:
    repoURL: http://gitea-http.gitea.svc.cluster.local/lab/k8s-apps.git
    targetRevision: main
    path: podinfo-gitops
  destination:
    server: https://kubernetes.default.svc
    namespace: gitops
  syncPolicy:
    automated:
      prune: true          # borra del clúster lo que se borre de Git
      selfHeal: true       # deshace los cambios hechos a mano
    syncOptions: [CreateNamespace=true]
EOF
kubectl apply -f ~/app-podinfo-gitops.yaml
kubectl -n argocd get application podinfo-gitops -w     # SYNC STATUS Synced, HEALTH Healthy; Ctrl+C
kubectl -n gitops get deploy,pods
```

| Clave | Qué hace |
|---|---|
| `repoURL` | El repo por el nombre **interno** del Service de Gitea (Argo CD está dentro del clúster) |
| `path` | La carpeta del repo con los manifiestos |
| `destination.namespace` | Dónde se crean |
| `automated` + `prune` + `selfHeal` | Sincroniza sola, borra lo que sobra y deshace la deriva |

Lo esperado: `Synced` y `Healthy` en menos de un minuto, y 2 pods en `gitops`. Si se queda en `Unknown` con
`repository not found`, revisa la URL (`kubectl -n gitea get svc`) y que el repo sea **público**.

#### 8.11.5 Drift, despliegue y vuelta atrás

**1. Drift con autocorrección:**

```bash
# [ansible01 · adminlab]
kubectl -n gitops scale deploy/podinfo --replicas=5
kubectl -n gitops get deploy podinfo -w          # 5 -> 2 en segundos; Ctrl+C
```

Compáralo con el T4 de Terraform (8.9): allí el drift solo se ve al hacer `plan`; aquí se corrige solo.

**2. Despliegue = commit:**

```bash
# [ansible01 · adminlab]  (en ~/k8s-apps)
sed -i 's/replicas: 2/replicas: 3/' podinfo-gitops/podinfo.yaml
git -c user.name=adminlab -c user.email=adminlab@lab.local commit -am "podinfo a 3 réplicas" && git push origin main
kubectl -n gitops get deploy podinfo -w          # a los ~3 min (o al pulsar Refresh en la web): 3; Ctrl+C
```

Argo CD consulta el repo cada 3 minutos por defecto. En la web, *Refresh* lo fuerza.

**3. Vuelta atrás = `git revert`:**

```bash
# [ansible01 · adminlab]  (en ~/k8s-apps)
git revert --no-edit HEAD && git push origin main
git log --oneline | head -3
```

Lo esperado: vuelve a 2 réplicas, y el historial de Git dice **quién**, **qué** y **cuándo**: la auditoría sale gratis.

**Anota en el checklist (filas 51-52).**

**Qué documentar:** CI frente a CD; *push* (Terraform, Ansible, `kubectl apply`) frente a *pull* (GitOps); y quién
gestiona qué en el lab (plataforma con Terraform, aplicaciones con Argo CD).

**Respuestas a las preguntas de K11:**

1. **¿Qué diferencia hay entre `kubectl apply` desde un pipeline y GitOps?** En el primero, el pipeline **empuja** con
   credenciales del clúster; en GitOps, un agente dentro del clúster **tira** de Git y corrige la deriva.
2. **¿Cómo se vuelve atrás en GitOps?** Con `git revert`: el estado anterior vuelve a ser el de Git.
3. **¿Qué hace `selfHeal`?** Deshace los cambios manuales que diferencian el clúster de Git.


---

### 6.12 Solución K12 — Operación del clúster: mantenimiento, copias de etcd y actualización

**Antes de empezar:** snapshot `*-antes-8.12` de los tres nodos (apagados) y, además, una copia de etcd (8.12.2).

#### 8.12.1 Mantenimiento de un nodo: `drain`, PodDisruptionBudget y `uncordon`

**1. Sin protección:**

```bash
# [ansible01 · adminlab]
kubectl -n demo get pods -l app.kubernetes.io/name=podinfo -o wide
kubectl drain k8s-w02 --ignore-daemonsets --delete-emptydir-data
kubectl get nodes
kubectl -n demo get pods -l app.kubernetes.io/name=podinfo -o wide
```

| Comando | Qué hace | Qué esperas |
|---|---|---|
| `drain` | Marca el nodo como no programable (*cordon*) y **desaloja** sus pods, respetando los PodDisruptionBudgets | `node/k8s-w02 drained` |
| `--ignore-daemonsets` | Los DaemonSets (calico-node, kube-proxy, node-exporter) se quedan: volverían a crearse en el mismo nodo | Sin la opción, el `drain` se niega |
| `--delete-emptydir-data` | Acepta perder los volúmenes `emptyDir` (temporales) | — |
| `get nodes` | `k8s-w02 Ready,SchedulingDisabled` | — |
| `get pods` | Los dos podinfo en `k8s-w01` | — |

**2. Parchear el SO del nodo** (lo que se haría en una ventana de mantenimiento):

```bash
# [k8s-w02 · root]
dnf update -y            # Kubernetes no se actualiza: está en el exclude= del repositorio
needs-restarting -r; reboot
```

```bash
# [ansible01 · adminlab]
kubectl get nodes -w     # k8s-w02 NotReady -> Ready,SchedulingDisabled; Ctrl+C
kubectl uncordon k8s-w02
```

`uncordon` vuelve a permitir pods en el nodo, pero **no** mueve los que ya están en `k8s-w01`: se reparten en el próximo
*rollout* o escalado.

**3. Con un PodDisruptionBudget:**

```bash
# [ansible01 · adminlab]
cat > ~/pdb-podinfo.yaml <<'EOF'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: podinfo
  namespace: demo
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: podinfo
EOF
kubectl apply -f ~/pdb-podinfo.yaml
kubectl -n demo get pdb podinfo
kubectl -n demo scale deploy/podinfo --replicas=1
kubectl -n demo get pdb podinfo
NODO=$(kubectl -n demo get pods -l app.kubernetes.io/name=podinfo -o jsonpath='{.items[0].spec.nodeName}'); echo "$NODO"
kubectl drain "$NODO" --ignore-daemonsets --delete-emptydir-data --timeout=60s
```

| Paso | Qué esperas | Qué demuestra |
|---|---|---|
| `get pdb` con 2 réplicas | `MIN AVAILABLE 1`, `ALLOWED DISRUPTIONS 1` | Se puede desalojar uno |
| Con 1 réplica | `ALLOWED DISRUPTIONS 0` | — |
| `drain` del nodo de esa réplica | Repite `Cannot evict pod as it would violate the pod's disruption budget` y acaba con `timed out` | El PDB **protege el servicio**: el administrador del nodo no puede dejarlo sin réplicas |

Arreglo: escalar antes del mantenimiento.

```bash
# [ansible01 · adminlab]
kubectl uncordon "$NODO"
kubectl -n demo scale deploy/podinfo --replicas=2
kubectl -n demo rollout status deploy/podinfo
kubectl drain "$NODO" --ignore-daemonsets --delete-emptydir-data && kubectl uncordon "$NODO"
```

#### 8.12.2 Copia de etcd

Todo el estado del clúster (objetos, Secrets, configuración) está en etcd. Sin copia de etcd, perder `k8s-cp01` es
perder el clúster.

```bash
# [k8s-cp01 · root]
ETCD="kubectl --kubeconfig /etc/kubernetes/admin.conf -n kube-system exec etcd-k8s-cp01 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"
$ETCD endpoint status -w table
$ETCD snapshot save /var/lib/etcd/snapshot-$(date +%F).db
ls -lh /var/lib/etcd/snapshot-*.db
kubectl --kubeconfig /etc/kubernetes/admin.conf -n kube-system exec etcd-k8s-cp01 -- etcdutl snapshot status /var/lib/etcd/snapshot-$(date +%F).db -w table
```

| Comando | Qué hace | Qué esperas |
|---|---|---|
| `ETCD=...` | Guarda en una variable el `etcdctl` del propio pod de etcd con sus certificados (etcd exige TLS mutuo) | — |
| `endpoint status` | Estado del miembro | Una fila con versión, tamaño de la base de datos y `IS LEADER true` |
| `snapshot save` | Copia consistente de la base de datos. `/var/lib/etcd` del pod es un `hostPath`: el fichero aparece en el nodo | `Snapshot saved at /var/lib/etcd/snapshot-2026-...db` |
| `etcdutl snapshot status` | Comprueba la copia | Hash, revisión, número de claves y tamaño |

Si `etcdctl` o `etcdutl` no existen en la imagen de tu versión, el error es `executable file not found`: descarga el
tarball de etcd de la misma versión (la de `endpoint status`) desde las *releases* de etcd en GitHub y usa los
binarios en `k8s-cp01`.

**Una copia en el mismo disco no es una copia.** Llévala a `ansible01`:

```bash
# [k8s-cp01 · root]
install -o adminlab -m 0600 /var/lib/etcd/snapshot-$(date +%F).db ~adminlab/
```

```bash
# [ansible01 · adminlab]
mkdir -p ~/copias-etcd && scp adminlab@k8s-cp01.lab.local:'snapshot-*.db' ~/copias-etcd/ && ls -lh ~/copias-etcd/
ssh adminlab@k8s-cp01.lab.local 'rm -f snapshot-*.db'
```

#### 8.12.3 Restaurar etcd (con el snapshot `antes-8.12` hecho)

**1. Un cambio que perder:**

```bash
# [ansible01 · adminlab]
kubectl create namespace borrame
kubectl get ns borrame
```

```bash
# [k8s-cp01 · root]
$ETCD snapshot save /var/lib/etcd/con-borrame.db       # si cerraste la sesión, vuelve a definir ETCD
```

```bash
# [ansible01 · adminlab]
kubectl delete namespace borrame
kubectl get ns borrame          # NotFound
```

**2. Restaurar en un directorio nuevo** (dentro de `/var/lib/etcd`, que el pod ve):

```bash
# [k8s-cp01 · root]
kubectl --kubeconfig /etc/kubernetes/admin.conf -n kube-system exec etcd-k8s-cp01 -- \
  etcdutl snapshot restore /var/lib/etcd/con-borrame.db --data-dir /var/lib/etcd/restaurado
ls /var/lib/etcd/restaurado
```

Lo esperado: un directorio `member/`. Es una base de datos nueva con el estado de la copia.

**3. Apuntar el pod de etcd al directorio restaurado.** El manifiesto es un pod estático: el kubelet lo recrea en
cuanto cambia el fichero.

```bash
# [k8s-cp01 · root]
cp -a /etc/kubernetes/manifests/etcd.yaml /root/etcd.yaml.antes-restauracion     # FUERA de manifests/
grep -n -A2 'name: etcd-data' /etc/kubernetes/manifests/etcd.yaml
```

Lo esperado: dos apariciones de `etcd-data`, una en `volumeMounts` (`mountPath: /var/lib/etcd`) y otra en `volumes`
(`hostPath: path: /var/lib/etcd`). Se cambia **solo** la del `hostPath`:

```bash
# [k8s-cp01 · root]
sed -i '/hostPath:/{n;s|path: /var/lib/etcd$|path: /var/lib/etcd/restaurado|}' /etc/kubernetes/manifests/etcd.yaml
diff /root/etcd.yaml.antes-restauracion /etc/kubernetes/manifests/etcd.yaml
```

El `diff` debe mostrar **una** línea: `path: /var/lib/etcd` → `path: /var/lib/etcd/restaurado` en el volumen
`etcd-data`. Si cambia otra cosa, restaura la copia y hazlo con `vim`.

```bash
# [k8s-cp01 · root]
watch crictl ps --name 'etcd|kube-apiserver'          # se reinician los dos; Ctrl+C cuando estén Running
```

```bash
# [ansible01 · adminlab]
kubectl get ns borrame
kubectl get nodes; kubectl get pods -A | grep -v -E 'Running|Completed'
```

Lo esperado: `borrame` **vuelve** (`Active`) y el clúster sigue sano. Si la API no vuelve en 2-3 minutos:
`crictl logs $(crictl ps -a --name etcd -q | head -1)` en `k8s-cp01`; y la vuelta atrás es copiar
`/root/etcd.yaml.antes-restauracion` a `manifests/` (o el snapshot de la VM).

**Para dejarlo limpio:** `kubectl delete namespace borrame`. El etcd sigue usando `/var/lib/etcd/restaurado`: es
válido, pero anótalo (en la 8.12.4, `kubeadm upgrade` lee el manifiesto actual).

#### 8.12.4 Actualización 1.36 → 1.37

Reglas: **una versión menor cada vez**; primero el plano de control, después los workers, de uno en uno; `kubectl`
admite una versión menor de diferencia con la API.

**0. Compatibilidad**, antes de tocar nada: comprueba en la documentación de Calico (requisitos del sistema), MetalLB,
Traefik y kube-prometheus-stack que tus versiones admiten Kubernetes 1.37, y anótalo. Abre Grafana
("Kubernetes / Compute Resources / Cluster") para ver el *upgrade* en directo.

**1. Plano de control (`k8s-cp01`):**

```bash
# [k8s-cp01 · root]
cp -a /etc/yum.repos.d/kubernetes.repo /root/kubernetes.repo.v1.36
sed -i 's/v1\.36/v1.37/g' /etc/yum.repos.d/kubernetes.repo
grep -E 'name|baseurl|gpgkey' /etc/yum.repos.d/kubernetes.repo
dnf list --showduplicates kubeadm --disableexcludes=kubernetes | tail -3
dnf install -y 'kubeadm-1.37.*' --disableexcludes=kubernetes
kubeadm version -o short
kubeadm upgrade plan
```

| Comando | Qué esperas | Si sale otra cosa |
|---|---|---|
| `sed` + `grep` | Las tres líneas con `v1.37` | — |
| `dnf list --showduplicates` | Versiones `1.37.z` | Vacío → el repositorio 1.37 no existe o la URL está mal |
| `kubeadm version` | `v1.37.z` | — |
| `upgrade plan` | Tabla con la versión actual y la objetivo de cada componente, y el comando exacto: `kubeadm upgrade apply v1.37.z` | Errores de *preflight* → léelos antes de seguir |

```bash
# [k8s-cp01 · root]
kubeadm upgrade apply v1.37.Z          # la versión exacta que dijo el plan
```

Tarda unos minutos y acaba con `SUCCESS! Your cluster was upgraded to "v1.37.z"`. Actualiza los manifiestos estáticos
(apiserver, controller-manager, scheduler, etcd si toca), CoreDNS y kube-proxy, y **renueva los certificados**.

```bash
# [ansible01 · adminlab]
kubectl drain k8s-cp01 --ignore-daemonsets
```

```bash
# [k8s-cp01 · root]
dnf install -y 'kubelet-1.37.*' 'kubectl-1.37.*' --disableexcludes=kubernetes
systemctl daemon-reload && systemctl restart kubelet
```

```bash
# [ansible01 · adminlab]
kubectl uncordon k8s-cp01
kubectl get nodes          # k8s-cp01 v1.37.z, workers v1.36.5
```

**2. Cada worker, de uno en uno** (primero `k8s-w01`, comprobar, y después `k8s-w02`):

```bash
# [k8s-w0X · root]
cp -a /etc/yum.repos.d/kubernetes.repo /root/kubernetes.repo.v1.36
sed -i 's/v1\.36/v1.37/g' /etc/yum.repos.d/kubernetes.repo
dnf install -y 'kubeadm-1.37.*' --disableexcludes=kubernetes
kubeadm upgrade node
```

```bash
# [ansible01 · adminlab]
kubectl drain k8s-w0X --ignore-daemonsets --delete-emptydir-data
```

```bash
# [k8s-w0X · root]
dnf install -y 'kubelet-1.37.*' 'kubectl-1.37.*' --disableexcludes=kubernetes
systemctl daemon-reload && systemctl restart kubelet
```

```bash
# [ansible01 · adminlab]
kubectl uncordon k8s-w0X
kubectl get nodes
```

Mientras, en otra terminal, comprueba que podinfo no se corta:

```bash
# [ansible01 · adminlab]
while true; do printf '%s %s\n' "$(date +%T)" "$(curl -s -m2 -o /dev/null -w '%{http_code}' http://podinfo.lab.local)"; sleep 1; done
```

Lo esperado: todo `200` (con 2 réplicas y el PDB). Un `000` durante el `drain` de un worker significa que las dos
réplicas estaban en el mismo nodo.

**3. `ansible01`:** actualiza también `kubectl` (`sed` en su `.repo` y `dnf install 'kubectl-1.37.*'`).

**4. Comprobación final:**

```bash
# [ansible01 · adminlab]
kubectl get nodes -o wide                         # 3 x v1.37.z
kubectl get pods -A | grep -v -E 'Running|Completed'
kubectl version
```

```bash
# [k8s-cp01 · root]
kubeadm certs check-expiration                    # ~365 días otra vez: el upgrade los renovó
```

**Ampliación (opcional): Velero** para copias de objetos y volúmenes con destino S3 (MinIO en `dns01` o en el host).

---

### 6.13 Solución K13 — Automatizar lo aprendido con Ansible

Proyecto **separado** en `ansible01:~/k8s-ansible` (no en `~/ansible-lab`: `stage7-setup` lo sincroniza con
`rsync --delete` y borraría lo tuyo; caso etapa7/04). Lo mismo que en la práctica de la Etapa 7: escribirlo a mano.

**Preparación:**

```bash
# [host]  la clave de ansible01 en los tres nodos (con el acceso que el host ya tiene)
for h in k8s-cp01 k8s-w01 k8s-w02; do
  ssh adminlab@ansible01 cat .ssh/id_ed25519.pub | ssh adminlab@$h.lab.local 'cat >> .ssh/authorized_keys'
done
```

```bash
# [ansible01 · adminlab]
mkdir -p ~/k8s-ansible/{inventory,roles,collections} && cd ~/k8s-ansible
cat > ansible.cfg <<'EOF'
[defaults]
inventory          = ./inventory/hosts.ini
remote_user        = adminlab
host_key_checking  = False
interpreter_python = auto_silent
roles_path         = ./roles
collections_path   = ./collections

[privilege_escalation]
become = True
EOF
cat > inventory/hosts.ini <<'EOF'
[control_plane]
k8s-cp01 ansible_host=10.10.10.100

[workers]
k8s-w01 ansible_host=10.10.10.101
k8s-w02 ansible_host=10.10.10.102

[k8s:children]
control_plane
workers
EOF
cat > requirements.yml <<'EOF'
collections:
  - name: ansible.posix          # mount, sysctl, firewalld
    version: "1.5.4"
  - name: community.general      # lvg, lvol, modprobe
    version: "8.6.0"             # compatible con ansible-core 2.14 (compruébalo con ansible-galaxy)
EOF
ansible-galaxy collection install -r requirements.yml -p ./collections
ansible k8s -m ping -o
```

Si `ansible-galaxy` avisa de que una versión no es compatible con tu `ansible-core` 2.14, baja la versión de esa
colección (mira `requires_ansible` en su página de Galaxy).

**Módulos para cada pieza del rol `k8s_node`** (consulta cada uno con `ansible-doc <módulo>`):

| Pieza (8.2.2) | Módulo |
|---|---|
| LVs | `community.general.lvol` (y `community.general.filesystem` para el XFS) |
| Montajes en `fstab` | `ansible.posix.mount` (`state: mounted`) |
| Swap | `ansible.builtin.command: swapoff -a` con `when: ansible_swaptotal_mb > 0` + `ansible.builtin.replace` en `fstab` |
| Módulos del kernel | `community.general.modprobe` + `ansible.builtin.copy` a `/etc/modules-load.d/k8s.conf` |
| sysctl | `ansible.posix.sysctl` (con `sysctl_file: /etc/sysctl.d/90-k8s.conf`) |
| NetworkManager | `ansible.builtin.copy` + handler `systemctl reload NetworkManager` |
| Zona `k8s` | `ansible.posix.firewalld` (`zone`, `source`, `port`, `service`, `permanent`, `immediate`; la zona nueva con `state: present`) |
| containerd | `ansible.builtin.yum_repository`, `ansible.builtin.dnf`, `ansible.builtin.command: containerd config default` **solo si** el fichero no tiene `SystemdCgroup = true` (`creates` no sirve aquí: piensa por qué), `ansible.builtin.replace` |
| Paquetes v1.36 | `ansible.builtin.yum_repository` con `exclude`, `ansible.builtin.dnf` con `disable_excludes: kubernetes` |
| kubelet | `ansible.builtin.systemd` (`enabled: true`) |

**Esqueleto del playbook `k8s-cluster.yml`:**

```yaml
- name: Preparar los nodos
  hosts: k8s
  roles: [k8s_node]

- name: Plano de control
  hosts: control_plane
  tasks:
    - name: kubeadm init (solo si no hay clúster)
      ansible.builtin.command: kubeadm init --config /root/kubeadm-config.yaml --upload-certs
      args:
        creates: /etc/kubernetes/admin.conf       # idempotente: si existe, no se ejecuta
    # ... Calico (kubectl create solo si no existe el namespace tigera-operator)

- name: Workers
  hosts: workers
  serial: 1
  tasks:
    - name: Comando join generado al vuelo
      ansible.builtin.command: kubeadm token create --print-join-command
      delegate_to: k8s-cp01
      register: join
      changed_when: false
      when: not (ansible_facts ... )   # piensa: ¿cómo sabes si el nodo ya está unido? (/etc/kubernetes/kubelet.conf)
    - name: kubeadm join
      ansible.builtin.command: "{{ join.stdout }}"
      args:
        creates: /etc/kubernetes/kubelet.conf
```

**Criterios:** `--syntax-check`, `--check --diff` y, en la ejecución real, la **segunda** da `changed=0`.

**Prueba de fuego** (con el snapshot `antes-8.12` o uno nuevo):

```bash
# [ansible01 · adminlab]
kubectl drain k8s-w02 --ignore-daemonsets --delete-emptydir-data && kubectl delete node k8s-w02
```

```bash
# [host]
virsh destroy k8s-w02 2>/dev/null; scripts/lab.sh snapshot revert k8s-w02 5     # el nodo vuelve a "antes de Kubernetes"
```

```bash
# [ansible01 · adminlab]  (en ~/k8s-ansible)
ansible-playbook k8s-cluster.yml --limit 'k8s-w02,k8s-cp01'
kubectl get nodes -w           # k8s-w02 vuelve a Ready solo con Ansible
```

Después: rol `node_exporter` para las VMs del lab (lo que en el E12 de la 8.8 se hizo a mano en `dns01`).

**Anota en el checklist (fila 56)** y la tabla de quién hace qué: Ansible (nodos), Terraform (plataforma), Argo CD
(aplicaciones).
