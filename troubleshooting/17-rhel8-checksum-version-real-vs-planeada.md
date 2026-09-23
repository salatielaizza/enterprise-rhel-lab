# 17 — RHEL 8: versión real instalada (8.6) distinta de la planeada (8.10)

**Objetivo**: dejar constancia de una discrepancia entre lo documentado y lo realmente instalado, para que la Etapa 1 no dé por sentado un dato que no se verificó.

**No es un fallo técnico** de ningún script: `rhel8-app01` se instaló correctamente y pasa sus tests. Es un error de **dato de entrada** (un checksum) que se coló en la documentación antes de instalar la VM real.

## Contexto

El plan original del laboratorio (`rhel8/installation.md`, `rhel8/differences.md`, `scripts/isos.conf.example`) fijaba **RHEL 8.10** ("última minor de RHEL 8") como versión objetivo, con un checksum SHA-256 obtenido inicialmente sin verificación directa en la página oficial.

Al preparar la descarga real, se pidió verificar los 4 checksums manualmente en https://developers.redhat.com/products/rhel/download. Al hacerlo para RHEL 8, se copió el checksum correspondiente a una versión distinta de la esperada, sin que el nombre de fichero de esa versión se comparase explícitamente con "8.10" en el momento de pegarlo en `config/isos.conf`.

## Diagnóstico posterior

```bash
bash scripts/lab.sh vm-create rhel8-app01
# ...
[INFO] rhel8-app01: RHEL 8, ISO rhel-8.6-x86_64-dvd.iso, ...
```

El propio log de instalación reveló el nombre real de fichero descargado: `rhel-8.6-x86_64-dvd.iso`, no `rhel-8.10-x86_64-dvd.iso` como documentaban `rhel8/installation.md` y `scripts/isos.conf.example`.

## Causa raíz

El checksum copiado a mano en `config/isos.conf` para la clave `rhel8` correspondía a RHEL 8.6, no a RHEL 8.10. Como el flujo de descarga (`scripts/download-isos.sh`) pide la ISO **por checksum**, no por número de versión, la API de Red Hat devolvió fielmente el fichero correcto para ese checksum — la herramienta no tuvo ningún fallo; el dato de entrada era el que no correspondía a la intención original.

## Decisión

Se decide **seguir con RHEL 8.6** en `rhel8-app01` en vez de volver a descargar la 8.10, porque:
- 8.6 es una versión menor de RHEL 8 completamente válida y con el mismo comportamiento general que documenta `rhel8/differences.md` a nivel de familia mayor (kernel 4.18, dnf, keyfile/ifcfg según corresponda, etc.).
- Repetir la descarga de ~13 GB solo por el número de versión menor no aporta nada relevante a los objetivos de comparación 7/8/9/10 de este laboratorio.
- Cualquier valor `[VERIFICADO]`/✔ que se registre para esta VM (con `lab.sh facts`/`collect-facts.sh`) debe entenderse como propio de **8.6**, no de 8.10.

## Corrección de la documentación (pendiente de aplicar en el repositorio real)

| Fichero | Cambio |
|---|---|
| `rhel8/installation.md` | Cabecera y tabla: "RHEL 8.10" → "RHEL 8.6 (planeada 8.10; ver troubleshooting/17)"; fila ISO: `rhel-8.6-x86_64-dvd.iso` |
| `rhel8/differences.md` | Cabecera: "RHEL 8.10" → "RHEL 8.6"; nota de versión real |
| `scripts/isos.conf.example` | Comentario y checksum de ejemplo de `rhel8` corregidos a 8.6, o anotados como solo orientativos (el fichero real que manda es `config/isos.conf`, ya correcto para 8.6 desde que el usuario lo verificó a mano) |
| `comparison/matrix.md` / `matrix.generated.md` | Cualquier columna "RHEL 8" debe indicar 8.6 en la cabecera cuando se rellene con datos reales |

## Validación

```bash
ssh rhel8-app01 cat /etc/redhat-release   # debe decir "Red Hat Enterprise Linux release 8.6 (Ootpa)"
scripts/lab.sh test test_install.sh rhel8-app01
```

## Prevención

Al verificar un checksum a mano contra la página de descargas de Red Hat, comparar explícitamente el **nombre de fichero completo** (incluyendo la versión menor) antes de copiar el hash, no solo el número de versión mayor. Una forma más segura para el futuro: usar `scripts/download-isos.sh --list <versión>` (aunque está marcado `[EXPERIMENTAL]`) para obtener el checksum directamente ligado a la versión exacta deseada, en vez de copiarlo a mano de la web.
