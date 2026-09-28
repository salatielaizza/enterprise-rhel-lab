# Troubleshooting — Etapa 3 (networking, NetworkManager, diagnóstico)

Ver formato y regla general en [`troubleshooting/README.md`](../README.md).

| Caso | Tema |
|---|---|
| [01 firewall-block](01-firewall-block.md) | Puerto bloqueado por firewalld |
| [02 wrong-ip](02-wrong-ip.md) | Dirección IP incorrecta |
| [03 wrong-gateway](03-wrong-gateway.md) | Gateway incorrecto |
| [04 wrong-dns](04-wrong-dns.md) | Servidor DNS del cliente incorrecto |
| [05 wrong-route](05-wrong-route.md) | Ruta estática incorrecta |
| [06 ssh-lento-usedns-fqdn-inexistente](06-ssh-lento-usedns-fqdn-inexistente.md) | SSH ~80s por conexión: `UseDNS` + FQDN inexistente (`lab.local` sin `dns01` aún) |
| [07 tabla-resumen-tests-set-e-command-substitution](07-tabla-resumen-tests-set-e-command-substitution.md) | Regresión `scp -O` + bug de `set -e` con `out="$(...)"; ec=$?` en `lab.sh test` |
| [08 medicion-tiempo-por-test-y-tabla-final](08-medicion-tiempo-por-test-y-tabla-final.md) | Medición de tiempo por sub-test/VM (`fmt_time` Ns/Mm SSs) + ediciones vim fallidas |

Nota: el caso 06 (`ssh-lento-usedns-fqdn-inexistente`) es un estado intermedio entre esta etapa y la
Etapa 4 (se resuelve del todo al desplegar `dns01`); ver también
[etapa2/05](../etapa2/05-findmnt-multiple-args-exit1.md) y
[etapa2/06](../etapa2/06-ausearch-colgado-timeout.md), encontrados "detrás" de este mismo caso.
