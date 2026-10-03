# 💿 Troubleshooting y guía de estudio — Etapa 1 (instalación RHEL 7/8/9/10)

Ver formato y regla general en [`troubleshooting/README.md`](../README.md).

Este documento tiene dos usos:

1. **Índice de los casos reales** de troubleshooting de la Etapa 1.
2. **Base de estudio**: todos los comandos que usan los scripts y los tests de esta etapa, con
   una explicación sencilla de qué hace cada uno y para qué sirve al diagnosticar.

> Regla del proyecto: *manual → documentado → repetible → automatizado*. Cada comando de esta
> guía se puede lanzar a mano; los scripts solo los encadenan.

---

## 1. Casos documentados

| Caso | Tema |
|---|---|
| [01 rhel10-bios-gpt-biosboot](01-rhel10-bios-gpt-biosboot.md) 🔎 | RHEL 10 en BIOS: falta partición biosboot (GPT por defecto) |
| [02 limpieza-scripts-alternativos-rhel10](02-limpieza-scripts-alternativos-rhel10.md) | Consolidación: scripts alternativos de RHEL 10 eliminados en favor de `lab.sh` |
| [03 rhel8-checksum-version-real-vs-planeada](03-rhel8-checksum-version-real-vs-planeada.md) 🔎 | RHEL 8: versión real instalada (8.6) distinta de la planeada (8.10) |

🔎 = encontrado de forma orgánica al ejecutar contra las VMs reales.

---

## 2. Flujo de la etapa (orden exacto)

| # | Comando | Script que ejecuta | Dónde corre |
|---|---|---|---|
| 1 | `scripts/lab.sh host-setup` | `scripts/00-host-setup.sh` | Host (Linux Mint) |
| 2 | `scripts/lab.sh network` | `scripts/01-create-network.sh` | Host |
| 3 | `scripts/lab.sh iso --check` / `iso` | `scripts/download-isos.sh` | Host |
| 4 | `scripts/lab.sh vm-create <host> --dry-run` | `scripts/02-create-vm.sh` | Host |
| 5 | `scripts/lab.sh vm-create <host>` | `scripts/02-create-vm.sh` + `kickstart/rhelN.ks.tpl` | Host → Anaconda en la VM |
| 6 | `scripts/lab.sh register <host> <usuario-RH>` | `lab.sh` (ssh + `subscription-manager`) | VM |
| 7 | `scripts/lab.sh test test_install.sh <host>` | `tests/test_install.sh` | VM (como root) |
| 8 | `scripts/lab.sh snapshot create <host> 1` | `scripts/03-snapshot.sh` | Host |

Toda la etapa trabaja contra `qemu:///system` (lo fija `scripts/lib.sh` con
`LIBVIRT_DEFAULT_URI`), así que `virsh` sin `-c` ya apunta al libvirt del sistema.

---

## 3. Comandos de los scripts, explicados

### 3.1 `00-host-setup.sh` — preparar el host

| Comando | Qué hace | Por qué |
|---|---|---|
| `grep -Eq '(vmx\|svm)' /proc/cpuinfo` | Busca las banderas de virtualización por hardware (`vmx` Intel, `svm` AMD) | Sin ellas KVM no funciona: hay que activar VT-x/AMD-V en la BIOS |
| `/lib64/ld-linux-x86-64.so.2 --help \| grep 'x86-64-v3 (supported'` | Pregunta al cargador dinámico qué niveles de la arquitectura x86-64 soporta la CPU | RHEL 10 exige **x86-64-v3**; si el host no lo tiene, `rhel10-app01` no arranca |
| `sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst virt-manager libguestfs-tools cpu-checker libosinfo-bin gettext-base openssl jq curl acl openssh-client` | Instala el hipervisor y las herramientas | `virtinst` trae `virt-install`; `libguestfs-tools` trae `virt-filesystems`/`guestfish` (caso 01); `gettext-base` trae `envsubst`; `libosinfo-bin` trae `osinfo-query` |
| `sudo systemctl enable --now libvirtd` | Arranca libvirt y lo deja activo en cada arranque | `enable` = persistente, `--now` = también ahora |
| `sudo usermod -aG libvirt,kvm "$USER"` | Añade tu usuario a los grupos `libvirt` y `kvm` | `-a` (append) es obligatorio: sin él, `-G` **sustituye** todos tus grupos. Requiere cerrar sesión |
| `sudo install -d -m 2775 -o "$USER" -g libvirt /var/lib/libvirt/lab/{isos,images}` | Crea los directorios con dueño, grupo y permisos en un solo paso | El `2` es el bit **setgid**: los ficheros nuevos heredan el grupo `libvirt`. Fuera de `$HOME` porque `libvirt-qemu` no puede leer tu home (permisos 750 + AppArmor) |
| `sudo virsh pool-info lab-isos` | Consulta si el pool existe (si falla, no existe) | Patrón idempotente: comprobar antes de crear |
| `sudo virsh pool-define-as lab-isos dir --target /var/lib/libvirt/lab/isos` | Define un pool de almacenamiento de tipo directorio | Un pool es "un sitio donde libvirt guarda discos/ISOs" |
| `sudo virsh pool-autostart lab-isos` / `pool-start` | Lo marca para arrancar solo y lo arranca | Un pool definido pero no arrancado no se puede usar |
| `ssh-keygen -t ed25519 -f ~/.ssh/lab_ed25519 -C "adminlab@lab.local"` | Crea la clave SSH del laboratorio | ed25519: clave corta, rápida y moderna. Se inyecta en las VMs desde el kickstart |
| `chmod 700 ~/.ssh` / `chmod 600 ~/.ssh/lab_config` | Permisos restrictivos | `ssh` ignora o rechaza ficheros con permisos demasiado abiertos |
| `Include ~/.ssh/lab_config` (en `~/.ssh/config`) | Carga los alias `Host rhel9-app01 → HostName 10.10.10.13` generados desde `hosts.conf` | Permite `ssh rhel9-app01` sin depender del DNS (evita el problema de nss-mdns con `.local`) |

### 3.2 `01-create-network.sh` — red `lab-net`

| Comando | Qué hace | Por qué |
|---|---|---|
| `virsh net-info lab-net` | Muestra si la red existe y si está activa (`Active: yes`) | Comprobación idempotente |
| `ip route \| grep '^10\.10\.10\.'` | Busca si ya hay una ruta a `10.10.10.0/24` en el host | Si una VPN u otra red usa ese rango, habría conflicto de rutas |
| `virsh net-define fichero.xml` | Registra la red a partir de un XML (`<forward mode='nat'/>`, bridge `virbr-lab`, IP `10.10.10.1/24`, **sin** `<dhcp>`) | NAT porque un bridge sobre Wi-Fi no funciona bien; sin DHCP porque todas las IPs son estáticas |
| `virsh net-autostart lab-net` / `virsh net-start lab-net` | Arranque automático y arranque inmediato | Igual que con los pools |
| `virsh net-dumpxml lab-net` | Imprime el XML real de la red | Para leer el gateway **real**, no suponerlo |
| `ip -br addr show virbr-lab` | Muestra la IP del bridge en formato breve | Debe aparecer `10.10.10.1/24` |
| `sudo ufw allow in on virbr-lab` / `sudo ufw route allow in on virbr-lab` | (Solo si usas ufw) permite tráfico entrante y enrutado por el bridge | ufw puede bloquear el NAT de las VMs |

### 3.3 `download-isos.sh` — descarga y verificación de ISOs

| Comando | Qué hace | Por qué |
|---|---|---|
| `curl ... https://sso.redhat.com/.../token -d grant_type=refresh_token -d client_id=rhsm-api --data-urlencode "refresh_token@-"` | Cambia tu *offline token* por un *access token* temporal | El token entra por **stdin** (`@-`): así no aparece en `ps` ni en el historial |
| `jq -er '.access_token'` | Extrae un campo de una respuesta JSON | `-e` hace que `jq` falle si el campo no existe |
| `curl -H @- "$API_URL/images/<sha256>/download"` | Pide a la API de Red Hat el enlace temporal de la ISO **por checksum** | La API identifica la imagen por SHA-256, no por versión (lección del caso 03) |
| `curl -fL --retry 5 --retry-delay 10 -C - -o fichero.iso.part URL` | Descarga reanudable | `-C -` continúa donde se cortó; `-f` falla con errores HTTP; `.part` evita dar por buena una descarga a medias |
| `sha256sum fichero.iso` | Calcula el hash SHA-256 | Si no coincide con el de `isos.conf`, la ISO está corrupta o no es la que crees |
| `df -BG --output=avail /var/lib/libvirt/lab/isos` | Espacio libre en GB | Evita llenar el disco a mitad de una descarga |
| `mv -n origen destino` | Mueve sin sobrescribir | `-n` (no-clobber) protege una ISO existente |

### 3.4 `02-create-vm.sh` — instalación desatendida con kickstart

| Comando | Qué hace | Por qué |
|---|---|---|
| `awk -v n="$1" '$1==n {print}' scripts/hosts.conf` (función `host_row`) | Lee la fila del host: versión, IP, vCPU, RAM, disco, disco de datos | `hosts.conf` es la **única fuente de verdad** del inventario |
| `virsh dominfo <vm>` | Comprueba si la VM ya existe | Sin `--force` no se destruye nada |
| `virsh destroy <vm>` / `virsh undefine <vm> --remove-all-storage --snapshots-metadata` | (Solo con `--force`) apaga en seco y borra la VM, sus discos y los metadatos de snapshots | `destroy` **no borra**: equivale a desenchufar. El borrado lo hace `undefine` |
| `ssh-keygen -R <ip> -f ~/.ssh/known_hosts_lab` | Borra la huella SSH antigua de esa IP | Una VM reinstalada tiene claves de host nuevas: sin esto, SSH avisa de "posible ataque MITM" |
| `openssl passwd -6 -stdin` | Genera el hash SHA-512 (`$6$...`) de la contraseña | El kickstart usa `rootpw --iscrypted`: la contraseña en claro no se escribe en ningún fichero |
| `envsubst '${LAB_HOSTNAME} ${LAB_IP} ...' < rhelN.ks.tpl > ks.cfg` | Sustituye **solo** las variables listadas en la plantilla | Limitar la lista evita sustituir otros `$` del kickstart |
| `osinfo-query -f short-id os` | Lista los sistemas que conoce la base `osinfo-db` del host | Se elige el `--os-variant` más concreto disponible (Mint puede no conocer `rhel10.2`) |
| `virt-install --name ... --memory ... --vcpus ... --cpu host-passthrough --os-variant ... --disk pool=lab-images,size=N,format=qcow2,bus=virtio --network network=lab-net,model=virtio --graphics none --noautoconsole --wait 60 --location ISO --initrd-inject ks.cfg --extra-args "inst.ks=file:/ks.cfg inst.text console=ttyS0,115200n8"` | Crea la VM y lanza Anaconda con el kickstart | Ver la explicación por opciones justo debajo |
| `virsh domstate <vm>` | Estado de la VM (`running`, `shut off`...) | El kickstart termina con `poweroff` |
| `virsh domblklist <vm> --details` | Lista los discos y lectores de la VM | Para localizar el lector de CD |
| `virsh change-media <vm> <dispositivo> --eject --config --force` | Expulsa la ISO | Si no se expulsa y luego borras la ISO, la VM no arranca |
| `virsh start <vm>` | Arranca la VM ya instalada | |
| `ssh -i ~/.ssh/lab_ed25519 -o BatchMode=yes -o ConnectTimeout=5 adminlab@<ip> true` (función `wait_ssh`) | Intenta entrar por SSH cada 5 s, sin pedir contraseña | `BatchMode=yes` evita que se quede esperando una contraseña; `true` no hace nada: solo prueba la conexión |

**Opciones clave de `virt-install`:**

- `--cpu host-passthrough`: la VM ve la CPU real. **Obligatorio** para RHEL 10 (x86-64-v3).
- `--location ISO --initrd-inject ks.cfg`: arranca el kernel de la ISO e introduce el kickstart en
  el initrd; por eso `inst.ks=file:/ks.cfg` lo encuentra en la raíz.
- `--graphics none` + `console=ttyS0`: toda la instalación va por consola serie
  (`virsh console <vm>`).
- `--wait 60`: espera hasta 60 **minutos**. Si se agota, no distingue "instalación lenta" de
  "Anaconda esperando una respuesta" (lección del caso 01).
- `--channel ...org.qemu.guest_agent.0`: canal para `qemu-guest-agent` (lo comprueba el test).

### 3.5 Kickstart `scripts/kickstart/rhelN.ks.tpl` — lo que deja instalado

| Directiva | Qué hace | Lo verifica el test |
|---|---|---|
| `selinux --enforcing` | SELinux en modo Enforcing | `getenforce` |
| `firewall --enabled --service=ssh` | firewalld activo con SSH permitido | `firewall-cmd --list-services` |
| `network --bootproto=static ... --hostname=...` | IP estática, gateway `10.10.10.1`, DNS de arranque, hostname FQDN | `hostnamectl --static` |
| `services --enabled=sshd,chronyd,qemu-guest-agent` | Servicios habilitados | `systemctl is-active` |
| `user --name=adminlab --uid=1001 --groups=wheel` | Usuario administrador con UID fijo | `id -u adminlab` |
| `ignoredisk --only-use=vda` | Solo toca el disco del sistema; `vdb` queda libre para la Etapa 2 | `test -b /dev/vdb` |
| `part biosboot ...` (**solo RHEL 10**) | Partición de 1 MiB para GRUB2 en BIOS+GPT | Caso 01 |
| `volgroup vg_system` + `logvol / /var swap` | LVM con `lv_root`, `lv_var`, `lv_swap`, en XFS | `lvs`, `findmnt` |
| `%post`: `authorized_keys`, `restorecon -R /home/adminlab/.ssh` | Instala tu clave pública y repone la etiqueta SELinux | Sin `restorecon`, SELinux puede impedir que `sshd` lea la clave |
| `%post`: `/etc/sudoers.d/90-adminlab-bootstrap` | sudo sin contraseña de arranque (lo sustituye la Etapa 2) | — |
| `%post`: `/etc/lab-release` con `LAB_STAGE=1` | Marca la etapa alcanzada | `test -f /etc/lab-release` |
| `%post --log=/root/ks-post.log` + `set -x` | Registra cada comando del `%post` | Primer sitio donde mirar si algo del `%post` falló |

### 3.6 `lab.sh register` — suscripción de Red Hat

| Comando | Qué hace | Por qué |
|---|---|---|
| `ssh -t adminlab@<ip> "sudo subscription-manager register --username <usuario>"` | Registra la VM con tu cuenta | `-t` asigna terminal: la contraseña se teclea en la VM y no pasa por scripts ni logs |
| `sudo subscription-manager status` | Muestra el estado de la suscripción | Debe indicar que el sistema está registrado |

### 3.7 `03-snapshot.sh` — snapshots por etapa

| Comando | Qué hace | Por qué |
|---|---|---|
| `virsh snapshot-info <vm> <nombre>` | Comprueba si el snapshot ya existe | No se sobrescribe nunca |
| `virsh shutdown <vm>` | Apagado ordenado (ACPI) | Snapshot consistente: sin escrituras a medias en disco |
| `virsh destroy <vm>` | Apagado forzado si en 120 s no se apagó | Último recurso; no borra nada |
| `virsh snapshot-create-as <vm> --name rhel9-stage1-complete --description "..."` | Crea un snapshot interno del qcow2 | Nombre estable `rhelN-stageM-complete` |
| `virsh snapshot-list <vm>` | Lista los snapshots | |
| `virsh snapshot-revert <vm> <nombre>` | Vuelve al estado guardado | Base de los ejercicios de troubleshooting: romper → diagnosticar → revertir |
| `virsh snapshot-delete <vm> <nombre>` | Borra el snapshot | |

---

## 4. Comandos de los tests (`tests/test_install.sh`), explicados

Se lanza con `scripts/lab.sh test test_install.sh <host|all>`, que copia `tests/` a la VM
(`push`) y lo ejecuta como root con `sudo -n bash lab-scripts/tests/test_install.sh`.
Cada `check` devuelve **PASS** si el comando sale con código 0. Todos son de **solo lectura**.

Para estudiar o diagnosticar un FAIL, lanza el comando manual dentro de la VM:

| Comprobación | Comando manual equivalente | Qué demuestra | Si da FAIL, mirar... |
|---|---|---|---|
| Hostname estático = `<host>.lab.local` | `hostnamectl --static` | Que el kickstart aplicó `--hostname` | `network` del kickstart; `hostnamectl set-hostname` |
| Versión mayor = RHEL N | `. /etc/os-release; echo $VERSION_ID` | Que se instaló la ISO correcta | `cat /etc/redhat-release` (caso 03) |
| SELinux Enforcing | `getenforce` | Política activa y aplicándose | `sestatus`, `/etc/selinux/config` |
| firewalld activo | `systemctl is-active firewalld` | Cortafuegos en marcha | `systemctl status firewalld` |
| firewalld permite ssh | `firewall-cmd --list-services` | El servicio `ssh` está en la zona por defecto | `firewall-cmd --get-active-zones` |
| sshd activo y habilitado | `systemctl is-active sshd; systemctl is-enabled sshd` | En marcha **ahora** y **tras reiniciar** (son cosas distintas) | `journalctl -u sshd -b` |
| chronyd activo | `systemctl is-active chronyd` | Servicio de hora en marcha | `chronyc sources -v` |
| qemu-guest-agent activo | `systemctl is-active qemu-guest-agent` | El host puede hablar con la VM por el canal virtio | Desde el host: `virsh qemu-agent-command <vm> '{"execute":"guest-ping"}'` |
| LVM: `vg_system` con `lv_root`, `lv_swap`, `lv_var` | `lvs vg_system` | Particionado LVM del kickstart | `vgs`, `pvs`, `lsblk` |
| `/` es XFS | `findmnt -no FSTYPE /` | Sistema de ficheros por defecto de RHEL 7+ | `lsblk -f` |
| `/var` es un LV aparte | `findmnt -no SOURCE /var` | Logs separados de `/`: si `/var` se llena, `/` no | `df -hT /var` |
| swap activa | `cat /proc/swaps` | Más de una línea = cabecera + al menos un swap | `swapon --show`, `free -h` |
| adminlab UID 1001 en `wheel` | `id adminlab` | UID fijo (estable entre etapas) y grupo administrador | `getent passwd adminlab` |
| adminlab tiene `authorized_keys` | `ls -lZ /home/adminlab/.ssh/` | Clave instalada (`-Z` muestra también la etiqueta SELinux) | `/root/ks-post.log` |
| `/etc/lab-release` existe | `cat /etc/lab-release` | El `%post` terminó; marca `LAB_STAGE` | `/root/ks-post.log` |
| Disco `/dev/vdb` presente (si `DATA_GB > 0`) | `lsblk /dev/vdb` | Disco de datos listo para la Etapa 2 | Desde el host: `virsh domblklist <vm>` |

**Leer el resultado:** cada test termina con `--- test_install en <host>: N PASS, M FAIL`, y
`lab.sh test` imprime una tabla global por host (PASS, FAIL, tiempo, estado). La etapa solo está
cerrada con **0 FAIL**.

---

## 5. Comandos de diagnóstico de los casos reales

| Comando | Qué hace | Caso |
|---|---|---|
| `virsh console <vm> --force` | Conecta a la consola serie (salir: `Ctrl+]`); `--force` quita otra sesión abierta | 01 — es la única forma de ver qué pregunta Anaconda |
| `sudo virt-filesystems --long --all -a <disco>.qcow2` | Lista particiones y sistemas de ficheros de un disco sin arrancar la VM | 01 — reveló el disco vacío |
| `sudo guestfish --ro -a <disco>.qcow2 run : pread-device /dev/sda 512 0 \| xxd \| tail -3` | Lee los primeros 512 bytes (MBR) en solo lectura (`--ro`) | 01 — sin `55 aa` al final no hay firma de arranque |
| `virsh qemu-monitor-command <vm> --hmp "info registers"` | Muestra los registros de la CPU virtual | 01 — `HLT=1` = CPU parada esperando, no colgada |
| `ksvalidator -v RHEL10 rhel10.ks` | Valida la sintaxis de un kickstart para una versión concreta | 01 — antes de reinstalar (paquete `pykickstart`) |
| `cat /etc/redhat-release` | Versión menor exacta instalada | 03 — reveló 8.6 en vez de 8.10 |
| Línea `[INFO] <vm>: RHEL N, ISO <fichero>` de `vm-create` | El script imprime la ISO que va a usar | 03 — leer el log antes de dar algo por hecho |

---

## 6. Chuleta: síntoma → primeros comandos

| Síntoma | Primeros comandos |
|---|---|
| `vm-create` no avanza y no da error | `virsh console <vm> --force` (¿Anaconda pregunta algo?) |
| La VM no arranca tras instalar | `virsh domblklist <vm> --details` (¿ISO aún montada o borrada?), `virsh console <vm>` |
| SSH no responde tras instalar | `virsh domstate <vm>`, `ping 10.10.10.X`, `virsh console <vm>` y dentro `/root/ks-post.log` |
| SSH avisa de huella cambiada | `ssh-keygen -R <ip> -f ~/.ssh/known_hosts_lab` (solo si **tú** reinstalaste la VM) |
| `Permission denied (publickey)` | `ls -lZ /home/adminlab/.ssh/`, `restorecon -Rv /home/adminlab/.ssh` |
| La ISO "no es la que esperaba" | `sha256sum <iso>` frente a `config/isos.conf`; nombre completo del fichero |
| `virsh` no ve las VMs como usuario | `id` (¿estás en `libvirt`?); `virsh -c qemu:///system list --all` |
| Red `lab-net` inactiva | `virsh net-info lab-net`, `virsh net-start lab-net`, `ip -br addr show virbr-lab` |

---

## 7. Preguntas de repaso

1. ¿Qué diferencia hay entre `virsh destroy` y `virsh undefine`?
2. ¿Por qué RHEL 10 necesita `--cpu host-passthrough` y qué es x86-64-v3?
3. ¿Por qué hace falta una partición `biosboot` en BIOS + GPT y no en BIOS + MBR?
4. ¿Qué diferencia hay entre `systemctl is-active` y `systemctl is-enabled`?
5. ¿Para qué sirve `restorecon` después de crear ficheros en el `%post`?
6. ¿Por qué se descarga la ISO por checksum y no por número de versión?
7. ¿Por qué `usermod -aG` y no `usermod -G`?
8. ¿Por qué apagar la VM antes de un snapshot interno de qcow2?
