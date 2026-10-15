# 📜 Etapa 6 — Bash avanzado y scripting (`scripts/stage6/`)

## Qué hace esta etapa

Instala dos herramientas propias escritas con patrones de bash "de producción" y programa una de ellas
con un **temporizador de systemd** (en vez de cron). El objetivo no es el resultado, sino practicar
`set -euo pipefail`, `trap`, `getopts`, arrays (normales y asociativos), *process substitution* y unidades
`.service` + `.timer`.

## Cómo se lanza

```bash
scripts/lab.sh stage6 <host|all>
```

## Ficheros

| Fichero | Corre en | Qué hace | Qué modifica |
|---|---|---|---|
| `01-bash-tools.sh` | todas (root) | Instala las dos herramientas (validadas con `bash -n`), crea `lab-healthcheck.service` (`Type=oneshot`) y `lab-healthcheck.timer` (1 min tras arrancar, después cada 5 min), lo habilita y lanza una primera ejecución. Termina con `set_stage 6` | `/usr/local/sbin/`, `/etc/systemd/system/lab-healthcheck.{service,timer}`, `/var/log/lab-healthcheck.log` |
| `files/lab-healthcheck.sh` | (instalada) | Comprueba servicios según el host (`sshd`, `chronyd` y `named` en `dns01`), uso de `/` y `/var` frente a un umbral y la carga; registra en el log con fecha. Opciones `-v` (verbose) y `-t <umbral %>`. Sale con 1 si algo falla | Solo escribe su log |
| `files/lab-logscan.sh` | (instalada) | Cuenta los intentos de SSH fallidos por IP en los últimos N minutos (`-m`) leyendo `journalctl -u sshd` | Nada (solo lectura) |

## Uso manual de las herramientas

```bash
ssh rhel9-app01
sudo /usr/local/sbin/lab-healthcheck.sh -v -t 80
sudo /usr/local/sbin/lab-logscan.sh -m 120
systemctl list-timers lab-healthcheck.timer
```

## Lección aprendida en esta etapa

`[[ cond ]] && cmd` como **última línea de una función** devuelve 1 si la condición es falsa y, con `set -e`,
aborta el script: el temporizador fallaba solo cuando se ejecutaba sin `-v`. Por eso en todo el repo se usa
`if ...; then ...; fi` explícito (caso [`etapa6/01`](../../troubleshooting/etapa6/01-log-verbose-set-e-lab-healthcheck.md)).

## Cómo se verifica

```bash
scripts/lab.sh test all <host|all>     # test_bash_tools
```

## Documentación relacionada

- Checklist: [`checklists/etapa6.md`](../../checklists/etapa6.md)
- Tema: [`scripting/bash-avanzado.md`](../../scripting/bash-avanzado.md)
- Patrones explicados y trampas de `set -e`: [`troubleshooting/etapa6/README_troubleshooting_etapa6.md`](../../troubleshooting/etapa6/README_troubleshooting_etapa6.md)
