# Tests

Scripts **PASS/FAIL de solo lectura** que se ejecutan *dentro* de las VMs (como root). Se lanzan desde el host:

```bash
scripts/lab.sh test all all                 # todo lo aplicable a la etapa alcanzada, en las 6 VMs
scripts/lab.sh test test_users.sh rhel9-app01
```
| Test | Etapa | Comprueba |
|---|---|---|
| `test_install.sh` | 1 | versión, hostname, SELinux, firewalld, sshd, LVM del sistema, XFS, swap, adminlab |
| `test_users.sh` | 2 | UID/GID fijos, membresías, `chage`, sudoers (perfiles y validez) |
| `test_permissions.sh` | 2 | dueños, modos, setgid/sticky, ACL, acceso funcional, contextos SELinux |
| `test_storage.sh` | 2 | LVM `vg_data`, XFS, fstab por UUID, montajes, VG con espacio libre |
| `test_services.sh` | 2/4 | servicios base y `lab-app` (activo, enabled, Restart, journal, sin AVC) |
| `test_network.sh` | 3 | IP, gateway, `lab0`, DNS esperado según etapa, pings, salida a Internet |
| `test_dns.sh` | 4 | A y PTR de todos los hosts contra dns01; estado de BIND en dns01 |
| `test_time.sh` | 4 | chrony activo, Leap Normal, desfase < 1 s, cliente sincronizado con dns01 |
| `test_ssh.sh` | 4 | `sshd -t`, ajustes efectivos de endurecimiento, claves, SFTP enjaulado |
| `run_all.sh` | — | ejecuta los aplicables según `LAB_STAGE` de `/etc/lab-release` |

Variables: `TEST_PEERS=all` (ping entre todos los hosts en `test_network.sh`). Código de salida ≠ 0 si algún test falla.
Los tests no modifican configuración; los que prueban permisos crean y borran un fichero temporal.
Resultado esperado tras cada etapa: **0 FAIL**. Guarda la salida en `results/` como evidencia.
