# Etapa 8.9 — Terraform: infraestructura como código sobre el clúster

> Parte de la [Etapa 8](etapa8-kubernetes-openshift.md). Requisitos: clúster de la 8.2, `local-path` (8.5) y, para el
> escenario T2, MetalLB (8.4) y kube-prometheus-stack (8.8) instalados a mano, como se hace en esas subetapas.
> Código: [`scripts/stage8/files/terraform/`](../scripts/stage8/files/terraform/).

## Qué vas a aprender

| Concepto | Dónde se ve |
|---|---|
| Declarativo: describes el estado final; Terraform calcula los pasos (`plan`) y los ejecuta (`apply`) | T1 |
| **Providers** (`kubernetes`, `helm`) y versiones fijadas (`~> 3.4`) con fichero de bloqueo `.terraform.lock.hcl` | T1 |
| **Estado** (`tfstate`): lo que Terraform cree que existe. Remoto y con **bloqueo**: backend `kubernetes` | T2, T5 |
| **`import`**: adoptar lo que ya existe sin recrearlo | T2, T3 |
| Variables, `tfvars` por entorno, valores **sensibles** fuera del repo, `validation` | T1, T3 |
| `for_each`, módulos reutilizables, outputs | T3 |
| **Drift**: alguien cambia algo a mano y el plan lo detecta | T4 |
| Bloqueo del estado: dos personas a la vez | T5 |
| CRDs y `kubernetes_manifest`: por qué hay dos capas | T6 |
| `prevent_destroy`, `moved`, destrucción controlada | T7 |
| Terraform y Ansible: quién hace qué | T8 |

**Terraform frente a Ansible.** Terraform **crea y destruye recursos** guardando un estado (ideal para infraestructura y
objetos de plataforma); Ansible **configura máquinas** de forma idempotente sin estado (paquetes, ficheros, servicios).
En el lab: Ansible prepara los nodos (8.13) y Terraform gestiona lo que vive dentro del clúster. **OpenTofu** es la
bifurcación abierta de Terraform (licencia MPL): mismos ficheros, comando `tofu`.

## Estructura

```text
scripts/stage8/files/terraform/
├── 10-plataforma/      namespaces + cuotas, MetalLB y kube-prometheus-stack (helm_release)      estado: tfstate-default-plataforma
├── 20-config/          pool de MetalLB y apps monitorizadas (usan CRDs de la capa 10)            estado: tfstate-default-config
└── modules/app-monitorizada/   Deployment + Service + ServiceMonitor + PrometheusRule
```

## Preparación (en ansible01, como adminlab)

```bash
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo dnf install -y terraform
terraform version                                  # 1.16.x en octubre de 2026
terraform -install-autocomplete

kubectl get nodes                                  # el kubeconfig de la 8.2 funciona
kubectl create namespace tfstate                   # donde vivirán los estados (paso único, a mano: ver backend.tf)
cp -r ~/enterprise-rhel-lab/scripts/stage8/files/terraform ~/terraform-lab && cd ~/terraform-lab
```

---

## Escenarios

El punto de partida es el de muchas empresas: **un clúster montado a mano** (8.2-8.8) que hay que pasar a código sin
cortar el servicio. Por eso el primer `apply` no crea la plataforma: la **adopta**.

### T1 — `init` y `plan`: leer antes de tocar (sin aplicar)

```bash
cd ~/terraform-lab/10-plataforma
# La contraseña de Grafana es sensible: nunca en un fichero del repo. Usa LA MISMA que creaste a mano en la 8.8:
export TF_VAR_grafana_admin_password="$(kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)"
terraform init                     # descarga providers, configura el backend y crea .terraform.lock.hcl
terraform fmt -check -recursive && terraform validate
terraform plan -var-file=lab.tfvars
```
Lee el plan línea a línea: `+` crear, `~` cambiar, `-` destruir, `-/+` destruir y recrear (¡corte!). Verás que quiere
**crear** `monitoring`, `metallb-system`, `demo`, `tienda` (8.6), el Secret y las dos releases de Helm... que ya existen. Si aplicaras, fallaría
con `already exists` (o `cannot re-use a name that is still in use`). **No apliques.**

**Documenta:** qué es el `.terraform.lock.hcl` (versiones exactas y hashes de los providers: **sí** va a git) y por qué el
estado **no** va a git (contiene el Secret en claro y cambia en cada `apply`).

### T2 — Adoptar lo hecho a mano (`import`) y primer `apply`

```bash
# 1. Descomenta los bloques de 10-plataforma/imports.tf
terraform plan -var-file=lab.tfvars -out=plan.tfplan
#   Plan: 7 to import, 4 to add, N to change, 0 to destroy
#     to add    -> lo nuevo de verdad: ResourceQuota y LimitRange de demo y de tienda
#     to change -> diferencias entre lo que hay y lo que dice el código (p. ej. etiquetas managed-by en los namespaces)
# 2. Lee CADA cambio. Si alguno no lo quieres, ajusta el CÓDIGO (no el clúster) y repite el plan.
#    0 to destroy es innegociable: si sale un "-" o "-/+", para y entiende por qué.
terraform apply plan.tfplan
# 3. Vuelve a comentar los imports (ya están en el estado) y comprueba la convergencia:
terraform plan -var-file=lab.tfvars          # "No changes. Your infrastructure matches the configuration."
```
Mira lo que ha quedado:
```bash
terraform state list
terraform state show 'kubernetes_namespace_v1.equipo["tienda"]'
kubectl get ns demo tienda --show-labels; kubectl -n tienda describe resourcequota cuota
kubectl -n tfstate get secret,lease                      # el estado (tfstate-default-plataforma) y su bloqueo
```
**Comprueba la cuota:** `kubectl -n tienda run sin-limites --image=busybox:1.37 --restart=Never -- sleep 3600` lo rechaza
Pod Security (`restricted`); ese es otro aprendizaje. Con un manifiesto que cumpla `restricted` y sin `resources`, el pod
arranca con los límites que pone el `LimitRange` (`kubectl -n tienda get pod <pod> -o yaml | grep -A6 resources`).

**Ojo con el Secret de Grafana:** si `TF_VAR_grafana_admin_password` no coincide con la que hay en el clúster, el plan la
cambiará. **Lección:** así se mete bajo IaC un entorno que ya existe, sin recrear nada.

### T3 — Un módulo, varias aplicaciones (capa 20)

```bash
cd ~/terraform-lab/20-config
terraform init
# El pool de MetalLB también se creó a mano (8.4): descomenta 20-config/imports.tf
terraform plan -var-file=lab.tfvars          # 2 to import + la app tienda-web (Deployment, Service, ServiceMonitor, regla)
terraform apply -var-file=lab.tfvars         # y vuelve a comentar los imports
terraform output apps
curl -s http://10.10.10.117 | head           # tienda-web por MetalLB
```
En Prometheus aparece `serviceMonitor/tienda/tienda-web` y la regla `tienda-web.errores` sin escribir YAML: el módulo lo hace
igual para todas. **Ejercicio:** añade una segunda app en `lab.tfvars` (por ejemplo `tienda-api`, sin `ip_lb`) y mira el plan:
solo crea lo de la app nueva. Prueba la `validation`: pon `imagen = "...:latest"` y lee el error. Comprueba que la cuota de
`tienda` (10 pods, 1 CPU de límites) frena una app con `replicas = 20`: el Deployment se crea, pero los pods no
(`kubectl -n tienda get events | grep -i quota`).

### T4 — Drift: alguien toca el clúster a mano

```bash
kubectl -n tienda scale deploy/tienda-web --replicas=5          # "un compañero" escala a mano
kubectl -n tienda label deploy/tienda-web urgente=si
terraform plan -var-file=lab.tfvars                             # ~ replicas: 5 -> 2  (y la etiqueta)
```
Decide: si el cambio era bueno, **pásalo al código** (`replicas = 5` en `lab.tfvars`); si no, `apply` lo revierte.
**Lección:** con IaC, el código es la fuente de verdad; los cambios a mano son *drift*. **Documenta** la decisión.

### T5 — Dos personas a la vez: el bloqueo del estado

Abre **dos sesiones** en ansible01, en `10-plataforma`, y lanza `terraform apply -var-file=lab.tfvars` en las dos, casi a la vez.
La segunda se queda esperando o falla con *Error acquiring the state lock*. Míralo:

```bash
kubectl -n tfstate get lease -o wide         # el titular del bloqueo
```
**Lección:** sin backend remoto con bloqueo, dos `apply` simultáneos corrompen el estado. `terraform force-unlock <ID>`
existe, pero solo cuando estás seguro de que el otro proceso murió.

### T6 — "no matches for kind": CRDs y `kubernetes_manifest`

Argo CD llega en la 8.11, así que su CRD `Application` todavía no existe. Crea `20-config/t6-prueba.tf`:

```hcl
resource "kubernetes_manifest" "app_argocd" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = { name = "podinfo", namespace = "argocd" }
    spec       = { project = "default" }
  }
}
```
`terraform plan` falla **en el plan**, no en el apply: `kubernetes_manifest` consulta el esquema del CRD al planificar. Pasa
lo mismo si un mismo `apply` instala un chart (que trae los CRDs) y a la vez crea objetos de esos CRDs. Borra el fichero.

**Soluciones reales:** capas separadas (lo que hace el lab: `10-plataforma` instala MetalLB y el operador de Prometheus,
`20-config` usa sus CRDs) o dos fases (`terraform apply -target=helm_release.metallb` y luego el resto). **Documenta** por
qué `-target` es para emergencias y no para el día a día.

### T7 — Proteger y renombrar: `prevent_destroy` y `moved`

```bash
terraform plan -destroy -var-file=lab.tfvars        # Error: Instance cannot be destroyed (kube_prometheus_stack)
```
`prevent_destroy` impide borrar la monitorización por error. Renombrar sin destruir:

```hcl
# En 10-plataforma/metallb.tf cambia  resource "helm_release" "metallb"  por  "balanceador", y añade:
moved {
  from = helm_release.metallb
  to   = helm_release.balanceador
}
```
`terraform plan` → "has moved to", 0 to destroy. Sin el bloque `moved`, el plan **destruiría y recrearía** MetalLB (corte de
servicio para todas las IPs .110-.119). Deshaz el cambio al terminar.

### T8 — Quién hace qué: Terraform y Ansible

Escribe en el checklist (y defiéndelo): qué del lab gestionarías con cada herramienta. Referencia del lab:

| Tarea | Herramienta | Por qué |
|---|---|---|
| Crear las VMs del clúster | Terraform (provider `libvirt`, ampliación) o `lab.sh vm-create` | Recurso con ciclo de vida: crear/destruir |
| Paquetes, LVs, swap, firewalld, containerd en los nodos | Ansible (8.13) | Configuración de SO, idempotente, sin estado |
| `kubeadm init/join` | Ansible | Pasos imperativos con orden |
| Namespaces, cuotas, Helm releases, apps | Terraform (esta subetapa) o GitOps con Argo CD (8.11) | Estado declarativo y plan revisable |

**Ampliación (opcional):** crear `k8s-w03` con el provider `dmacvicar/libvirt` desde el host, con una imagen KVM de RHEL 9 y
cloud-init. Comprueba la versión del provider y su documentación al hacerlo: su esquema cambió mucho entre versiones.

## Errores típicos

| Síntoma | Causa | Arreglo |
|---|---|---|
| `Error: Kubernetes cluster unreachable` | kubeconfig/contexto (`kube_context`) incorrectos | `kubectl config get-contexts` y `TF_VAR_kube_context` |
| `namespaces "tfstate" not found` en `init` | el backend no crea su namespace | `kubectl create namespace tfstate` |
| `cannot re-use a name that is still in use` (helm) | la release ya existe (instalada a mano) | T2 (`import`) |
| `no matches for kind "..."` | CRD aún no instalado al hacer el plan | T6 |
| `already exists` al aplicar | el objeto se creó fuera de Terraform | T2/T3 (`import`) |
| `Error acquiring the state lock` | otro `apply` en curso (o uno que murió) | Esperar; `force-unlock` solo con certeza |
| El plan siempre muestra cambios en un `helm_release` | valores que el chart normaliza distinto | Alinear el fichero de valores; nunca ignorar sin entenderlo |
