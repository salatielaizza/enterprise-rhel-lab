# Troubleshooting — Etapa 8 (Kubernetes y OpenShift, Prometheus/Grafana, Terraform)

Ver formato y regla general en [`troubleshooting/README.md`](../README.md).

Todavía sin casos: se añaden al ejecutar la etapa. Además de las incidencias que surjan solas (🔎), los escenarios de
la 8.8 ([E00-E12](../../kubernetes/monitorizacion-prometheus-grafana.md)) y de la 8.9
([T1-T8](../../kubernetes/terraform-iac.md)) se provocan a propósito: documenta como caso los que no salgan como
dice la guía o los que enseñen algo que no esté ya escrito.

| Caso | Tema |
|---|---|
| — | — |

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
