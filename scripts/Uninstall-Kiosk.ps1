<#
.SYNOPSIS
    Removes the Expressway apps, auto-start task and shortcuts.

.DESCRIPTION
    Leaves the shared runtimes (.NET, VC++), the Prolific driver and the power/update settings in place,
    because other software may need them. -KeepLogs keeps C:\Expressway\logs.
#>
[CmdletBinding()]
param([switch]$KeepLogs, [switch]$Force, [switch]$NoPause)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Kiosk.Common.psm1') -Force -DisableNameChecking

if (Invoke-SelfElevation $PSCommandPath $PSBoundParameters) { exit 0 }

$root = Get-InstallRoot
$install = Get-KitConfig 'install.json'

if (-not $Force) {
    $answer = Read-Host "Remove the Expressway kiosk software from $root? (y/N)"
    if ($answer -notmatch '^(y|yes)$') { Write-Host 'Nothing removed.'; exit 0 }
}

Unregister-ScheduledTask -TaskName $install.taskName -Confirm:$false -ErrorAction SilentlyContinue
foreach ($p in Get-WatchdogProcesses) { Invoke-CimMethod -InputObject $p -MethodName Terminate | Out-Null }
Get-Process -Name 'BCELOnePayTerminal', 'CefSharp.BrowserSubprocess', 'OnePayTerminalConnectorGUI' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$desktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
foreach ($name in 'Expressway Wrapper', 'OnePay Connector (test)', 'Expressway Settings', 'Expressway Check') {
    Remove-Item (Join-Path $desktop "$name.lnk") -ErrorAction SilentlyContinue
}
Remove-Item (Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'Expressway') -Recurse -Force -ErrorAction SilentlyContinue

Get-ChildItem -Path $root -Force | Where-Object { -not ($KeepLogs -and $_.Name -eq 'logs') } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
if (-not $KeepLogs) { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host 'Expressway kiosk software removed.' -ForegroundColor Green
Write-Host 'Kept: .NET runtimes, Visual C++ runtime, Prolific driver, power and Windows Update settings.'
if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
