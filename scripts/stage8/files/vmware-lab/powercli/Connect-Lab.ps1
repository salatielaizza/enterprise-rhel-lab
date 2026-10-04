<#
.SYNOPSIS
  Conecta PowerCLI a vCenter (por defecto) o a un ESXi del lab. Etapa 8.
.DESCRIPTION
  La contraseña se pide de forma interactiva (Get-Credential) y NUNCA se guarda en disco.
  El resto de scripts de esta carpeta llaman a este si no hay una conexión abierta.
  Uso (en ansible01):  pwsh
                       PS> . ~/vmware-lab/powercli/Connect-Lab.ps1
                       PS> . ~/vmware-lab/powercli/Connect-Lab.ps1 -Server esxi01.lab.local -User root
  Contra el ESXi gratuito (esxi01) solo funcionan las consultas (Get-*): la API no
  permite operaciones de escritura en la edición gratuita.
#>
param(
  [string]$Server = 'vcsa01.lab.local',
  [string]$User   = 'administrator@vsphere.local'
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Module -ListAvailable -Name VCF.PowerCLI, VMware.PowerCLI)) {
  throw 'PowerCLI no está instalado (lab.sh stage8-setup lo instala en ansible01).'
}
# Certificados autofirmados del lab: en producción, certificados de la CA corporativa.
Set-PowerCLIConfiguration -Scope Session -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
if ($global:DefaultVIServer -and $global:DefaultVIServer.Name -eq $Server -and $global:DefaultVIServer.IsConnected) {
  Write-Host "Ya conectado a $Server"
  return
}
$cred = Get-Credential -UserName $User -Message "Contraseña de $User en $Server"
Connect-VIServer -Server $Server -Credential $cred | Format-Table Name, Version, Build, User -AutoSize
