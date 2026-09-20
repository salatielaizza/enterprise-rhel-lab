# Procesos, señales y prioridades

## 1. Objetivo
Observar, priorizar y terminar procesos; interpretar estados (R, S, D, Z, T) y carga (`uptime`, `top`).

## 2. Prerrequisitos
VM con `procps-ng` y `psmisc` (incluidos por el kickstart).

## 3. Arquitectura
Todo proceso tiene PID, PPID, UID, estado y cgroup. systemd (PID 1) es el ancestro; `lab-app.service` es el proceso de práctica.

## 4. Procedimiento manual y comandos
| Comando | Qué hace | Por qué | Salida / fallo |
|---|---|---|---|
| `ps -eo pid,ppid,user,stat,ni,pcpu,pmem,cmd --sort=-pcpu \| head` | Procesos ordenados por CPU | Localizar el "culpable" | Columna STAT: `R` ejecutando, `S` dormido, `D` espera E/S (no interrumpible), `Z` zombi, `T` parado |
| `top` (`P` CPU, `M` memoria, `1` por CPU, `k` matar) | Vista interactiva | Carga y consumo en vivo | `load average` >> nº de vCPU = saturación |
| `pgrep -a lab-app` / `pstree -p` | Buscar por nombre / árbol | Encontrar PID y padre | — |
| `kill -TERM PID` (15) / `kill -KILL PID` (9) / `kill -HUP PID` (1) | Enviar señales | TERM = cierre ordenado; KILL no se puede capturar; HUP suele recargar | `kill -l` lista señales |
| `pkill -u devuser` / `killall nombre` | Matar por usuario/nombre | Cuidado con el alcance | — |
| `nice -n 10 cmd` / `renice +10 -p PID` | Prioridad (−20 alta … 19 baja) | Repartir CPU | Solo root baja el valor de nice |
| `cmd &`, `jobs`, `fg`, `bg`, `Ctrl+Z` | Control de trabajos de la shell | Tareas en segundo plano | Ligados a la sesión (usar systemd/tmux para persistir) |
| `systemctl status lab-app`, `systemd-cgls` | Procesos por unidad/cgroup | Ver qué proceso pertenece a qué servicio | — |
| `ls -l /proc/PID/`, `cat /proc/PID/status` | Estado interno del proceso | Depuración fina | — |

`htop` **no está** en los repositorios base de RHEL (viene de EPEL): usa `top`.

## 5. Resultado esperado y validación
Puedes generar carga (`yes > /dev/null &`), verla en `top`, bajarle prioridad y terminarla sin afectar a `sshd`.

## 6. Troubleshooting
- Proceso que no muere con TERM: bloqueado en estado `D` (E/S) → no responde ni a KILL hasta que la E/S termina.
- Zombis (`Z`): el padre no recoge el estado; se resuelve terminando/reiniciando al **padre**, no al zombi.
- `lab-app` "resucita": `Restart=on-failure` → detenerlo con `systemctl stop`, no con `kill`.

## 7. Errores comunes
`kill -9` como primera opción; `killall` en sistemas donde el nombre coincide con otros procesos; confundir *load average* con % de CPU.

## 8. Diferencias RHEL 7 / 8 / 9 / 10
Herramientas equivalentes. El **controlador de cgroups** difiere (v1 en 7/8, v2 por defecto en 9+ ◦): afecta a límites de recursos (`MemoryLimit=` vs `MemoryMax=`). Comprobar con `stat -fc %T /sys/fs/cgroup` (`tmpfs` = v1, `cgroup2fs` = v2).

## 9. Automatización
Ninguna (práctica interactiva).

## 10. Ejercicio
Crea 2 procesos `yes` (uno con `nice -n 19`), compara su %CPU; limita `lab-app` con `systemctl set-property lab-app CPUQuota=20%` y observa; provoca un zombi con un script que hace `sleep` en un hijo sin `wait`.

## 11. Criterios de aceptación
Diagnosticas un proceso descontrolado y lo detienes con la señal adecuada, explicando por qué.
