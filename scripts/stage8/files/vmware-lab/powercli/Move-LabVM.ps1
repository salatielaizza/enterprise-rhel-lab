<#
.SYNOPSIS
  vMotion de una VM al otro host del clúster, midiendo cuánto tarda. Etapa 8, fase B.
.DESCRIPTION
  Hace lo mismo que 'lab.sh stage8 vmotion' (Ansible) pero con PowerCLI, para comparar
  las dos herramientas. Si la VM no está en el datastore compartido, la mueve también a
  él (vMotion de cómputo + almacenamiento).
  Uso:  pwsh ~/vmware-lab/powercli/Move-LabVM.ps1
        pwsh ~/vmware-lab/powercli/Move-LabVM.ps1 -VM rhel9-vm01 -Destination esxi03.lab.local
#>
param(
  [string]$VM          = 'rhel9-vm01',
  [string]$Cluster     = 'lab-cluster',
  [string]$Datastore   = 'nfs-vmware',
  [string]$Destination = '',
  [string]$Server      = 'vcsa01.lab.local'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Connect-Lab.ps1') -Server $Server

$v = Get-VM -Name $VM
$src = $v.VMHost.Name
if (-not $Destination) {
  $Destination = (Get-Cluster -Name $Cluster | Get-VMHost |
                  Where-Object { $_.Name -ne $src -and $_.ConnectionState -eq 'Connected' } |
                  Select-Object -First 1).Name
}
if (-not $Destination) { throw "No hay otro host conectado en $Cluster" }

$params = @{ VM = $v; Destination = (Get-VMHost -Name $Destination); Confirm = $false }
if ((($v | Get-Datastore).Name) -notcontains $Datastore) {
  Write-Host "La VM no está en $Datastore: se mueve también el almacenamiento"
  $params.Datastore = Get-Datastore -Name $Datastore
}
Write-Host "vMotion $VM : $src -> $Destination ..."
$t = Measure-Command { Move-VM @params | Out-Null }
$v = Get-VM -Name $VM
Write-Host ("Hecho en {0:n1} s. Ahora en {1}, datastore {2}, estado {3}" -f `
  $t.TotalSeconds, $v.VMHost.Name, (($v | Get-Datastore).Name -join ','), $v.PowerState)
