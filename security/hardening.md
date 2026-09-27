# Hardening general del sistema (Etapa 5)

## Objetivo
Aplicar una base de hardening más allá de SSH (ya hecho en la Etapa 4): política de contraseñas, caducidad de cuentas, parámetros de red a nivel de kernel (`sysctl`) y un aviso legal de acceso.

## Preparación
Etapas 1-4 completadas. `scripts/stage5/03-os-hardening.sh` aplica los cuatro bloques de forma idempotente (con copia de seguridad de cada fichero tocado) y es el último script de la etapa (marca `LAB_STAGE=5`).

## Procedimiento manual y comandos
| Comando | Qué hace | Por qué | Salida / fallo |
|---|---|---|---|
| `sudo vi /etc/security/pwquality.conf` (`minlen=12`, `dcredit=-1`, `ucredit=-1`, `lcredit=-1`, `ocredit=-1`) | Exige contraseñas de al menos 12 caracteres con mayúscula, minúscula, dígito y símbolo | Solo se aplica al **cambiar** la contraseña, no retroactivo | Pruébalo con `passwd <usuario>` |
| `sudo vi /etc/login.defs` (`PASS_MAX_DAYS 90`, `PASS_MIN_DAYS 1`, `PASS_WARN_AGE 7`) | Caducidad de contraseñas para usuarios **nuevos** | Los ya existentes se actualizan con `chage` | `sudo chage -l <usuario>` para comprobar uno concreto |
| `sudo vi /etc/sysctl.d/98-lab-hardening.conf` + `sudo sysctl --system` | Parámetros de red del kernel persistentes | Mitigar *IP spoofing*/*source routing*/redirecciones ICMP no autorizadas | `sysctl -n <parámetro>` para comprobar el valor efectivo |
| `sudo vi /etc/issue` | Aviso mostrado **antes** de iniciar sesión (consola/tty) | Requisito habitual de cumplimiento ("acceso solo autorizado") | No afecta a SSH salvo que también se configure `Banner` ahí |
| `sudo chage -l <usuario>` | Ver caducidad efectiva de un usuario | Confirmar que login.defs se aplicó a los nuevos altas | — |

## Automatización
`scripts/stage5/03-os-hardening.sh`: aplica los 4 bloques anteriores de forma idempotente (comprueba antes de escribir), hace `cp -a` de cada fichero tocado con timestamp, y termina con `set_stage 5`.

## Verificación
`tests/test_hardening.sh`: `minlen>=12`, `PASS_MAX_DAYS<=90`, los 3 parámetros `sysctl` esperados, ficheros de drop-in y `/etc/issue` presentes.

## Errores comunes
Cambiar `login.defs` esperando que afecte a usuarios ya existentes (no lo hace: hace falta `chage`); poner `PASS_MAX_DAYS` tan bajo que resulte imposible de gestionar en un laboratorio de aprendizaje; olvidar `sysctl --system` tras crear el fichero en `sysctl.d` (el valor no se aplica hasta releer la configuración o reiniciar).

## Diferencias RHEL 7 / 8 / 9 / 10
`pwquality` sustituye a `cracklib` desde RHEL 7 en adelante, así que el fichero y las claves son las mismas en las 4 versiones. El mecanismo de aplicación de PAM (`authselect` en 8+ vs `authconfig` en 7) puede cambiar cómo se regenera el stack de PAM si además se toca `system-auth` (◦, este script no lo hace: solo edita `pwquality.conf`, que ambos mecanismos respetan).

## Prevención
Cambiar un parámetro cada vez y volver a correr los tests, no todos a la vez sin comprobar; guardar siempre la copia de seguridad con timestamp; documentar el motivo de cada valor elegido (no copiar una plantilla de hardening sin entenderla).

## Relevancia profesional
El hardening de sistemas (políticas de contraseña, sysctl, banners de acceso) es contenido habitual en entrevistas de sysadmin/DevOps de nivel medio, normalmente presentado como pregunta de escenario ("¿cómo asegurarías un servidor recién instalado antes de ponerlo en producción?") — ver los cuestionarios del [Linux SysAdmin Interview Prep Kit](https://toolsunpacked.com/linux-sysadmin-interview-prep-kit/) y de [Red Hat System Administrator (Whizlabs)](https://www.whizlabs.com/blog/red-hat-linux-system-administrator-interview-questions/). Es también uno de los pilares de herramientas de auditoría automatizada como [Lynis](https://en.wikipedia.org/wiki/Lynis), que muchas empresas usan para puntuar sus propios servidores.

## Ampliaciones futuras
Cuando exista un servicio web real (Apache httpd/NGINX, Etapa 9), añadir su propio hardening específico (cabeceras HTTP de seguridad, TLS, límites de tasa) y comparar el mismo enfoque de "un cambio, un test, una copia de seguridad" aplicado a un servicio distinto a SSH.
