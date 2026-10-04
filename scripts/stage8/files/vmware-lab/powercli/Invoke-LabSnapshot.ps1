<#
.SYNOPSIS
  Snapshots de VMware de una VM del lab: listar, crear, revertir o borrar.
.DESCRIPTION
  Equivalente en PowerCLI de 'lab.sh stage8 snapshot' (Ansible).
  Uso:  pwsh ~/vmware-lab/powercli/Invoke-LabSnapshot.ps1                         # lista
        pwsh ~/vmware-lab/powercli/Invoke-LabSnapshot.ps1 -Action New    -Name antes-de-X
        pwsh ~/vmware-lab/powercli/Invoke-LabSnapshot.ps1 -Action Revert -Name antes-de-X
        pwsh ~/vmware-lab/powercli/Invoke-LabSnapshot.ps1 -Action Remove -Name antes-de-X
#>
param(
  [ValidateSet('List', 'New', 'Revert', 'Remove')]
  [string]$Action = 'List',
  [string]$VM     = 'rhel9-vm01',
  [string]$Name   = 'lab-snap',
  [string]$Server = 'vcsa01.lab.local'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Connect-Lab.ps1') -Server $Server
$v = Get-VM -Name $VM

switch ($Action) {
  'New'    { New-Snapshot -VM $v -Name $Name -Description "Invoke-LabSnapshot.ps1 $(Get-Date -Format s)" -Confirm:$false | Out-Null }
  'Revert' { Set-VM -VM $v -Snapshot (Get-Snapshot -VM $v -Name $Name) -Confirm:$false | Out-Null }
  'Remove' { Get-Snapshot -VM $v -Name $Name | Remove-Snapshot -Confirm:$false }
}
Get-Snapshot -VM $v | Select-Object Name, Created, IsCurrent,
  @{ n = 'SizeGB'; e = { [math]::Round($_.SizeGB, 2) } } | Format-Table -AutoSize
