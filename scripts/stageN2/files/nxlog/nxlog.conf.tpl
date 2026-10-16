## =============================================================================
## nxlog.conf — Agente NXLog Community Edition del lab (Etapa N2)
## Generado por 10-nxlog-agent.sh a partir de scripts/stageN2/files/nxlog/nxlog.conf.tpl
##
## Qué hace: lee el log de auditd (/var/log/audit/audit.log, las reglas de la Etapa 5),
## extrae campos clave con expresiones regulares y lo envía a Graylog en formato GELF por TCP.
##   Entrada (Input) -> procesado (Exec) -> Salida (Output) unidas por una ruta (Route).
## En Windows el mismo agente usaría im_msvistalog (Visor de eventos) en vez de im_file.
## =============================================================================

User nxlog
Group nxlog
LogFile /var/log/nxlog/nxlog.log
LogLevel INFO

<Extension gelf>
    Module      xm_gelf
</Extension>

<Input audit>
    Module      im_file
    File        "/var/log/audit/audit.log"
    # SavePos: recuerda por dónde iba al reiniciar (no duplica ni pierde).
    # ReadFromLast: la primera vez empieza por el final (no reenvía todo el histórico).
    # Los comentarios van SIEMPRE en su propia línea: NXLog no admite comentarios al final de una directiva.
    SavePos     TRUE
    ReadFromLast TRUE
    <Exec>
        $Message = $raw_event;
        $SourceName = 'auditd';
        $siem_agent = 'nxlog-ce';
        if $raw_event =~ /type=(\S+)/ $audit_type = $1;
        if $raw_event =~ / res=(\w+)/ $audit_res = $1;
        if $raw_event =~ / addr=(\d+\.\d+\.\d+\.\d+)/ $audit_addr = $1;
        if $raw_event =~ / acct="([^"]+)"/ $audit_acct = $1;
        if $raw_event =~ / exe="([^"]+)"/ $audit_exe = $1;
        if $raw_event =~ / key="([^"]+)"/ $audit_key = $1;
        if $raw_event =~ /type=USER_CMD .*cmd=([0-9A-F]+)/ $audit_cmd_hex = $1;
    </Exec>
</Input>

<Output graylog>
    Module      om_tcp
    Host        @SIEM_IP@
    Port        12201
    OutputType  GELF_TCP
</Output>

<Route auditd_to_graylog>
    Path        audit => graylog
</Route>
