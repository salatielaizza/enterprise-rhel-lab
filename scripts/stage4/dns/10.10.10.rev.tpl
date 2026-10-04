; Zona inversa 10.10.10.in-addr.arpa — serial @@SERIAL@@
$TTL 3600
@       IN  SOA dns01.lab.local. hostmaster.lab.local. (
                @@SERIAL@@ ; serial
                3600       ; refresh
                900        ; retry
                604800     ; expire
                300 )      ; TTL negativo
        IN  NS  dns01.lab.local.

1       IN  PTR kvm-host.lab.local.
11      IN  PTR rhel7-app01.lab.local.
12      IN  PTR rhel8-app01.lab.local.
13      IN  PTR rhel9-app01.lab.local.
14      IN  PTR rhel10-app01.lab.local.
20      IN  PTR dns01.lab.local.
30      IN  PTR ansible01.lab.local.
; Etapa 8 — VMware vSphere
60      IN  PTR esxi01.lab.local.
61      IN  PTR esxi02.lab.local.
62      IN  PTR esxi03.lab.local.
63      IN  PTR vcsa01.lab.local.
64      IN  PTR rhel9-vm01.lab.local.
