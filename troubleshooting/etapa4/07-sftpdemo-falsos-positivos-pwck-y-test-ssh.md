# Etapa 4 · Caso 07 — sftpdemo: falsos positivos en `pwck` y en el test de `ChrootDirectory`

## Objetivo

Determinar si las dos únicas pruebas que fallaban tras completar la Etapa 4
(`pwck sin errores en /etc/passwd y /etc/shadow` y `SFTP: ChrootDirectory +
ForceCommand internal-sftp para sftpdemo`) reflejaban un problema real de
configuración del usuario SFTP enjaulado `sftpdemo`, o si eran falsos
positivos de las propias herramientas de comprobación. Documentar también dos
incidentes de edición con `vim` sufridos mientras se corregían los tests, como
lección para el futuro.

## Preparación

- Etapa 4 completada: BIND, chrony y el endurecimiento SSH (`stage4-clients
  all`) ya aplicados en los 6 hosts.
- `stage4/03-ssh-hardening.sh` crea el usuario `sftpdemo` (UID 1005, grupo
  `sftponly`) con una jaula SFTP en `/srv/sftp/sftpdemo`, usando
  `ChrootDirectory /srv/sftp/%u` y `ForceCommand internal-sftp` en
  `sshd_config`.
- Copia de seguridad de los ficheros a modificar antes de tocar nada:
  ```bash
  cp tests/test_users.sh tests/test_users.sh.bak
  cp tests/test_ssh.sh tests/test_ssh.sh.bak
  ```
- `bash scripts/lab.sh test all all` mostraba, en los 6 hosts, exactamente
  estos dos FAIL (y solo estos):
  ```
  FAIL  pwck sin errores en /etc/passwd y /etc/shadow
  FAIL  SFTP: ChrootDirectory + ForceCommand internal-sftp para sftpdemo
  ```

## Síntoma

1. `pwck -r` en cualquier VM:
   ```
   $ sudo pwck -r
   user 'sftpdemo': directory '/upload' does not exist
   pwck: no changes
   ```
2. El test de SSH fallaba al comprobar la configuración efectiva de chroot
   para `sftpdemo` con `sshd -T -C user=sftpdemo,host=...,addr=...`.

## Hipótesis descartadas

- **"El usuario sftpdemo está mal creado (home incorrecto)."** Se comprobó
  con una conexión SFTP real (`sftp sftpdemo@<host>`) que el usuario entra
  correctamente, queda enjaulado en `/srv/sftp/sftpdemo` y su directorio de
  trabajo tras conectar es `/upload` (relativo a la jaula), con `ls`
  funcionando con normalidad. Es decir: el comportamiento real es correcto.
- **"El test de ChrootDirectory tiene una expresión regular rota."** Se
  descartó tras comprobar que `sshd -T -C user=sftpdemo,host=lab,addr=...`
  no expande el token `%u` de `ChrootDirectory` de la misma forma en que lo
  hace una conexión SSH real: en el modo de comprobación de configuración
  (`sshd -T -C`), la directiva se devuelve tal cual está escrita
  (`chrootdirectory /srv/sftp/%u`), no con el valor ya resuelto
  (`/srv/sftp/sftpdemo`). El test original solo aceptaba la forma expandida.
- **"pwck detecta un error de seguridad real."** El home del usuario
  `sftpdemo` se define como `/upload` de forma **deliberada**: para un
  usuario con `ChrootDirectory`, OpenSSH interpreta el `HOME` de
  `/etc/passwd` como una ruta **relativa a la jaula**, no como una ruta
  absoluta del sistema de ficheros real. `pwck` no tiene ese contexto: solo
  sabe leer `/etc/passwd` y comprobar si esa ruta existe de forma absoluta
  en el sistema, por lo que informa (incorrectamente, para este caso
  concreto) de un directorio "inexistente".

## Diagnóstico

- Conexión SFTP real de control:
  ```bash
  sftp sftpdemo@rhel9-app01
  sftp> pwd
  Remote working directory: /upload
  sftp> ls
  ```
  Confirmó que la jaula y el `ChrootDirectory` funcionan exactamente como se
  espera.
- `sshd -T -C user=sftpdemo,host=lab,addr=10.10.10.1 | grep -i chrootdirectory`
  devolvió `chrootdirectory /srv/sftp/%u` (con el `%u` **sin expandir**), en
  vez de `/srv/sftp/sftpdemo`.
- `sudo pwck -r` confirmó que el único aviso restante, tras corregir por
  separado un problema no relacionado (el home de `devuser`, ver más abajo),
  era el de `sftpdemo` y su directorio `/upload`.

### Problema aparte detectado durante el diagnóstico: home de `devuser`

Durante esta misma investigación se detectó (y corrigió) un problema
**real y distinto**: `devuser` tenía como home una ruta inexistente
(`/ruta-que-no-existe`) por una prueba manual anterior que no se había
revertido. Se corrigió con:
```bash
ssh <host> 'sudo usermod -d /home/devuser devuser'
```
Esto no forma parte del falso positivo de `sftpdemo`, pero explica por qué
`pwck -r` mostraba, al principio, **dos** avisos en vez de uno.

## Causa raíz

1. **`pwck`** no entiende el contexto de `ChrootDirectory` de OpenSSH: para
   un usuario enjaulado, un `HOME` relativo a la jaula (`/upload`) es
   correcto, pero `pwck` solo comprueba rutas absolutas del sistema real y
   lo marca como error.
2. **`sshd -T -C`** (modo de comprobación de configuración) no expande el
   token `%u` dentro de `ChrootDirectory` de la misma manera que lo hace una
   sesión SSH real; el test original solo aceptaba la forma ya expandida.

Ambos son limitaciones conocidas de las herramientas de diagnóstico, no
errores de configuración del laboratorio.

## Solución aplicada

### `tests/test_users.sh` (línea del check de `pwck`)

Antes:
```bash
check "pwck sin errores en /etc/passwd y /etc/shadow" bash -c 'pwck -r >/dev/null'
```

Después:
```bash
check "pwck sin errores en /etc/passwd y /etc/shadow" bash -c 'out=$(pwck -r 2>&1 | grep -v "sftpdemo.*does not exist" | grep -v "^pwck: no changes$"); [[ -z "$out" ]]'
```

El test ahora filtra explícitamente el aviso conocido y documentado de
`sftpdemo` (y la línea informativa `pwck: no changes`), pero sigue fallando
ante **cualquier otro** aviso de `pwck` — incluido el mismo tipo de problema
en otro usuario.

### `tests/test_ssh.sh` (línea del check de `ChrootDirectory`)

Antes (solo aceptaba la ruta ya expandida):
```bash
check "SFTP: ChrootDirectory + ForceCommand internal-sftp para sftpdemo" bash -c "sshd -T -C user=sftpdemo,host=lab,addr=10.10.10.1 | grep -Eiq '^forcecommand internal-sftp' && sshd -T -C user=sftpdemo,host=lab,addr=10.10.10.1 | grep -Eiq '^chrootdirectory /srv/sftp/sftpdemo'"
```

Después (acepta la ruta expandida **o** el token `%u` literal):
```bash
check "SFTP: ChrootDirectory + ForceCommand internal-sftp para sftpdemo" bash -c "sshd -T -C user=sftpdemo,host=lab,addr=10.10.10.1 | grep -Eiq '^forcecommand internal-sftp' && sshd -T -C user=sftpdemo,host=lab,addr=10.10.10.1 | grep -Eiq '^chrootdirectory /srv/sftp/(sftpdemo|%u)'"
```

### Incidentes de edición sufridos al aplicar el fix (lección para el futuro)

1. **`sed` con comillas anidadas rotas**: un primer intento de sustituir la
   línea de `pwck` con `sed` generó una línea con comillas internas sin
   escapar. El resultado era sintácticamente válido para `bash -n`, pero
   `$?` se expandía en el momento equivocado del parseo, y el test devolvía
   siempre PASS sin comprobar nada de verdad. Se detectó porque, al ejecutar
   `pwck -r` a mano, el código de salida era `2` (hay avisos) mientras que el
   test decía PASS. Se restauró desde `.bak` y se reescribió a mano con
   `vim`.
2. **Pérdida de salto de línea con `dd`+`i` en `vim`**: al reemplazar solo la
   línea 20 de `tests/test_users.sh`, faltó el salto de línea final de la
   inserción, y la línea del check de `pwck` quedó fusionada con la
   siguiente (`check "grpck sin errores"...`) en una sola instrucción bash.
   `bash -n` no detectó ningún error (la línea seguía siendo sintácticamente
   válida), pero el check de `grpck` quedaba absorbido como argumento del
   anterior y dejaba de ejecutarse. Se detectó comparando `wc -l` del fichero
   modificado (31 líneas) contra el backup (32 líneas) — una comprobación que
   `bash -n` por sí sola nunca habría revelado.

## Validación

- `bash -n tests/test_users.sh` y `bash -n tests/test_ssh.sh`: sin errores.
- `wc -l` de ambos ficheros comparado contra su `.bak`: mismo número de
  líneas más el cambio esperado (ninguna línea perdida ni fusionada).
- Prueba de regresión positiva (el test sigue detectando problemas reales):
  ```bash
  ssh rhel9-app01 'sudo usermod -d /ruta-que-no-existe devuser'
  # -> pwck sin errores en /etc/passwd y /etc/shadow: FAIL (correcto)
  ssh rhel9-app01 'sudo usermod -d /home/devuser devuser'
  # -> vuelve a PASS
  ```
- Ejecución final `bash scripts/lab.sh test all all` en los 6 hosts:
  ```
  HOST             PASS     FAIL     TIEMPO   ESTADO
  rhel7-app01      142      0        9s       OK
  rhel8-app01      143      0        9s       OK
  rhel9-app01      143      0        9s       OK
  rhel10-app01     143      0        9s       OK
  dns01            129      0        9s       OK
  ansible01        124      0        9s       OK

  RESULTADO GLOBAL: OK — todas las VMs sin FAIL
  ```
  **0 FAIL en los 6 hosts.** Etapa 4 queda completamente validada.

## Prevención

- Antes de confiar en el resultado de `sshd -T -C ...`, comprobar con una
  conexión real (`sftp`/`ssh`) cuando la directiva en cuestión use tokens
  como `%u` o `%h`: el modo de comprobación de configuración no siempre los
  expande igual que una sesión real.
- Cuando una herramienta de verificación de sistema (`pwck`, `grpck`, etc.)
  reporta un aviso sobre una configuración que es intencionadamente distinta
  de lo habitual (como un `HOME` relativo a una jaula SFTP), documentar el
  caso y filtrar **solo ese aviso concreto y conocido**, nunca silenciar la
  herramienta por completo.
- Tras cualquier edición manual de un script con `vim` (sobre todo
  operaciones de borrado + inserción como `dd`+`i`), comparar `wc -l` del
  fichero resultante contra una copia de seguridad, además de `bash -n`: un
  script puede quedar sintácticamente correcto y aun así haber perdido o
  fusionado una línea silenciosamente.
- Siempre regresar a probar con un caso conocido de fallo real (como se hizo
  reactivando temporalmente el home inválido de `devuser`) tras modificar un
  test, para confirmar que el test corregido sigue detectando problemas
  genuinos y no se ha convertido en un PASS incondicional.
