<#
.SYNOPSIS
    Health check: shows PASS/WARN/FAIL for everything the kiosk needs and saves a report.

.DESCRIPTION
    Does not change anything. Use -Full to re-check every installed file against the payload hashes.
    Exit code 0 = no FAIL, 1 = at least one FAIL.
#>
[CmdletBinding()]
param([switch]$Full, [switch]$NoPause)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Kiosk.Common.psm1') -Force -DisableNameChecking

$root = Get-InstallRoot
$prereq = Get-KitConfig 'prerequisites.json'
$install = Get-KitConfig 'install.json'
$results = New-Object System.Collections.Generic.List[object]

function Add-Result([string]$Area, [string]$Status, [string]$Detail) {
    $results.Add([pscustomobject]@{ Area = $Area; Status = $Status; Detail = $Detail })
}

function Invoke-Check([string]$Area, [scriptblock]$Check) {
    try { & $Check } catch { Add-Result $Area 'FAIL' $_.Exception.Message }
}

Invoke-Check 'Windows' {
    $win = Get-WindowsInfo
    $status = 'PASS'
    if ($win.Build -lt 14393) { $status = 'FAIL' }
    Add-Result 'Windows' $status ("{0} {1} build {2}" -f $win.Name, $win.Release, $win.Build)
}

Invoke-Check '.NET Framework' {
    $release = Get-NetFrameworkRelease
    if ($release -ge $prereq.netFramework.minRelease) { Add-Result '.NET Framework' 'PASS' "release $release" }
    else { Add-Result '.NET Framework' 'FAIL' "release $release, need $($prereq.netFramework.minVersion)+" }
}

Invoke-Check 'VC++ x86' {
    $version = Get-VcRedistX86Version
    if ($version) { Add-Result 'VC++ x86' 'PASS' $version } else { Add-Result 'VC++ x86' 'FAIL' 'not installed' }
}

Invoke-Check '.NET 7 x86' {
    $found = Get-DotnetDesktopX86Versions $prereq.dotnetDesktop.major
    if ($found.Count -gt 0) { Add-Result '.NET 7 x86' 'PASS' ($found -join ', ') } else { Add-Result '.NET 7 x86' 'FAIL' 'Desktop Runtime 7 (x86) not installed' }
}

Invoke-Check 'Apps' {
    $missing = @()
    foreach ($file in 'Wrapper\BCELOnePayTerminal.exe', 'Wrapper\libcef.dll', 'Connector\OnePayTerminalConnectorGUI.exe',
                      'Connector\OnePayTerminalConnector.dll') {
        if (-not (Test-Path (Join-Path $root $file))) { $missing += $file }
    }
    $version = ''
    if (Test-Path (Join-Path $root 'payload.json')) { $version = 'payload ' + (Read-JsonFile (Join-Path $root 'payload.json')).version }
    if ($missing.Count -gt 0) { Add-Result 'Apps' 'FAIL' ('missing: ' + ($missing -join ', ')) } else { Add-Result 'Apps' 'PASS' "installed in $root $version" }
}

Invoke-Check 'Debug DLLs' {
    $missing = @('msvcp140d.dll', 'vcruntime140d.dll', 'ucrtbased.dll' | Where-Object { -not (Test-Path (Join-Path $root "Connector\$_")) })
    if ($missing.Count -gt 0) { Add-Result 'Debug DLLs' 'FAIL' ('missing in Connector: ' + ($missing -join ', ')) } else { Add-Result 'Debug DLLs' 'PASS' 'all 3 next to OnePayTerminalConnector.dll' }
}

if ($Full) {
    Invoke-Check 'File hashes' {
        $manifest = Read-JsonFile (Join-Path $root 'payload.json')
        $bad = 0
        foreach ($entry in $manifest.files) {
            if ($entry.path -like 'Wrapper/BCELOnePayTerminal.exe.config' -or $entry.path -notmatch '^(Wrapper|Connector)/') { continue }
            $path = Join-Path $root ($entry.path -replace '/', '\')
            if (-not (Test-Path -LiteralPath $path) -or (Get-FileHashHex $path) -ne $entry.sha256) { $bad++ }
        }
        if ($bad -eq 0) { Add-Result 'File hashes' 'PASS' 'every app file matches the payload' } else { Add-Result 'File hashes' 'FAIL' "$bad files missing or changed; reinstall" }
    }
}

$settings = $null
Invoke-Check 'Settings' {
    $current = Get-WrapperSettings (Join-Path $root 'Wrapper\BCELOnePayTerminal.exe.config')
    $client = ConvertFrom-LenientJson $current['ClientSetting']
    $script:settings = [pscustomobject]@{
        terminalId         = $current['TerminalId']
        staticQrId         = [string](Get-JsonValue $client 'staticQrId' '')
        comPort            = $current['SerialPortName']
        url                = $current['CefSharpUrl']
        monitorEnvironment = 'production'
    }
    if ($script:settings.url -notlike 'https://expressway.bcel.one*') { $script:settings.monitorEnvironment = 'test' }
    $problems = @()
    if (Test-PlaceholderId $script:settings.terminalId) { $problems += 'Terminal ID not set' }
    if (Test-PlaceholderId $script:settings.staticQrId) { $problems += 'Static QR ID not set' }
    if ($problems.Count -gt 0) { Add-Result 'Settings' 'FAIL' (($problems -join '; ') + ' - run Configure.cmd') }
    else { Add-Result 'Settings' 'PASS' ("Terminal {0}, QR {1}" -f $script:settings.terminalId, $script:settings.staticQrId) }
    if ([int]$current['CefSharpRemoteDebuggingPort'] -gt 0) { Add-Result 'Debug port' 'WARN' "CefSharp remote debugging is on (port $($current['CefSharpRemoteDebuggingPort']))" }
}

Invoke-Check 'Prolific' {
    $devices = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.PNPDeviceID -like 'USB\VID_067B*' })
    if ($devices.Count -eq 0) { Add-Result 'Prolific' 'WARN' 'no Prolific adapter plugged in'; return }
    foreach ($d in $devices) {
        $code = [int]$d.ConfigManagerErrorCode
        if ($code -eq 0) { Add-Result 'Prolific' 'PASS' $d.Name }
        elseif ($code -eq 10) { Add-Result 'Prolific' 'FAIL' "$($d.Name): error 10 - chip not supported by this driver (old/fake PL2303HXA?)" }
        else { Add-Result 'Prolific' 'FAIL' "$($d.Name): device error $code" }
    }
}

Invoke-Check 'COM port' {
    if ($null -eq $script:settings) { return }
    $port = @(Get-ComPortList | Where-Object { $_.Port -eq $script:settings.comPort })
    if ($port.Count -eq 0) { Add-Result 'COM port' 'FAIL' "$($script:settings.comPort) does not exist on this PC" }
    elseif ($port[0].ErrorCode -ne 0) { Add-Result 'COM port' 'FAIL' "$($script:settings.comPort) has device error $($port[0].ErrorCode)" }
    else { Add-Result 'COM port' 'PASS' ("{0} = {1}" -f $port[0].Port, $port[0].Name) }
}

Invoke-Check 'UI URL' {
    if ($null -eq $script:settings) { return }
    Enable-ModernTls
    $response = Invoke-WebRequest -Uri $script:settings.url -UseBasicParsing -TimeoutSec 15
    Add-Result 'UI URL' 'PASS' ("{0} -> HTTP {1}" -f $script:settings.url, $response.StatusCode)
}

Invoke-Check 'Auto-start' {
    $task = Get-ScheduledTask -TaskName $install.taskName -ErrorAction SilentlyContinue
    if ($null -eq $task) { Add-Result 'Auto-start' 'FAIL' "task '$($install.taskName)' missing"; return }
    $state = 'running'
    if (Test-Path (Join-Path $root 'state\maintenance.flag')) { Add-Result 'Auto-start' 'WARN' 'maintenance mode is on (Start-Kiosk.cmd turns it off)'; return }
    if (@(Get-WrapperProcesses $root).Count -eq 0) { $state = 'Wrapper not running' }
    $status = 'PASS'
    if ($state -ne 'running') { $status = 'WARN' }
    Add-Result 'Auto-start' $status "task registered; $state"
}

Invoke-Check 'Speaker' {
    $speaker = Get-SpeakerState
    if ($null -eq $speaker) { Add-Result 'Speaker' 'WARN' 'no speaker found; payment sounds will not play' }
    elseif ($speaker.Muted -or $speaker.Percent -lt 20) { Add-Result 'Speaker' 'WARN' ("volume {0}%, muted: {1}" -f $speaker.Percent, $speaker.Muted) }
    else { Add-Result 'Speaker' 'PASS' ("volume {0}%" -f $speaker.Percent) }
}

$colors = @{ PASS = 'Green'; WARN = 'Yellow'; FAIL = 'Red' }
Write-Host ''
Write-Host ("Expressway kiosk check - {0} - {1}" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd HH:mm')) -ForegroundColor Cyan
foreach ($r in $results) {
    Write-Host ('  {0,-15}' -f $r.Area) -NoNewline
    Write-Host ('{0,-6}' -f $r.Status) -ForegroundColor $colors[$r.Status] -NoNewline
    Write-Host $r.Detail
}
if ($script:settings) { Show-MonitorSummary $script:settings }

$report = Join-Path $root ('logs\check-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
try {
    $results | Format-Table -AutoSize | Out-String -Width 200 | Set-Content -Path $report -Encoding UTF8
    Write-Host ''
    Write-Host "Report saved: $report"
} catch { }

$failed = @($results | Where-Object { $_.Status -eq 'FAIL' }).Count
if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
if ($failed -gt 0) { exit 1 } else { exit 0 }
