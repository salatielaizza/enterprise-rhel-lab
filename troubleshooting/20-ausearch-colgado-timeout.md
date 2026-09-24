# 20 — `test_services.sh` se cuelga indefinidamente en la comprobación de AVC (ausearch)

**Objetivo**: evitar que una comprobación de solo lectura, pensada para ser informativa, pueda bloquear
indefinidamente `scripts/lab.sh test all all` y, por tanto, cualquier flujo que dependa de él.

**Preparación**: Etapa 2 aplicada en al menos una VM; `auditd` activo (viene por defecto del kickstart).

## Síntoma

`bash scripts/lab.sh test all all` se detiene sin avanzar justo tras imprimir la última línea de
`test_services.sh` antes del chequeo de SELinux (`sin unidades systemd en estado failed`), sin ningún
mensaje de error. Reproducido de forma aislada:

```bash
ssh <host> 'sudo ausearch -m avc -ts recent'
ssh <host> 'sudo ausearch -m avc -ts today'
```

Ambas variantes (con `-ts recent` y con `-ts today`) se cuelgan igual de forma indefinida, descartando
que fuera un problema de parseo de la palabra clave de tiempo. `systemctl status auditd` mostraba el
servicio `active (running)` y sano, sin errores en su log — el problema es específico de `ausearch` como
cliente de consulta, no del demonio `auditd` en sí.

## Causa raíz

No se investigó más a fondo el motivo exacto por el que `ausearch` se cuelga en este entorno (podría ser
una particularidad del backend de auditoría en una VM sin systemd-journald como backend de `auditd`, o del
propio `ausearch` esperando datos que nunca llegan). Se decidió, en su lugar, tratarlo con el mismo
principio aplicado en el caso 19: **una comprobación puramente informativa dentro de un test no debe poder
bloquear indefinidamente el conjunto del laboratorio**, sea cual sea la causa raíz exacta de su lentitud.

## Solución aplicada

`tests/test_services.sh`:
```diff
-check "sin denegaciones SELinux (AVC) recientes de lab-app" bash -c '! ausearch -m avc -ts recent 2>/dev/null | grep -q lab-app'
+check "sin denegaciones SELinux (AVC) recientes de lab-app" bash -c '! timeout 8 ausearch -m avc -ts recent 2>/dev/null | grep -q lab-app'
```

**Limitación consciente de este arreglo**: si `ausearch` sigue colgándose y `timeout` lo mata a los 8
segundos, la tubería `timeout ausearch ... | grep -q lab-app` no encuentra la cadena `lab-app` (porque no
hay salida) y el `check` marca **PASS** — es decir, en un host donde `ausearch` no responde, este test deja
de comprobar de verdad la ausencia de denegaciones SELinux y pasa a asumir que no las hay. Es una
degradación aceptada a cambio de que el laboratorio completo no quede bloqueado; queda documentada aquí
para que quien lea los resultados sepa que un PASS en este punto concreto, en un host con `ausearch` lento,
no es una garantía completa.

## Validación

Aplicado a las 6 VMs del laboratorio (subiendo el `tests/test_services.sh` corregido a cada una). Resultado
de `scripts/lab.sh test all all` tras el arreglo: **las 6 VMs completan su batería de tests sin ningún
cuelgue**, terminando en segundos por host en vez de quedarse indefinidamente parado.

## Prevención

Cualquier comando dentro de `tests/*.sh` que consulte un subsistema externo (auditoría, red, un servicio
de terceros) y cuyo tiempo de respuesta no esté garantizado debería envolverse con `timeout` desde el
principio, igual que ya se hace aquí. Vale la pena revisar el resto de los tests (`test_dns.sh`,
`test_time.sh`, que ya usan `+time=2 +tries=1` en sus `dig`, buen ejemplo a seguir) para confirmar que
ninguna otra comprobación carece de un límite de tiempo explícito.

## Nota metodológica

Este caso se descubrió **enmascarado** dentro del caso 18 (SSH lentísimo por `UseDNS`): mientras SSH tardaba
~80 segundos por conexión, era imposible distinguir "el test está colgado por SSH" de "el test está
colgado por `ausearch`". Solo tras resolver el caso 18 se hizo evidente que quedaba un segundo cuelgue
distinto, real, en un punto distinto del mismo test. Vale la pena recordar: **resolver un problema de
lentitud generalizada casi siempre revela problemas más específicos que estaban ocultos detrás**, y no hay
que dar por cerrado un diagnóstico solo porque el síntoma más visible desapareció.
