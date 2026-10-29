<#
.SYNOPSIS
    Maintenance mode. -On closes the Wrapper and keeps it closed; -Off starts it again.
    Needs no administrator rights.
#>
param([switch]$On, [switch]$Off)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Kiosk.Common.psm1') -Force -DisableNameChecking

$root = Get-InstallRoot
$flag = Join-Path $root 'state\maintenance.flag'

if ($On) {
    Set-Content -Path $flag -Value ("maintenance since {0} by {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $env:USERNAME)
    Get-WrapperProcesses $root | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host 'Kiosk stopped. The Wrapper stays closed until you run Start-Kiosk.cmd.' -ForegroundColor Yellow
} elseif ($Off) {
    Remove-Item $flag -ErrorAction SilentlyContinue
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $PSScriptRoot 'Run-Wrapper.ps1'))
    Write-Host 'Kiosk started.' -ForegroundColor Green
} else {
    Write-Host 'Use -On or -Off.'
    exit 1
}
Start-Sleep -Seconds 2
