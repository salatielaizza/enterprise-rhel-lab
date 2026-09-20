; Zona directa lab.local — el serial (@@SERIAL@@) lo genera 01-setup-dns.sh (AAMMDDhhmm)
$TTL 3600
@       IN  SOA dns01.lab.local. hostmaster.lab.local. (
                @@SERIAL@@ ; serial
                3600       ; refresh
                900        ; retry
                604800     ; expire
                300 )      ; TTL negativo
        IN  NS  dns01.lab.local.

kvm-host        IN  A   10.10.10.1
rhel7-app01     IN  A   10.10.10.11
rhel8-app01     IN  A   10.10.10.12
rhel9-app01     IN  A   10.10.10.13
rhel10-app01    IN  A   10.10.10.14
dns01           IN  A   10.10.10.20
ansible01       IN  A   10.10.10.30

; Infraestructura futura (reservada; NO crear registros hasta instalar el host):
;rhel9-web01     IN  A   10.10.10.40
;rhel9-monitor01 IN  A   10.10.10.50
