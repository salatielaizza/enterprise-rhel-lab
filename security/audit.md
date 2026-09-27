# Auditoría con auditd (Etapa 5)

## Objetivo
Vigilar con `auditd` los ficheros más sensibles del sistema (identidades, SSH, sudo) y saber consultar esos eventos con `ausearch`/`aureport`.

## Preparación
Etapas 1-4 completadas. `scripts/stage5/02-audit-rules.sh` instala `audit` (si falta), añade `/etc/audit/rules.d/lab-hardening.rules` y las carga con `augenrules --load` (no requiere reiniciar `auditd` en la mayoría de los casos).

## Procedimiento manual y comandos
| Comando | Qué hace | Por qué | Salida / fallo |
|---|---|---|---|
| `sudo auditctl -l` | Lista las reglas cargadas en el kernel | Confirmar que se aplicaron | Debe incluir las rutas vigiladas |
| `sudo auditctl -w /ruta -p wa -k etiqueta` | Añade una regla de vigilancia (escritura+atributos) **en caliente** | Prueba rápida antes de hacerla persistente | No sobrevive a un reinicio por sí sola |
| `/etc/audit/rules.d/*.rules` + `sudo augenrules --load` | Reglas persistentes | Se recompilan a `/etc/audit/audit.rules` y se cargan sin reiniciar el servicio | Falla si hay una sintaxis inválida: revisa con `auditctl -l` después |
| `sudo ausearch -k lab-identity` | Busca eventos por la etiqueta (`-k`) de una regla | Filtrar sin bucear en el log crudo | Sin resultados = nadie ha tocado esa ruta desde el arranque/rotación |
| `sudo ausearch -f /etc/shadow` | Busca eventos sobre un fichero concreto | Alternativa a filtrar por clave | — |
| `sudo aureport --auth --summary` / `aureport -k` | Informes agregados (autenticación, por clave, etc.) | Vista rápida sin parsear a mano | — |
| `sudo systemctl status auditd` | Estado del servicio | auditd corre siempre como proceso independiente del kernel (que es quien genera los eventos) | — |

## Automatización
`scripts/stage5/02-audit-rules.sh` instala el paquete `audit` si falta, escribe `/etc/audit/rules.d/lab-hardening.rules` con reglas `-w` sobre `/etc/passwd`, `/etc/shadow`, `/etc/group`, `/etc/ssh/sshd_config` y `/etc/sudoers` (+ `/etc/sudoers.d/`), y las carga con `augenrules --load`.

## Verificación
`tests/test_audit.sh`: `auditd` activo y habilitado, las reglas mínimas presentes en `auditctl -l`, fichero de reglas del lab presente.

## Troubleshooting relacionado
Ver caso `20-ausearch-colgado-timeout.md` (`ausearch` puede colgarse sin responder; siempre con timeout/`&` en scripts que lo invoquen).

## Errores comunes
Editar `/etc/audit/audit.rules` a mano en vez de un fichero en `rules.d/` (se sobrescribe al regenerar); olvidar `augenrules --load` tras cambiar las reglas; poner reglas demasiado amplias (`-w /` o `-w /etc`) que generan tanto ruido que el log deja de ser útil.

## Diferencias RHEL 7 / 8 / 9 / 10
El paquete se llama `audit` en las cuatro; `augenrules` está disponible desde RHEL 7 pero conviene confirmar la ruta exacta de `rules.d` la primera vez (◦). En modo `immutable` (regla `-e 2`) auditd requiere **reiniciar la máquina** para cambiar cualquier regla — el lab **no** activa ese modo a propósito, para poder iterar sin reiniciar.

## Prevención
Reglas específicas y con `-k <etiqueta>` siempre (facilita buscar después); revisar `auditctl -l` tras cada cambio, nunca asumir que "se ha cargado"; no activar `-e 2` (immutable) salvo que el ejercicio sea precisamente ese.

## Relevancia profesional
La auditoría (`auditd`, `ausearch`, cumplimiento normativo) es un tema habitual en vacantes de administración de sistemas orientadas a *compliance*/seguridad, y aparece junto a SELinux en los temarios de certificación RHCSA/RHCE citados en [Whizlabs](https://www.whizlabs.com/blog/red-hat-linux-system-administrator-interview-questions/) y en las guías de [preparación RHCSA (LinuxCert Guru)](https://linuxcert.guru/blog/?name=top-google-question-rhcsa). Saber responder "¿quién cambió este fichero y cuándo?" con evidencia real del sistema es una habilidad muy valorada en entornos regulados (banca, telco).

## Ampliaciones futuras
Añadir reglas de vigilancia sobre la configuración de un servidor web cuando se despliegue (Etapa 9), y sobre altas/bajas de usuarios de prueba creados específicamente para practicar auditoría de identidades (`useradd`/`userdel` con `-k lab-identity-changes`).
