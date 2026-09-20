# 14 — Zona que no carga

**Objetivo**: distinguir "registro erróneo" de "zona no cargada" leyendo el log de named.
**Preparación**: Etapa 4; snapshot de dns01.

## Cómo provocar
En dns01: `sudo mv /var/named/lab.local.zone /var/named/lab.local.zone.off && sudo rndc reload` (o restart). Variante: quitar el punto final de `dns01.lab.local.` en el registro NS/SOA.

## Síntoma
`dig @10.10.10.20 dns01.lab.local` → `status: SERVFAIL` (zona configurada pero no cargada) — o `NXDOMAIN` si la zona desaparece por completo de `named.conf`. Los nombres externos siguen resolviendo.

## Hipótesis
Servicio caído (no: responde), registro erróneo (no: falla toda la zona), zona rota.

## Diagnóstico
```bash
sudo journalctl -u named -n 30            # "zone lab.local/IN: loading from master file … failed: file not found"
sudo named-checkconf -z /etc/named.conf   # muestra el error de carga
sudo named-checkzone lab.local /var/named/lab.local.zone
ls -lZ /var/named/                        # propietario root:named, contexto named_zone_t
```

## Causa raíz
El fichero de zona falta o es inválido (sintaxis, punto final, permisos/SELinux).

## Solución
Restaurar/corregir el fichero (`mv` de vuelta o `lab.sh stage4-dns`), `restorecon -R /var/named`, `named-checkzone`, `rndc reload`.

## Validación
`dig @10.10.10.20 dns01.lab.local +short` → 10.10.10.20; `test_dns.sh`.

## Prevención
Validación previa, permisos `root:named 0640`, `restorecon`, y reversión con snapshot/Git.
