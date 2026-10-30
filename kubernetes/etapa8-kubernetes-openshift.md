# Etapa 8 — Kubernetes y OpenShift, con Prometheus/Grafana y Terraform

> **Estado: 🚧 En curso** (8.1 empezada el 2026-10-29).
> **Tutorial práctico continuo:** cada tema empieza con el **concepto** (resumen de la documentación oficial, con su
> enlace) e inmediatamente se **practica** en el lab, a mano y sin scripts, como si fuera un ticket de trabajo real.
> Cada tema termina con un **error común en el mercado**: lo que se ve de verdad en empresas y cómo evitarlo.
> Checklist: [`checklists/etapa8.md`](../checklists/etapa8.md) · Ficheros: [`scripts/stage8/`](../scripts/stage8/README_stage8.md) ·
> Casos reales: [`troubleshooting/etapa8/`](../troubleshooting/etapa8/README_troubleshooting_etapa8.md)

## Cómo leer este tutorial

Cada subetapa empieza con un **ticket**: la petición tal como llegaría a un equipo de sistemas o plataforma. Después,
cada tema sigue siempre el mismo orden:

| Bloque | Qué contiene |
|---|---|
| 📘 **Concepto** | Lo más importante de la documentación oficial, resumido. Al final, la **Fuente** con el enlace: si algo de aquí contradice a la documentación de tu versión, manda la documentación |
| 🛠️ **Práctica** | Los comandos completos, listos para pegar, con una tabla **Qué esperas · Si sale otra cosa** |
| ⚠️ **Error común en el mercado** | El fallo que más se ve en ese tema, cómo se detecta y cómo se evita |

**Dónde se ejecuta cada comando:** va siempre en la primera línea del bloque.

| Etiqueta | Significa |
|---|---|
| `# [host]` | Linux Mint, en la raíz del repo (`~/Proyectos/PROYECTO_ENTERPRISE_RHEL_INFRASTRUCTURE_LAB/enterprise-rhel-lab`) |
| `# [ansible01 · adminlab]` | `ssh adminlab@ansible01`; aquí se usan `podman`, `kubectl`, `helm` y `terraform` |
| `# [k8s-cp01 · root]` | `ssh adminlab@k8s-cp01` y después `sudo -i` |
| `# [nodos · root]` | Lo mismo en **los tres** nodos (`k8s-cp01`, `k8s-w01`, `k8s-w02`), uno detrás de otro |
| `# [workers · root]` | Solo en `k8s-w01` y `k8s-w02` |

Si un comando no da lo que dice la tabla, **para**: no sigas encadenando comandos. Pega la salida y conviértelo en un
caso de `troubleshooting/etapa8/NN-*.md`. Las salidas marcadas **✅ Resultado real** son de este lab; el resto son las
**esperadas**.

## Objetivo y alcance

Montar un clúster **Kubernetes** de 3 nodos sobre RHEL 9 con `kubeadm` y operarlo como en una empresa: red,
almacenamiento, seguridad, Helm, copias de etcd y actualizaciones. Después, **monitorizarlo con Prometheus y Grafana**
provocando averías reales, **gestionarlo como código con Terraform** y con **GitOps**, y conocer **OpenShift**.

- **Entra:** las subetapas 8.1 a 8.13 y la automatización con Ansible de lo hecho a mano.
- **No entra:** alta disponibilidad del plano de control (un solo `k8s-cp01`), almacenamiento de red (Etapa 15) y
  comandos `lab.sh stage8-*`.

## Prerrequisitos

| Qué | Cómo comprobarlo | Por qué |
|---|---|---|
| Etapas 1-7 completas | `scripts/lab.sh status` y snapshots `*-stage7-complete` | Los nodos se crean con `lab.sh` y pasan por las etapas 2-5 |
| `dns01` y `ansible01` encendidas | `scripts/lab.sh up dns01; scripts/lab.sh up ansible01` | DNS y hora de todo el lab; `ansible01` es la estación de control |
| Repos de Red Hat | `sudo subscription-manager repos --list-enabled` en una VM | `dnf` en los nodos y en `ansible01` |
| ~19 GiB de RAM libres en el host | `free -h` | Clúster (14 GiB) + `dns01` y `ansible01` (5 GiB) |
| ≥ 60 GB libres en el host (100 GB cubren toda la etapa, OpenShift incluido) | `df -h` del pool `lab-images` (ver [Presupuesto de disco](#presupuesto-de-disco-del-host)) | Los discos son qcow2 *thin*: ocupan lo que se escribe, no su tamaño virtual |
| Salida a Internet desde lab-net | `curl -sI https://registry.k8s.io` desde `ansible01` | Imágenes, charts y paquetes |

## Arquitectura

```text
 TU LINUX MINT (host)  ── repo git · lab.sh (VMs, snapshots) · OpenShift Local (8.10)
        │
 red lab-net 10.10.10.0/24 · DNS dns01 (.20)
        │
 ansible01 (.30) · ESTACIÓN DE CONTROL ── podman · kubectl · helm · terraform · ansible
        │  API de Kubernetes https://k8s-api.lab.local:6443
        ▼
 k8s-cp01 (.100)              k8s-w01 (.101)             k8s-w02 (.102)
 plano de control             worker                     worker
 apiserver · etcd             kubelet · containerd       kubelet · containerd
 scheduler · controller-mgr   kube-proxy · calico-node   kube-proxy · calico-node
        │
 Pods 10.244.0.0/16 (Calico) · Services 10.96.0.0/12 · LoadBalancer (MetalLB) .110-.119
```

| Nombre (lab.local) | IP | Qué es | Subetapa |
|---|---|---|---|
| `k8s-cp01` / `k8s-api` | .100 | Plano de control (API, etcd, scheduler, controller-manager) | 8.2 |
| `k8s-w01`, `k8s-w02` | .101, .102 | Nodos de trabajo | 8.2 |
| `ingress` | .110 | Controlador de entrada (Traefik) | 8.4 |
| `grafana` / `prometheus` / `alertmanager` | .111 / .112 / .113 | kube-prometheus-stack | 8.8 |
| `podinfo` | .114 | Aplicación de ejemplo | 8.3-8.4 |
| `gitea` | .115 | Git dentro del clúster | 8.7 |
| `argocd` | .116 | GitOps | 8.11 |
| `tienda` | .117 | App creada con Terraform | 8.9 |

Los tres nodos están en `scripts/hosts.conf` como **opcionales** (`lab.sh ... all` no los incluye) y sus registros DNS
ya están en la zona de la Etapa 4. Cada nodo tiene un disco de datos de 40 GB: la Etapa 2 usa 8 GB (`vg_data`) y la
8.2 crea `lv_containerd` (16 GB), `lv_kubelet` (6 GB) y `lv_localpath` (8 GB).

| Conjunto | RAM | Notas |
|---|---|---|
| `dns01` + `ansible01` | 5 GiB | Siempre encendidas en esta etapa |
| Clúster (cp01 4 GiB + 2 × 5 GiB) | 14 GiB | Total ≈ 19 GiB |
| OpenShift Local (8.10) | 10,5-11 GiB | **Con el clúster apagado** |

### Versiones fijadas (octubre de 2026)

| Componente | Versión | Dónde |
|---|---|---|
| Podman (ansible01) | 5.8.2-8.el9_8 (AppStream de RHEL 9.8) — **real** | 8.1 |
| UBI 9 minimal | 9.8 — **real** | 8.1 |
| Kubernetes | v1.36.5; upgrade a 1.37 en la 8.12 | `cluster/kubeadm-config.yaml` |
| containerd | `containerd.io` del repositorio de Docker para RHEL | 8.2 |
| Calico (operador Tigera) | v3.32.1 | `cluster/calico-custom-resources.yaml` |
| MetalLB (chart) | 0.16.1 | 8.4 y `terraform/10-plataforma` |
| local-path-provisioner | v0.0.37 | 8.5 |
| kube-prometheus-stack (chart) | 88.6.2 | 8.8 y `terraform/10-plataforma` |
| podinfo | 6.15.0 | `apps/podinfo.yaml` |
| node_exporter (VMs) | v1.12.1 | 8.8 |
| Terraform | 1.16.x; providers `kubernetes ~> 3.4`, `helm ~> 3.3` | 8.9 |
| Argo CD | v3.5.2 | 8.11 |

Antes de instalar cada pieza, **comprueba** en sus notas de versión que sigue siendo la recomendada y anota en el
checklist la que uses de verdad. Nunca `latest`.

## Presupuesto de disco del host

📘 **Concepto.** `lab.sh vm-create` crea los discos como **qcow2 *thin***: un disco de 40 GB ocupa en el host solo los
bloques que la VM ha escrito alguna vez. Dos matices importantes:

- **Lo borrado dentro de la VM no se devuelve al host.** Las VMs del lab no tienen `discard` activado, así que un
  bloque escrito una vez sigue ocupado en el qcow2 aunque la VM borre el fichero. El máximo que puede crecer cada disco
  de datos está acotado por sus LVs (8 + 16 + 6 + 8 GB), pero en la práctica se queda muy por debajo.
- **Los snapshots internos conservan los bloques antiguos.** Desde que haces un snapshot, cada bloque que cambia ocupa
  dos veces (el viejo, para el snapshot, y el nuevo). Cuantos más snapshots y más cambios entre ellos, más crece.

*Fuente:* [qemu-img — formato qcow2](https://www.qemu.org/docs/master/system/images.html) ·
[libvirt — Domain XML, elemento `driver` (`discard`)](https://libvirt.org/formatdomain.html#hard-drives-floppy-disks-cdroms)

**Estimación para esta etapa** (orientativa: compruébala con tus medidas):

| Qué | Ocupación real aproximada en el host |
|---|---|
| 3 discos de sistema (RHEL 9 mínimo + etapas 2-5 + paquetes de Kubernetes) | 9-12 GB |
| Disco de datos de `k8s-cp01` (imágenes del plano de control, etcd) | 2-4 GB |
| Discos de datos de los workers (imágenes de todas las subetapas, Prometheus, Gitea) | 8-15 GB entre los dos |
| Snapshots (`stage5`, `cluster-vacio` y los `antes-*`) | 5-15 GB, según los cambios entre ellos |
| **Clúster completo** | **≈ 25-45 GB** |
| OpenShift Local (8.10, en tu home, `~/.crc`) | ≈ 35 GB, que se recuperan con `crc delete` |

Con ~100 GB libres caben los dos, aunque con poco margen al final. Para no tener que borrar nada que ya existe:

1. **Prometheus con retención reducida:** `kube-prometheus-stack-values.yaml` usa un PVC de 5 Gi y `retentionSize: 3GB`
   (7 días o 3 GB, lo que llegue antes). Para un lab sobra.
2. **Medir antes de cada subetapa** (abajo). **Umbral para parar: menos de 20 GB libres.**
3. **Snapshots con cabeza:** `stage5` y `cluster-vacio` se conservan; de los `antes-*`, basta el último. Si llegas al
   umbral, borra el `antes-*` anterior al crear el siguiente (`virsh snapshot-delete <nodo> <nodo>-antes-8.6`): son
   snapshots de esta etapa, nada que ya existiera.
4. **OpenShift Local al final** y solo si tras la 8.13 quedan ≥ 40 GB libres; después, `crc delete`.

🛠️ **Práctica: medir** (solo lectura, en el host, antes de la 8.2 y antes de cada subetapa):

```bash
# [host]
POOL="$(virsh pool-dumpxml lab-images | sed -n 's:.*<path>\(.*\)</path>.*:\1:p')"; echo "$POOL"
df -h "$POOL" ~
virsh vol-list lab-images --details | grep -E 'Name|k8s'
du -ch "$POOL"/k8s-* 2>/dev/null | tail -1
```

| Comando | Qué esperas |
|---|---|
| `pool-dumpxml` | La ruta del pool (por ejemplo, `/var/lib/libvirt/images/lab`) |
| `df -h "$POOL" ~` | Espacio libre del sistema de ficheros del pool y del de tu home (CRC usa `~/.crc`). Si son el mismo, salen iguales |
| `vol-list --details` | `Capacity` = tamaño virtual (20 o 40 GiB); `Allocation` = lo que ocupa de verdad |
| `du -ch` | El total real de los discos de `k8s-*` (vacío antes de crearlos) |

Anota en el checklist la ocupación tras la 8.2, la 8.8 y la 8.13: es un buen dato para dimensionar de verdad.

⚠️ **Error común en el mercado: llenar el disco del hipervisor con discos *thin*.** Se crean VMs con discos *thin*
"porque no ocupan" y se sobreasigna el almacenamiento (la suma de tamaños virtuales supera el disco real) sin vigilarlo:
el día que las VMs escriben, el disco del hipervisor se llena y **todas** las VMs se pausan a la vez (`virsh list`
muestra `paused`, error `I/O error`). **Cómo evitarlo:** medir la ocupación real, umbrales de alerta en el hipervisor y
no confiar en el tamaño virtual.

## Orden de trabajo y snapshots

La numeración va de 8.1 a 8.13, pero **OpenShift Local (8.10) se hace al final**: exige el clúster apagado y
`crc setup` toca el host.

| # | Subetapa | 📸 Snapshot (con los nodos **apagados**) |
|---|---|---|
| 1 | 8.1 Podman | — (vale `ansible01-stage7-complete`) |
| 2 | 8.2 kubeadm | `*-stage5-complete` antes; `*-cluster-vacio` al terminar |
| 3-5 | 8.3 Objetos · 8.4 Red · 8.5 Almacenamiento | |
| 6 | 8.6 Seguridad | `*-antes-8.6` |
| 7-8 | 8.7 Helm · 8.8 Prometheus/Grafana | `*-antes-8.9` al terminar la 8.8 |
| 9 | 8.9 Terraform | |
| 10 | 8.11 CI y GitOps | `*-antes-8.12` + copia de etcd |
| 11-12 | 8.12 Operación · 8.13 Ansible | |
| 13 | 8.10 OpenShift Local | |

Un snapshot de un clúster encendido no es consistente (etcd escribiendo a mitad): el procedimiento está en el paso
8.2.7. Si vas justo de tiempo, prioriza 8.2, 8.3, 8.4, 8.8 y 8.9: es lo que más aparece en las ofertas.

## Reglas de la etapa

1. Cada paso: hacer → comprobar → anotar en el checklist el resultado **obtenido**.
2. **El host no se toca**, salvo en la 8.10 y con revisión previa de solo lectura.
3. **Nombres completos** de imagen (`registro/ruta:etiqueta`), nunca nombres cortos ni `latest`.
4. **Antes de aplicar, simula:** `kubectl apply --dry-run=server`, `helm template`, `terraform plan`.
5. **Ningún secreto en el repo:** contraseñas, `kubeconfig`, claves privadas y `tfstate` se quedan en las VMs.

---

## 8.1 Contenedores con Podman

> 🎫 **Ticket PLAT-801.** "Antes de pedir un clúster, el equipo de desarrollo quiere ver su aplicación en un contenedor
> en un servidor RHEL: que corra sin root, que lea datos del disco con SELinux activo y que arranque sola si el
> servidor se reinicia."

**Dónde:** `ansible01`, como `adminlab`. **Vuelta atrás:** cada tema tiene la suya; si todo falla,
`scripts/lab.sh snapshot revert ansible01 7`.

| Tema | Estado |
|---|---|
| 8.1.1 Instalar Podman | ✅ 2026-10-29 |
| 8.1.2 Contenedor = proceso aislado | ✅ 2026-10-29 |
| 8.1.3 Imágenes y capas | ✅ 2026-10-30 |
| 8.1.4 Volúmenes y SELinux | ✅ 2026-10-30 |
| 8.1.5 Pods y YAML de Kubernetes | ⏳ |
| 8.1.6 Servicio systemd con Quadlet | ⏳ |

### 8.1.1 Instalar Podman en RHEL 9

📘 **Concepto.** Un **contenedor** es un proceso (o un grupo de procesos) que el kernel aísla con *namespaces* (qué ve:
PIDs, red, montajes, usuarios) y limita con *cgroups* (cuánto usa: CPU, memoria). La **imagen** es el sistema de ficheros
y la configuración de arranque de ese proceso, empaquetados por capas. Podman es el motor de contenedores de RHEL:
**sin demonio** (cada `podman run` es un proceso hijo tuyo, no de un servicio central como `dockerd`) y **rootless**
(un usuario normal ejecuta contenedores sin `sudo`). En RHEL 9 se instala con el metapaquete `container-tools`
(podman, buildah, skopeo) desde AppStream; en RHEL 8 era un módulo.

*Fuente:* [Red Hat — Building, running, and managing containers (RHEL 9)](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/building_running_and_managing_containers/index) ·
[Podman — documentación](https://docs.podman.io/en/latest/)

🛠️ **Práctica.** El kickstart del lab es mínimo: Podman no viene instalado (`podman: command not found`).

```bash
# [ansible01 · adminlab]
sudo subscription-manager repos --list-enabled | grep 'Repo ID'
dnf info podman container-tools 2>&1 | grep -E '^(Name|Version|Release|Repository)|Error|error'
sudo dnf install -y container-tools
podman --version
podman info --format '{{.Host.Security.Rootless}} {{.Host.NetworkBackend}} {{.Store.GraphRoot}}'
grep adminlab /etc/subuid /etc/subgid
getenforce
```

| Comando | Qué esperas | Si sale otra cosa |
|---|---|---|
| `repos --list-enabled` | `rhel-9-for-x86_64-baseos-rpms` y `...-appstream-rpms` | Vacío → la suscripción no da repos |
| `dnf info` (descarga metadatos: prueba que el certificado es válido) | `podman` y `container-tools` en `rhel-9-for-x86_64-appstream-rpms` | `Failed to download metadata` / `403` → certificado caducado |
| `dnf install -y container-tools` | `Complete!` | — |
| `podman info --format` | `true netavark /home/adminlab/.local/share/containers/storage`: rootless, backend de red actual, imágenes en tu home | `false` → estás como root |
| `grep /etc/subuid /etc/subgid` | `adminlab:100000:65536` en los dos | Sin línea → rootless falla con `cannot find mappings` |
| `getenforce` | `Enforcing` | Otra cosa → el tema 8.1.4 no tiene sentido |

> ✅ **Resultado real (2026-10-29):** `container-tools-1-15.el9`, `podman-5.8.2-8.el9_8` (build de RHEL 9.8, la misma
> versión menor que `ansible01`); `true netavark /home/adminlab/.local/share/containers/storage`;
> `adminlab:100000:65536`.

⚠️ **Error común en el mercado: instalar "la última versión" desde fuera de la distribución.** Se descarga un binario
estático de GitHub o se añade un repositorio de terceros para tener la última Podman o Docker. El resultado es una
versión que Red Hat no ha probado con ese kernel, ese `container-selinux` y ese `crun`, sin soporte y que el siguiente
`dnf update` puede romper. **Cómo evitarlo:** la versión de AppStream de tu versión menor; si necesitas algo más nuevo,
se sube la versión menor de RHEL.

### 8.1.2 Un contenedor es un proceso aislado, no una máquina

📘 **Concepto.** `podman run` descarga la imagen si no la tiene, crea el contenedor y ejecuta su proceso principal. Ese
proceso tiene **PID 1 dentro** de su espacio de PIDs, pero en el host es un proceso más. En modo rootless, el usuario 0
del contenedor es **tu propio usuario** en el host, y el resto de UIDs se mapean al rango subordinado de
`/etc/subuid` (*user namespaces*): aunque el proceso "sea root" dentro, fuera no tiene privilegios. `-p host:contenedor`
publica un puerto.

*Fuente:* [podman-run(1)](https://docs.podman.io/en/latest/markdown/podman-run.1.html) ·
[podman-top(1)](https://docs.podman.io/en/latest/markdown/podman-top.1.html) ·
[Rootless (tutorial oficial)](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
timeout 30 skopeo inspect docker://ghcr.io/stefanprodan/podinfo:6.15.0 | grep -E '"(Digest|Created)"'
podman run -d --name web -p 8080:9898 ghcr.io/stefanprodan/podinfo:6.15.0
curl -s localhost:8080 | head -5
podman ps
podman exec web ps
ps -ef | grep [p]odinfo
podman top web user huser pid hpid
podman rm -f web
```

| Comando | Qué esperas | Qué demuestra |
|---|---|---|
| `skopeo inspect` | Un `"Digest": "sha256:..."` (lee el registro **sin descargar**) | Que la versión fijada existe. `manifest unknown` → no existe |
| `podman run -d -p 8080:9898` | Capas descargándose y un ID | `address already in use` → algo usa el 8080 |
| `curl localhost:8080` | JSON con `"version": "6.15.0"` | — |
| `podman exec web ps` | podinfo con PID 1 | Espacio de PIDs propio |
| `ps -ef \| grep [p]odinfo` | `podinfo` como proceso del host, con un UID grande (100000+) | Desde fuera es un proceso normal |
| `podman top ... user huser pid hpid` | Usuario dentro y su UID en el host; PID dentro y fuera | El mapeo de `/etc/subuid` |

⚠️ **Error común en el mercado: tratar el contenedor como una VM.** Se entra con `exec` a "arreglar" cosas (instalar
paquetes, editar ficheros) en un contenedor en marcha. Al recrearlo, todo se pierde, y nadie sabe qué cambió. **Cómo
evitarlo:** el contenedor es desechable; cualquier cambio va a la imagen (`Containerfile`) o a la configuración
(variables, volúmenes), y se recrea.

### 8.1.3 Imágenes propias y capas

📘 **Concepto.** Un `Containerfile` (mismo formato que un `Dockerfile`) describe cómo construir una imagen. `FROM` fija
la base; `COPY` y `RUN` crean **capas**; `USER`, `CMD`, `LABEL` y `ENV` solo son **metadatos**. Las capas son
**copy-on-write**: una capa que solo cambia los permisos de un fichero guarda el fichero entero otra vez. El último
argumento de `podman build` es el **contexto**: el directorio cuyo contenido se envía al build y del que salen los
`COPY`. Las imágenes construidas en local se llaman `localhost/<nombre>`; un nombre **corto** (sin registro) se busca
en los `unqualified-search-registries` de `/etc/containers/registries.conf`.

*Fuente:* [podman-build(1)](https://docs.podman.io/en/latest/markdown/podman-build.1.html) ·
[Containerfile(5)](https://github.com/containers/common/blob/main/docs/Containerfile.5.md) ·
[containers-registries.conf(5)](https://github.com/containers/image/blob/main/docs/containers-registries.conf.5.md)

🛠️ **Práctica.** Cada imagen en su propio directorio (el contexto) y con nombre completo.

```bash
# [ansible01 · adminlab]
skopeo list-tags docker://registry.access.redhat.com/ubi9/ubi-minimal | grep -E '"9\.[0-9]+"' | tail -3
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
  while true; do saludar; sleep 30; done   # modo servicio (8.1.6)
else
  saludar                                  # modo una sola vez
fi
EOF
cat > Containerfile <<'EOF'
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.8
LABEL description="Etapa 8.1 - imagen de prueba" maintainer="adminlab"
COPY saludo.sh /usr/local/bin/saludo.sh
RUN chmod 0755 /usr/local/bin/saludo.sh
USER 1001
CMD ["/usr/local/bin/saludo.sh"]
EOF
ls -la
podman build -t localhost/lab/saludo:1.0 .
podman run --rm localhost/lab/saludo:1.0
podman image inspect localhost/lab/saludo:1.0 --format 'User={{.Config.User}}  Cmd={{.Config.Cmd}}  Capas={{len .RootFS.Layers}}'
podman history localhost/lab/saludo:1.0 | head -6
podman images localhost/lab/saludo
```

| Comando | Qué esperas | Si sale otra cosa |
|---|---|---|
| `skopeo list-tags` | Etiquetas `"9.6"`, `"9.7"`, `"9.8"`: usa la más alta en el `FROM` | — |
| `pwd` | `/home/adminlab/podman-lab/saludo` **antes** de los `cat >` | Otro directorio → los ficheros acaban en otro sitio |
| `ls -la` | `Containerfile` y `saludo.sh`, con más de 0 bytes | — |
| `podman build ... .` | `STEP 1/6`...`STEP 6/6`, `Successfully tagged localhost/lab/saludo:1.0` | Se para en `COPY` → el fichero no está en el contexto |
| `podman run --rm` | `... Hola desde <id> (uid=1001)` | `Trying to pull registry.access.redhat.com/lab/saludo` → la imagen no existe en local |

> ✅ **Resultado real (2026-10-30):** `User=1001  Cmd=[/usr/local/bin/saludo.sh]`, `Capas=3`; en `history`, `COPY` y
> `RUN chmod` con `3.58kB` cada uno, y `USER`, `CMD` y `LABEL` con `0B`; `localhost/lab/saludo 1.0 38202e4c3e82 109 MB`.
>
> **Primer intento fallido** (caso etapa8/01, pendiente de documentar): el `Containerfile` se creó en `~` y el script
> en `~/podman-lab/saludo`. El build desde `~` se paró en el `COPY` y dejó una imagen intermedia `<none>` con
> `User=` vacío y `Cmd=[/bin/bash]`; después, `podman run lab/saludo:1.0` intentó descargarla de
> `registry.access.redhat.com`, `registry.redhat.io` y `docker.io`.

Cómo leer las capas: `Capas=3` = UBI (sus capas vienen aplanadas en una) + `COPY` + `RUN`. El `RUN chmod` ocupa lo
mismo que el `COPY` porque, con copy-on-write, cambiar los permisos guarda el fichero entero otra vez. La forma
correcta es `COPY --chmod=0755 saludo.sh /usr/local/bin/`. Los 109 MB son la imagen completa, pero en disco solo
añade unos 7 kB: la capa de UBI se **comparte**.

⚠️ **Error común en el mercado: secretos dentro de la imagen.** Se construye desde un directorio con todo
(`podman build .` en el home o en la raíz de un repo) o se hace `COPY . .`, y en la imagen acaban claves SSH, `.env`
con contraseñas o el `.git`. Además, un `RUN rm secreto` en una capa posterior **no** lo borra: sigue en la capa
anterior y cualquiera que descargue la imagen lo extrae. **Cómo evitarlo:** un directorio por imagen, un
`.containerignore`, `COPY` de ficheros concretos, y los secretos en tiempo de ejecución (variables, Secrets de
Kubernetes), nunca en el build.

### 8.1.4 Volúmenes y SELinux

📘 **Concepto.** Con SELinux en *enforcing*, los procesos de los contenedores corren con el tipo **`container_t`** y
solo pueden acceder a ficheros con tipos permitidos (`container_file_t`). Un directorio del home es `user_home_t`: el
contenedor no lo puede leer **aunque los permisos Unix lo permitan**. Las opciones de volumen `:z` y `:Z` piden a
Podman que **reetiquete** el contenido: `:z` con una etiqueta compartida por todos los contenedores; `:Z` con una
etiqueta **privada** de ese contenedor, con categorías MCS únicas (`s0:c87,c584`), de forma que otro contenedor no
pueda leerlo.

*Fuente:* [podman-run(1), opción `--volume` (apartado "Labeling Volume Mounts")](https://docs.podman.io/en/latest/markdown/podman-run.1.html) ·
[Red Hat — Using SELinux (RHEL 9)](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/using_selinux/index)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
mkdir -p ~/datos && echo "hola desde el host" > ~/datos/hola.txt
ls -laZ ~/datos
podman run --rm -v ~/datos:/datos registry.access.redhat.com/ubi9/ubi-minimal:9.8 cat /datos/hola.txt
sudo timeout 20 ausearch -m avc -ts recent | grep denied | tail -2
podman run --rm -v ~/datos:/datos:Z registry.access.redhat.com/ubi9/ubi-minimal:9.8 cat /datos/hola.txt
ls -laZ ~/datos
```

| Paso | Qué esperas | Qué demuestra |
|---|---|---|
| `ls -laZ` (antes) | `adminlab`, `unconfined_u:object_r:user_home_t:s0` | — |
| Sin `:Z` | `cat: /datos/hola.txt: Permission denied` | Los permisos Unix están bien; algo más bloquea |
| `ausearch -m avc` | `avc: denied { read } ... scontext=...container_t... tcontext=...user_home_t` | Es SELinux. `timeout` por el caso [etapa2/06](../troubleshooting/etapa2/06-ausearch-colgado-timeout.md) |
| Con `:Z` | `hola desde el host` | — |
| `ls -laZ` (después) | `system_u:object_r:container_file_t:s0:cX,cY` | Podman reetiquetó el directorio |

> ✅ **Resultado real (2026-10-30):** `hola desde el host`; `~/datos` y `hola.txt` en
> `system_u:object_r:container_file_t:s0:c87,c584`; el home (`..`) sigue en `user_home_dir_t`. Los permisos Unix
> (`adminlab`, 644) no cambiaron.

Un segundo `Permission denied` distinto, por permisos Unix: la imagen `saludo` corre como UID 1001, que en el host es
100000 + 1000 = **101000**, y ese UID no es dueño de `~/datos`. `podman unshare chown 1001:1001 ~/datos` lo arregla
(dentro de `unshare` los UIDs son los del contenedor); `ls -ln ~/datos` muestra `101000`. Se deshace con
`podman unshare chown 0:0 ~/datos`.

⚠️ **Error común en el mercado: `setenforce 0` "para que funcione".** Ante el primer `Permission denied` de un
contenedor, se desactiva SELinux en el servidor (o se pone `SELINUX=disabled`) y se deja así para siempre: todo el
servidor pierde una capa de seguridad por un volumen mal etiquetado. El error "contrario" es igual de grave: `:Z` sobre
`/home`, `/etc` o `/var`, que reetiqueta todo y puede dejar el servidor sin login. **Cómo evitarlo:** leer el AVC
(`ausearch`), usar `:Z` solo en directorios dedicados y, para rutas fijas, una regla persistente con
`semanage fcontext` + `restorecon`.

### 8.1.5 Pods: contenedores que comparten red

📘 **Concepto.** Un **pod** es un grupo de contenedores que comparten espacios de nombres, sobre todo la **red**: misma
IP, mismos puertos, y se hablan por `localhost`. Un contenedor especial, el **infra** (en Kubernetes, *pause*), mantiene
vivos esos espacios aunque los demás se reinicien. Es la unidad mínima de Kubernetes, y Podman la reproduce en local:
`podman kube generate` escribe el **YAML de Kubernetes** de un pod de Podman y `podman kube play` hace lo contrario.

*Fuente:* [podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html) ·
[podman-kube-generate(1)](https://docs.podman.io/en/latest/markdown/podman-kube-generate.1.html) ·
[Kubernetes — Pods](https://kubernetes.io/docs/concepts/workloads/pods/)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
podman pod create --name saludo-pod -p 8081:9898
podman run -d --pod saludo-pod --name web ghcr.io/stefanprodan/podinfo:6.15.0
podman run -d --pod saludo-pod --name cliente registry.access.redhat.com/ubi9/ubi-minimal:9.8 \
  bash -c 'while true; do curl -s localhost:9898/version; echo; sleep 10; done'
podman ps --pod
podman logs cliente | tail -2
curl -s localhost:8081/version
podman kube generate saludo-pod > ~/podman-lab/saludo-pod.yaml
grep -E 'apiVersion|kind|- name|image:' ~/podman-lab/saludo-pod.yaml
podman pod rm -f saludo-pod
podman kube play ~/podman-lab/saludo-pod.yaml
podman pod ps
podman kube down ~/podman-lab/saludo-pod.yaml
```

| Paso | Qué esperas | Qué demuestra |
|---|---|---|
| `pod create -p 8081:9898` | El ID del pod | El puerto se publica en el **pod**, no en cada contenedor |
| `podman ps --pod` | **Tres** contenedores: `web`, `cliente` y `xxxx-infra` | El infra mantiene los espacios compartidos |
| `logs cliente` | JSON con `"version": "6.15.0"` | `cliente` llega a `web` por `localhost` |
| `kube generate` + `grep` | `apiVersion: v1`, `kind: Pod`, `web` y `cliente` con sus imágenes | El mismo objeto que usa Kubernetes |
| `kube play` / `pod ps` | El pod recreado, `Running` | Del YAML a contenedores |

Si `podman run --name web` dice `name "web" is already in use`, queda el del 8.1.2: `podman rm -f web`. Guarda
`saludo-pod.yaml`: en la 8.3 lo comparas con un Deployment.

⚠️ **Error común en el mercado: meter varias aplicaciones en un mismo pod.** Se ponen la aplicación y su base de datos
(o dos servicios) en el mismo pod "porque se hablan". Ya no se pueden escalar, actualizar ni reiniciar por separado, y
si uno falla se lleva al otro. **Cómo evitarlo:** un pod = una aplicación; solo comparten pod los contenedores
*auxiliares* de esa aplicación (un *sidecar* de logs o un proxy).

### 8.1.6 Que el contenedor arranque con el servidor: Quadlet

📘 **Concepto.** Sin orquestador, quien arranca un contenedor al iniciar el servidor es **systemd**. **Quadlet** es un
generador de systemd que viene con Podman: lee ficheros declarativos `.container` (en `~/.config/containers/systemd/`
para usuarios) y genera las unidades `.service` en cada `daemon-reload`. Las unidades generadas no se habilitan con
`systemctl enable`: las activa la sección `[Install]`. Para que los servicios de usuario arranquen sin que el usuario
inicie sesión, hace falta **linger** (`loginctl enable-linger`).

*Fuente:* [podman-systemd.unit(5) — Quadlet](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html) ·
[loginctl(1)](https://www.freedesktop.org/software/systemd/man/latest/loginctl.html)

🛠️ **Práctica.**

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
/usr/libexec/podman/quadlet -dryrun -user
systemctl --user daemon-reload
systemctl --user start saludo
systemctl --user status saludo --no-pager
journalctl --user -u saludo -n 5 --no-pager
loginctl show-user adminlab -p Linger
sudo loginctl enable-linger adminlab
loginctl show-user adminlab -p Linger
sudo reboot
```

```bash
# [host]  (espera ~30 s)
ssh adminlab@ansible01
# [ansible01 · adminlab]
podman ps
journalctl --user -u saludo -n 3 --no-pager
```

| Paso | Qué esperas | Si sale otra cosa |
|---|---|---|
| `quadlet -dryrun -user` | El `.service` generado, con `ExecStart=/usr/bin/podman run ... localhost/lab/saludo:1.0 /usr/local/bin/saludo.sh --bucle` | Un error de sintaxis sale aquí y no se genera nada |
| `start saludo` + `status` | `active (running)` | `Unit saludo.service not found` → el generador no la creó |
| `journalctl` | Una línea de saludo cada 30 s | — |
| `Linger` | Primero el valor previo (anótalo); después `Linger=yes` | — |
| Tras el reboot, `podman ps` | `saludo` en `Up` sin hacer nada | Sin linger, no arranca hasta que entras |

**Vuelta atrás:** `systemctl --user stop saludo`, `rm ~/.config/containers/systemd/saludo.container`,
`systemctl --user daemon-reload` y, si antes era `no`, `sudo loginctl disable-linger adminlab`.

**Comparación entre versiones (opcional, sin tocar nada):** desde el proyecto de la Etapa 7,
`cd ~/ansible-lab && ansible app -m command -a 'rpm -q podman' -o` (un `rc=1` es "no instalado") y
`ansible app -m command -a 'stat -fc %T /sys/fs/cgroup' -o` (`cgroup2fs` = cgroup v2, `tmpfs` = v1). Kubernetes
reciente exige cgroup v2. Anota lo medido en la sección "Diferencias RHEL 7/8/9/10".

⚠️ **Error común en el mercado: contenedores "de producción" lanzados a mano.** Un `podman run -d` (o `docker run`)
desde una sesión SSH, sin unidad de systemd ni política de reinicio: funciona hasta el primer reinicio del servidor
por parches, y entonces el servicio no vuelve y nadie sabe con qué parámetros se lanzó. **Cómo evitarlo:** Quadlet (o
un orquestador) con la configuración en un fichero versionado.

**Lo que aporta Kubernetes que Podman + systemd no tiene:** varios nodos, reprogramación automática si un nodo cae,
Services con balanceo, escalado declarativo (`replicas: 3`) y actualizaciones progresivas. Es la 8.2.

**Checklist:** filas 1-4.

---

## 8.2 Clúster con kubeadm

> 🎫 **Ticket PLAT-802.** "Necesitamos un clúster Kubernetes *on-premise* sobre RHEL 9 para los equipos de desarrollo:
> un nodo de control y dos workers, con SELinux y firewall activos (lo exige Seguridad), versiones fijadas y que se
> pueda administrar desde la estación de control, no desde los nodos."

**Dónde:** el host (VMs), los tres nodos como root y `ansible01`. **Vuelta atrás:** snapshot `*-stage5-complete`
(8.2.1) y `*-cluster-vacio` (8.2.7); en un nodo concreto, `kubeadm reset -f`.

### 8.2.0 Cómo está hecho un clúster

📘 **Concepto.** Un clúster tiene un **plano de control** y **nodos**:

| Componente | Dónde | Qué hace |
|---|---|---|
| `kube-apiserver` | Plano de control | La única puerta: todo (kubectl, kubelets, controladores) pasa por la API, que valida, autoriza y guarda |
| `etcd` | Plano de control | Base de datos clave-valor con **todo** el estado del clúster |
| `kube-scheduler` | Plano de control | Decide en qué nodo va cada pod nuevo, según recursos, afinidades y *taints* |
| `kube-controller-manager` | Plano de control | Los bucles de control: comparan estado deseado y real y corrigen (ReplicaSets, nodos, endpoints...) |
| `kubelet` | Cada nodo | Arranca y vigila los pods asignados a su nodo, a través del runtime |
| Runtime (containerd) | Cada nodo | Descarga imágenes y ejecuta contenedores (interfaz CRI) |
| `kube-proxy` | Cada nodo | Programa las reglas que hacen funcionar los Services |
| CNI (Calico) | Cada nodo | Da IP a los pods y los conecta entre nodos |

`kubeadm` es la herramienta oficial para **arrancar** un clúster con buenas prácticas (`init`, `join`, `upgrade`); no
instala la red de pods ni nada más.

*Fuente:* [Kubernetes Components](https://kubernetes.io/docs/concepts/overview/components/) ·
[Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)

### 8.2.1 Las VMs, con la base del lab

📘 **Concepto.** kubeadm pide, en cada máquina: un Linux compatible, 2 GB de RAM y 2 CPU, conectividad completa entre
nodos, **hostname, MAC y `product_uuid` únicos**, ciertos puertos abiertos y swap desactivada (o configurada). Además,
los certificados del clúster exigen **hora sincronizada**. Los nodos del lab salen de `lab.sh` (kickstart con IP fija,
`hostname` y UUID propios) y pasan por las etapas 2-5: usuarios y LVM, red con DNS de `dns01`, chrony, y SELinux.

*Fuente:* [Installing kubeadm — Before you begin](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#before-you-begin)

🛠️ **Práctica.**

```bash
# [host]
free -h; df -h "$(virsh pool-dumpxml lab-images | sed -n 's:.*<path>\(.*\)</path>.*:\1:p')"
grep '^k8s' scripts/hosts.conf
scripts/lab.sh vm-create k8s-cp01
scripts/lab.sh vm-create k8s-w01
scripts/lab.sh vm-create k8s-w02
scripts/lab.sh status
for h in k8s-cp01 k8s-w01 k8s-w02; do scripts/lab.sh register "$h" TU_USUARIO_DE_RED_HAT; done
scripts/lab.sh stage4-dns
for h in k8s-cp01 k8s-w01 k8s-w02; do
  scripts/lab.sh stage2 "$h" && scripts/lab.sh stage3 "$h" --lab-dns && \
  scripts/lab.sh stage4-clients "$h" && scripts/lab.sh stage5 "$h"
done
for h in k8s-cp01 k8s-w01 k8s-w02; do scripts/lab.sh test all "$h"; done
dig +short k8s-api.lab.local @10.10.10.20
for h in k8s-cp01 k8s-w01 k8s-w02; do scripts/lab.sh snapshot create "$h" 5; done
```

| Paso | Qué esperas | Si sale otra cosa |
|---|---|---|
| `free` / `df` | ≥ 19 GiB disponibles; ≥ 60 GB libres en el pool `lab-images` | RAM: apaga las `app01` que no uses. Disco: ver [Presupuesto de disco](#presupuesto-de-disco-del-host) |
| `grep '^k8s'` | 3 líneas: RHEL 9, `.100/.101/.102`, 4096/5120 MB, discos 20 y 40, `opcional` | — |
| `vm-create` | La VM instalada y encendida (pide la contraseña de `adminlab` una vez) | `virsh console k8s-cp01` para ver la instalación (`Ctrl+]` para salir) |
| `status` | Las tres con `SSH OK` | — |
| `register` | Cambia `TU_USUARIO_DE_RED_HAT` por tu usuario; la contraseña se pide en la VM | — |
| `stage2`...`stage5` | Cada etapa termina sin errores | Arréglalo **ahora**: después no sabrás de dónde viene |
| `test all` | 0 FAIL en los tres | — |
| `dig` | `10.10.10.100` | — |
| `snapshot create ... 5` | `<nodo>-stage5-complete` en los tres | — |

⚠️ **Error común en el mercado: relojes desincronizados.** Nodos sin NTP (o con NTP bloqueado por el firewall) que se
desfasan unos minutos: aparecen errores `x509: certificate has expired or is not yet valid` al unir un nodo, tokens
rechazados y etcd inestable, y se pierde mucho tiempo buscando en la red o en los certificados. **Cómo evitarlo:**
chrony en todos los nodos contra la misma fuente (aquí `dns01`, Etapa 4) y comprobarlo con `chronyc tracking` antes de
instalar nada.

### 8.2.2 Preparar cada nodo

Hazlo **completo en `k8s-cp01`** primero, entendiendo cada bloque, y después repítelo en los workers. Diferencias entre
nodos: solo los puertos de firewalld (apartado e).

```bash
# [host]
ssh adminlab@k8s-cp01
# [k8s-cp01]
sudo -i
```

#### a. Almacenamiento propio

📘 **Concepto.** Lo que más crece en un nodo es `/var/lib/containerd` (imágenes y capas), `/var/lib/kubelet` (volúmenes
`emptyDir`, datos de los pods) y los volúmenes persistentes locales. El kubelet vigila el espacio de dos sistemas de
ficheros, **nodefs** (el de `/var/lib/kubelet`) e **imagefs** (el del runtime), y cuando bajan de un umbral
(*eviction thresholds*) marca `DiskPressure` y **desaloja pods**. Separarlos en LVs propios evita que una imagen grande
llene `/var` y tumbe el sistema operativo.

*Fuente:* [Node-pressure Eviction](https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/)

🛠️ **Práctica.**

```bash
# [nodos · root]
vgs vg_data
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

| Paso | Qué esperas | Si sale otra cosa |
|---|---|---|
| `vgs vg_data` | ~40 GiB con ≥ 30 GiB en `VFree` | Menos → los tres LVs no caben: **para** |
| `lvcreate` | `Logical volume "lv_..." created.` | `Insufficient free space` |
| `cp -a /etc/fstab ...` | Copia de seguridad antes de tocarlo | — |
| `findmnt --verify` | `Success, no errors or warnings detected` | Un error aquí es el modo emergencia en el próximo arranque (caso [etapa2/02](../troubleshooting/etapa2/02-bad-fstab.md)): restaura la copia |
| `df -h` | 16G, 6G y 8G montados | `mount point does not exist` → falta un `mkdir` |

⚠️ **Error común en el mercado: nodos con todo en `/` o en `/var`.** Las imágenes que nadie limpia y los logs de los
pods llenan el disco del sistema; el kubelet empieza a desalojar pods en cascada y, si `/var` llega al 100 %, el nodo
deja de responder (journald, rpm y el propio kubelet fallan). **Cómo evitarlo:** sistemas de ficheros separados para
el runtime y el kubelet, límites de logs (`containerLogMaxSize`) y alertas de disco (E10 de la 8.8).

#### b. Swap

📘 **Concepto.** Por defecto, el kubelet **no arranca** si hay swap activa (`failSwapOn: true`). El scheduler reparte
pods según la memoria que piden; con swap, un nodo sobrecargado seguiría aceptando trabajo degradándose en silencio.
Las versiones recientes admiten swap de forma controlada (`NodeSwap`, `memorySwap.swapBehavior`), pero hay que
configurarlo a propósito.

*Fuente:* [Swap memory management](https://kubernetes.io/docs/concepts/cluster-administration/swap-memory-management/)

🛠️ **Práctica.**

```bash
# [nodos · root]
swapon --show
swapoff -a
sed -i.antes-swap '/lv_swap/ s/^/#/' /etc/fstab
grep -n lv_swap /etc/fstab
systemctl daemon-reload && swapon --show
```

Lo esperado: primero el `lv_swap` de 2G; después, la línea de `fstab` empieza por `#` y `swapon --show` sale vacío.

⚠️ **Error común en el mercado: `swapoff -a` sin tocar `fstab`.** El clúster funciona... hasta el primer reinicio del
nodo: la swap vuelve, el kubelet no arranca y el nodo queda `NotReady` en mitad de una ventana de parches. **Cómo
evitarlo:** cambiar siempre el estado actual **y** el persistente, y comprobarlo reiniciando un nodo antes de dar el
trabajo por terminado.

#### c. Módulos del kernel y sysctl

📘 **Concepto.** `overlay` es el sistema de ficheros de las capas de las imágenes. `br_netfilter` hace que el tráfico
que cruza un *bridge* pase por iptables/nftables, que es donde kube-proxy y el CNI ponen sus reglas. `ip_forward = 1`
convierte el nodo en un **router** entre la red del lab y la de pods. Todo debe persistir tras un reinicio
(`/etc/modules-load.d/`, `/etc/sysctl.d/`).

*Fuente:* [Container Runtimes — Network configuration](https://kubernetes.io/docs/setup/production-environment/container-runtimes/#prerequisite-ipv4-forwarding-optional)

🛠️ **Práctica.**

```bash
# [nodos · root]
cat > /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay && modprobe br_netfilter
cat > /etc/sysctl.d/90-k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system | grep -E 'bridge-nf-call-iptables|ip_forward'
```

Lo esperado: las tres claves con `= 1`. `cannot stat /proc/sys/net/bridge/...` → falta cargar `br_netfilter`.

⚠️ **Error común en el mercado: `ip_forward` desactivado por un endurecimiento posterior.** Un perfil de seguridad
(CIS, un playbook de hardening) pone `net.ipv4.ip_forward = 0` en todos los servidores, incluidos los nodos: los pods
dejan de verse entre nodos y los Services de fuera dejan de responder, sin que nadie relacione el cambio con la
avería. **Cómo evitarlo:** los nodos de Kubernetes con su propio perfil de hardening, y comprobar `sysctl
net.ipv4.ip_forward` en el diagnóstico de red.

#### d. NetworkManager y las interfaces de Calico

📘 **Concepto.** Calico crea una interfaz `cali*` por pod y otras de túnel (`vxlan.calico`, `tunl0`). Si NetworkManager
intenta gestionarlas, puede cambiarlas o borrar sus rutas. La documentación de Calico pide declararlas `unmanaged`.

*Fuente:* [Calico — Troubleshooting: Configure NetworkManager](https://docs.tigera.io/calico/latest/operations/troubleshoot/troubleshooting#configure-networkmanager)

🛠️ **Práctica.**

```bash
# [nodos · root]
cat > /etc/NetworkManager/conf.d/calico.conf <<'EOF'
[keyfile]
unmanaged-devices=interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico;interface-name:vxlan-v6.calico;interface-name:wireguard.cali;interface-name:wg-v6.cali
EOF
systemctl reload NetworkManager
nmcli general status
```

Lo esperado: `connected`, y tu sesión SSH no se corta.

⚠️ **Error común en el mercado: pods que pierden la red "a ratos".** Sin esta configuración, los fallos son
intermitentes (al crear o borrar pods, al reiniciar NetworkManager) y casi imposibles de reproducir; se acaba
culpando a la aplicación. **Cómo evitarlo:** aplicar los requisitos del CNI **antes** de instalarlo, no cuando
aparecen los síntomas.

#### e. firewalld: una zona `k8s`

📘 **Concepto.** firewalld asigna cada paquete a una **zona** por su interfaz o por su **origen**; los orígenes tienen
prioridad. Una zona `k8s` con los orígenes del lab (`10.10.10.0/24`), de los pods (`10.244.0.0/16`) y de los
Services (`10.96.0.0/12`) permite abrir los puertos de Kubernetes solo a esas redes, sin apagar el firewall. La
documentación de Kubernetes lista los puertos de cada tipo de nodo.

*Fuente:* [Ports and Protocols](https://kubernetes.io/docs/reference/networking/ports-and-protocols/) ·
[firewalld — Zones](https://firewalld.org/documentation/zone/) ·
[Calico — Network requirements](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements#network-requirements)

> ⚠️ Al poner `10.10.10.0/24` como origen de la zona `k8s`, el SSH que llega del host deja de pasar por `public`. Si
> `k8s` no permite `ssh`, la sesión se corta en el `--reload`. Mantén **dos** sesiones abiertas.

🛠️ **Práctica.**

```bash
# [nodos · root]
firewall-cmd --zone=public --list-services
firewall-cmd --permanent --new-zone=k8s
for src in 10.10.10.0/24 10.244.0.0/16 10.96.0.0/12; do firewall-cmd --permanent --zone=k8s --add-source=$src; done
firewall-cmd --permanent --zone=k8s --add-service=ssh
firewall-cmd --permanent --zone=k8s --add-port={10250/tcp,10249/tcp,9100/tcp,4789/udp,5473/tcp,7946/tcp,7946/udp,9091/tcp}
```

```bash
# [k8s-cp01 · root]  API, etcd y métricas del plano de control
firewall-cmd --permanent --zone=k8s --add-port={6443/tcp,2379-2380/tcp,2381/tcp,10257/tcp,10259/tcp}
```

```bash
# [workers · root]  NodePort
firewall-cmd --permanent --zone=k8s --add-port=30000-32767/tcp
```

```bash
# [nodos · root]
firewall-cmd --reload
firewall-cmd --get-active-zones
firewall-cmd --zone=k8s --list-all
```

```bash
# [host]  en otra terminal, antes de cerrar nada
ssh adminlab@k8s-cp01 hostname
```

| Paso | Qué esperas | Si sale otra cosa |
|---|---|---|
| `--zone=public --list-services` | `cockpit dhcpv6-client ssh` (más lo de las Etapas 4-5) | Lo que salga distinto de esos tres, añádelo también a `k8s` |
| `--get-active-zones` | `k8s` con los tres orígenes y `public` con la interfaz | Sin `k8s` → repite con `--permanent` y `--reload` |
| `ssh ... hostname` | El nombre del nodo | Falla → en la sesión abierta: `firewall-cmd --zone=k8s --add-service=ssh` |

| Puerto | Para qué |
|---|---|
| 6443 | API de Kubernetes |
| 2379-2380 / 2381 | etcd (clientes y pares) / métricas de etcd |
| 10250 | API del kubelet (logs, exec, métricas) |
| 10257 / 10259 / 10249 | Métricas de controller-manager / scheduler / kube-proxy |
| 4789/udp, 5473 | VXLAN de Calico, Typha |
| 7946 tcp+udp | memberlist de MetalLB |
| 9100, 9091 | node-exporter, métricas de Calico |
| 30000-32767 | NodePort (workers) |

⚠️ **Error común en el mercado: `systemctl disable --now firewalld` en todos los nodos.** Es lo que hacen muchas guías
de Internet "para que funcione": el clúster queda expuesto (la API del kubelet en 10250, NodePorts y métricas abiertos
a toda la red) y la auditoría de seguridad lo marca como crítico. **Cómo evitarlo:** abrir los puertos documentados,
solo para los orígenes necesarios. Si la red de pods falla, firewalld es el primer sospechoso: `journalctl -k
--since -10min | grep -i -E 'reject|drop'`; para confirmarlo, parar firewalld **un momento** y volver a arrancarlo.

#### f. containerd

📘 **Concepto.** El kubelet habla con el runtime por **CRI**. containerd es el runtime más usado; en RHEL no viene, y
el paquete `containerd.io` sale del repositorio de Docker (solo containerd, no Docker). Ese paquete trae el plugin
**CRI desactivado** (`disabled_plugins = ["cri"]`), así que se genera la configuración por defecto. El kubelet y el
runtime deben usar el **mismo driver de cgroups**: con systemd como init, `systemd` (`SystemdCgroup = true` en
containerd y `cgroupDriver: systemd` en el kubelet). La imagen *sandbox* (`pause`) de containerd debería coincidir con
la que espera kubeadm.

*Fuente:* [Container Runtimes — containerd](https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd) ·
[Configuring a cgroup driver](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/configure-cgroup-driver/) ·
[containerd — CRI config](https://github.com/containerd/containerd/blob/main/docs/cri/config.md)

🛠️ **Práctica.**

```bash
# [nodos · root]
dnf install -y dnf-plugins-core
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf install -y containerd.io
rpm -q containerd.io container-selinux; containerd --version
restorecon -Rv /var/lib/containerd /var/lib/kubelet /var/lib/local-path
cp -a /etc/containerd/config.toml /etc/containerd/config.toml.paquete
grep -n disabled_plugins /etc/containerd/config.toml.paquete
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
grep -n 'SystemdCgroup\|enable_selinux\|sandbox' /etc/containerd/config.toml
systemctl enable --now containerd && systemctl is-active containerd
```

| Paso | Qué esperas | Si sale otra cosa |
|---|---|---|
| `rpm -q` / `--version` | Los dos paquetes y la versión de containerd (anótala: 1.7 o 2.x) | — |
| `restorecon -Rv` | Cambia los contextos (ahora existe la política de `container-selinux`): `container_var_lib_t` en `/var/lib/containerd` | — |
| `grep disabled_plugins` | `disabled_plugins = ["cri"]` en el fichero del paquete | — |
| `grep SystemdCgroup...` | `SystemdCgroup = true`, `enable_selinux = false` y la imagen `pause` | `SystemdCgroup` sigue en `false` → la línea tenía otro formato: edítala con `vim` |
| `is-active` | `active` | `failed` → `journalctl -u containerd -n 30` (casi siempre, sintaxis de `config.toml`) |

En containerd 2.x las secciones cambian de nombre (`[plugins.'io.containerd.cri.v1.runtime'...]`), pero la línea
`SystemdCgroup` existe en las dos versiones. `enable_selinux = false` es el valor por defecto: el sistema sigue en
*enforcing*, pero los contenedores no se aíslan entre sí; en la 8.6.5 lo activas en un worker.

⚠️ **Error común en el mercado: drivers de cgroups distintos.** El kubelet con `systemd` y containerd con `cgroupfs`
(o al revés): el nodo parece funcionar, pero bajo carga aparecen pods que se reinician sin motivo, métricas de memoria
incoherentes y nodos `NotReady`. **Cómo evitarlo:** configurarlo de forma explícita en los dos lados y comprobarlo
(`grep SystemdCgroup` y `cgroupDriver` en la configuración del kubelet).

#### g. kubeadm, kubelet y kubectl

📘 **Concepto.** Los paquetes oficiales están en `pkgs.k8s.io`, con **un repositorio por versión menor** (v1.36 solo
tiene 1.36.z). La documentación recomienda `exclude=` en el `.repo` para que un `dnf update` rutinario no actualice
Kubernetes: las actualizaciones del clúster tienen un orden (8.12). El kubelet queda reiniciándose en bucle hasta el
`init` o el `join`: aún no tiene configuración.

*Fuente:* [Installing kubeadm, kubelet and kubectl](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#installing-kubeadm-kubelet-and-kubectl)

🛠️ **Práctica.**

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
crictl --runtime-endpoint unix:///run/containerd/containerd.sock info | grep -A3 RuntimeReady
```

| Paso | Qué esperas | Si sale otra cosa |
|---|---|---|
| `dnf list --showduplicates` | Varias `1.36.z`, entre ellas `1.36.5` | Si ya no está, usa la última 1.36 y cámbiala también en `kubeadm-config.yaml` |
| `dnf install` | `Complete!` | — |
| `kubeadm version` | `v1.36.5` | — |
| `crictl info` | `"type": "RuntimeReady", "status": true` | `connect: no such file` → containerd parado |

**Comprobación del nodo, antes de pasar al siguiente:**

```bash
# [nodos · root]
swapon --show | wc -l                                         # 0
sysctl -n net.ipv4.ip_forward                                 # 1
firewall-cmd --get-active-zones | grep -c k8s                 # 1
systemctl is-active containerd                                # active
grep -c 'SystemdCgroup = true' /etc/containerd/config.toml    # 1
rpm -q kubelet kubeadm kubectl                                # 1.36.5
```

⚠️ **Error común en el mercado: Kubernetes actualizado por un `dnf update` de parches.** Sin `exclude=`, la ventana
mensual de parches del sistema sube el kubelet de un nodo a la versión siguiente sin actualizar el plano de control:
el kubelet queda por delante de la API (fuera de la política de versiones) y el nodo falla. **Cómo evitarlo:**
`exclude=` (o `dnf versionlock`) y actualizaciones de Kubernetes como cambio propio.

### 8.2.3 `kubeadm init` y la red de pods

📘 **Concepto.** `kubeadm init` ejecuta **fases**: `preflight` (comprobaciones), `certs` (CA y certificados en
`/etc/kubernetes/pki/`), `kubeconfig`, `kubelet-start`, `control-plane` y `etcd` (escribe los manifiestos de **pods
estáticos** en `/etc/kubernetes/manifests/`, que el kubelet arranca sin API), `upload-config`, `mark-control-plane`
(etiqueta y *taint*), `bootstrap-token` y `addons` (CoreDNS y kube-proxy). Se configura con un fichero
(`ClusterConfiguration`, `InitConfiguration`, `KubeletConfiguration`, `KubeProxyConfiguration`). Hasta que hay un
**CNI**, el nodo está `NotReady` y CoreDNS en `Pending`. Calico se instala con su **operador** (Tigera), que recibe un
objeto `Installation` con el pool de IPs de los pods.

*Fuente:* [Creating a cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/) ·
[kubeadm init phases](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init-phase/) ·
[Static Pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/) ·
[Calico — Install on on-premises deployments](https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises)

🛠️ **Práctica.**

```bash
# [host]
scp scripts/stage8/files/cluster/kubeadm-config.yaml scripts/stage8/files/cluster/calico-custom-resources.yaml \
    adminlab@k8s-cp01.lab.local:
```

```bash
# [k8s-cp01 · root]
less ~adminlab/kubeadm-config.yaml
kubeadm config validate --config ~adminlab/kubeadm-config.yaml
kubeadm config images list --config ~adminlab/kubeadm-config.yaml
kubeadm config images pull --config ~adminlab/kubeadm-config.yaml
kubeadm init --config ~adminlab/kubeadm-config.yaml --upload-certs | tee /root/kubeadm-init.log
mkdir -p ~adminlab/.kube && cp /etc/kubernetes/admin.conf ~adminlab/.kube/config
chown -R adminlab: ~adminlab/.kube && chmod 600 ~adminlab/.kube/config
ls /etc/kubernetes/manifests/
```

Las decisiones del fichero (cada una comentada en él):

| Clave | Valor | Por qué |
|---|---|---|
| `controlPlaneEndpoint` | `k8s-api.lab.local:6443` | Un nombre DNS: un segundo nodo de control solo cambiaría el registro |
| `podSubnet` / `serviceSubnet` | `10.244.0.0/16` / `10.96.0.0/12` | No chocan con el lab, con libvirt ni con la red de casa |
| `bind-address: 0.0.0.0`, `listen-metrics-urls`, `metricsBindAddress` | Métricas fuera de `127.0.0.1` | Si no, Prometheus los da por caídos (E00 de la 8.8) |
| `cgroupDriver: systemd` | Igual que containerd | Apartado f |
| `containerLogMaxSize: 10Mi`, `containerLogMaxFiles: 3` | Logs acotados | `/var` tiene 4 GB |

| Paso | Qué esperas | Si sale otra cosa |
|---|---|---|
| `config validate` | `ok` | `unknown field` → una clave mal escrita |
| `images list` / `pull` | 7 imágenes de `registry.k8s.io` | Compara la versión de `pause` con la de `sandbox` en `config.toml`: si difieren, el `init` avisará; iguálalas y `systemctl restart containerd` |
| `kubeadm init` | `Your Kubernetes control-plane has initialized successfully!` y dos comandos `kubeadm join` | `[ERROR ...]` en `preflight` → dice qué falta; arréglalo y repite. Fallo posterior → `kubeadm reset -f` |
| `ls manifests/` | `etcd.yaml`, `kube-apiserver.yaml`, `kube-controller-manager.yaml`, `kube-scheduler.yaml` | — |

```bash
# [k8s-cp01 · adminlab]
kubectl get nodes
kubectl -n kube-system get pods
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/tigera-operator.yaml
kubectl -n tigera-operator rollout status deploy/tigera-operator --timeout=3m
kubectl create -f ~/calico-custom-resources.yaml
watch kubectl get tigerastatus
kubectl get nodes
kubectl -n kube-system get pods -l k8s-app=kube-dns
```

| Paso | Qué esperas | Por qué |
|---|---|---|
| `get nodes` (antes de Calico) | `k8s-cp01 NotReady control-plane` | No hay CNI |
| `get pods -n kube-system` | Componentes en `Running`, `coredns` en `Pending` | CoreDNS es un pod normal: necesita red de pods |
| `create -f tigera-operator.yaml` | Muchos `created` (con `create`, no `apply`: los CRDs no caben en la anotación de `apply`) | — |
| `create -f calico-custom-resources.yaml` | `installation.operator.tigera.io/default created` | — |
| `watch get tigerastatus` | En 2-4 min, todo `AVAILABLE True` (`Ctrl+C` para salir) | Atascado → `kubectl -n calico-system get pods` y `describe` |
| `get nodes` / CoreDNS | `Ready`; `coredns` en `Running` | — |

> `admin.conf` es **cluster-admin** con un certificado de un año: trátalo como la contraseña de root.

⚠️ **Error común en el mercado: la red de pods solapada con la de la empresa.** Se deja el `podSubnet` de un ejemplo
de Internet (`192.168.0.0/16` es típico de los ejemplos de Calico) y resulta ser la red de oficinas o de la VPN: los
pods no llegan a esos servidores, o los usuarios de la VPN no llegan al clúster, y cambiarlo después obliga a
**reconstruir el clúster**. **Cómo evitarlo:** pedir a Redes los rangos libres antes del `init` y documentarlos, como
hace la tabla de direccionamiento del lab.

### 8.2.4 Unir los workers

📘 **Concepto.** `kubeadm join` usa un **token de arranque** (caduca a las 24 h por defecto) y el **hash de la CA**
(`--discovery-token-ca-cert-hash`): el nodo comprueba que habla con el clúster correcto antes de enviarle nada.
`kubeadm token create --print-join-command` genera un token nuevo y el comando completo.

*Fuente:* [kubeadm join](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-join/) ·
[kubeadm token](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-token/)

🛠️ **Práctica.**

```bash
# [k8s-cp01 · root]
kubeadm token create --print-join-command
```

```bash
# [workers · root]  (pega el comando que imprimió k8s-cp01; tiene esta forma)
kubeadm join k8s-api.lab.local:6443 --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:0123...cdef
```

```bash
# [k8s-cp01 · adminlab]
kubectl get nodes -o wide
kubectl label node k8s-w01 k8s-w02 node-role.kubernetes.io/worker=
```

Lo esperado: `This node has joined the cluster`; después, 3 nodos `Ready`, `v1.36.5`, `containerd://...`. Si el join da
timeout: desde el worker, `curl -k https://k8s-api.lab.local:6443/livez` (debe decir `ok`) y el 6443 en la zona `k8s`
de `k8s-cp01`.

⚠️ **Error común en el mercado: `--discovery-unsafe-skip-ca-verification`.** Cuando el hash "da problemas", se une el
nodo saltándose la verificación de la CA. El nodo confía en quien responda en esa dirección: un atacante en la red
podría hacerse pasar por el plano de control. **Cómo evitarlo:** generar el comando con `--print-join-command`, que
incluye el hash correcto.

### 8.2.5 Administrar desde `ansible01`

📘 **Concepto.** `kubectl` lee el **kubeconfig** (`~/.kube/config`): clústeres (URL y CA), usuarios (credenciales) y
**contextos** (combinación de clúster, usuario y namespace). La política de versiones permite que `kubectl` esté **una
versión menor** por encima o por debajo de la API. Helm se instala desde el binario oficial verificando su suma.

*Fuente:* [Organizing access using kubeconfig files](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/) ·
[Version Skew Policy](https://kubernetes.io/releases/version-skew-policy/) ·
[Installing Helm](https://helm.sh/docs/intro/install/)

🛠️ **Práctica.**

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
kubectl get nodes; kubectl config get-contexts
rpm -q bash-completion || sudo dnf install -y bash-completion
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl; complete -o default -F __start_kubectl k' >> ~/.bashrc
source ~/.bashrc
```

```bash
# [ansible01 · adminlab]  Helm 4
HELM_VERSION=v4.0.0       # cámbialo por la última 4.x estable de https://github.com/helm/helm/releases
curl -fsSLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum" | sha256sum -c
tar xzf "helm-${HELM_VERSION}-linux-amd64.tar.gz" && sudo install -m 0755 linux-amd64/helm /usr/local/bin/helm
rm -rf linux-amd64 "helm-${HELM_VERSION}-linux-amd64.tar.gz"
helm version
rpm -q git || sudo dnf install -y git
git clone https://github.com/salatielaizza/enterprise-rhel-lab.git ~/enterprise-rhel-lab
```

| Paso | Qué esperas | Si sale otra cosa |
|---|---|---|
| `kubectl get nodes` | Los 3 nodos | `scp` pide contraseña → copia la clave de `ansible01` desde el host: `ssh adminlab@ansible01 cat .ssh/id_ed25519.pub \| ssh adminlab@k8s-cp01 'cat >> .ssh/authorized_keys'` |
| `get-contexts` | `* kubernetes-admin@lab-k8s` | — |
| `sha256sum -c` | `helm-v4...tar.gz: OK` | `FAILED` → **no** lo instales |
| `git clone` | `~/enterprise-rhel-lab` con `scripts/stage8/files` | Para actualizarlo: `git -C ~/enterprise-rhel-lab pull` |

⚠️ **Error común en el mercado: el `admin.conf` repartido por el equipo.** Todos usan el mismo kubeconfig de
cluster-admin (copiado por correo o a un repositorio), sin forma de saber quién hizo qué, y cuando caduca al año, el
clúster "deja de funcionar" para todos a la vez. **Cómo evitarlo:** un acceso por persona con permisos limitados
(8.6) y el `admin.conf` guardado como credencial de emergencia.

### 8.2.6 Comprobación de salud

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

Lo esperado: 3 `Ready`; nada fuera de `Running`; `readyz check passed`; tu configuración guardada en el clúster;
certificados con ~364 días y la CA con 10 años; y la base del lab sigue en 0 FAIL.

### 8.2.7 Snapshot del clúster vacío (desde el host)

Es el punto de vuelta más valioso de la etapa. Se apaga primero (workers antes que el plano de control) y se enciende
en orden inverso.

```bash
# [host]
scripts/lab.sh down k8s-w02; scripts/lab.sh down k8s-w01; scripts/lab.sh down k8s-cp01
watch 'virsh list --all | grep k8s'            # los tres en "apagado"/"shut off"; Ctrl+C
for h in k8s-cp01 k8s-w01 k8s-w02; do
  virsh snapshot-create-as "$h" --name "$h-cluster-vacio" --description "Etapa 8.2: clúster recién creado, sin apps"
done
virsh snapshot-list k8s-cp01
scripts/lab.sh up k8s-cp01; sleep 60; scripts/lab.sh up k8s-w01; scripts/lab.sh up k8s-w02
```

Para volver aquí: apaga los tres y `virsh snapshot-revert <nodo> <nodo>-cluster-vacio`. El mismo procedimiento, con
otro nombre, sirve para `*-antes-8.6`, `*-antes-8.9` y `*-antes-8.12`.

**Checklist:** filas 5-14.

---

## 8.3 Objetos de Kubernetes

> 🎫 **Ticket APP-803.** "El equipo de producto quiere desplegar `podinfo` en el namespace `demo`: dos réplicas, sin
> cortes al actualizar, posibilidad de volver atrás en segundos, la configuración fuera de la imagen y un proceso por
> lotes que solo se ejecute una vez."

**Dónde:** `ansible01`, desde `~/enterprise-rhel-lab/scripts/stage8/files`. **Vuelta atrás:**
`kubectl delete -f apps/podinfo.yaml` (borra el namespace `demo` entero).

### 8.3.1 Objetos, estado deseado y Deployments

📘 **Concepto.** Un objeto de Kubernetes es un **registro de intención**: tú escribes el `spec` (estado deseado) y el
sistema escribe el `status` (estado real). Los **controladores** comparan ambos sin parar y corrigen. Un
**Deployment** describe una aplicación y gestiona **ReplicaSets**; cada ReplicaSet mantiene N **Pods** idénticos. Al
cambiar la plantilla del pod (`spec.template`), el Deployment crea un ReplicaSet nuevo y va pasando pods del viejo al
nuevo (*rolling update*, controlado por `maxSurge` y `maxUnavailable`); el viejo se guarda para poder volver atrás
(`rollout undo`). `kubectl explain` es la documentación de la API de **tu** versión, dentro del clúster.

*Fuente:* [Objects In Kubernetes](https://kubernetes.io/docs/concepts/overview/working-with-objects/) ·
[Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) ·
[ReplicaSet](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
cd ~/enterprise-rhel-lab/scripts/stage8/files
less apps/podinfo.yaml
kubectl apply -f apps/podinfo.yaml --dry-run=server
kubectl apply -f apps/podinfo.yaml
kubectl -n demo get deploy,rs,pods,svc -o wide --show-labels
kubectl explain deployment.spec.strategy.rollingUpdate
```

| Línea del `get` | Qué esperas | Cómo se relaciona |
|---|---|---|
| `deployment.apps/podinfo` | `READY 2/2` | Crea un ReplicaSet... |
| `replicaset.apps/podinfo-<hash>` | `DESIRED 2 CURRENT 2 READY 2` | ...que crea los pods... |
| `pod/podinfo-<hash>-<id>` × 2 | `Running`, uno en cada worker | ...con la etiqueta `pod-template-hash` de su ReplicaSet |
| `service/podinfo` | `LoadBalancer`, `EXTERNAL-IP <pending>` | Sin MetalLB aún (8.4) |

**Estado deseado en acción:**

```bash
# [ansible01 · adminlab]
kubectl -n demo delete pod "$(kubectl -n demo get pods -o name | head -1 | cut -d/ -f2)"
kubectl -n demo get pods -w                         # Ctrl+C cuando haya 2 Running
kubectl -n demo scale deploy/podinfo --replicas=4
kubectl -n demo get pods -o wide
kubectl -n demo scale deploy/podinfo --replicas=2
```

Lo esperado: el pod borrado pasa a `Terminating` y **a la vez** aparece uno nuevo; al escalar, 4 pods repartidos entre
`k8s-w01` y `k8s-w02`.

**Rolling update y vuelta atrás:**

```bash
# [ansible01 · adminlab]
kubectl -n demo set env deploy/podinfo PODINFO_UI_MESSAGE="version 2"
kubectl -n demo annotate deploy/podinfo kubernetes.io/change-cause="mensaje version 2" --overwrite
kubectl -n demo rollout status deploy/podinfo
kubectl -n demo get rs
kubectl -n demo rollout history deploy/podinfo
kubectl -n demo rollout undo deploy/podinfo
kubectl -n demo rollout status deploy/podinfo
kubectl -n demo get rs
```

| Paso | Qué esperas | Qué demuestra |
|---|---|---|
| `set env` | `env updated` | Cambiar la plantilla = revisión nueva |
| `rollout status` | `Waiting for ... 1 of 2 updated replicas` y `successfully rolled out` | Pods sustituidos de uno en uno, sin corte |
| `get rs` | Dos ReplicaSets: el nuevo `2/2`, el viejo `0/0` | El viejo se guarda |
| `rollout history` | Revisiones con su `CHANGE-CAUSE` | Sin la anotación, `<none>`: nadie sabría qué cambió |
| `rollout undo` + `get rs` | El viejo vuelve a `2/2` | Vuelta atrás en segundos |

⚠️ **Error común en el mercado: pods sin `requests` ni `limits` y sin *probes*.** Es lo que sale de
`kubectl create deployment` o de un YAML copiado: el scheduler no sabe cuánto ocupa cada pod y llena nodos hasta
quedarse sin memoria; y sin *readinessProbe*, el Service manda tráfico a pods que aún están arrancando, con errores en
cada despliegue. **Cómo evitarlo:** todo Deployment con `resources.requests`, `limits.memory`, `readinessProbe` y
`livenessProbe`, como `apps/podinfo.yaml`.

### 8.3.2 Etiquetas y selectores

📘 **Concepto.** Las **etiquetas** son pares clave-valor en los objetos; los **selectores** las usan para agrupar.
Todo se une por etiquetas: un ReplicaSet "posee" los pods que coinciden con su selector, y un Service envía tráfico a
los pods que coinciden con el suyo. Si un pod pierde la etiqueta, sale de los dos.

*Fuente:* [Labels and Selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/) ·
[Recommended Labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
POD=$(kubectl -n demo get pods -l app.kubernetes.io/name=podinfo -o name | head -1)
kubectl -n demo label "$POD" app.kubernetes.io/name-
kubectl -n demo get pods --show-labels
kubectl -n demo get endpointslices -l kubernetes.io/service-name=podinfo -o wide
kubectl -n demo delete "$POD"
```

Lo esperado: **tres** pods (el huérfano sigue `Running` y el ReplicaSet creó otro), y en los EndpointSlices solo dos IPs:
el huérfano ya no recibe tráfico. Nadie lo gestiona: hay que borrarlo a mano.

⚠️ **Error común en el mercado: un Service sin endpoints.** El selector del Service dice `app: web` y los pods llevan
`app.kubernetes.io/name: web` (o hay una errata): el Service existe, tiene IP y DNS, pero toda petición falla con
`connection refused` o timeout. **Cómo detectarlo:** `kubectl get endpointslices -l kubernetes.io/service-name=<svc>`
vacío. Es la primera comprobación ante "el Service no responde".

### 8.3.3 ConfigMaps y Secrets

📘 **Concepto.** Un **ConfigMap** guarda configuración no confidencial; un **Secret**, datos sensibles. Los dos se
inyectan como variables de entorno o como ficheros. Los Secrets van en **base64**, que es una codificación, **no** un
cifrado: cualquiera con permiso `get` sobre ellos los lee, y en etcd se guardan en claro salvo que se configure cifrado
en reposo (8.6.4).

*Fuente:* [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) ·
[Secrets](https://kubernetes.io/docs/concepts/configuration/secret/) ·
[Good practices for Kubernetes Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
kubectl -n demo create configmap podinfo-cfg --from-literal=PODINFO_UI_COLOR=#34577c
kubectl -n demo set env deploy/podinfo --from=configmap/podinfo-cfg
kubectl -n demo exec deploy/podinfo -- env | grep PODINFO_UI_COLOR
kubectl -n demo create secret generic podinfo-token --from-literal=token=NoEsSecreto123
kubectl -n demo get secret podinfo-token -o jsonpath='{.data.token}'; echo
kubectl -n demo get secret podinfo-token -o jsonpath='{.data.token}' | base64 -d; echo
kubectl -n demo set env deploy/podinfo PODINFO_UI_COLOR-
kubectl -n demo delete configmap podinfo-cfg
kubectl -n demo delete secret podinfo-token
```

Lo esperado: la variable dentro del pod; `Tm9Fc1NlY3JldG8xMjM=` y, decodificado, `NoEsSecreto123`. El `PODINFO_UI_COLOR-`
(con `-` final) quita la variable: `kubectl apply -f apps/podinfo.yaml` **no** la quitaría, porque `apply` solo borra
lo que él mismo puso (lo guarda en la anotación `last-applied-configuration`).

⚠️ **Error común en el mercado: Secrets en Git "porque están en base64".** Se suben al repositorio los YAML de los
Secrets con sus valores en base64, como si estuvieran protegidos: cualquiera con acceso al repo (o a su historial, para
siempre) tiene las contraseñas. **Cómo evitarlo:** los Secrets se crean fuera de Git (como en este lab), o se cifran
antes de subirlos (Sealed Secrets, SOPS) o se leen de un gestor externo (Vault, External Secrets).

### 8.3.4 Jobs, DaemonSets y taints

📘 **Concepto.** Un **Job** ejecuta pods **hasta que terminan bien** (no los reinicia para siempre como un Deployment);
un **CronJob** crea Jobs con un horario. Un **DaemonSet** pone **un pod por nodo** (agentes de red, logs, métricas). Un
**taint** en un nodo repele los pods que no tengan la *toleration* correspondiente: el plano de control lleva
`node-role.kubernetes.io/control-plane:NoSchedule`, y por eso las aplicaciones no van ahí. El namespace `demo` aplica
**Pod Security `restricted`** (8.6.3): los pods tienen que declarar un `securityContext` seguro.

*Fuente:* [Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/) ·
[DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) ·
[Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
kubectl describe node k8s-cp01 | grep Taints
kubectl get ds -A
kubectl -n demo create job pi --image=busybox:1.37 -- sh -c 'echo hola'
```

Lo esperado: el *taint* `NoSchedule`; `kube-proxy` y `calico-node` con `DESIRED 3` (uno por nodo, incluido
`k8s-cp01`); y el Job **rechazado**: `violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false ...,
runAsNonRoot != true ..., seccompProfile ...`. El mensaje es la receta del arreglo:

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
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
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
kubectl -n demo get job hola -w                     # COMPLETIONS 1/1; Ctrl+C
kubectl -n demo logs job/hola
kubectl -n demo get events --sort-by=.lastTimestamp | tail -10
```

Lo esperado: `1/1`, el mensaje y la fecha; los eventos cuentan la historia (`Scheduled`, `Pulled`, `Created`,
`Started`, `Completed`). `ttlSecondsAfterFinished` lo borra solo a los 10 minutos.

⚠️ **Error común en el mercado: imágenes con `:latest`.** El mismo YAML despliega cosas distintas cada día, dos nodos
pueden ejecutar versiones diferentes de la "misma" imagen, y `rollout undo` no vuelve a nada (la etiqueta apunta ya a
la versión nueva). **Cómo evitarlo:** etiquetas de versión fijas (o el *digest* `@sha256:`), como todo el lab.

**Checklist:** filas 15-16.

---

## 8.4 Red: Services, DNS, MetalLB, Ingress y NetworkPolicies

> 🎫 **Ticket NET-804.** "`podinfo` tiene que ser accesible desde la red de la oficina con un nombre fijo, más
> aplicaciones van a compartir la misma IP de entrada, y Seguridad exige que, dentro del clúster, solo hablen entre sí
> los componentes que lo necesitan."

### 8.4.1 Services y DNS interno

📘 **Concepto.** Un **Service** da una IP virtual estable (**ClusterIP**) y un nombre DNS
(`<servicio>.<namespace>.svc.cluster.local`) a un conjunto de pods; kube-proxy reparte el tráfico entre ellos. Tipos:
**ClusterIP** (solo dentro), **NodePort** (además, un puerto 30000-32767 en todos los nodos) y **LoadBalancer**
(además, una IP externa que asigna un proveedor). Las IPs reales detrás del Service están en los **EndpointSlices**.
**CoreDNS** resuelve los nombres del clúster y **reenvía** el resto al DNS del nodo (`forward . /etc/resolv.conf`).

*Fuente:* [Service](https://kubernetes.io/docs/concepts/services-networking/service/) ·
[DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
kubectl -n demo get svc podinfo -o wide
kubectl -n demo get endpointslices -l kubernetes.io/service-name=podinfo -o wide
kubectl run dnstest -it --rm --image=busybox:1.37 --restart=Never -- nslookup podinfo.demo.svc.cluster.local
kubectl run dnstest -it --rm --image=busybox:1.37 --restart=Never -- nslookup dns01.lab.local
kubectl -n kube-system get cm coredns -o yaml | grep -A1 forward
NP=$(kubectl -n demo get svc podinfo -o jsonpath='{.spec.ports[0].nodePort}'); echo "NodePort: $NP"
curl -s "http://k8s-w01.lab.local:$NP" | head -3
```

| Paso | Qué esperas |
|---|---|
| `get svc` | `CLUSTER-IP 10.96.x.x`, `PORT(S) 80:3xxxx/TCP` |
| `get endpointslices` | Las dos IPs `10.244.x.x`, puerto 9898 |
| `nslookup podinfo...` | La ClusterIP |
| `nslookup dns01.lab.local` | `10.10.10.20`: CoreDNS reenvía a `dns01` |
| `curl ...:$NP` | El JSON de podinfo por el NodePort |

(`kubectl run` funciona en `default` porque ese namespace no tiene Pod Security `restricted`.)

⚠️ **Error común en el mercado: NodePort como forma de "publicar" en producción.** Se abren puertos 3xxxx en todos los
nodos y se dan a los usuarios con la IP de un nodo concreto: si ese nodo cae o se sustituye, el servicio "desaparece",
y los puertos quedan abiertos en todos los nodos. **Cómo evitarlo:** LoadBalancer o Ingress/Gateway delante; NodePort
solo como pieza interna.

### 8.4.2 MetalLB: LoadBalancer sin nube

📘 **Concepto.** En la nube, `type: LoadBalancer` crea un balanceador del proveedor. En un CPD propio no hay nadie que
lo haga: **MetalLB** asigna IPs de un **IPAddressPool** y las anuncia. En **modo L2**, un nodo (elegido por IP)
responde a **ARP** por esa IP y kube-proxy reparte desde ahí; si el nodo cae, otro la anuncia. No reparte carga entre
nodos: es alta disponibilidad, no balanceo. Con `externalTrafficPolicy: Local`, solo anuncian los nodos con un pod
listo y se conserva la IP del cliente.

*Fuente:* [MetalLB — Installation](https://metallb.io/installation/) ·
[MetalLB — Layer 2 mode](https://metallb.io/concepts/layer2/) ·
[Service — External traffic policy](https://kubernetes.io/docs/reference/networking/virtual-ips/#external-traffic-policy)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
kubectl create namespace metallb-system
kubectl label namespace metallb-system pod-security.kubernetes.io/enforce=privileged
helm repo add metallb https://metallb.github.io/metallb && helm repo update
helm search repo metallb/metallb --versions | head -3
helm install metallb metallb/metallb --version 0.16.1 -n metallb-system --wait
kubectl -n metallb-system get pods -o wide
kubectl apply -f cluster/metallb-pool.yaml
kubectl -n demo get svc podinfo
curl -s http://podinfo.lab.local | head -3
kubectl -n demo scale deploy/podinfo --replicas=1
kubectl -n demo get pods -l app.kubernetes.io/name=podinfo -o wide
kubectl -n demo get events --field-selector involvedObject.kind=Service --sort-by=.lastTimestamp | tail -3
kubectl -n demo scale deploy/podinfo --replicas=2
```

| Paso | Qué esperas | Si sale otra cosa |
|---|---|---|
| `label ... privileged` | El *speaker* necesita `hostNetwork` para responder ARP | Sin la etiqueta, sus pods se rechazan |
| `helm install --wait` | `STATUS: deployed`; `controller` + un `speaker` por nodo | — |
| `get svc podinfo` | `EXTERNAL-IP 10.10.10.114` (la anotación `metallb.io/loadBalancerIPs` de `apps/podinfo.yaml`) | `<pending>` → el pool no se aplicó |
| `curl podinfo.lab.local` | El JSON | — |
| Eventos con 1 réplica | `announcing from node "k8s-w0X"`: el nodo **donde está el pod** | — |

⚠️ **Error común en el mercado: el pool de MetalLB solapado con el DHCP.** Se elige un rango "libre" sin preguntar a
Redes y el DHCP de la oficina reparte esas mismas IPs: conflictos de ARP, servicios que van y vienen y equipos de
usuarios sin red. **Cómo evitarlo:** reservar el rango en el plan de direccionamiento (aquí, `.110-.119`) y excluirlo
del DHCP.

### 8.4.3 Ingress y Gateway API con Traefik

📘 **Concepto.** Un LoadBalancer gasta una IP por servicio. Un **controlador de entrada** usa **una IP para muchos**
servicios y decide el destino por el nombre (`Host`) o la ruta. **Ingress** es la API clásica (una sola pieza; las
funciones avanzadas van en anotaciones propias de cada controlador). **Gateway API** es su sucesora: separa
`GatewayClass` (el proveedor), `Gateway` (la entrada, de plataforma) y `HTTPRoute` (las rutas, de cada equipo).
`ingress-nginx` se ha retirado (anuncio en noviembre de 2025, sin mantenimiento desde marzo de 2026); Traefik soporta
las dos APIs. Los CRDs de Gateway API se instalan aparte.

*Fuente:* [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) ·
[Gateway API](https://gateway-api.sigs.k8s.io/) ·
[Traefik — Getting started with Kubernetes](https://doc.traefik.io/traefik/getting-started/kubernetes/)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
GWAPI=v1.6.3     # la que indique la documentación de tu versión de Traefik
kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GWAPI}/standard-install.yaml"
kubectl create namespace traefik
helm repo add traefik https://traefik.github.io/charts && helm repo update
helm search repo traefik/traefik | head -3
TRAEFIK_CHART=<versión-de-helm-search>
helm install traefik traefik/traefik -n traefik --version "$TRAEFIK_CHART" \
  --set service.annotations."metallb\.io/loadBalancerIPs"=10.10.10.110 \
  --set providers.kubernetesGateway.enabled=true \
  --set gateway.listeners.web.namespacePolicy.from=All \
  --wait
kubectl -n traefik get svc traefik
kubectl get gatewayclass; kubectl get gateway -A
```

Cambia `<versión-de-helm-search>` por la `CHART VERSION` (y anótala). Lo esperado: `EXTERNAL-IP 10.10.10.110`, una
`GatewayClass traefik` aceptada y un `Gateway` (por ejemplo `traefik-gateway`) programado.

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
curl -s http://ingress.lab.local | head -3
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: otro.lab.local' http://10.10.10.110/
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
curl -s -H 'Host: podinfo-gw.lab.local' http://10.10.10.110/ | head -3
```

Lo esperado: el JSON por `ingress.lab.local`, un `404` con otro `Host` (decide la cabecera, no la IP) y el JSON por el
`HTTPRoute` con su propio nombre, en la **misma IP**.

⚠️ **Error común en el mercado: Ingress sin `ingressClassName`.** Con dos controladores en el clúster (algo normal
durante una migración, como la de ingress-nginx), un Ingress sin clase lo atiende el controlador por defecto, o
ninguno, o los dos, según la configuración: el tráfico llega a donde no toca. **Cómo evitarlo:** `ingressClassName`
siempre explícito, o `parentRefs` explícitos en Gateway API.

### 8.4.4 NetworkPolicies

📘 **Concepto.** Por defecto, **cualquier pod habla con cualquier pod** de cualquier namespace. Una **NetworkPolicy**
selecciona pods (`podSelector`) y, para ellos, permite solo el tráfico de entrada (`ingress`) o salida (`egress`) que
liste: en cuanto un pod está seleccionado por una política de un tipo, todo lo demás de ese tipo se descarta. Los
orígenes pueden ser pods (`podSelector`), namespaces (`namespaceSelector`) o rangos (`ipBlock`). El puerto es el del
**pod**, no el del Service. Las aplica el CNI (Calico).

*Fuente:* [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
less apps/networkpolicies.yaml
kubectl apply -f apps/loadgen.yaml
kubectl apply -f apps/networkpolicies.yaml
kubectl -n demo exec deploy/loadgen -- wget -qO- -T3 http://podinfo | head -3
kubectl run intruso -it --rm --image=busybox:1.37 --restart=Never -- wget -qO- -T3 http://podinfo.demo
curl -s -m3 http://podinfo.lab.local | head -3
curl -s -m3 -o /dev/null -w '%{http_code}\n' http://ingress.lab.local
```

| Prueba | Qué esperas | Por qué |
|---|---|---|
| Desde `loadgen` | El JSON | `podinfo-desde-loadgen` |
| `intruso` (namespace `default`) | `download timed out` | Ninguna regla lo permite: el paquete se **descarta** (timeout, no "refused") |
| Desde `ansible01` por MetalLB | El JSON | El `ipBlock 10.10.10.0/24` y el origen conservado por `externalTrafficPolicy: Local` |
| Por el Ingress | **Falla** (`000`, `502` o `504`) | El origen real es el **pod de Traefik** (`10.244.x.x`), que no está permitido |

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

Vuelve el JSON. `podinfo-desde-monitoring` hará lo mismo por Prometheus en la 8.8 (escenario E08).

⚠️ **Error común en el mercado: "denegar todo" también en la salida, y se rompe el DNS.** Se aplica una política de
salida por defecto (`policyTypes: ["Egress"]` sin reglas) y se abren solo los puertos de la aplicación: todos los pods
del namespace dejan de resolver nombres, porque el DNS (CoreDNS, UDP/TCP 53 en `kube-system`) no está permitido.
**Cómo evitarlo:** toda política de salida restrictiva incluye la regla hacia CoreDNS; y cada política nueva se prueba
desde los clientes reales (incluidos el Ingress y la monitorización).

**Checklist:** filas 17-20.

---

## 8.5 Almacenamiento: PV, PVC y StorageClass

> 🎫 **Ticket APP-805.** "La aplicación de fechas necesita guardar datos que sobrevivan a reinicios y despliegues.
> No hay cabina de almacenamiento todavía: usad el disco local de los nodos, pero documentad las limitaciones."

### 8.5.1 PV, PVC y StorageClass

📘 **Concepto.** Un **PersistentVolumeClaim (PVC)** es una petición ("1 Gi, lectura-escritura"); un
**PersistentVolume (PV)** es el volumen real; una **StorageClass** dice qué **provisionador** lo crea y cómo. Con
`volumeBindingMode: WaitForFirstConsumer`, el volumen no se crea hasta que hay un pod que lo usa (así se crea en su
nodo). `ReadWriteOnce` = montable en escritura por **un nodo** a la vez. `reclaimPolicy: Delete` borra los datos al
borrar el PVC; `Retain` los conserva. **local-path-provisioner** crea cada volumen como un directorio del nodo: el PV
queda atado a ese nodo (*nodeAffinity*).

*Fuente:* [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) ·
[Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/) ·
[local-path-provisioner](https://github.com/rancher/local-path-provisioner)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.37/deploy/local-path-storage.yaml
kubectl -n local-path-storage rollout status deploy/local-path-provisioner
kubectl -n local-path-storage get cm local-path-config -o jsonpath='{.data.config\.json}'; echo
kubectl -n local-path-storage edit configmap local-path-config     # /opt/local-path-provisioner -> /var/lib/local-path; :wq
kubectl -n local-path-storage get cm local-path-config -o jsonpath='{.data.config\.json}'; echo
kubectl -n local-path-storage rollout restart deploy/local-path-provisioner
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get storageclass
```

Lo esperado: `"paths":["/var/lib/local-path"]` (el LV de la 8.2) y `local-path (default) rancher.io/local-path Delete
WaitForFirstConsumer`.

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
cat > ~/fechas-deploy.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fechas
  namespace: demo
  labels: {app.kubernetes.io/name: fechas}
spec:
  replicas: 1
  strategy: {type: Recreate}
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
kubectl apply -f ~/fechas-pvc.yaml
kubectl -n demo get pvc fechas
kubectl -n demo describe pvc fechas | tail -2
kubectl apply -f ~/fechas-deploy.yaml
kubectl -n demo get pvc fechas -w                 # Pending -> Bound; Ctrl+C
kubectl -n demo get pods -l app.kubernetes.io/name=fechas -o wide
sleep 30; kubectl -n demo delete pod -l app.kubernetes.io/name=fechas
kubectl -n demo rollout status deploy/fechas
kubectl -n demo exec deploy/fechas -- head -3 /datos/fechas.log
```

| Paso | Qué esperas | Qué demuestra |
|---|---|---|
| PVC solo | `Pending`, `waiting for first consumer to be created before binding` | *WaitForFirstConsumer*: no es un error |
| Con el Deployment | `Bound`; el pod en un worker (anota cuál) | — |
| Pod borrado y recreado | El nuevo lee fechas **anteriores** a su creación | Los datos sobreviven al pod |

```bash
# [k8s-w0X · root]  (el nodo del pod)
ls -l /var/lib/local-path/
ls -lZ /var/lib/local-path/*/
```

Lo esperado: un directorio `pvc-<uuid>_demo_fechas` con `fechas.log` y su contexto SELinux (anótalo: lo usas en la
8.6.5). Para terminar: `kubectl delete -f ~/fechas-deploy.yaml -f ~/fechas-pvc.yaml`; con `Delete`, el directorio
desaparece del nodo a los pocos segundos.

⚠️ **Error común en el mercado: `ReadWriteOnce` con `RollingUpdate`.** Una aplicación con un volumen RWO y la
estrategia por defecto: en el siguiente despliegue, el pod nuevo cae en otro nodo y se queda en
`ContainerCreating` con `Multi-Attach error for volume`, porque el viejo todavía lo tiene montado; el despliegue se
cuelga. **Cómo evitarlo:** `strategy: Recreate` (como aquí) o un StatefulSet. Y con almacenamiento local, saber que si
el nodo cae, el pod **no** puede ir a otro (lo verás en el E07 de la 8.8): para datos importantes, almacenamiento de
red (CSI, NFS, Ceph; la Etapa 15 monta NFS).

**Checklist:** fila 21.

---

## 8.6 Seguridad: RBAC, ServiceAccounts, Pod Security, Secrets y SELinux

> 🎫 **Ticket SEC-806.** "Auditoría: el equipo de la tienda tiene que poder desplegar en su namespace y en ningún
> otro; las aplicaciones no pueden correr como root; queremos saber dónde están las contraseñas y si los contenedores
> están aislados entre sí."

**Antes de empezar:** snapshot `*-antes-8.6` (paso 8.2.7 con ese nombre). La 8.6.5 toca containerd en un worker.

### 8.6.1 Autenticación y RBAC: un usuario que no es administrador

📘 **Concepto.** Kubernetes **no guarda usuarios**: autentica a quien presente un certificado firmado por su CA (el
`CN` es el usuario y el `O`, el grupo), un token o una identidad de un proveedor OIDC. Después, **RBAC** autoriza:
un **Role** (en un namespace) o **ClusterRole** (para todo el clúster) lista verbos sobre recursos, y un
**RoleBinding** o **ClusterRoleBinding** los asigna a usuarios, grupos o ServiceAccounts. Un RoleBinding puede usar un
ClusterRole genérico (`view`, `edit`, `admin`) limitado a su namespace. La API **CertificateSigningRequest** permite
pedir a la CA del clúster que firme un certificado de cliente. `kubectl auth can-i` (con `--as` para suplantar)
comprueba permisos.

*Fuente:* [Authenticating](https://kubernetes.io/docs/reference/access-authn-authz/authentication/) ·
[Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) ·
[Certificates and Certificate Signing Requests](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
mkdir -p ~/rbac && cd ~/rbac
kubectl create namespace tienda
openssl genrsa -out dev-tienda.key 3072 && chmod 600 dev-tienda.key
openssl req -new -key dev-tienda.key -subj "/CN=dev-tienda/O=equipo-tienda" -out dev-tienda.csr
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
kubectl get csr dev-tienda -o jsonpath='{.status.certificate}' | base64 -d > dev-tienda.crt
openssl x509 -in dev-tienda.crt -noout -subject -enddate
kubectl create rolebinding equipo-tienda-edit --clusterrole=edit --group=equipo-tienda -n tienda
kubectl config set-credentials dev-tienda --client-certificate=dev-tienda.crt --client-key=dev-tienda.key --embed-certs
kubectl config set-context dev-tienda --cluster=lab-k8s --user=dev-tienda --namespace=tienda
kubectl --context dev-tienda auth can-i create deployments
kubectl --context dev-tienda auth can-i get pods -n demo
kubectl --context dev-tienda auth can-i get nodes
kubectl --context dev-tienda get pods -n demo
kubectl auth can-i --list --as=dev-tienda --as-group=equipo-tienda -n tienda | head -10
```

| Paso | Qué esperas | Qué demuestra |
|---|---|---|
| `get csr` | `Pending`; tras `approve`, `Approved,Issued` | La CA firma solo lo que un administrador aprueba |
| `openssl x509` | `subject=O=equipo-tienda, CN=dev-tienda` y fecha a 30 días | — |
| `can-i create deployments` | `yes` | `edit` en `tienda` |
| `can-i get pods -n demo` | `no` | Un RoleBinding solo vale en su namespace |
| `can-i get nodes` | `no` | Los nodos no tienen namespace: harían falta ClusterRole + ClusterRoleBinding |
| `get pods -n demo` | `Forbidden: User "dev-tienda" cannot list resource "pods" ... in the namespace "demo"` | El error dice usuario, verbo, recurso y namespace |

⚠️ **Error común en el mercado: `cluster-admin` para todo el mundo.** Para no "perder tiempo con permisos", se da
`cluster-admin` a todos los desarrolladores o a la cuenta de un pipeline. Un error en un `kubectl delete` o una
credencial filtrada afecta a **todo** el clúster. **Cómo evitarlo:** RoleBindings por namespace con los ClusterRoles
`view`/`edit`, grupos en vez de usuarios, y `auth can-i --list --as` para revisar.

### 8.6.2 ServiceAccounts: la identidad de los pods

📘 **Concepto.** Los procesos de los pods se autentican ante la API con una **ServiceAccount** (por defecto, `default`
de su namespace). Su token se monta en `/var/run/secrets/kubernetes.io/serviceaccount/` (token de corta duración,
renovado por el kubelet), junto con la CA. Como usuario, su nombre es `system:serviceaccount:<ns>:<nombre>`. Si un
pod no habla con la API, `automountServiceAccountToken: false`.

*Fuente:* [Service Accounts](https://kubernetes.io/docs/concepts/security/service-accounts/) ·
[Configure Service Accounts for Pods](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)

🛠️ **Práctica.**

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
kubectl -n demo exec cliente-api -- sh -c '
  SA=/var/run/secrets/kubernetes.io/serviceaccount; API=https://kubernetes.default.svc
  H="Authorization: Bearer $(cat $SA/token)"
  echo "listar pods:   $(curl -s --cacert $SA/ca.crt -H "$H" $API/api/v1/namespaces/demo/pods -o /dev/null -w %{http_code})"
  echo "borrar un pod: $(curl -s --cacert $SA/ca.crt -H "$H" -X DELETE $API/api/v1/namespaces/demo/pods/cliente-api -o /dev/null -w %{http_code})"
  echo "leer secrets:  $(curl -s --cacert $SA/ca.crt -H "$H" $API/api/v1/namespaces/demo/secrets -o /dev/null -w %{http_code})"'
kubectl delete -f ~/rbac/sa-lector.yaml
```

Lo esperado: `200`, `403` y `403`.

⚠️ **Error común en el mercado: aplicaciones con una ServiceAccount con demasiados permisos.** Un chart o un operador
de terceros pide un ClusterRole con `*` sobre `*`, y se instala sin leerlo; si esa aplicación se compromete, el
atacante tiene el clúster. **Cómo evitarlo:** leer el RBAC con `helm template` antes de instalar (8.7.1), mínimo
privilegio y `automountServiceAccountToken: false` en lo que no use la API.

### 8.6.3 Pod Security Admission

📘 **Concepto.** Los **Pod Security Standards** definen tres niveles: **privileged** (sin restricciones), **baseline**
(impide lo claramente peligroso: `privileged`, `hostNetwork`, `hostPID`, `hostPath`...) y **restricted** (buenas
prácticas obligatorias: `runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`,
`seccompProfile`, solo tipos de volumen seguros). El controlador **Pod Security Admission** los aplica por
**namespace** con etiquetas y tres modos: `enforce` (rechaza), `audit` (registra) y `warn` (avisa).

*Fuente:* [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) ·
[Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
kubectl get ns -L pod-security.kubernetes.io/enforce
kubectl -n demo run root --image=busybox:1.37 --restart=Never -- sleep 60
kubectl label --dry-run=server --overwrite ns metallb-system pod-security.kubernetes.io/enforce=restricted
```

| Paso | Qué esperas |
|---|---|
| `get ns -L` | `demo restricted`, `metallb-system privileged`; el resto, vacío (= sin restricciones) |
| `run root` en `demo` | `Forbidden: violates PodSecurity "restricted:latest": ...` con la lista de lo que falta |
| `label --dry-run=server` | `Warning: existing pods in namespace "metallb-system" violate the new PodSecurity enforce level ... hostNetwork=true ...`: dice qué se rompería, **sin cambiar nada** |

`monitoring` y `metallb-system` son `privileged` porque node-exporter y el *speaker* de MetalLB son agentes de nodo
(`hostNetwork`, `hostPID`).

⚠️ **Error común en el mercado: namespaces sin nivel (o todo `privileged`).** Como el valor por defecto no restringe
nada, cualquier pod puede montar el disco del nodo (`hostPath: /`) o correr `privileged`: desde ahí, el nodo entero.
Y el error contrario: activar `enforce: restricted` en producción de golpe, que rechaza los pods en su próximo
reinicio. **Cómo evitarlo:** `warn` y `audit` primero, el `--dry-run=server` de arriba, y después `enforce`.

### 8.6.4 Secrets: qué protege y qué no

📘 **Concepto.** Los Secrets se protegen con **RBAC** (quién tiene `get`/`list` sobre `secrets`; el ClusterRole `edit`
lo incluye). En etcd se guardan **en claro** salvo que el apiserver use **cifrado en reposo**
(`EncryptionConfiguration`, `--encryption-provider-config`). Quien tenga una copia de etcd o del disco del plano de
control tiene todos los Secrets.

*Fuente:* [Good practices for Kubernetes Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/) ·
[Encrypting Confidential Data at Rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
kubectl -n tienda create secret generic bd --from-literal=password='Tienda.2026!'
kubectl --context dev-tienda -n tienda get secret bd -o jsonpath='{.data.password}' | base64 -d; echo
```

```bash
# [k8s-cp01 · root]
kubectl --kubeconfig /etc/kubernetes/admin.conf -n kube-system exec etcd-k8s-cp01 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
  get /registry/secrets/tienda/bd --print-value-only | grep -a -o 'Tienda.2026!'
```

```bash
# [ansible01 · adminlab]
kubectl -n tienda delete secret bd
```

Lo esperado: la contraseña en claro las dos veces. **Ampliación** (con el snapshot hecho): cifrado en reposo según la
fuente de arriba. Antes de editar `kube-apiserver.yaml`, cópialo **fuera** de `/etc/kubernetes/manifests/`.

⚠️ **Error común en el mercado: copias de etcd sin proteger.** Se programan copias de etcd (bien) y se dejan en un
NFS o un bucket con acceso amplio (mal): en ellas están, en claro, todas las contraseñas y tokens del clúster.
**Cómo evitarlo:** cifrado en reposo en el apiserver y las copias tratadas como secretos (cifradas y con acceso
mínimo).

### 8.6.5 SELinux en los contenedores

📘 **Concepto.** Con `enable_selinux = true` en containerd, cada contenedor corre como **`container_t` con categorías
MCS propias**, como el `:Z` de la 8.1.4: un pod comprometido no puede leer los ficheros de otro ni del nodo. Los
contenedores `privileged` corren como `spc_t` (sin confinamiento). Los volúmenes que el runtime no reetiqueta
(`hostPath`, directorios de local-path) necesitan la etiqueta `container_file_t` de forma persistente
(`semanage fcontext` + `restorecon`). En el pod, `securityContext.seLinuxOptions` permite fijar la etiqueta.

*Fuente:* [Configure a Security Context — SELinux](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#assign-selinux-labels-to-a-container) ·
[Red Hat — Using SELinux (RHEL 9)](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/using_selinux/index)

🛠️ **Práctica** (en `k8s-w02`).

```bash
# [ansible01 · adminlab]
kubectl drain k8s-w02 --ignore-daemonsets --delete-emptydir-data
```

```bash
# [k8s-w02 · root]
cp -a /etc/containerd/config.toml /etc/containerd/config.toml.antes-8.6
sed -i 's/enable_selinux = false/enable_selinux = true/' /etc/containerd/config.toml
grep -n 'enable_selinux' /etc/containerd/config.toml
systemctl restart containerd && systemctl is-active containerd
```

```bash
# [ansible01 · adminlab]
kubectl uncordon k8s-w02
kubectl -n demo scale deploy/podinfo --replicas=4
kubectl -n demo get pods -o wide
```

```bash
# [k8s-w02 · root]
ps -eZ | grep -E 'podinfo|calico-node' | grep -v grep
```

```bash
# [k8s-w01 · root]
ps -eZ | grep podinfo | grep -v grep
```

| Nodo | Qué esperas |
|---|---|
| `k8s-w02` | `podinfo` como `container_t:s0:cX,cY` (categorías distintas por pod); `calico-node` como `spc_t` |
| `k8s-w01` | El mismo contexto para todos los pods, heredado de containerd (normalmente `container_runtime_t`) |

**Qué se rompe:** un volumen de local-path en `k8s-w02`:

```bash
# [ansible01 · adminlab]
kubectl -n demo scale deploy/podinfo --replicas=2
sed -i '/^    spec:$/a\      nodeSelector: {kubernetes.io/hostname: k8s-w02}' ~/fechas-deploy.yaml
grep -n -B1 nodeSelector ~/fechas-deploy.yaml
kubectl apply -f ~/fechas-pvc.yaml -f ~/fechas-deploy.yaml
sleep 20; kubectl -n demo logs deploy/fechas --tail=3; kubectl -n demo get pods -l app.kubernetes.io/name=fechas
```

```bash
# [k8s-w02 · root]
timeout 20 ausearch -m AVC -ts recent | grep denied | tail -3
ls -dZ /var/lib/local-path /var/lib/local-path/*/
```

Se usa `nodeSelector` y no `nodeName`: con `nodeName` el pod se salta el scheduler y local-path (*WaitForFirstConsumer*)
nunca sabría dónde crear el volumen. Lo esperado (compruébalo, no lo supongas): `Permission denied` al escribir en
`/datos` y un AVC con `scontext=...container_t:s0:cX,cY` y la etiqueta del directorio que viste en la 8.5. Si **no**
falla, anota qué etiqueta tenía el directorio: también es un resultado.

```bash
# [k8s-w02 · root]
semanage fcontext -a -t container_file_t '/var/lib/local-path(/.*)?'
restorecon -Rv /var/lib/local-path
```

```bash
# [ansible01 · adminlab]
kubectl -n demo rollout restart deploy/fechas
sleep 20; kubectl -n demo exec deploy/fechas -- tail -2 /datos/fechas.log
kubectl delete -f ~/fechas-deploy.yaml -f ~/fechas-pvc.yaml
sed -i '/nodeSelector: {kubernetes.io\/hostname: k8s-w02}/d' ~/fechas-deploy.yaml
```

Si el AVC persiste por las categorías MCS, documéntalo: es la razón por la que los drivers de almacenamiento (CSI)
reetiquetan cada volumen al montarlo. Decide si `k8s-w02` se queda con `enable_selinux = true` o vuelve a la copia
`config.toml.antes-8.6` (con `drain`/`uncordon`), y **anótalo**: si los dos workers difieren, un fallo de volumen en
uno solo tiene aquí su explicación.

⚠️ **Error común en el mercado: SELinux desactivado en los nodos "porque Kubernetes no lo soporta".** Muchas guías lo
desactivan en el primer paso. Kubernetes y containerd funcionan con SELinux en *enforcing*; desactivarlo quita la
última barrera si un contenedor escapa de sus namespaces. **Cómo evitarlo:** SELinux en *enforcing*, `enable_selinux`
en el runtime y reglas `semanage fcontext` para las rutas de datos.

**Checklist:** filas 22-23.

---

## 8.7 Helm: charts, valores y releases

> 🎫 **Ticket APP-807.** "Necesitamos un servidor Git dentro del clúster para el proyecto de GitOps. Instaladlo desde
> su chart oficial, con la configuración versionada y pudiendo volver atrás si una actualización sale mal."

### 8.7.1 Charts, valores y releases

📘 **Concepto.** **Helm** es el gestor de paquetes de Kubernetes. Un **chart** es un conjunto de plantillas de
manifiestos con unos **valores** por defecto (`values.yaml`); al instalarlo con tus valores (`-f` o `--set`) se crea
una **release**, con un historial de **revisiones** (cada `upgrade` o `rollback` añade una). Helm guarda ese historial
en Secrets del namespace de la release. `helm template` renderiza los manifiestos **sin aplicarlos**; `helm show
values` enseña los valores del chart; `helm get values` los de la release. Una clave de valores que el chart no usa se
**ignora en silencio**.

*Fuente:* [Using Helm](https://helm.sh/docs/intro/using_helm/) ·
[Charts](https://helm.sh/docs/topics/charts/) ·
[helm template](https://helm.sh/docs/helm/helm_template/)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
helm list -A
helm -n metallb-system history metallb
helm -n metallb-system get values metallb
helm -n metallb-system get values metallb --all | head -15
helm template metallb metallb/metallb --version 0.16.1 | grep -E '^kind:' | sort | uniq -c
kubectl -n metallb-system get secrets -l owner=helm
```

Lo esperado: `metallb` y `traefik` `deployed`; una revisión; `null` en tus valores (no cambiaste nada) y todos los
efectivos con `--all`; el recuento de objetos que crea el chart (`Deployment`, `DaemonSet`, `ClusterRole`...) y un
Secret `sh.helm.release.v1.metallb.v1`.

⚠️ **Error común en el mercado: `helm install` sin `--version`.** La misma orden instala cada mes una versión distinta
del chart; en una reinstalación de emergencia aparece un cambio incompatible que nadie ha probado. **Cómo evitarlo:**
`--version` siempre (como en todo el lab) y la versión anotada junto al fichero de valores.

### 8.7.2 Gitea con Helm

🛠️ **Práctica.** El chart trae PostgreSQL y Valkey activados por defecto (varios GB de RAM); `apps/gitea-values.yaml`
los apaga y usa SQLite.

```bash
# [ansible01 · adminlab]
cd ~/enterprise-rhel-lab/scripts/stage8/files
kubectl create namespace gitea
kubectl label namespace gitea pod-security.kubernetes.io/enforce=baseline
GITEA_PW="$(openssl rand -base64 18)"; echo "Gitea gitea-admin: $GITEA_PW"
kubectl -n gitea create secret generic gitea-admin --from-literal=username=gitea-admin --from-literal=password="$GITEA_PW"
helm repo add gitea-charts https://dl.gitea.com/charts/ && helm repo update
helm search repo gitea-charts/gitea --versions | head -3
GITEA_CHART=<versión-de-helm-search>
helm show values gitea-charts/gitea --version "$GITEA_CHART" > /tmp/gitea-defaults.yaml
diff <(grep -E '^[a-z]' /tmp/gitea-defaults.yaml | cut -d: -f1 | sort) <(grep -E '^[a-z]' apps/gitea-values.yaml | cut -d: -f1 | sort)
helm template gitea gitea-charts/gitea -n gitea --version "$GITEA_CHART" -f apps/gitea-values.yaml | grep -E '^kind:' | sort | uniq -c
helm install gitea gitea-charts/gitea -n gitea --version "$GITEA_CHART" -f apps/gitea-values.yaml --wait --timeout 10m
kubectl -n gitea get pods,pvc,svc
```

| Paso | Qué esperas | Si sale otra cosa |
|---|---|---|
| `echo "Gitea ..."` | La contraseña: guárdala **ya** en tu gestor | Recuperarla: `kubectl -n gitea get secret gitea-admin -o jsonpath='{.data.password}' \| base64 -d` |
| `diff` de claves | Las líneas `>` (las nuestras) existen también en los valores del chart | Una clave nuestra que no existe en el chart se ignoraría en silencio |
| `helm template \| uniq -c` | Un `Deployment`, Services, un PVC; **ningún** StatefulSet de PostgreSQL o Valkey | Si salen, los subcharts cambiaron de nombre: revisa `/tmp/gitea-defaults.yaml` |
| `get pods,pvc,svc` | Pod `Running`, PVC `Bound` 5Gi en `local-path`, `gitea-http` con `EXTERNAL-IP 10.10.10.115` | PVC `Pending` → StorageClass por defecto (8.5) |

Entra en http://gitea.lab.local con `gitea-admin`, crea la organización `lab` y el repositorio **público** `k8s-apps`
(con un README, para que exista la rama `main`). Lo usa la 8.11.

### 8.7.3 `upgrade`, `history` y `rollback`

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
helm -n gitea upgrade gitea gitea-charts/gitea --version "$GITEA_CHART" -f apps/gitea-values.yaml \
  --set resources.limits.memory=768Mi --wait
helm -n gitea history gitea
kubectl -n gitea get deploy gitea -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}'; echo
helm -n gitea rollback gitea 1 --wait
helm -n gitea history gitea
kubectl -n gitea get deploy gitea -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}'; echo
```

Lo esperado: `REVISION: 2` con `768Mi`; tras el rollback, una **revisión 3** (`Rollback to 1`, el rollback no borra
historia) y `512Mi`, el valor del fichero.

⚠️ **Error común en el mercado: cambios con `--set` que se pierden.** En una incidencia se hace `helm upgrade ... --set
replicas=5` y funciona; semanas después, otro `helm upgrade -f values.yaml` (sin el `--set`) lo deshace sin que nadie
lo note, y la incidencia vuelve. **Cómo evitarlo:** todo cambio va al fichero de valores versionado; `helm get values`
para ver lo que tiene la release antes de un `upgrade`.

**Checklist:** fila 24.

---

## 8.8 Monitorización con Prometheus y Grafana

> 🎫 **Ticket OBS-808.** "Montad la monitorización del clúster y de los servidores del lab: métricas, paneles para los
> equipos y alertas que despierten a la guardia **solo** cuando el usuario note algo. Después, ensayad las averías más
> frecuentes para que la guardia sepa reconocerlas."

**Requisitos:** 8.2, 8.4 (MetalLB y NetworkPolicies), 8.5 (local-path) y 8.7 (Helm). Ficheros en
`scripts/stage8/files/monitoring/`. La guía [monitorizacion-prometheus-grafana.md](monitorizacion-prometheus-grafana.md)
tiene los mismos escenarios en formato de consulta rápida.

### 8.8.1 Cómo funciona Prometheus

📘 **Concepto.** Prometheus **tira** (*pull*): cada `scrape_interval` pide `/metrics` por HTTP a cada **objetivo**
(*target*) y guarda **series temporales** (nombre de métrica + etiquetas → valores con marca de tiempo) en su propia
base de datos. Lo que no expone métricas se traduce con un **exporter**: `node-exporter` (el sistema operativo),
`kube-state-metrics` (el estado de los objetos de Kubernetes) y el kubelet/cAdvisor (CPU y memoria de cada
contenedor). Tipos de métrica: **counter** (solo sube: peticiones, errores), **gauge** (sube y baja: memoria en uso) e
**histogram** (cuenta observaciones en *buckets*: latencias). `up` vale 1 si el último *scrape* de un objetivo
funcionó y 0 si no. Grafana **no guarda** métricas: consulta a Prometheus y dibuja.

*Fuente:* [Prometheus — Overview](https://prometheus.io/docs/introduction/overview/) ·
[Metric types](https://prometheus.io/docs/concepts/metric_types/) ·
[Jobs and instances](https://prometheus.io/docs/concepts/jobs_instances/)

**PromQL** — el lenguaje de consulta:

```promql
up                                                   # 1 = el objetivo responde, 0 = caído
rate(http_requests_total{namespace="demo"}[5m])      # contador -> peticiones por segundo (media de 5 min)
sum by (status) (rate(http_requests_total[5m]))      # agregar por una etiqueta
container_memory_working_set_bytes{namespace="demo"} # gauge, tal cual
histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))   # p95 de latencia
```

Regla: **counters con `rate()`**, **gauges tal cual**, **histogramas con `histogram_quantile()`**.

*Fuente:* [Querying basics](https://prometheus.io/docs/prometheus/latest/querying/basics/) ·
[Functions](https://prometheus.io/docs/prometheus/latest/querying/functions/) ·
[Histograms and summaries](https://prometheus.io/docs/practices/histograms/)

### 8.8.2 El Operator, las reglas y Alertmanager

📘 **Concepto.** **kube-prometheus-stack** instala el **Prometheus Operator** y lo que gestiona: Prometheus,
Alertmanager, Grafana, node-exporter y kube-state-metrics, con ~150 reglas y ~25 dashboards de serie. El Operator
convierte objetos de Kubernetes en configuración: un **ServiceMonitor** dice qué Services rascar y por qué puerto; un
**PrometheusRule** contiene reglas. El Prometheus del chart **solo** carga los ServiceMonitor y PrometheusRule con la
etiqueta `release: kube-prometheus-stack`. Hay dos tipos de reglas: **recording** (precalculan una consulta como serie
nueva) y **alerting** (consulta + umbral + `for:`, el tiempo que debe cumplirse antes de disparar: `pending` →
`firing`). **Alertmanager** recibe las alertas y las **agrupa** (`group_by`), las **enruta** a receptores
(`routes`), las **inhibe** (una *critical* tapa a su *warning*) y respeta **silencios**. La alerta `Watchdog` está
**siempre** disparada: si deja de llegar, el sistema de alertas está roto.

*Fuente:* [Prometheus Operator — Getting started](https://prometheus-operator.dev/docs/getting-started/introduction/) ·
[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) ·
[Recording rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/) ·
[Alerting rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/) ·
[Alertmanager](https://prometheus.io/docs/alerting/latest/alertmanager/)

🛠️ **Práctica: instalación.**

```bash
# [ansible01 · adminlab]
cd ~/enterprise-rhel-lab/scripts/stage8/files/monitoring
kubectl create namespace monitoring
kubectl label namespace monitoring pod-security.kubernetes.io/enforce=privileged
GPW="$(openssl rand -base64 18)"; echo "Grafana admin: $GPW"
kubectl -n monitoring create secret generic grafana-admin --from-literal=admin-user=admin --from-literal=admin-password="$GPW"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
less kube-prometheus-stack-values.yaml
helm template kube-prometheus-stack prometheus-community/kube-prometheus-stack --version 88.6.2 \
  -n monitoring -f kube-prometheus-stack-values.yaml | grep -E '^kind:' | sort | uniq -c
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version 88.6.2 -n monitoring -f kube-prometheus-stack-values.yaml --wait --timeout 15m
kubectl -n monitoring get pods -o wide
kubectl -n monitoring get svc | grep LoadBalancer
kubectl -n monitoring get pvc
```

| Paso | Qué esperas | Si sale otra cosa |
|---|---|---|
| `label ... privileged` | node-exporter usa `hostNetwork` y `hostPID` | Sin ella, los pods de node-exporter se rechazan |
| Contraseña de Grafana | Aleatoria, en un Secret (`existingSecret` en los valores) | Guárdala: `kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' \| base64 -d` |
| `helm template \| uniq -c` | CRDs no salen (van aparte); `Prometheus`, `Alertmanager`, `ServiceMonitor`, `PrometheusRule`, Deployments y un DaemonSet | — |
| `helm install --wait` | `STATUS: deployed` en 5-10 minutos | Timeout → `kubectl -n monitoring get pods` y `describe` del que no arranque |
| `get pods` | operator, `prometheus-kps-prometheus-0`, `alertmanager-kps-alertmanager-0`, grafana, kube-state-metrics y 3 node-exporter | — |
| `get svc` | `.111` grafana, `.112` prometheus, `.113` alertmanager | `<pending>` → pool de MetalLB |
| `get pvc` | El de Prometheus `Bound`, 5Gi (retención: 7 días o 3 GB, lo que llegue antes) | — |

```bash
# [ansible01 · adminlab]
kubectl apply -f alertmanager/alert-receiver.yaml
kubectl apply -f servicemonitor-podinfo.yaml
kubectl apply -f rules/podinfo-slo.yaml -f rules/lab-vms.yaml
kubectl apply -f dashboards/podinfo-red.yaml
kubectl apply -f ../apps/loadgen.yaml
kubectl get servicemonitor,prometheusrule -A | grep -v kps
kubectl -n monitoring logs -f deploy/alert-receiver          # deja esta terminal abierta: es la "guardia"
```

| Fichero | Qué es |
|---|---|
| `alertmanager/alert-receiver.yaml` | El "móvil de guardia": un webhook que imprime las alertas en su log |
| `servicemonitor-podinfo.yaml` | Que Prometheus rasque podinfo cada 15 s por el puerto `http` |
| `rules/podinfo-slo.yaml` | Reglas RED de podinfo: tráfico, % de errores y p95, y sus alertas |
| `rules/lab-vms.yaml` | Alertas de las VMs de fuera del clúster (E12) y de disco de los nodos (E10) |
| `dashboards/podinfo-red.yaml` | Un dashboard como código: un ConfigMap con la etiqueta `grafana_dashboard: "1"` que carga el sidecar de Grafana |

**Comprobación inicial:**

- http://prometheus.lab.local → *Status → Targets*: todo `UP` (si algo está `DOWN`, es el E00).
- *Alerts*: solo `Watchdog` disparada.
- http://grafana.lab.local (usuario `admin`, contraseña `$GPW`) → *Dashboards*: los de serie y **Lab · podinfo (RED)**.
- `promtool test rules tests/podinfo-slo.test.yaml` (si ya tienes `promtool`, 8.11.1): `SUCCESS`. Las alertas también
  se prueban sin clúster.

⚠️ **Error común en el mercado: alertar por causas en vez de por síntomas.** Alertas de "CPU al 80 %", "un pod se ha
reiniciado" o "memoria del nodo al 70 %" que despiertan a la guardia por la noche sin que ningún usuario note nada.
En semanas, la guardia ignora las alertas (*alert fatigue*) y se pierde la que importaba. **Cómo evitarlo:** las
alertas que despiertan, sobre lo que nota el usuario (errores, latencia, servicio caído) y con `for:`; las causas, en
paneles o como *warning* en horario laboral.

### 8.8.3 Escenarios de guardia

Cada escenario es un ticket de guardia. Al terminar cada uno, limpia para no mezclar alertas:

```bash
# [ansible01 · adminlab]  (en ~/enterprise-rhel-lab/scripts/stage8/files/monitoring)
kubectl -n demo delete deploy,svc,servicemonitor,networkpolicy -l lab/escenario
kubectl -n demo set env deploy/loadgen PATHS="/"
```

Anota en el checklist (filas 25-40), de cada uno: cuánto tardó la alerta, la consulta PromQL que lo demuestra y el
comando que dio la causa.

#### E00 — Falsas alarmas del plano de control

> 🎫 "Recién instalado y ya salen `KubeControllerManagerDown`, `KubeSchedulerDown` o alertas de etcd."

📘 kubeadm deja esas métricas en `127.0.0.1` por defecto; `kubeadm-config.yaml` ya las saca a `0.0.0.0` y firewalld
las abre solo al lab. Si salen, el clúster se creó sin ese fichero o falta un puerto.

```bash
# [k8s-cp01 · root]
ss -ltnp | grep -E ':(10257|10259|2381|10249) '
firewall-cmd --zone=k8s --list-ports
grep -n bind-address /etc/kubernetes/manifests/kube-*.yaml
```

Lo esperado: los cuatro puertos en `0.0.0.0` o `*`, y abiertos en la zona `k8s`. Arreglo: editar el manifiesto
estático (el kubelet reinicia el pod solo) o abrir el puerto.

⚠️ **Error común:** silenciar para siempre las alertas del plano de control "porque son falsas". El día que el
scheduler cae de verdad, nadie se entera. Se arregla la causa (métricas y puertos), no la alerta.

#### E01 — CrashLoopBackOff

> 🎫 "El servicio no levanta tras el despliegue de esta mañana."

📘 Un contenedor que termina con error se reinicia con espera creciente (*back-off*): estado `CrashLoopBackOff`. El
log del intento fallido es el del contenedor **anterior**: `kubectl logs --previous`.

*Fuente:* [Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/) ·
[Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)

```bash
# [ansible01 · adminlab]
kubectl apply -f scenarios/e01-crashloop.yaml
kubectl -n demo get pods -l app.kubernetes.io/name=e01-crash -w          # Error -> CrashLoopBackOff; Ctrl+C
kubectl -n demo describe pod -l app.kubernetes.io/name=e01-crash | sed -n '/Last State/,/Ready/p'
kubectl -n demo logs deploy/e01-crash --previous
```

Prometheus: `kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} == 1` y
`increase(kube_pod_container_status_restarts_total{namespace="demo"}[10m]) > 0`. La alerta de serie
`KubePodCrashLooping` tiene `for: 15m`: mientras tanto, está *Pending*. Causa en el log: `unknown flag: --puerto`.
Arreglo: el parámetro correcto (`--port`) o `kubectl rollout undo`.

⚠️ **Error común:** mirar `kubectl logs` sin `--previous` y ver solo el arranque en curso (vacío o a medias), y
concluir que "no hay errores".

#### E02 — OOMKilled

> 🎫 "La aplicación se reinicia sola cada pocos minutos, sin errores en el log."

📘 `requests` es lo que el scheduler **reserva** para planificar; `limits.memory` es el **techo**: si el contenedor lo
supera, el kernel lo mata (OOM killer) con código **137** (128 + SIGKILL 9), motivo `OOMKilled`.

*Fuente:* [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

```bash
# [ansible01 · adminlab]
kubectl apply -f scenarios/e02-oomkill.yaml
kubectl -n demo get pod -l app.kubernetes.io/name=e02-memoria -w          # Ctrl+C tras un par de reinicios
kubectl -n demo describe pod -l app.kubernetes.io/name=e02-memoria | grep -A4 'Last State'
```

Lo esperado: `Reason: OOMKilled`, `Exit Code: 137`. Prometheus:
`kube_pod_container_status_last_terminated_reason{reason="OOMKilled"} == 1` y
`container_memory_working_set_bytes{namespace="demo",container="app"}` subiendo hasta 128 Mi. Llega la alerta propia
`ContenedorOOMKilled` a la guardia.

⚠️ **Error común:** subir el límite de memoria cada vez que hay un OOMKilled. Si es una fuga de memoria, ningún límite
la arregla: solo retrasa el siguiente reinicio. Hay que mirar la tendencia de memoria antes de decidir.

#### E03 — CPU throttling

> 🎫 "La API va lenta, la CPU del nodo está al 20 % y no hay errores."

📘 `limits.cpu` se aplica con el CFS del kernel: en cada periodo, si el contenedor gasta su cuota, se le **para**
hasta el siguiente (*throttling*), aunque el nodo tenga CPU libre.

```bash
# [ansible01 · adminlab]
kubectl apply -f scenarios/e03-cpu-throttling.yaml
```

```promql
sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{namespace="demo"}[5m]))
  / sum by (pod) (rate(container_cpu_cfs_periods_total{namespace="demo"}[5m]))
```

La alerta `CPUThrottlingHigh` es *info*: aparece en *Alerts*, pero la ruta de Alertmanager solo envía *warning* y
*critical* a la guardia, a propósito.

⚠️ **Error común:** límites de CPU muy bajos "por si acaso" en todas las aplicaciones. Se pagan en latencia sin que
ningún panel de CPU del nodo lo muestre. Muchas organizaciones dejan `requests` de CPU y quitan el `limit`.

#### E04 — Errores 5xx y el método RED

> 🎫 "Los clientes ven errores intermitentes."

📘 **RED**: *Rate* (tráfico), *Errors* (errores), *Duration* (latencia), las tres señales de un servicio. Se alerta
sobre el **ratio** de errores (lo que nota el usuario), no sobre el número absoluto, y con `for:` para no despertar a
nadie por un error suelto.

*Fuente:* [Prometheus — Alerting (buenas prácticas)](https://prometheus.io/docs/practices/alerting/)

```bash
# [ansible01 · adminlab]
kubectl -n demo set env deploy/loadgen PATHS="/ /status/500 /status/503"
```

```promql
podinfo:http_errors:ratio_rate5m
sum by (status) (rate(http_requests_total{namespace="demo"}[1m]))
```

Lo esperado: en Grafana (**Lab · podinfo (RED)**), el % de errores cruza el 5 % y, a los ~2 minutos,
`FIRING critical PodinfoErroresAltos` en la guardia; con `PATHS="/"`, `RESOLVED`.

⚠️ **Error común:** alertar con `http_requests_total{status="500"} > 0` (el contador, sin `rate`): la alerta se queda
disparada para siempre después del primer error, porque un contador nunca baja.

#### E05 — Latencia: percentiles, no medias

> 🎫 "Algunos usuarios dicen que va muy lento; el panel de latencia media está bien."

```bash
# [ansible01 · adminlab]
kubectl -n demo set env deploy/loadgen PATHS="/ / / /delay/2"
```

```promql
histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{namespace="demo"}[5m])))
sum(rate(http_request_duration_seconds_sum{namespace="demo"}[5m])) / sum(rate(http_request_duration_seconds_count{namespace="demo"}[5m]))
```

Lo esperado: el p95 y el p99 suben a ~2 s (1 de cada 4 peticiones es lenta), la media sube mucho menos y salta
`PodinfoLatenciaAlta` (*warning*).

⚠️ **Error común:** SLOs y paneles con la latencia **media**: esconden a los usuarios lentos. Los SLOs de latencia se
escriben con percentiles.

#### E06 — Vivo pero no listo (readiness)

> 🎫 "Una réplica no recibe tráfico, pero está `Running`."

📘 La *livenessProbe* **reinicia** el contenedor si falla; la *readinessProbe* lo **saca del balanceo** sin reiniciarlo.

*Fuente:* [Liveness, Readiness, and Startup Probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/)

```bash
# [ansible01 · adminlab]
POD=$(kubectl -n demo get pod -l app.kubernetes.io/name=podinfo -o name | head -1)
kubectl -n demo exec "$POD" -- curl -s -X POST http://localhost:9898/readyz/disable
kubectl -n demo get pods -l app.kubernetes.io/name=podinfo
kubectl -n demo get endpointslices -l kubernetes.io/service-name=podinfo -o wide
kubectl -n demo exec "$POD" -- curl -s -X POST http://localhost:9898/readyz/enable
```

Lo esperado: `READY 0/1` con `STATUS Running`, una sola IP en los EndpointSlices, y
`kube_pod_status_ready{namespace="demo",condition="false"} == 1`.

⚠️ **Error común:** la misma comprobación para *liveness* y *readiness*, que además depende de la base de datos: si la
base de datos va lenta, Kubernetes **reinicia** todas las réplicas a la vez y convierte una lentitud en una caída.

#### E07 — Se cae un nodo

> 🎫 "Ha caído un servidor físico."

📘 El kubelet informa cada pocos segundos; sin noticias, el nodo pasa a `NotReady`/`Unknown` y recibe el *taint*
`node.kubernetes.io/unreachable`. Los pods lo toleran 300 s (`tolerationSeconds`) y después se desalojan y se recrean
en otro nodo. Un pod con un PV local atado a ese nodo **no** puede moverse.

*Fuente:* [Nodes — Node status](https://kubernetes.io/docs/concepts/architecture/nodes/#node-status) ·
[Taint based Evictions](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/#taint-based-evictions)

```bash
# [host]
virsh shutdown k8s-w02        # para un fallo "duro": virsh destroy k8s-w02
```

```bash
# [ansible01 · adminlab]
kubectl get nodes -w                                  # anota la hora de NotReady; Ctrl+C
kubectl describe node k8s-w02 | sed -n '/Conditions/,/Addresses/p'
kubectl -n demo get pods -o wide -w                   # a los ~5 min, recreados en k8s-w01; Ctrl+C
```

Lo esperado: `NotReady` a los ~40 s; `up{job="node-exporter"} == 0` para ese nodo; `TargetDown` y, a los 15 min,
`KubeNodeNotReady`. Vuelta atrás: `virsh start k8s-w02`. Documenta la línea temporal real.

⚠️ **Error común:** aplicaciones con una sola réplica "porque es un entorno pequeño", o con todas las réplicas en el
mismo nodo: la caída de un nodo es un corte de varios minutos. Dos réplicas como mínimo y
`topologySpreadConstraints` o *anti-affinity* para repartirlas.

#### E08 — Prometheus no ve una aplicación nueva

> 🎫 "Hemos desplegado el catálogo y en Grafana no sale nada."

📘 El método vale para cualquier "no veo métricas": (1) ¿la app expone `/metrics`?, (2) ¿Prometheus tiene el
objetivo?, (3) ¿el ServiceMonitor tiene la etiqueta que selecciona el Prometheus?, (4) ¿coincide el **nombre del
puerto**?, (5) ¿lo bloquea una NetworkPolicy?

*Fuente:* [Prometheus Operator — Troubleshooting ServiceMonitor changes](https://prometheus-operator.dev/docs/platform/troubleshooting/)

```bash
# [ansible01 · adminlab]
kubectl apply -f scenarios/e08-servicemonitor-ignorado.yaml
kubectl -n demo exec deploy/catalogo -- curl -s localhost:9898/metrics | grep -m2 http_requests_total
kubectl -n monitoring get prometheus kps-prometheus -o jsonpath='{.spec.serviceMonitorSelector}'; echo
kubectl -n demo label servicemonitor catalogo release=kube-prometheus-stack
kubectl -n demo get svc catalogo -o jsonpath='{.spec.ports[*].name}'; echo
kubectl -n demo patch servicemonitor catalogo --type=json -p '[{"op":"replace","path":"/spec/endpoints/0/port","value":"http"}]'
kubectl -n demo get networkpolicy
kubectl apply -f scenarios/e08-solucion-networkpolicy.yaml
```

| Fallo | Cómo se ve | Arreglo |
|---|---|---|
| 1. Falta la etiqueta | No aparece en *Status → Targets* | `release=kube-prometheus-stack` |
| 2. Puerto mal nombrado | En *Service Discovery*, 0 objetivos activos | El ServiceMonitor pide `metrics`; el Service lo llama `http` |
| 3. NetworkPolicy | `DOWN` con `context deadline exceeded` y `TargetDown` | Abrir `monitoring` → `catalogo:9898` |

A los ~30 s, `UP`. Limpieza: `kubectl delete -f scenarios/e08-solucion-networkpolicy.yaml -f
scenarios/e08-servicemonitor-ignorado.yaml`.

⚠️ **Error común:** dar por buena una aplicación porque "funciona", sin comprobar que aparece en *Targets*. El día de
la incidencia no hay métricas de ella.

#### E09 — Imagen que no existe

> 🎫 "El despliegue de la versión nueva no termina."

```bash
# [ansible01 · adminlab]
kubectl apply -f scenarios/e09-imagen-inexistente.yaml
kubectl -n demo get pods -l app.kubernetes.io/name=e09-version
kubectl -n demo describe pod -l app.kubernetes.io/name=e09-version | tail -5
```

Lo esperado: `ErrImagePull` → `ImagePullBackOff`, y en los eventos `manifest unknown`. Si fuera la actualización de un
Deployment existente, el *rollout* se queda a medias y las réplicas viejas siguen sirviendo: `rollout status` y
`rollout undo`.

⚠️ **Error común:** `imagePullPolicy: Always` con `latest` y un registro caído: cualquier reinicio de pod falla,
incluidos los de versiones que funcionaban.

#### E10 — Disco del nodo lleno

> 🎫 "Los pods del nodo 1 desaparecen y aparecen como `Evicted`."

📘 Por debajo de los umbrales de `nodefs`/`imagefs` (`evictionHard`), el kubelet marca `DiskPressure`, limpia imágenes
y **desaloja pods**.

*Fuente:* [Node-pressure Eviction](https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/)

```bash
# [k8s-w01 · root]
df -h /var/lib/kubelet
fallocate -l 5G /var/lib/kubelet/relleno-e10.img          # ajústalo para dejar < 10 % libre; fallocate reserva
                                                          # bloques sin escribir datos: el qcow2 del host no crece
df -h /var/lib/kubelet
```

```bash
# [ansible01 · adminlab]
kubectl describe node k8s-w01 | grep -A2 DiskPressure
kubectl get pods -A | grep -i evicted
```

Lo esperado: `NodoK8sDiscoCasiLleno` (regla del lab, 2 min), `DiskPressure True` y pods desalojados. Vuelta atrás:
`rm /var/lib/kubelet/relleno-e10.img` y `kubectl delete pod -A --field-selector=status.phase=Failed`.

⚠️ **Error común:** no tener alerta de disco **antes** del umbral del kubelet: la primera señal es la cascada de
desalojos.

#### E11 — Ventana de mantenimiento: silencios, agrupación e inhibición

> 🎫 "Mañana a las 10:00 se reinicia `k8s-w02` por parches: que no salte la guardia."

1. Alertmanager (http://alertmanager.lab.local) → *New Silence*: `node="k8s-w02"`, 30 min, con el número de cambio en
   el comentario. Repite el E07: la guardia no recibe nada; en *Alerts* siguen visibles, silenciadas.
2. Agrupación: E04 y E05 a la vez llegan como pocos mensajes (`group_by: [alertname, namespace]`).
3. Inhibición: una *critical* y una *warning* del mismo `alertname`/`namespace` → solo llega la *critical*.
4. Por CLI: `kubectl -n monitoring exec sts/alertmanager-kps-alertmanager -- amtool silence query --alertmanager.url=http://localhost:9093`

⚠️ **Error común:** silencios sin fecha de fin o demasiado amplios (`severity=~".+"`), creados en una ventana y nunca
borrados: semanas después, una avería real no llega a nadie.

#### E12 — Las VMs de fuera del clúster

> 🎫 "Queremos las mismas alertas para `dns01`, que no está en Kubernetes."

```bash
# [dns01 · root]
curl -sSLO https://github.com/prometheus/node_exporter/releases/download/v1.12.1/node_exporter-1.12.1.linux-amd64.tar.gz
curl -sSL https://github.com/prometheus/node_exporter/releases/download/v1.12.1/sha256sums.txt | grep linux-amd64.tar.gz | sha256sum -c
tar xzf node_exporter-1.12.1.linux-amd64.tar.gz && install -m 0755 node_exporter-1.12.1.linux-amd64/node_exporter /usr/local/bin/
useradd --system --no-create-home --shell /sbin/nologin node_exporter
cat > /etc/systemd/system/node_exporter.service <<'EOF'
[Unit]
Description=Prometheus node_exporter
After=network-online.target
[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter --collector.systemd --collector.systemd.unit-include=(named|chronyd|sshd)\.service
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
restorecon -v /usr/local/bin/node_exporter && systemctl daemon-reload && systemctl enable --now node_exporter
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.10.10.0/24" port port="9100" protocol="tcp" accept' && firewall-cmd --reload
curl -s localhost:9100/metrics | grep -m1 node_systemd_unit_state
```

El job `lab-vms` ya está en los valores del chart. Comprueba `up{job="lab-vms"}` y después `systemctl stop named` en
`dns01` → `DNSdelLabParado` (1 min); `systemctl start named` → `RESOLVED`.

*Fuente:* [node_exporter](https://github.com/prometheus/node_exporter)

⚠️ **Error común:** exporters escuchando en `0.0.0.0` sin firewall: las métricas del sistema (procesos, montajes,
servicios) quedan abiertas a toda la red. La regla `rich-rule` de arriba solo deja entrar al lab.

### 8.8.4 Grafana

📘 **Concepto.** Grafana consulta **fuentes de datos** (aquí, Prometheus) y dibuja **paneles** agrupados en
**dashboards**; las **variables** (`$namespace`) hacen un dashboard reutilizable. En kube-prometheus-stack, un
*sidecar* carga como dashboard cualquier ConfigMap con la etiqueta `grafana_dashboard: "1"`: es **dashboards como
código**, y lo que se cambia en la web sin guardarlo en el ConfigMap se pierde.

*Fuente:* [Grafana — Dashboards](https://grafana.com/docs/grafana/latest/dashboards/) ·
[Variables](https://grafana.com/docs/grafana/latest/dashboards/variables/) ·
[Provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)

🛠️ **Práctica.**

1. *Explore* → Prometheus → las consultas de 8.8.1, cambiando el rango de tiempo.
2. Dashboards de serie: "Kubernetes / Compute Resources / Namespace (Pods)" (`demo`) y "Node Exporter / Nodes": busca
   en ellos E02, E03 y E07.
3. *Dashboards → New → Import* → ID **1860** (*Node Exporter Full*).
4. En `dashboards/podinfo-red.yaml`, añade un panel "pods no listos" con
   `sum(kube_pod_status_ready{namespace="demo",condition="false"})`, `kubectl apply` y recarga: persiste.
5. Una variable `namespace` (`label_values(kube_pod_info, namespace)`) usada en las consultas.
6. *Administration → Users*: un usuario con rol *Viewer* para el equipo de la aplicación.

⚠️ **Error común en el mercado: Grafana con `admin/admin` o `admin/prom-operator`.** Las contraseñas por defecto de
la imagen o del chart, expuestas por un LoadBalancer: cualquiera de la red ve (y cambia) todos los paneles y fuentes
de datos. **Cómo evitarlo:** contraseña en un Secret (`existingSecret`, como aquí), usuarios con rol *Viewer* y, en
empresa, SSO.

**Antes de la 8.9:** snapshot `*-antes-8.9`.

---

## 8.9 Infraestructura como código con Terraform

> 🎫 **Ticket IAC-809.** "La plataforma se montó a mano y nadie sabe exactamente qué hay. Pasadla a código sin cortar
> el servicio: namespaces con cuotas, MetalLB y la monitorización, y un módulo para que los equipos publiquen
> aplicaciones monitorizadas siempre igual."

**Requisitos:** 8.4 (MetalLB y su pool), 8.6 (namespace `tienda`) y 8.8 (kube-prometheus-stack y el Secret
`grafana-admin`), instalados a mano tal como dicen esas subetapas. Código en `scripts/stage8/files/terraform/`. La guía
[terraform-iac.md](terraform-iac.md) tiene los mismos escenarios en formato de consulta rápida.

### 8.9.1 Terraform: declarativo, providers y estado

📘 **Concepto.** Terraform es **declarativo**: describes el estado final en ficheros `.tf` (HCL) y Terraform calcula
los pasos. Los **providers** traducen recursos a llamadas de una API (aquí, `hashicorp/kubernetes` y `hashicorp/helm`);
se fijan con restricciones de versión (`~> 3.4`) y el fichero **`.terraform.lock.hcl`** guarda las versiones exactas y
sus *hashes* (va a Git). El **estado** (`tfstate`) es lo que Terraform cree que existe y su correspondencia con el
código; puede contener secretos en claro y **no** va a Git. Un **backend** remoto guarda el estado fuera de tu equipo
y, si lo admite, lo **bloquea** durante cada operación; el backend `kubernetes` lo guarda en un Secret y bloquea con un
Lease. Flujo: `init` (providers y backend) → `plan` (diferencia entre código, estado y realidad) → `apply`.

*Fuente:* [What is Terraform?](https://developer.hashicorp.com/terraform/intro) ·
[State](https://developer.hashicorp.com/terraform/language/state) ·
[Backend kubernetes](https://developer.hashicorp.com/terraform/language/backend/kubernetes) ·
[Dependency lock file](https://developer.hashicorp.com/terraform/language/files/dependency-lock) ·
[Kubernetes provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs)

| Capa del lab | Qué gestiona | Estado |
|---|---|---|
| `10-plataforma/` | Namespaces con cuotas, Secret de Grafana, MetalLB y kube-prometheus-stack (`helm_release`) | `tfstate-default-plataforma` |
| `20-config/` | Pool de MetalLB y aplicaciones con el módulo (usan CRDs de la capa 10) | `tfstate-default-config` |
| `modules/app-monitorizada/` | Deployment + Service + ServiceMonitor + PrometheusRule | — |

**Terraform frente a Ansible:** Terraform **crea y destruye recursos** con un estado; Ansible **configura máquinas**
de forma idempotente sin estado. **OpenTofu** es la bifurcación abierta (MPL) de Terraform: mismos ficheros, comando
`tofu`.

🛠️ **Práctica: preparación.**

```bash
# [ansible01 · adminlab]
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo dnf install -y terraform
terraform version
kubectl create namespace tfstate
cp -r ~/enterprise-rhel-lab/scripts/stage8/files/terraform ~/terraform-lab && cd ~/terraform-lab
ls 10-plataforma 20-config
```

Lo esperado: `Terraform v1.16.x`; el namespace `tfstate` (el backend no lo crea); y los `.tf` de las dos capas.

⚠️ **Error común en el mercado: el `terraform.tfstate` en Git.** Se sube el estado al repositorio "para compartirlo":
contiene contraseñas en claro, y dos personas trabajando con copias distintas del estado acaban destruyendo recursos
que el otro creó. **Cómo evitarlo:** backend remoto con bloqueo, `*.tfstate*` en `.gitignore`, y el `.lock.hcl` sí en
Git.

### 8.9.2 T1 — `init` y `plan`: leer antes de tocar

📘 **Concepto.** `terraform plan` no cambia nada: compara y muestra `+` crear, `~` cambiar, `-` destruir y `-/+`
**destruir y recrear** (corte de servicio). `terraform validate` comprueba la sintaxis y las referencias; `terraform
fmt -check` el formato. Las variables sensibles se pasan por entorno (`TF_VAR_<nombre>`), nunca en ficheros del repo.

*Fuente:* [terraform plan](https://developer.hashicorp.com/terraform/cli/commands/plan) ·
[Input variables](https://developer.hashicorp.com/terraform/language/values/variables)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
cd ~/terraform-lab/10-plataforma
export TF_VAR_grafana_admin_password="$(kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)"
terraform init
terraform fmt -check -recursive && terraform validate
terraform plan -var-file=lab.tfvars
```

| Paso | Qué esperas | Si sale otra cosa |
|---|---|---|
| `init` | Descarga los providers, `Successfully configured the backend "kubernetes"`, crea `.terraform.lock.hcl` | `namespaces "tfstate" not found` → falta el `create namespace` |
| `fmt` / `validate` | Sin salida / `Success!` | — |
| `plan` | Quiere **crear** `monitoring`, `metallb-system`, `demo`, `tienda`, el Secret y las dos releases... que ya existen | `Kubernetes cluster unreachable` → kubeconfig o `kube_context` |

**No apliques:** fallaría con `already exists` o `cannot re-use a name that is still in use`.

⚠️ **Error común en el mercado: `terraform apply -auto-approve` sin leer el plan.** En un pipeline o "porque el
cambio era pequeño": un `-/+` escondido entre 40 líneas recrea una base de datos o un balanceador. **Cómo evitarlo:**
`plan -out=plan.tfplan`, leer cada `-` y `-/+`, y `apply plan.tfplan` (se aplica exactamente lo revisado).

### 8.9.3 T2 — Adoptar lo hecho a mano con `import`

📘 **Concepto.** Los bloques `import { to = ... id = ... }` traen al estado un recurso que ya existe, sin recrearlo;
el `plan` dice `will be imported` y, si el código difiere de la realidad, también `will be updated in-place`. Así se
mete bajo código un entorno existente.

*Fuente:* [Import](https://developer.hashicorp.com/terraform/language/import)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]  (en ~/terraform-lab/10-plataforma)
vim imports.tf                                  # descomenta los bloques import
terraform plan -var-file=lab.tfvars -out=plan.tfplan
terraform apply plan.tfplan
vim imports.tf                                  # vuelve a comentarlos: ya están en el estado
terraform plan -var-file=lab.tfvars
terraform state list
kubectl -n tienda describe resourcequota
kubectl -n tfstate get secret,lease
```

| Paso | Qué esperas | Si sale otra cosa |
|---|---|---|
| `plan -out` | `Plan: 7 to import, 4 to add, N to change, 0 to destroy`. *add* = las ResourceQuota y LimitRange de `demo` y `tienda`; *change* = diferencias como etiquetas `managed-by` | **Cualquier** `-` o `-/+` → para y entiende por qué; corrige el **código**, no el clúster |
| `apply plan.tfplan` | `Apply complete!` | — |
| Segundo `plan` | `No changes. Your infrastructure matches the configuration.` | Cambios persistentes en un `helm_release` → valores que el chart normaliza: alinea el fichero |
| `describe resourcequota` | La cuota de `tienda` (10 pods, 1 CPU de límites) | — |
| `get secret,lease` | `tfstate-default-plataforma` y su Lease | — |

Si `TF_VAR_grafana_admin_password` no coincide con la del clúster, el plan la cambiaría: por eso se lee del Secret.

⚠️ **Error común en el mercado: "recrear" en vez de importar.** Para pasar a Terraform algo que ya existe, se borra y
se deja que Terraform lo cree de nuevo: corte de servicio y, si había datos (PVCs), pérdida. **Cómo evitarlo:**
`import` y `0 to destroy` como condición innegociable.

### 8.9.4 T3 — Módulos y `for_each`

📘 **Concepto.** Un **módulo** es un conjunto de recursos reutilizable con entradas (`variable`) y salidas (`output`).
`for_each` crea una instancia por elemento de un mapa (aquí, una app por entrada de `apps` en `lab.tfvars`). Las
**validaciones** de variables rechazan valores incorrectos antes del plan.

*Fuente:* [Modules](https://developer.hashicorp.com/terraform/language/modules) ·
[for_each](https://developer.hashicorp.com/terraform/language/meta-arguments/for_each) ·
[Custom validation rules](https://developer.hashicorp.com/terraform/language/values/variables#custom-validation-rules)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
cd ~/terraform-lab/20-config
terraform init
vim imports.tf                                  # descomenta: el pool de MetalLB se creó a mano en la 8.4
terraform plan -var-file=lab.tfvars
terraform apply -var-file=lab.tfvars
vim imports.tf                                  # vuelve a comentarlos
terraform output apps
curl -s http://10.10.10.117 | head -3
```

Lo esperado: `2 to import` y la app `tienda-web` (Deployment, Service, ServiceMonitor, regla); en Prometheus,
`serviceMonitor/tienda/tienda-web` y la regla `tienda-web.errores`, sin escribir YAML. Prueba: añade `tienda-api` en
`lab.tfvars` (solo crea lo nuevo), pon `imagen = "...:latest"` (lo rechaza la validación) y `replicas = 20` (la cuota
lo frena: `kubectl -n tienda get events | grep -i quota`).

⚠️ **Error común en el mercado: copiar y pegar en lugar de módulos.** Cada aplicación con su propio bloque de 200
líneas copiado de la anterior: cuando cambia el estándar (una etiqueta, una alerta), hay que tocar 30 sitios y siempre
se olvida alguno. **Cómo evitarlo:** un módulo con versiones, y las diferencias entre apps como variables.

### 8.9.5 T4 — *Drift*

📘 **Concepto.** Un cambio hecho fuera de Terraform (a mano, por otra herramienta) es ***drift***: el siguiente `plan`
lo muestra como diferencia, y `apply` lo revierte al código. Con IaC, el código es la fuente de verdad.

*Fuente:* [Manage resource drift](https://developer.hashicorp.com/terraform/tutorials/state/resource-drift)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]  (en ~/terraform-lab/20-config)
kubectl -n tienda scale deploy/tienda-web --replicas=5
kubectl -n tienda label deploy/tienda-web urgente=si
terraform plan -var-file=lab.tfvars
```

Lo esperado: `~ replicas: 5 -> 2` y la etiqueta. Decide: si el cambio era bueno, pásalo al **código**; si no, `apply`
lo revierte. Documenta la decisión.

⚠️ **Error común en el mercado: "arreglos" a mano en producción que el siguiente `apply` deshace.** En una incidencia
se escala o se cambia algo en la consola; días después, un `apply` rutinario lo revierte y la incidencia vuelve. **Cómo
evitarlo:** cada cambio de emergencia se pasa al código en cuanto pasa la emergencia, y `plan` periódicos para detectar
*drift*.

### 8.9.6 T5 — Bloqueo del estado

🛠️ **Práctica.** Abre **dos sesiones** en `ansible01`, en `~/terraform-lab/10-plataforma` (con el `export` de la
contraseña en las dos), y lanza `terraform apply -var-file=lab.tfvars` en las dos casi a la vez.

```bash
# [ansible01 · adminlab]  (tercera sesión)
kubectl -n tfstate get lease -o wide
```

Lo esperado: la segunda espera o falla con `Error acquiring the state lock`, y el Lease muestra el titular. Contesta
`no` en la primera.

⚠️ **Error común en el mercado: `terraform force-unlock` como reflejo.** Se fuerza el desbloqueo porque "se ha
quedado colgado", mientras el `apply` de un compañero sigue en marcha: el estado se corrompe. **Cómo evitarlo:**
`force-unlock <ID>` solo con la certeza de que el proceso que lo tenía ha muerto.

### 8.9.7 T6 — CRDs que aún no existen

📘 **Concepto.** `kubernetes_manifest` consulta el esquema del CRD **al planificar**: si el CRD no existe, el `plan`
falla con `no matches for kind`. Por eso un mismo `apply` no puede instalar un chart con CRDs y crear objetos de esos
CRDs: capas separadas (como el lab) o dos fases.

*Fuente:* [kubernetes_manifest](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]  (en ~/terraform-lab/20-config)
cat > t6-prueba.tf <<'EOF'
resource "kubernetes_manifest" "app_argocd" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = { name = "podinfo", namespace = "argocd" }
    spec       = { project = "default" }
  }
}
EOF
terraform plan -var-file=lab.tfvars
rm t6-prueba.tf
```

Lo esperado: el error **en el plan** (Argo CD llega en la 8.11).

⚠️ **Error común en el mercado: `-target` como forma de trabajar.** Para esquivar este error, se aplica siempre por
partes con `-target=...`; el estado deja de reflejar el conjunto y los cambios fuera del *target* se acumulan sin
revisar. **Cómo evitarlo:** capas con estados separados; `-target` solo en emergencias.

### 8.9.8 T7 — `prevent_destroy` y `moved`

📘 **Concepto.** `lifecycle { prevent_destroy = true }` hace que cualquier plan que destruya ese recurso **falle**. Un
bloque `moved { from = ...  to = ... }` renombra un recurso en el estado sin destruirlo.

*Fuente:* [lifecycle](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle) ·
[Refactoring con moved](https://developer.hashicorp.com/terraform/language/modules/develop/refactoring)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]  (en ~/terraform-lab/10-plataforma)
terraform plan -destroy -var-file=lab.tfvars          # Error: Instance cannot be destroyed (kube_prometheus_stack)
```

En `metallb.tf` cambia `resource "helm_release" "metallb"` por `"balanceador"` y lanza `terraform plan`: sale
destruir `metallb` y crear `balanceador`, es decir, desinstalar y reinstalar MetalLB (corte de todas las IPs .110-.119). Añade al final de `metallb.tf`:

```hcl
moved {
  from = helm_release.metallb
  to   = helm_release.balanceador
}
```

`terraform plan` → `has moved to`, `0 to destroy`. Deshaz el cambio al terminar.

⚠️ **Error común en el mercado: renombrar recursos "por limpieza" sin `moved`.** Un cambio de nombre en el código que
parece inocuo en la revisión del *pull request* y que, aplicado, destruye y recrea el recurso. **Cómo evitarlo:** leer
el plan (no solo el diff del código) y `moved` en todo renombrado.

### 8.9.9 T8 — Quién hace qué

| Tarea | Herramienta | Por qué |
|---|---|---|
| Crear las VMs | Terraform (provider `libvirt`) o `lab.sh vm-create` | Ciclo de vida: crear y destruir |
| Paquetes, LVs, swap, firewalld, containerd | Ansible (8.13) | Configuración del sistema, idempotente, sin estado |
| `kubeadm init/join` | Ansible | Pasos imperativos con orden |
| Namespaces, cuotas, releases de plataforma | Terraform | Estado y plan revisable |
| Aplicaciones de los equipos | Argo CD (8.11) | Git como fuente de verdad, autocorrección |

Escribe la tuya en el checklist (filas 41-48) y defiéndela.

---

## 8.10 OpenShift: Red Hat OpenShift Local (CRC)

> **Orden:** se hace **al final de la etapa**. Necesita el clúster kubeadm apagado y es la única subetapa que toca el
> host.
>
> 🎫 **Ticket PLAT-810.** "El cliente usa OpenShift. Antes de la reunión técnica, comprobad qué cambia respecto a
> nuestro Kubernetes: si nuestros manifiestos funcionan tal cual, cómo se publica una aplicación y cómo se gestiona el
> clúster."

### 8.10.1 OpenShift frente a Kubernetes "a pelo"

📘 **Concepto.** **OpenShift** es la distribución de Kubernetes de Red Hat: trae integrado lo que en la 8.2-8.9 se
montó a mano (red, registro de imágenes, monitorización, entrada HTTP, consola web) y se gestiona con **operadores**,
incluidas sus propias actualizaciones (`ClusterVersion`, `ClusterOperators`). Diferencias clave: los **proyectos** son
namespaces con RBAC y cuotas preparados; las **Security Context Constraints (SCC)** sustituyen a Pod Security, y la
de por defecto, `restricted-v2`, asigna a cada proyecto un **rango de UIDs** y rechaza un `runAsUser` fijo fuera de
él; las **Routes** publican Services por nombre (`*.apps-crc.testing`); **S2I** construye imágenes dentro del clúster;
`oc` es el cliente (compatible con `kubectl`). **OpenShift Local** (CRC) es un OpenShift de un nodo en una VM de tu
equipo: necesita 4 vCPU, ~10,5 GiB de RAM y 35 GB de disco, y `crc setup` configura el host (libvirt, una red `crc`,
`dnsmasq` de NetworkManager para `*.crc.testing`). Linux Mint **no** es una plataforma soportada.

*Fuente:* [OpenShift Local — Introducing](https://crc.dev/docs/introducing/) ·
[OpenShift Container Platform — documentación](https://docs.redhat.com/en/documentation/openshift_container_platform/) (capítulos *Managing security context constraints* y *Configuring routes*)

> ⚠️ El host ya enruta `*.lab.local` hacia `dns01` (`lab.sh host-dns`, Etapa 4): un cambio en el DNS del host puede
> romperlo. Primero solo lectura, y una decisión con la lista de cambios delante. Si algo preocupa, se practica en el
> **Developer Sandbox** de Red Hat (OpenShift en la nube, gratuito y temporal).

🛠️ **Práctica: revisión de solo lectura y descarga.**

```bash
# [host]
nproc; free -h; df -h ~
virsh net-list --all
resolvectl query dns01.lab.local
systemctl is-active NetworkManager
scripts/lab.sh down k8s-w02; scripts/lab.sh down k8s-w01; scripts/lab.sh down k8s-cp01
free -h
```

Anota todo: es el "antes". Descarga de console.redhat.com (OpenShift → Local) el tarball de `crc` y el *pull secret*
(`pull-secret.txt`) en `~/Descargas`. Después, sin `sudo`:

```bash
# [host]
mkdir -p ~/bin ~/crc && tar xJf ~/Descargas/crc-linux-amd64.tar.xz -C ~/crc --strip-components=1
install -m 0755 ~/crc/crc ~/bin/crc
crc version
crc config set memory 11264
crc config set cpus 4
crc config set consent-telemetry no
crc setup --check-only
```

| Paso | Qué esperas | Si sale otra cosa |
|---|---|---|
| `free -h` con el clúster apagado | ≥ 11 GiB disponibles | — |
| `crc version` | Versión de CRC y de OpenShift (anótalas) | `command not found` → `~/bin` no está en el `PATH`: usa `~/bin/crc` |
| `crc setup --check-only` | La lista de comprobaciones y las que `crc setup` arreglaría (= los cambios en el host) | Si tu versión no tiene la opción, `crc setup --help`; **no** lances `crc setup` sin saber qué hará |

🛠️ **Práctica: (tras decidirlo) arrancar y comparar.**

```bash
# [host]
crc setup
crc start -p ~/Descargas/pull-secret.txt
eval "$(crc oc-env)"
oc login -u developer -p developer https://api.crc.testing:6443
resolvectl query dns01.lab.local
oc new-project tienda
sed -e '/^kind: Namespace/,/^---/d' -e 's/namespace: demo/namespace: tienda/' scripts/stage8/files/apps/podinfo.yaml > /tmp/podinfo-oc.yaml
oc apply -f /tmp/podinfo-oc.yaml
oc get pods; oc get events --sort-by=.lastTimestamp | tail -5
```

Lo esperado: OpenShift arranca en 10-20 minutos; `dns01.lab.local` sigue resolviendo (si no, el `dnsmasq` de CRC ha
pisado el DNS del lab: caso de troubleshooting, y `crc cleanup` lo deshace); y podinfo **no** arranca: los eventos
dicen que `runAsUser: 100` no está en el rango permitido por `restricted-v2`.

```bash
# [host]
sed -i '/runAsUser: 100/d' /tmp/podinfo-oc.yaml
oc apply -f /tmp/podinfo-oc.yaml
oc get pods; oc exec deploy/podinfo -- id
oc expose svc/podinfo
oc get route podinfo
curl -s "http://$(oc get route podinfo -o jsonpath='{.spec.host}')" | head -3
```

Lo esperado: pods `Running` con un UID alto asignado por OpenShift, y la Route `podinfo-tienda.apps-crc.testing`
respondiendo. Para el resto de la comparación:

| En OpenShift | Comando | Lo equivalente en el lab |
|---|---|---|
| Proyecto | `oc get project tienda -o yaml` | 8.6 a mano |
| S2I | `oc new-app` con un repositorio de GitHub | Podman fuera del clúster (8.1) |
| Monitorización | Consola → *Observe* (en CRC, apagada: `crc config set enable-cluster-monitoring true`, pide 14 GiB) | 8.8 entero |
| Operadores y versión | `oc login -u kubeadmin` (`crc console --credentials`); `oc get clusteroperators`, `oc get clusterversion` | `kubeadm upgrade` (8.12) |

**OpenShift Virtualization** (KubeVirt) ejecuta VMs como objetos de Kubernetes: es la alternativa de Red Hat a vSphere
tras la compra de VMware por Broadcom. CRC no la soporta; se estudia en teoría (`VirtualMachine`, `DataVolume`,
migración en vivo, Migration Toolkit for Virtualization) y se relaciona con las Etapas 10 y 14.

```bash
# [host]  dejarlo como estaba
crc stop
crc delete            # si necesitas liberar los ~35 GB
crc cleanup           # deshace lo que hizo crc setup
resolvectl query dns01.lab.local
virsh net-list --all
```

⚠️ **Error común en el mercado: `oc adm policy add-scc-to-user anyuid` para que "funcione".** Al primer rechazo por
SCC, se da `anyuid` (o `privileged`) a la ServiceAccount de la aplicación, o a todo el proyecto: se pierde la principal
ventaja de seguridad de OpenShift. **Cómo evitarlo:** quitar el `runAsUser` fijo y hacer la imagen compatible con UIDs
arbitrarios (ficheros con permisos de grupo 0), que es lo que pide la documentación de OpenShift para imágenes.

**Checklist:** filas 49-50.

---

## 8.11 CI/CD y GitOps (Gitea + Argo CD)

> 🎫 **Ticket DEV-811.** "Queremos que ningún cambio de manifiestos llegue al clúster sin pasar una validación, y que
> las aplicaciones se desplieguen desde Git: lo que está en `main` es lo que corre, y volver atrás es un *revert*."

### 8.11.1 CI: validar antes de aplicar

📘 **Concepto.** **Integración continua (CI):** cada cambio pasa automáticamente unas comprobaciones antes de aceptarse.
Para infraestructura: sintaxis y estilo (`yamllint`), validez frente al esquema de la API (`kubeconform`), reglas y
pruebas unitarias de alertas (`promtool check rules`, `promtool test rules`) y `terraform fmt`/`validate`.
`scripts/stage8/files/ci/validar.sh` hace todo eso sin clúster y sin tocar nada; si falta una herramienta, la salta y
lo dice.

*Fuente:* [kubeconform](https://github.com/yannh/kubeconform) ·
[Unit testing for rules (promtool)](https://prometheus.io/docs/prometheus/latest/configuration/unit_testing_rules/) ·
[yamllint](https://yamllint.readthedocs.io/)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
sudo dnf install -y python3-pip python3-pyyaml
pip3 install --user yamllint && yamllint --version
KC_VERSION=v0.7.0        # la última de https://github.com/yannh/kubeconform/releases
cd /tmp
curl -fsSLO "https://github.com/yannh/kubeconform/releases/download/${KC_VERSION}/kubeconform-linux-amd64.tar.gz"
curl -fsSL "https://github.com/yannh/kubeconform/releases/download/${KC_VERSION}/CHECKSUMS" | grep 'kubeconform-linux-amd64.tar.gz' | sha256sum -c
tar xzf kubeconform-linux-amd64.tar.gz kubeconform && install -m 0755 kubeconform ~/.local/bin/
PROM_VERSION=3.x.y       # la última 3.x de https://github.com/prometheus/prometheus/releases (sin la "v")
curl -fsSLO "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
curl -fsSL "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/sha256sums.txt" | grep "prometheus-${PROM_VERSION}.linux-amd64.tar.gz" | sha256sum -c
tar xzf "prometheus-${PROM_VERSION}.linux-amd64.tar.gz" "prometheus-${PROM_VERSION}.linux-amd64/promtool"
install -m 0755 "prometheus-${PROM_VERSION}.linux-amd64/promtool" ~/.local/bin/
kubeconform -v; promtool --version
git -C ~/enterprise-rhel-lab pull
~/enterprise-rhel-lab/scripts/stage8/files/ci/validar.sh
rm -rf /tmp/ci-prueba && cp -r ~/enterprise-rhel-lab/scripts/stage8/files /tmp/ci-prueba
sed -i 's/> 0.05/> 0.10/' /tmp/ci-prueba/monitoring/rules/podinfo-slo.yaml
/tmp/ci-prueba/ci/validar.sh | grep -E 'FALLO|RESULTADO'
```

| Paso | Qué esperas | Si sale otra cosa |
|---|---|---|
| `sha256sum -c` | `...tar.gz: OK` | `FAILED` → no lo instales; si el `grep` no devuelve nada, el fichero de sumas cambió de nombre: míralo en la página de la versión |
| `validar.sh` | Los bloques 1-4 con `OK` y `RESULTADO: OK` (lo `OMITIDO` no cuenta como fallo) | — |
| En la copia rota | `FALLO tests/podinfo-slo.rules.yaml desfasado` y `RESULTADO: 1 FALLO(S)` | — |

Prueba también una sangría rota (la caza `yamllint`) y `replicas: "dos"` en `apps/podinfo.yaml` (la caza
`kubeconform`).

⚠️ **Error común en el mercado: un CI que solo comprueba la sintaxis.** El pipeline pasa `yamllint` y da por bueno un
manifiesto con un campo inexistente (que la API ignora o rechaza al aplicar) o una alerta que nunca dispara. **Cómo
evitarlo:** validar contra el esquema de la versión de la API y **probar** las alertas con datos (`promtool test
rules`).

### 8.11.2 GitOps con Argo CD

📘 **Concepto.** **GitOps:** el estado deseado vive en Git y un agente **dentro** del clúster lo aplica y lo vigila
(*pull*), en lugar de que un pipeline empuje los cambios con credenciales del clúster (*push*). **Argo CD** compara una
`Application` (repositorio, ruta, revisión y destino) con lo que hay en el clúster: `Synced`/`OutOfSync` y
`Healthy`. Con sincronización automática, `prune` borra lo que se quita de Git y `selfHeal` deshace los cambios hechos
a mano. Por defecto consulta el repositorio cada 3 minutos. Volver atrás es un `git revert`.

*Fuente:* [Argo CD — Overview](https://argo-cd.readthedocs.io/en/stable/) ·
[Getting Started](https://argo-cd.readthedocs.io/en/stable/getting_started/) ·
[Automated Sync Policy](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
kubectl create namespace argocd
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.2/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=5m
kubectl -n argocd patch svc argocd-server -p '{"spec":{"type":"LoadBalancer"},"metadata":{"annotations":{"metallb.io/loadBalancerIPs":"10.10.10.116"}}}'
kubectl -n argocd get svc argocd-server
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

Lo esperado: muchos `serverside-applied` (sin `--server-side`, los CRDs grandes fallan con `metadata.annotations: Too
long`), `EXTERNAL-IP 10.10.10.116` y la contraseña inicial de `admin`. Entra en https://argocd.lab.local (certificado
autofirmado), cámbiala y borra después ese Secret.

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
      prune: true
      selfHeal: true
    syncOptions: [CreateNamespace=true]
EOF
kubectl apply -f ~/app-podinfo-gitops.yaml
kubectl -n argocd get application podinfo-gitops -w          # Synced / Healthy; Ctrl+C
kubectl -n gitops get deploy,pods
```

`git push` pide usuario y contraseña: `gitea-admin` y la de la 8.7.2. Los manifiestos no llevan `namespace`: lo pone
la `Application`. El `repoURL` es el nombre **interno** del Service de Gitea. Si la `Application` se queda en
`Unknown` con `repository not found`, revisa la URL (`kubectl -n gitea get svc`) y que el repositorio sea público.

```bash
# [ansible01 · adminlab]  (en ~/k8s-apps)
kubectl -n gitops scale deploy/podinfo --replicas=5
kubectl -n gitops get deploy podinfo -w                      # 5 -> 2 en segundos (selfHeal); Ctrl+C
sed -i 's/replicas: 2/replicas: 3/' podinfo-gitops/podinfo.yaml
git -c user.name=adminlab -c user.email=adminlab@lab.local commit -am "podinfo a 3 réplicas" && git push origin main
kubectl -n gitops get deploy podinfo -w                      # 3 en ~3 min, o Refresh en la web; Ctrl+C
git revert --no-edit HEAD && git push origin main
git log --oneline | head -3
```

Lo esperado: el escalado manual se deshace solo; el commit se despliega solo; el `revert` vuelve a 2 réplicas, y el
historial de Git dice quién, qué y cuándo. Compáralo con el T4 de Terraform: allí el *drift* solo se ve al hacer
`plan`.

⚠️ **Error común en el mercado: el *hotfix* manual que Argo CD deshace.** En plena incidencia, alguien cambia algo con
`kubectl` en un namespace con `selfHeal`; Argo CD lo revierte en segundos y la incidencia "vuelve sola". Lo contrario
también pasa: se desactiva `selfHeal` "un momento" y se queda así. **Cómo evitarlo:** en GitOps, el arreglo de
emergencia es un commit (o se pausa la sincronización de esa `Application`, documentándolo, y se vuelve a activar).

**Checklist:** filas 51-52.

---

## 8.12 Operación del clúster: mantenimiento, etcd y actualización

> 🎫 **Ticket OPS-812.** "Ventana de mantenimiento del sábado: parches del sistema en los workers sin corte, copia de
> etcd verificada y fuera del nodo, y actualización del clúster a la 1.37."

**Antes de empezar:** snapshot `*-antes-8.12` de los tres nodos (apagados).

### 8.12.1 Mantenimiento de un nodo: `drain`, PodDisruptionBudget y `uncordon`

📘 **Concepto.** `kubectl cordon` marca un nodo como no programable; `kubectl drain` lo marca y **desaloja** sus pods
usando la API de *eviction*, que respeta los **PodDisruptionBudgets**. Un PDB (`minAvailable` o `maxUnavailable`)
limita cuántos pods de una aplicación pueden estar caídos a la vez por interrupciones **voluntarias** (mantenimiento),
no por fallos. Los DaemonSets se ignoran con `--ignore-daemonsets`. `uncordon` vuelve a permitir pods, pero no mueve
los que ya están en otros nodos.

*Fuente:* [Safely Drain a Node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/) ·
[Disruptions](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/) ·
[Specifying a Disruption Budget](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)

🛠️ **Práctica.**

```bash
# [ansible01 · adminlab]
kubectl drain k8s-w02 --ignore-daemonsets --delete-emptydir-data
kubectl get nodes
kubectl -n demo get pods -l app.kubernetes.io/name=podinfo -o wide
```

```bash
# [k8s-w02 · root]
dnf update -y            # Kubernetes no se actualiza: está en el exclude= del repositorio
needs-restarting -r; reboot
```

```bash
# [ansible01 · adminlab]
kubectl get nodes -w     # k8s-w02 vuelve Ready,SchedulingDisabled; Ctrl+C
kubectl uncordon k8s-w02
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
kubectl -n demo scale deploy/podinfo --replicas=1
kubectl -n demo get pdb podinfo
NODO=$(kubectl -n demo get pods -l app.kubernetes.io/name=podinfo -o jsonpath='{.items[0].spec.nodeName}'); echo "$NODO"
kubectl drain "$NODO" --ignore-daemonsets --delete-emptydir-data --timeout=60s
kubectl uncordon "$NODO"
kubectl -n demo scale deploy/podinfo --replicas=2 && kubectl -n demo rollout status deploy/podinfo
```

| Paso | Qué esperas | Qué demuestra |
|---|---|---|
| Primer `drain` | `node/k8s-w02 drained`; `Ready,SchedulingDisabled`; podinfo en `k8s-w01` | — |
| `get pdb` con 1 réplica | `ALLOWED DISRUPTIONS 0` | — |
| `drain` del nodo de esa réplica | `Cannot evict pod as it would violate the pod's disruption budget` hasta el `timed out` | El PDB protege el servicio: hay que escalar antes del mantenimiento |

⚠️ **Error común en el mercado: `drain --disable-eviction` o borrar pods a mano para "acabar antes".** Se salta el PDB
y se deja la aplicación sin réplicas en mitad de la ventana. El error simétrico: un PDB con `minAvailable` igual al
número de réplicas (`ALLOWED DISRUPTIONS 0` para siempre), que bloquea **todos** los mantenimientos. **Cómo
evitarlo:** al menos 2 réplicas, PDB con margen y `drain` normal.

### 8.12.2 Copia y restauración de etcd

📘 **Concepto.** etcd guarda todo el estado del clúster: sin copia de etcd, perder el plano de control es perder el
clúster. `etcdctl snapshot save` hace una copia **consistente** de un miembro en marcha (con TLS mutuo: CA, certificado
y clave); `etcdutl snapshot status` la comprueba y `etcdutl snapshot restore` crea, a partir de ella, un **directorio
de datos nuevo**. Para restaurar en un clúster kubeadm se apunta el pod estático de etcd a ese directorio.

*Fuente:* [Operating etcd clusters for Kubernetes — Backing up / Restoring](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/) ·
[etcd — Disaster recovery](https://etcd.io/docs/v3.6/op-guide/recovery/)

🛠️ **Práctica: copia.**

```bash
# [k8s-cp01 · root]
ETCD="kubectl --kubeconfig /etc/kubernetes/admin.conf -n kube-system exec etcd-k8s-cp01 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"
$ETCD endpoint status -w table
$ETCD snapshot save /var/lib/etcd/snapshot-$(date +%F).db
kubectl --kubeconfig /etc/kubernetes/admin.conf -n kube-system exec etcd-k8s-cp01 -- \
  etcdutl snapshot status /var/lib/etcd/snapshot-$(date +%F).db -w table
install -o adminlab -m 0600 /var/lib/etcd/snapshot-$(date +%F).db ~adminlab/
```

```bash
# [ansible01 · adminlab]
mkdir -p ~/copias-etcd && scp adminlab@k8s-cp01.lab.local:'snapshot-*.db' ~/copias-etcd/ && ls -lh ~/copias-etcd/
ssh adminlab@k8s-cp01.lab.local 'rm -f snapshot-*.db'
```

| Paso | Qué esperas | Si sale otra cosa |
|---|---|---|
| `endpoint status` | Una fila con versión, tamaño e `IS LEADER true` | — |
| `snapshot save` | `Snapshot saved at /var/lib/etcd/snapshot-...db` (`/var/lib/etcd` es un `hostPath`: el fichero queda en el nodo) | `executable file not found` → la imagen de tu versión no trae los binarios: descarga el tarball de etcd de la misma versión |
| `snapshot status` | Hash, revisión, claves y tamaño | — |
| `scp` | La copia en `ansible01` | — |

🛠️ **Práctica: restauración.**

```bash
# [ansible01 · adminlab]
kubectl create namespace borrame
```

```bash
# [k8s-cp01 · root]  (si cerraste la sesión, vuelve a definir ETCD)
$ETCD snapshot save /var/lib/etcd/con-borrame.db
```

```bash
# [ansible01 · adminlab]
kubectl delete namespace borrame
```

```bash
# [k8s-cp01 · root]
kubectl --kubeconfig /etc/kubernetes/admin.conf -n kube-system exec etcd-k8s-cp01 -- \
  etcdutl snapshot restore /var/lib/etcd/con-borrame.db --data-dir /var/lib/etcd/restaurado
ls /var/lib/etcd/restaurado
cp -a /etc/kubernetes/manifests/etcd.yaml /root/etcd.yaml.antes-restauracion      # FUERA de manifests/
sed -i '/hostPath:/{n;s|path: /var/lib/etcd$|path: /var/lib/etcd/restaurado|}' /etc/kubernetes/manifests/etcd.yaml
diff /root/etcd.yaml.antes-restauracion /etc/kubernetes/manifests/etcd.yaml
watch crictl ps --name 'etcd|kube-apiserver'          # se reinician; Ctrl+C cuando estén Running
```

```bash
# [ansible01 · adminlab]
kubectl get ns borrame
kubectl get nodes; kubectl get pods -A | grep -v -E 'Running|Completed'
kubectl delete namespace borrame
```

| Paso | Qué esperas | Si sale otra cosa |
|---|---|---|
| `snapshot restore` + `ls` | Un directorio `member/` | — |
| `diff` | **Una** línea: el `hostPath` del volumen `etcd-data` pasa a `/var/lib/etcd/restaurado` | Cambia algo más → restaura la copia y edítalo con `vim` |
| `get ns borrame` | `Active`: ha vuelto | La API no vuelve en 2-3 min → `crictl logs $(crictl ps -a --name etcd -q \| head -1)`; vuelta atrás: copia `/root/etcd.yaml.antes-restauracion` a `manifests/` |

Desde ahora etcd usa `/var/lib/etcd/restaurado`: es válido; anótalo.

⚠️ **Error común en el mercado: copias que nunca se han restaurado.** Hay un cron de `snapshot save` desde hace años,
en el mismo disco del nodo, y el día que hace falta se descubre que la copia está vacía, corrupta o se perdió con el
disco. **Cómo evitarlo:** copia fuera del nodo, `snapshot status` en cada copia y un ensayo de restauración periódico
como este. Y nunca dejar la copia de un manifiesto **dentro** de `/etc/kubernetes/manifests/`: el kubelet la arrancaría
como un segundo etcd.

### 8.12.3 Actualizar de 1.36 a 1.37

📘 **Concepto.** La **política de versiones** obliga a actualizar **una versión menor cada vez** y en orden: primero el
plano de control (`kubeadm upgrade plan` → `kubeadm upgrade apply`), después kubelet y kubectl de ese nodo, y luego los
workers de uno en uno (`kubeadm upgrade node`, kubelet, `uncordon`). El kubelet puede ir hasta tres versiones menores
**por detrás** de la API, nunca por delante. `kubeadm upgrade apply` **renueva** los certificados del plano de control
(caducan al año). Antes: comprobar la compatibilidad de los complementos (Calico, MetalLB, Traefik,
kube-prometheus-stack).

*Fuente:* [Upgrading kubeadm clusters](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/) ·
[Version Skew Policy](https://kubernetes.io/releases/version-skew-policy/) ·
[Certificate Management with kubeadm](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/)

🛠️ **Práctica.** En otra terminal, un bucle que demuestre que no hay corte:

```bash
# [ansible01 · adminlab]
while true; do printf '%s %s\n' "$(date +%T)" "$(curl -s -m2 -o /dev/null -w '%{http_code}' http://podinfo.lab.local)"; sleep 1; done
```

**Plano de control:**

```bash
# [k8s-cp01 · root]
cp -a /etc/yum.repos.d/kubernetes.repo /root/kubernetes.repo.v1.36
sed -i 's/v1\.36/v1.37/g' /etc/yum.repos.d/kubernetes.repo
dnf list --showduplicates kubeadm --disableexcludes=kubernetes | tail -3
dnf install -y 'kubeadm-1.37.*' --disableexcludes=kubernetes
kubeadm upgrade plan
kubeadm upgrade apply v1.37.Z          # la versión exacta que dice el plan
```

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
kubectl get nodes
```

**Cada worker, de uno en uno** (`k8s-w01`, comprobar, y después `k8s-w02`):

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

| Paso | Qué esperas | Si sale otra cosa |
|---|---|---|
| `dnf list --showduplicates` | Versiones `1.37.z` | Vacío → el repositorio 1.37 no está |
| `upgrade plan` | Tabla de versiones y el comando exacto | Errores de *preflight* → léelos antes de seguir |
| `upgrade apply` | `SUCCESS! Your cluster was upgraded to "v1.37.z"` | — |
| `get nodes` tras el plano de control | `k8s-cp01` en 1.37, workers en 1.36.5 | — |
| Bucle de `curl` | Todo `200` | Un `000` durante un `drain` → las dos réplicas estaban en el mismo nodo |
| Final | 3 nodos en `v1.37.z`; `kubeadm certs check-expiration` con ~365 días otra vez | — |

Actualiza también `kubectl` en `ansible01` (`sed` en su `.repo` y `dnf install 'kubectl-1.37.*'`).

⚠️ **Error común en el mercado: clústeres que nadie actualiza... hasta que caducan los certificados.** Un clúster
kubeadm sin actualizar en un año: un lunes, la API rechaza a todos (`x509: certificate has expired`) y el kubelet de
los nodos deja de hablar con ella. Y, cuando por fin se actualiza, se intenta saltar varias versiones de golpe.
**Cómo evitarlo:** actualizar al menos una vez al año (renueva los certificados), una versión menor cada vez, y una
alerta sobre la caducidad de los certificados.

**Checklist:** filas 53-55.

---

## 8.13 Automatizar lo aprendido con Ansible

> 🎫 **Ticket PLAT-813.** "Mañana hay que añadir un worker más y dentro de un mes habrá que reconstruir uno. Que la
> preparación de un nodo y su incorporación al clúster sean un playbook, no una página de wiki."

### 8.13.1 Del procedimiento manual al rol

📘 **Concepto.** Solo se automatiza lo que ya se ha hecho y entendido a mano. Un **rol** idempotente debe dejar el nodo
igual que la 8.2.2 y, en una segunda ejecución, dar `changed=0`. Los pasos imperativos (`kubeadm init`, `join`) se
hacen idempotentes con `creates:` (no ejecutar si existe un fichero que el paso crea). Para esta etapa hacen falta las
colecciones `ansible.posix` (mount, sysctl, firewalld) y `community.general` (lvol, filesystem, modprobe), con versiones
compatibles con `ansible-core` 2.14 de `ansible01`.

*Fuente:* [Ansible — Roles](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html) ·
[ansible.posix](https://docs.ansible.com/ansible/latest/collections/ansible/posix/index.html) ·
[community.general](https://docs.ansible.com/ansible/latest/collections/community/general/index.html) ·
[command — `creates`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/command_module.html)

🛠️ **Práctica.** Proyecto **separado** en `ansible01:~/k8s-ansible` (nunca en `~/ansible-lab`, que `stage7-setup`
sincroniza con `rsync --delete`: caso etapa7/04).

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
  - name: ansible.posix
    version: "1.5.4"
  - name: community.general
    version: "8.6.0"
EOF
ansible-galaxy collection install -r requirements.yml -p ./collections
ansible k8s -m ping -o
ansible-galaxy role init roles/k8s_node
```

Lo esperado: las dos colecciones instaladas (si `ansible-galaxy` avisa de que una versión no es compatible con tu
`ansible-core`, baja esa versión; mira `requires_ansible` en su página de Galaxy) y 3 `pong`.

**El rol `k8s_node`** — cada pieza de la 8.2.2 con su módulo (consulta cada uno con `ansible-doc <módulo>`):

| Pieza (8.2.2) | Módulo |
|---|---|
| a. LVs y XFS | `community.general.lvol`, `community.general.filesystem` |
| a. Montajes | `ansible.posix.mount` (`state: mounted`) |
| b. Swap | `ansible.builtin.command: swapoff -a` con `when: ansible_swaptotal_mb > 0`, y `ansible.builtin.replace` en `fstab` |
| c. Módulos y sysctl | `community.general.modprobe`, `ansible.builtin.copy` a `modules-load.d`, `ansible.posix.sysctl` con `sysctl_file` |
| d. NetworkManager | `ansible.builtin.copy` + handler que recarga NetworkManager |
| e. Zona `k8s` | `ansible.posix.firewalld` (`zone`, `source`, `port`, `service`, `permanent: true`, `immediate: true`; la zona con `state: present`) |
| f. containerd | `ansible.builtin.yum_repository`, `ansible.builtin.dnf`, `ansible.builtin.shell: containerd config default > ...` **solo** si el fichero no tiene `SystemdCgroup = true` (regístralo antes con un `ansible.builtin.command: grep` y `changed_when: false`), `ansible.builtin.replace` y handler de reinicio |
| g. Kubernetes 1.36 | `ansible.builtin.yum_repository` con `exclude`, `ansible.builtin.dnf` con `disable_excludes: kubernetes`, `ansible.builtin.systemd` (`enabled: true`) |

**El playbook `k8s-cluster.yml`:**

```yaml
- name: Preparar los nodos
  hosts: k8s
  roles: [k8s_node]

- name: Plano de control
  hosts: control_plane
  tasks:
    - name: Fichero de configuración de kubeadm
      ansible.builtin.copy:
        src: ~/enterprise-rhel-lab/scripts/stage8/files/cluster/kubeadm-config.yaml
        dest: /root/kubeadm-config.yaml
        mode: "0600"
    - name: kubeadm init (solo si no hay clúster)
      ansible.builtin.command: kubeadm init --config /root/kubeadm-config.yaml --upload-certs
      args:
        creates: /etc/kubernetes/admin.conf

- name: Workers
  hosts: workers
  serial: 1
  tasks:
    - name: Comando join generado al vuelo
      ansible.builtin.command: kubeadm token create --print-join-command
      delegate_to: k8s-cp01
      register: join
      changed_when: false
    - name: kubeadm join (solo si el nodo no está unido)
      ansible.builtin.command: "{{ join.stdout }}"
      args:
        creates: /etc/kubernetes/kubelet.conf
```

Para Calico, después del `init`, `creates:` no sirve (`kubectl create -f` no deja ningún fichero en el nodo): registra
una comprobación previa (`kubectl get ns tigera-operator`, con `failed_when: false` y `changed_when: false`) y lanza el
`kubectl create` solo `when:` esa comprobación falló.

**Criterios:** `--syntax-check`, `--check --diff`, y en la ejecución real la **segunda** da `changed=0`.

**Prueba de fuego:** reconstruir un worker solo con Ansible.

```bash
# [ansible01 · adminlab]
kubectl drain k8s-w02 --ignore-daemonsets --delete-emptydir-data && kubectl delete node k8s-w02
```

```bash
# [host]
scripts/lab.sh snapshot revert k8s-w02 5          # vuelve a "antes de Kubernetes"
```

```bash
# [ansible01 · adminlab]  (en ~/k8s-ansible)
ansible-playbook k8s-cluster.yml --limit 'k8s-w02,k8s-cp01'
kubectl get nodes -w           # k8s-w02 vuelve a Ready; Ctrl+C
```

Después, como ampliación: un rol `node_exporter` para las VMs del lab (lo que el E12 hizo a mano en `dns01`).

⚠️ **Error común en el mercado: playbooks que "funcionan una vez".** Tareas `command`/`shell` sin `creates`,
`changed_when` ni comprobación previa: la segunda ejecución falla (`kubeadm init` sobre un clúster existente) o, peor,
rehace algo que ya estaba bien, y nadie se atreve a volver a lanzarlo. **Cómo evitarlo:** módulos declarativos siempre
que existan, `creates`/`when` en los imperativos, y la segunda ejecución con `changed=0` como criterio de aceptación.

**Checklist:** fila 56 y la tabla de quién hace qué: Ansible (nodos), Terraform (plataforma), Argo CD (aplicaciones).

---

## Diferencias RHEL 7/8/9/10

Solo con datos **medidos** en el lab o de documentación oficial (regla del proyecto):

| Aspecto | RHEL 7 | RHEL 8 | RHEL 9 | RHEL 10 | Fuente / estado |
|---|---|---|---|---|---|
| Herramientas de contenedores | Repositorio *extras* | Módulo `container-tools:rhel8` | Metapaquete `container-tools` (AppStream) | Por verificar | RHEL 9: **medido** (`container-tools-1-15.el9`, podman 5.8.2); RHEL 7 y 8: documentación de Red Hat |
| cgroups por defecto | v1 | v1 | v2 | v2 | Documentación de Red Hat; por medir en el lab con `stat -fc %T /sys/fs/cgroup` (8.1.6) |
| Nodos de Kubernetes del lab | — | — | ✔ | — | Decisión de la etapa: kubelet recientes exigen cgroup v2 |

**Impacto en una migración:** las aplicaciones contenerizadas en RHEL 7/8 con cgroup v1 deben revisarse (límites,
herramientas de monitorización) al pasar a RHEL 9/10; la instalación de Podman cambia de módulo a paquete.

## Primeros comandos ante cualquier problema del clúster

```bash
kubectl get nodes -o wide; kubectl get pods -A | grep -v -E 'Running|Completed'   # qué no está bien
kubectl describe pod <pod> -n <ns>                                     # Events: casi siempre dicen la causa
kubectl logs <pod> -n <ns> [--previous]                                # --previous: el contenedor que murió
kubectl get events -A --sort-by=.lastTimestamp | tail -30
journalctl -u kubelet -u containerd --since -15min                    # en el nodo afectado
crictl ps -a; crictl logs <id>                                         # en el nodo, sin pasar por la API
firewall-cmd --get-active-zones; journalctl -k | grep -i -E 'reject|drop'   # red de pods: firewalld primero
```

## Cierre de la etapa

- [ ] `checklists/etapa8.md` completo, con resultados **obtenidos**.
- [ ] `scripts/stage8/files/ci/validar.sh` en verde.
- [ ] `scripts/lab.sh test all <nodo>` con 0 FAIL en los tres nodos.
- [ ] Casos reales en `troubleshooting/etapa8/` (el primero: etapa8/01, contexto de build y nombre corto) y su índice.
- [ ] Snapshots `*-stage8-complete` de los tres nodos (apagados).
