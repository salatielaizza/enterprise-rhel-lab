# Troubleshooting — Etapa 8 (Kubernetes y OpenShift, Prometheus/Grafana, Terraform)

Ver formato y regla general en [`troubleshooting/README.md`](../README.md).

Casos reales (🔎 = encontrado al ejecutar, no provocado). Además de las incidencias que surjan solas, los escenarios de
la 8.8 ([E00-E12](../../kubernetes/monitorizacion-prometheus-grafana.md)) y de la 8.9
([T1-T8](../../kubernetes/terraform-iac.md)) se provocan a propósito: documenta como caso los que no salgan como
dice la guía o los que enseñen algo que no esté ya escrito.

| Caso | Subetapa | Tema |
|---|---|---|
| [01](01-build-contexto-equivocado-y-nombre-corto.md) 🔎 | 8.1.3 | `podman build` desde el directorio equivocado y nombre corto de imagen |
| [02](02-barra-invertida-en-mitad-de-linea.md) 🔎 | 8.1.5 | Una `\` en mitad de la línea: `executable file ' bash' not found` y pod `Degraded` |
| [03](03-journalctl-user-sin-diario-persistente.md) 🔎 | 8.1.6 | `journalctl --user` sin entradas: diario volátil |
| [04](04-ssh-alias-nodos-k8s-no-generados.md) 🔎 | 8.2.1 | `ssh k8s-cp01`: `Could not resolve hostname` (alias SSH generados con el inventario antiguo) |

## Primeros comandos ante cualquier problema del clúster

```bash
kubectl get nodes -o wide; kubectl get pods -A | grep -v Running        # qué no está bien
kubectl describe pod <pod> -n <ns>                                     # Events: casi siempre dicen la causa
kubectl logs <pod> -n <ns> [--previous]                                # --previous: el contenedor que murió
kubectl get events -A --sort-by=.lastTimestamp | tail -30
journalctl -u kubelet -u containerd --since -15min                    # en el nodo afectado
crictl ps -a; crictl logs <id>                                         # en el nodo, sin pasar por la API
firewall-cmd --get-active-zones; journalctl -k | grep -i reject        # red de pods: firewalld primero
```
