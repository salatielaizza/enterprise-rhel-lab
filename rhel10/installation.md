# RHEL 10 — Instalación de rhel10-app01

> Estado: **[NO VERIFICADO]** — procedimiento preparado y validado estáticamente
> (`bash -n`, `shellcheck`, dry-run con libvirt simulado). Pendiente de ejecución real.

## Objetivo

Añadir una cuarta generación al laboratorio para comparar **RHEL 7 → 8 → 9 → 10**
con una VM de función equivalente a `rhel7/8/9-app01`, sin alterar nombres, IPs
ni estructura existentes.

## Prerrequisitos

| Requisito | Cómo se comprueba | Por qué |
|---|---|---|
| CPU del host x86-64-v3 (AVX2, BMI2, FMA, MOVBE…) | `scripts/00-host-audit.sh` | RHEL 10 sube el baseline de v2 a v3; sin ello el instalador no arranca |
| Fase 1 (libvirt) y Fase 2 (`lab-net`) completadas | `virsh -r net-info lab-net` | La VM se conecta solo a lab-net |
| ISO RHEL 10 DVD verificada | `scripts/download-isos.sh --verify --only rhel10` | Instalación offline y reproducible |
| Clave pública SSH del administrador | `ls ~/.ssh/id_ed25519.pub` | Acceso sin contraseña; root bloqueado |

[TEÓRICO] El i5-12400F (Alder Lake) y también el i5 de 6.ª gen (Skylake) del portátil
soportan x86-64-v3. **Confírmalo con la auditoría**, no con esta tabla.

## Arquitectura

```text
lab-net 10.10.10.0/24  (NAT libvirt, aislada de la red física)
 ├─ rhel7-app01   10.10.10.11   legacy
 ├─ rhel8-app01   10.10.10.12
 ├─ rhel9-app01   10.10.10.13
 ├─ rhel10-app01  10.10.10.14   ← NUEVO (sigue el patrón .11/.12/.13)
 ├─ dns01         10.10.10.20
 ├─ ansible01     10.10.10.30
 ├─ rhel9-web01   10.10.10.40   (reservado)
 └─ rhel9-monitor01 10.10.10.50 (reservado)
```

Sizing: **2 vCPU / 2048 MiB / 30 GB qcow2 thin** (igual que el resto de app01; RHEL 10
minimal no necesita más). Con 31 GB de RAM en el host, todas las VMs caben, pero no
es necesario tener las cuatro app01 arrancadas a la vez salvo en pruebas comparativas.

## Procedimiento

1. Auditoría (solo lectura): `./scripts/00-host-audit.sh`
2. Descargar ISO: `./scripts/download-isos.sh --dry-run --only rhel10` y luego sin `--dry-run`
3. Dry-run de creación: `./scripts/02b-create-vm-rhel10.sh`
4. Revisar la tabla "VM PROPUESTA" (Disk = qcow2, Network = lab-net)
5. Crear: `./scripts/02b-create-vm-rhel10.sh --apply` (pide escribir `crear rhel10-app01`)
6. Validar: `./tests/test_rhel10.sh --vm`
7. Snapshot: `virsh -c qemu:///system snapshot-create-as rhel10-app01 rhel10-stage1-complete`

## Comandos

**`--cpu host-passthrough`** — qué hace: expone a la VM el modelo de CPU real del host.
Por qué: los modelos genéricos de QEMU pueden no anunciar AVX2 y RHEL 10 fallaría
("CPU not supported" / kernel panic temprano). Salida esperada dentro de la VM:
`/lib64/ld-linux-x86-64.so.2 --help` muestra `x86-64-v3 (supported, searched)`.
Si aparece sin `supported`, revisa `virsh dumpxml rhel10-app01 | grep cpu`.
Contrapartida: una VM host-passthrough no es migrable en vivo a un host con otra CPU.

**`--os-variant`** — le dice a libvirt qué dispositivos por defecto usar. Si el
`osinfo-db` de Mint 22 no conoce `rhel10.x`, el script usa la mayor `rhel9.x`
(mismos drivers virtio). Solo afecta a valores por defecto de hardware virtual,
no a lo que se instala. Se documenta en la evidencia.

**`--location ISO --initrd-inject ks`** — virt-install extrae kernel/initrd de la ISO
e inyecta el kickstart en el initrd; `inst.ks=file:/rhel10-app01.ks` lo usa.
Ventaja frente a servir el kickstart por HTTP: no hay que abrir ningún puerto en el host.

## Resultado esperado

VM instalada sin interacción, arrancando desde `vda`, con `adminlab` en `wheel`,
root bloqueado, SELinux Enforcing, firewalld con solo `ssh`, chronyd activo.

## Validación

`./tests/test_rhel10.sh --vm` → todas las líneas `PASS`, y un fichero
`evidence/rhel10-app01/stage1-*.txt` con las salidas marcadas `[VERIFICADO][VM]`.

## Troubleshooting

| Síntoma | Comprobación | Causa probable |
|---|---|---|
| Kernel panic / "CPU not supported" al arrancar el instalador | `virsh dumpxml rhel10-app01 \| grep -A2 '<cpu'` | Falta host-passthrough |
| `Could not access storage file ... Permission denied` | salida del dry-run §7 | libvirt-qemu no atraviesa tu `$HOME` (ver Permisos) |
| Instalación se queda esperando | `virsh console rhel10-app01` | Error en kickstart (se muestra en consola) |
| Sin red tras instalar | `nmcli con show` en la VM | `--gateway` distinto del real de lab-net |

### Permisos (ISO dentro de tu home)

En Ubuntu 24.04 / Mint 22 el home suele tener permisos 750 y el usuario
`libvirt-qemu` no puede leer ISOs dentro. El script **se detiene** y no lo arregla solo.
Opciones (requieren tu confirmación, modifican fuera del proyecto):

- A) Copiar la ISO a `/var/lib/libvirt/images/iso/` (recomendado, no cambia permisos de tu home)
- B) `setfacl -m u:libvirt-qemu:x` en cada directorio de la ruta (solo "atravesar", no listar)

## Errores comunes

- Usar el ISO "Boot" en lugar del "DVD": requiere red y registro para instalar.
- Olvidar que RHEL 10 ya no soporta ficheros `ifcfg-*` (ver differences.md).
- Suponer que VNC está disponible en el instalador (en RHEL 10 el acceso gráfico remoto es por RDP) [TEÓRICO].

## Diferencias RHEL 7/8/9

Ver `rhel10/differences.md` y la matriz de `comparison/`.

## Automatización futura

Etapa 7: el kickstart se convierte en plantilla Jinja2 y la creación en un rol
`libvirt_vm`; los parámetros de esta VM pasan al inventario (`host_vars/rhel10-app01.yml`).

## Ejercicio práctico

Crea la VM con un modelo de CPU genérico (`--cpu qemu64`) en una VM de pruebas
desechable y documenta el error. Explica por qué RHEL 9 sí arranca con ese modelo y RHEL 10 no.

## Criterios de aceptación

- [ ] `test_rhel10.sh --vm` todo PASS
- [ ] Evidencia guardada en `evidence/rhel10-app01/`
- [ ] Snapshot `rhel10-stage1-complete` creado
- [ ] Registro DNS A/PTR añadido en dns01 (Etapa 4)
- [ ] Columna RHEL 10 de la matriz rellenada con datos `[VERIFICADO]`
