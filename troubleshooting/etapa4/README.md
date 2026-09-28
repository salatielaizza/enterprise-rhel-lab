# Troubleshooting — Etapa 4 (BIND, chrony, SSH/SFTP)

Ver formato y regla general en [`troubleshooting/README.md`](../README.md).

| Caso | Tema |
|---|---|
| [01 dns-failure](01-dns-failure.md) | `dns01` caído: clientes sin resolución |
| [02 ssh-failure](02-ssh-failure.md) | `Permission denied (publickey)` |
| [03 time-sync-failure](03-time-sync-failure.md) | Cliente sin sincronizar con `dns01` |
| [04 dns-wrong-record](04-dns-wrong-record.md) | Registro A erróneo en la zona |
| [05 dns-wrong-zone](05-dns-wrong-zone.md) | Zona que no carga |
| [06 dns-cambiado-en-perfil-pero-no-en-resolv-rhel8](06-dns-cambiado-en-perfil-pero-no-en-resolv-rhel8.md) | DNS actualizado en nmcli pero no en `resolv.conf` (solo RHEL 8) |
| [07 sftpdemo-falsos-positivos-pwck-y-test-ssh](07-sftpdemo-falsos-positivos-pwck-y-test-ssh.md) | `sftpdemo` con chroot: `pwck` y test de `ChrootDirectory` con falsos positivos |
