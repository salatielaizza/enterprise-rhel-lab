# 06 — La marca de la Etapa 7 no se aplicaba ni se comprobaba bien (tres fallos encadenados)

## Objetivo

Documentar tres fallos relacionados con la **marca de etapa** (`LAB_STAGE=7` en `/etc/lab-release`), detectados
en la Fase 18 al ejecutar por primera vez el flujo completo de `lab.sh` (`stage7-setup` → `stage7 site` →
`test all all`) contra las 6 VMs. Ninguno se había visto antes porque el bug del `printf` vacío de
`02-run-playbook.sh` paraba `lab.sh stage7 site` antes de llegar a la parte de la marca.

## Preparación

- Las 6 VMs encendidas; `stage7-setup` ya sincronizando con `rsync --delete` (caso [04](04-restos-de-ejercicios-en-nodo-de-control.md)).
- Cómo funciona la marca en el lab:
  - `scripts/common.sh` → `set_stage N` escribe `LAB_STAGE=N` en `/etc/lab-release` y **nunca la reduce**
    (`if (( cur < n ))`).
  - `tests/lib.sh` → `lab_stage` (una **función**) la lee; `check "desc" cmd...` ejecuta `"$@"` en la misma shell.
  - `tests/run_all.sh` añade los tests según la etapa: `[[ $stage -ge 7 ]] && tests+=(test_ansible.sh)`.
  - `scripts/stage7/03-mark-stage.sh` llama a `set_stage 7`; `lab.sh stage7 site` lo ejecuta en cada nodo gestionado.

## Síntoma

Log de la validación del 2026-10-22 (`fase18-validacion.log`):

```
=========== 2. stage7 site, 1ª vez por lab.sh ===========
PLAY RECAP ... changed=0 ... failed=0   (los 5 hosts)
bash: lab-scripts/stage7/03-mark-stage.sh: No such file or directory          ← A
```

```
== rhel7-app01: etapa alcanzada = 7 ==
### test_ansible.sh
...
FAIL  etapa 7 marcada (set_stage)                                              ← B
--- test_ansible en rhel7-app01: 6 PASS, 1 FAIL
(lo mismo en rhel8/9/10-app01 y dns01)
```

```
== ansible01: etapa alcanzada = 6 ==                                           ← C
(ningún "### test_ansible.sh" en ansible01)
RESULTADO del host ansible01: OK (155 PASS, 0 FAIL)
```

## Hipótesis descartadas

| Hipótesis | Por qué se descartó |
|---|---|
| Los nodos no estaban en la etapa 7 y el FAIL era correcto | `run_all.sh` imprimía `etapa alcanzada = 7` en los 5 nodos, y `cat /etc/lab-release` en rhel9-app01 mostraba `LAB_STAGE=7` |
| `set_stage` había bajado la etapa de algún host | `set_stage` solo escribe si `cur < n`: nunca reduce |
| ansible01 "pasaba" `test_ansible` | No lo ejecutaba: en su bloque no hay ningún `### test_ansible.sh`. Su `OK` solo cubría los tests hasta la Etapa 6 |
| El `rsync --delete` del caso 04 borró `stage7/` de los nodos | `rsync` solo actúa sobre `~adminlab/ansible-lab` **de ansible01**; `~/lab-scripts` de los nodos lo gestiona `push` en `lab.sh` |

## Diagnóstico

**A — `lab.sh stage7 site` no copia los scripts a los nodos que va a marcar.** Leyendo `scripts/lab.sh`:

```bash
stage7_setup() {
  push ansible01                      # ← solo ansible01
  ...
}
stage7() {
  run_remote ansible01 stage7/02-run-playbook.sh "$playbook" "$@"
  if [[ "$playbook" == site ]]; then
    for h in "${ANSIBLE_MANAGED_HOSTS[@]}"; do
      run_remote "$h" stage7/03-mark-stage.sh     # ← sin 'push "$h"' antes
    done
  fi
}
```

`run_remote` ejecuta `sudo bash lab-scripts/stage7/03-mark-stage.sh` con la copia que el nodo tenga en
`~/lab-scripts`, que solo refresca un `push` de **otro** comando de `lab.sh`. Si esa copia es anterior a
`stage7/`, el script no existe. Tras el paso 6 de la validación (`lab.sh test all all`), el `ls ~/lab-scripts/`
de rhel9-app01 sí mostraba `stage7/` (y `stage8/`, `stageN2/`): la copia se había refrescado después, por otro
comando, no por `stage7()`. La fecha del directorio lo confirma (`push` lo borra y lo vuelve a crear):

```bash
ssh adminlab@rhel9-app01 'ls -ld --time-style=long-iso ~/lab-scripts'
# drwxr-xr-x. 11 adminlab adminlab 191 2026-10-22 16:09 /home/adminlab/lab-scripts
```

16:09 es la hora del `test all all` (paso 6), posterior al `stage7 site` (paso 2) que falló.

**B — El test de la marca falla siempre.** En `tests/test_ansible.sh`:

```bash
check "etapa 7 marcada (set_stage)" bash -c '(( $(lab_stage) >= 7 ))'
```

`bash -c` abre un **proceso bash nuevo**, que no hereda las funciones de la shell que lo lanza. `lab_stage` es
una función de `lib.sh`:

```bash
ssh adminlab@rhel9-app01 'cat /etc/lab-release; type lab_stage'
# LAB_STAGE=7
# bash: line 1: type: lab_stage: not found
```

Dentro del `bash -c`, `$(lab_stage)` da "command not found" (salida vacía), la expresión queda
`(( >= 7 ))` (error de sintaxis) y `check` lo cuenta como FAIL. Reproducido con una maqueta de `lib.sh`:

| `LAB_STAGE` | Antes (`bash -c`) | Ahora (función) |
|---|---|---|
| 6 | FAIL | FAIL (correcto) |
| 7 | **FAIL** | PASS |
| 8 | **FAIL** | PASS |

**C — ansible01 nunca alcanza la etapa 7.** `03-mark-stage.sh` solo se lanzaba en `ANSIBLE_MANAGED_HOSTS`
(los 5 nodos gestionados); nada marcaba el nodo de control. ansible01 se quedaba en `LAB_STAGE=6`, `run_all.sh`
no le añadía `test_ansible.sh` y **todas sus comprobaciones** (vault cifrado, permisos de la clave y de
`.vault_pass.txt`, "proyecto sin restos"…) nunca se habían ejecutado.

## Causa raíz

- **A:** `stage7()` depende de un `push` hecho antes por otro comando; el resto de etapas (`stage2()`,
  `stage5()`…) hace `push "$h"` antes de `run_remote` en cada host.
- **B:** el test usa una función de `lib.sh` dentro de `bash -c`, que no la hereda. El propio checklist del
  proyecto lo advertía: *"mejor definir funciones cortas en el propio test y pasarlas a `check`"*.
- **C:** la etapa se pensó solo para los nodos gestionados; el nodo de control también tiene tests de la
  Etapa 7, pero nada lo marcaba.

Los tres pasaron desapercibidos porque `lab.sh stage7 site` nunca había llegado hasta la marca (bug del
`printf`), y porque un test que no se ejecuta (C) no da FAIL: da un falso "OK".

## Solución aplicada

| Fallo | Fichero | Cambio |
|---|---|---|
| A | `scripts/lab.sh` → `stage7()` | `push "$h"` antes de `run_remote "$h" stage7/03-mark-stage.sh` |
| B | `tests/test_ansible.sh` | Función propia `etapa7_marcada() { (( $(lab_stage) >= 7 )); }` y `check "..." etapa7_marcada` (en los nodos gestionados y en ansible01) |
| C | `scripts/stage7/03-mark-stage.sh` | En ansible01, el requisito es `~/ansible-lab/ansible.cfg` y `~/.vault_pass.txt` (en vez de `/etc/ansible-lab-managed.txt`); después, `set_stage 7` |
| C | `scripts/lab.sh` → `stage7_setup()` | Tras el ping + become en verde: `run_remote ansible01 stage7/03-mark-stage.sh` |

Como `set_stage` nunca reduce la etapa, relanzar `stage7-setup` cuando ansible01 esté en una etapa posterior
(por ejemplo, la 8) no lo devuelve a la 7.

## Validación

```bash
scripts/lab.sh stage7-setup        # al final: "[ansible01] Etapa 7 marcada como alcanzada en ansible01"
scripts/lab.sh stage7 site         # sin "No such file"; 5 x "Etapa 7 marcada como alcanzada en <host>"
scripts/lab.sh test all all        # "== ansible01: etapa alcanzada = 7 ==", test_ansible también en ansible01
```

Resultado real (2026-10-22, `fase18-validacion-marca.log`):

```
[ansible01] Etapa 7 marcada como alcanzada en ansible01          ← C (stage7-setup)
PLAY RECAP ... changed=0 ... failed=0   (los 5 hosts)
[rhel7-app01] Etapa 7 marcada como alcanzada en rhel7-app01      ← A (sin "No such file")
[rhel8-app01] ... [rhel9-app01] ... [rhel10-app01] ... [dns01] Etapa 7 marcada ...

== rhel7-app01: etapa alcanzada = 7 ==
PASS  etapa 7 marcada (set_stage)                                 ← B
--- test_ansible en rhel7-app01: 7 PASS, 0 FAIL      (igual en rhel8/9/10-app01 y dns01)

== ansible01: etapa alcanzada = 7 ==                              ← C
### test_ansible.sh                                               ← por primera vez en ansible01
PASS  inventory/group_vars/all/vault.yml está cifrado (no en texto plano)
PASS  proyecto sin restos (*.lab-bak.*, *.swp, host_vars/)
PASS  etapa 7 marcada en el nodo de control (set_stage)
--- test_ansible en ansible01: 11 PASS, 0 FAIL

HOST             PASS     FAIL
rhel7-app01      180      0
rhel8-app01      181      0
rhel9-app01      181      0
rhel10-app01     181      0
dns01            167      0
ansible01        166      0
RESULTADO GLOBAL: OK — todas las VMs sin FAIL
```

**0 FAIL en las 6 VMs**, con `test_ansible.sh` ejecutado en las 6 (antes, solo en 5 y siempre con un FAIL).

## Prevención

- **Toda función de `lab.sh` que ejecute un script en un host le hace `push` antes**, aunque otro comando ya
  lo haya hecho: nunca depender del estado que dejó un comando anterior.
- **En los tests, nunca usar funciones de `lib.sh` dentro de `bash -c`**: definir una función corta en el propio
  test y pasarla a `check`.
- **Un test que no se ejecuta no falla: hay que comprobar que se ejecuta.** Al cerrar una etapa, buscar en la
  salida de `test all all` el `### test_<etapa>.sh` en **cada** host que deba tenerlo, no solo el `0 FAIL` final.
- Relacionados: [04](04-restos-de-ejercicios-en-nodo-de-control.md) (dependencia del estado previo del nodo de
  control) y los casos de `set -e` de etapas anteriores (otra familia de trampas de bash en los tests).
