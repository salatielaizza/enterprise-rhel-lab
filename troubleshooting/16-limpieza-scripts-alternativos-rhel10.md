# 16 — Limpieza: scripts alternativos de RHEL 10 sustituidos por el flujo `lab.sh`

**Objetivo**: dejar constancia de por qué ciertos ficheros existieron, por qué se consideraron redundantes y por qué se eliminaron, para que una futura vuelta a este commit no genere confusión ("¿por qué desapareció esto?").

**No es un fallo técnico** como los casos 01-15: es una decisión de consolidación del propio autor del proyecto, documentada aquí porque forma parte del historial de la Etapa 1.

## Contexto

Durante la resolución del caso 15 (biosboot en RHEL 10), al revisar el árbol del proyecto antes de subirlo a GitHub aparecieron ficheros de un enfoque alternativo para crear `rhel10-app01`, escrito en una sesión de trabajo distinta a la que terminó consolidándose como el flujo oficial (`scripts/lab.sh vm-create <host> [--force] [--dry-run]`, sobre `scripts/02-create-vm.sh` + `scripts/kickstart/rhel10.ks.tpl`).

## Ficheros identificados y su relación con el flujo oficial

| Fichero alternativo (eliminado) | Equivalente oficial (el que se usa) | Diferencia de diseño |
|---|---|---|
| `kickstart/rhel10-app01.ks.tmpl` (en la raíz del proyecto) | `scripts/kickstart/rhel10.ks.tpl` | Plantilla duplicada de RHEL 10; la oficial es la que aplicó el fix de `biosboot` del caso 15 y la que renderiza `02-create-vm.sh` |
| `scripts/02b-create-vm-rhel10.sh` | `scripts/02-create-vm.sh` (vía `lab.sh vm-create <host>`) | Script específico solo para RHEL 10, con bandera `--apply` en vez de dry-run por defecto invertido. El flujo oficial es único para las 4 versiones (7/8/9/10) a partir de `hosts.conf`, evitando mantener dos rutas de código para el mismo propósito |
| `tests/test_rhel10.sh` | `tests/test_install.sh` (parametrizado por host, vía `scripts/lab.sh test test_install.sh <host>`) | Test aislado fuera del framework común (`tests/lib.sh`, función `check()`/`summary()`) que usan el resto de tests del proyecto |
| `scripts/download-isos.sh.bak`, `.bak2` | — | Copias de seguridad tomadas antes de dos parches (ver casos de esta misma sesión sobre `download-isos.sh`: el bug de `find_existing()` y el del salto de línea en el token). El fix ya está incorporado en el fichero real; las copias ya no aportan nada una vez el fix quedó validado y confirmado en producción (las 4 ISOs se descargaron con éxito) |
| `scripts/kickstart/rhel10.ks.tpl.bak` | — | Copia de seguridad de `rhel10.ks.tpl` tomada antes de aplicar el fix de `biosboot` (caso 15). El fix ya está confirmado con una instalación real completa; la copia queda sin uso |

## Decisión

Se eliminan los 6 ficheros de la tabla. El proyecto queda con **un único camino** para cada operación (una plantilla de kickstart por versión, un script de creación de VM parametrizado por `hosts.conf`, un framework de tests común), que es justo el criterio que ya seguía el resto del repositorio antes de esta limpieza.

## Comandos ejecutados (a título de registro; ver el commit de Git para el estado exacto)

```bash
rm kickstart/rhel10-app01.ks.tmpl
rmdir kickstart/                              # queda vacía tras el rm anterior
rm scripts/02b-create-vm-rhel10.sh
rm tests/test_rhel10.sh
rm scripts/download-isos.sh.bak scripts/download-isos.sh.bak2
rm scripts/kickstart/rhel10.ks.tpl.bak
```

## Prevención

Cuando se explore un enfoque alternativo a un script ya existente en el proyecto (por ejemplo, para depurar un problema como el del caso 15), conviene hacerlo en una rama de Git separada o dejar una nota explícita en el propio fichero (`# EXPERIMENTAL - no usado por lab.sh`) en vez de dejarlo suelto en el árbol principal, para no tener que reconstruir después, como aquí, por qué existía y si es seguro borrarlo.
