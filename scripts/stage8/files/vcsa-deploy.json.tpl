{
  "__version": "${VCSA_TPL_VERSION}",
  "__comments": "enterprise-rhel-lab Etapa 8: vCenter (tiny) desplegado en esxi02. Renderizado por scripts/stage8/07-vcsa-deploy.sh; las contraseñas se inyectan con jq en un fichero temporal 600 que se borra al terminar.",
  "new_vcsa": {
    "esxi": {
      "hostname": "${VCSA_ESXI_HOST}",
      "username": "root",
      "password": "",
      "deployment_network": "VM Network",
      "datastore": "${VCSA_DATASTORE}"
    },
    "appliance": {
      "thin_disk_mode": true,
      "deployment_option": "tiny",
      "name": "vcsa01"
    },
    "network": {
      "ip_family": "ipv4",
      "mode": "static",
      "system_name": "vcsa01.${LAB_DOMAIN}",
      "ip": "10.10.10.63",
      "prefix": "24",
      "gateway": "${LAB_GW}",
      "dns_servers": ["${LAB_DNS_SERVER}"]
    },
    "os": {
      "password": "",
      "ntp_servers": "${LAB_DNS_SERVER}",
      "ssh_enable": true
    },
    "sso": {
      "password": "",
      "domain_name": "vsphere.local"
    }
  },
  "ceip": {
    "settings": {
      "ceip_enabled": false
    }
  }
}
