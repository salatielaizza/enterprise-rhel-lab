<#
.SYNOPSIS
  Informe del entorno vSphere del lab: hosts, VMs y datastores -> pantalla y CSV.
.DESCRIPTION
  Solo lectura: funciona contra vCenter y también contra el ESXi gratuito (esxi01).
  Los CSV quedan en ~/vmware-lab/reports/<fecha>-{hosts,vms,datastores}.csv: sirven como
  evidencia para checklists/etapa8.md y para comparar el estado antes/después de un cambio.
  Uso:  pwsh ~/vmware-lab/powercli/Get-LabReport.ps1
        pwsh ~/vmware-lab/powercli/Get-LabReport.ps1 -Server esxi01.lab.local -User root
#>
param(
  [string]$Server = 'vcsa01.lab.local',
  [string]$User   = 'administrator@vsphere.local',
  [string]$OutDir = (Join-Path $HOME 'vmware-lab/reports')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Connect-Lab.ps1') -Server $Server -User $User
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

$hosts = Get-VMHost | Select-Object Name, ConnectionState, Version, Build, NumCpu,
  @{ n = 'MemoryTotalGB'; e = { [math]::Round($_.MemoryTotalGB, 1) } },
  @{ n = 'MemoryUsageGB'; e = { [math]::Round($_.MemoryUsageGB, 1) } },
  @{ n = 'Cluster';       e = { ($_ | Get-Cluster -ErrorAction SilentlyContinue).Name } }

$vms = Get-VM | Select-Object Name, PowerState, NumCpu, MemoryGB,
  @{ n = 'VMHost';     e = { $_.VMHost.Name } },
  @{ n = 'Datastores'; e = { ($_ | Get-Datastore).Name -join ',' } },
  @{ n = 'IP';         e = { $_.Guest.IPAddress -join ',' } },
  @{ n = 'Tools';      e = { $_.ExtensionData.Guest.ToolsRunningStatus } }

$ds = Get-Datastore | Select-Object Name, Type,
  @{ n = 'CapacityGB';  e = { [math]::Round($_.CapacityGB, 1) } },
  @{ n = 'FreeSpaceGB'; e = { [math]::Round($_.FreeSpaceGB, 1) } },
  @{ n = 'Hosts';       e = { ($_ | Get-VMHost).Name -join ',' } }

Write-Host "`n== Hosts";      $hosts | Format-Table -AutoSize
Write-Host "== VMs";          $vms   | Format-Table -AutoSize
Write-Host "== Datastores";   $ds    | Format-Table -AutoSize

$hosts | Export-Csv -NoTypeInformation -Path (Join-Path $OutDir "$stamp-hosts.csv")
$vms   | Export-Csv -NoTypeInformation -Path (Join-Path $OutDir "$stamp-vms.csv")
$ds    | Export-Csv -NoTypeInformation -Path (Join-Path $OutDir "$stamp-datastores.csv")
Write-Host "CSV guardados en $OutDir ($stamp-*.csv)"
