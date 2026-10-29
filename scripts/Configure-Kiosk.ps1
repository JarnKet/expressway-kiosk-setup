<#
.SYNOPSIS
    Sets this kiosk's own values in the Wrapper config (BCELOnePayTerminal.exe.config).

.DESCRIPTION
    Terminal ID, static QR ID, COM port, UI environment (Prod/Dev/custom URL), Topmost, log server URL
    and the CefSharp remote debugging port. Asks for each value (current value is the default), or takes
    them from parameters or a JSON file such as config\kiosk.example.json.
    The values are saved to C:\Expressway\kiosk.json so a reinstall or update keeps them.

.EXAMPLE
    .\Configure.cmd
.EXAMPLE
    .\Configure.cmd -TerminalId T01 -StaticQrId itm123 -ComPort COM3 -Environment Prod -NonInteractive
.EXAMPLE
    .\Configure.cmd -ConfigFile D:\kiosks\T01.json
#>
[CmdletBinding()]
param(
    [string]$TerminalId,
    [string]$StaticQrId,
    [string]$ComPort,
    [ValidateSet('Prod', 'Dev', 'Custom')][string]$Environment,
    [string]$Url,
    [ValidateSet('Yes', 'No')][string]$Topmost,
    [string]$LogServerUrl,
    [int]$RemoteDebuggingPort = -1,
    [string]$ConfigFile,
    [switch]$NonInteractive,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Kiosk.Common.psm1') -Force -DisableNameChecking

if (Invoke-SelfElevation $PSCommandPath $PSBoundParameters) { exit 0 }

$root = Get-InstallRoot
$configPath = Join-Path $root 'Wrapper\BCELOnePayTerminal.exe.config'
$savedPath = Join-Path $root 'kiosk.json'
$environments = Get-KioskEnvironments (Join-Path $root 'config\environments.private.json')

function Read-Value([string]$Label, [string]$Default) {
    $shown = $Default
    if (-not $shown) { $shown = '' }
    $answer = Read-Host ("  {0} [{1}]" -f $Label, $shown)
    if ($answer -eq '') { return $Default }
    if ($answer -eq '-') { return '' }   # '-' clears a value
    $answer.Trim()
}

function Find-EnvironmentName([string]$Url) {
    foreach ($name in $environments.Keys) {
        if ($environments[$name].url -and $environments[$name].url.TrimEnd('/') -eq $Url.TrimEnd('/')) { return $name }
    }
    'Custom'
}

function Get-StartingValues {
    $current = Get-WrapperSettings $configPath
    $client = $null
    try { $client = ConvertFrom-LenientJson $current['ClientSetting'] } catch { }
    $values = [ordered]@{
        terminalId          = $current['TerminalId']
        staticQrId          = [string](Get-JsonValue $client 'staticQrId' '')
        comPort             = $current['SerialPortName']
        environment         = Find-EnvironmentName $current['CefSharpUrl']
        url                 = $current['CefSharpUrl']
        topmost             = ($current['Topmost'] -eq 'True')
        logServerUrl        = $current['LogServerUrl']
        remoteDebuggingPort = -1
    }
    if ($ConfigFile -and -not (Test-Path $ConfigFile)) { throw "Config file not found: $ConfigFile" }
    foreach ($source in @($savedPath, $ConfigFile)) {
        if (-not $source -or -not (Test-Path $source)) { continue }
        $file = Read-JsonFile $source
        foreach ($key in @($values.Keys)) {
            $value = Get-JsonValue $file $key $null
            if ($null -ne $value) { $values[$key] = $value }
        }
        # A debug port in a file is a deliberate override; otherwise it follows the environment
        if ($null -ne (Get-JsonValue $file 'remoteDebuggingPort' $null)) { $script:PortExplicit = $true }
    }
    $values
}

function Resolve-Values($Values) {
    # Command-line parameters win over files
    $map = @{ TerminalId = 'terminalId'; StaticQrId = 'staticQrId'; ComPort = 'comPort'; Environment = 'environment'; LogServerUrl = 'logServerUrl' }
    foreach ($param in $map.Keys) {
        if ($script:Bound.ContainsKey($param)) { $Values[$map[$param]] = $script:Bound[$param] }
    }
    if ($script:Bound.ContainsKey('Url')) { $Values.url = $Url; $Values.environment = 'Custom' }
    if ($script:Bound.ContainsKey('Topmost')) { $Values.topmost = ($Topmost -eq 'Yes') }
    if ($RemoteDebuggingPort -ge 0) { $Values.remoteDebuggingPort = $RemoteDebuggingPort; $script:PortExplicit = $true }
    $Values
}

function Request-Values($Values) {
    Write-Host ''
    Write-Host 'Expressway kiosk settings  (Enter keeps the value in [brackets], "-" clears it)' -ForegroundColor Cyan
    $Values.terminalId = Read-Value 'Terminal ID' $Values.terminalId
    $Values.staticQrId = Read-Value 'Static QR ID' $Values.staticQrId

    $ports = @(Get-ComPortList)
    Write-Host '  COM ports on this PC:'
    if ($ports.Count -eq 0) { Write-Host '    (none - plug in the USB-serial adapter)' -ForegroundColor Yellow }
    foreach ($p in $ports) {
        $mark = ''
        if ($p.Prolific) { $mark = '  <- Prolific adapter' }
        Write-Host ("    {0,-6} {1}{2}" -f $p.Port, $p.Name, $mark)
    }
    $default = $Values.comPort
    $prolific = @($ports | Where-Object { $_.Prolific })
    if (-not $default -and $prolific.Count -gt 0) { $default = $prolific[0].Port }
    $Values.comPort = ([string](Read-Value 'COM port' $default)).ToUpperInvariant()

    $names = (@($environments.Keys) + 'Custom') -join '/'
    $Values.environment = Read-Value "Environment ($names)" $Values.environment
    if ($Values.environment -eq 'Custom') { $Values.url = Read-Value 'UI URL' $Values.url }
    $topDefault = 'No'
    if ($Values.topmost) { $topDefault = 'Yes' }
    $Values.topmost = ((Read-Value 'Keep window on top (Yes/No)' $topDefault) -match '^(y|yes|true)$')
    $Values.logServerUrl = Read-Value 'Log server URL (blank = none)' $Values.logServerUrl
    $Values
}

function Complete-Values($Values) {
    $envName = [string]$Values.environment
    $match = @($environments.Keys | Where-Object { $_ -eq $envName })
    if ($match.Count -gt 0) {
        $envName = $match[0]
        $target = $environments[$envName]
        if (-not $target.url) { throw "No URL is known for '$envName' (the Dev URL comes with the private payload)." }
        $Values.environment = $envName
        $Values.url = $target.url
        if (-not $script:PortExplicit) { $Values.remoteDebuggingPort = [int]$target.remoteDebuggingPort }
        $Values.monitorEnvironment = $target.monitorEnvironment
    } elseif ($envName -eq 'Custom') {
        if ([int]$Values.remoteDebuggingPort -lt 0) { $Values.remoteDebuggingPort = 0 }
        $Values.monitorEnvironment = 'test'
    } else {
        throw "Unknown environment '$envName'. Use one of: $((@($environments.Keys) + 'Custom') -join ', ')"
    }
    $Values
}

function Test-Values($Values) {
    $errors = @()
    if (Test-PlaceholderId $Values.terminalId) { $errors += 'Terminal ID is empty or a placeholder' }
    if (Test-PlaceholderId $Values.staticQrId) { $errors += 'Static QR ID is empty or a placeholder (the UI ignores it)' }
    if ($Values.comPort -notmatch '^COM\d+$') { $errors += "COM port '$($Values.comPort)' must look like COM3" }
    if ($Values.url -notmatch '^https://' -and $Values.url -notmatch '^http://(localhost|127\.0\.0\.1)') { $errors += "UI URL '$($Values.url)' must start with https://" }
    if ($Values.logServerUrl -and $Values.logServerUrl -notmatch '^https?://') { $errors += 'Log server URL must start with http:// or https://' }
    if ($errors.Count -gt 0) { throw ("Invalid settings:`n  - " + ($errors -join "`n  - ")) }
    $present = @(Get-ComPortList | ForEach-Object { $_.Port })
    if ($present -notcontains $Values.comPort) { Write-Problem "$($Values.comPort) does not exist on this PC right now (adapter unplugged?)" }
}

function Save-Values($Values) {
    $backupDir = Join-Path $root 'state\config-backups'
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    Copy-Item $configPath (Join-Path $backupDir ('BCELOnePayTerminal.exe.config.' + (Get-Date -Format 'yyyyMMdd-HHmmss')))
    Get-ChildItem $backupDir | Sort-Object LastWriteTime -Descending | Select-Object -Skip 10 | Remove-Item -Force

    $current = Get-WrapperSettings $configPath
    $topmostText = 'False'
    if ($Values.topmost) { $topmostText = 'True' }
    Set-WrapperSettings $configPath ([ordered]@{
        CefSharpUrl                 = $Values.url
        CefSharpRemoteDebuggingPort = [string]$Values.remoteDebuggingPort
        Topmost                     = $topmostText
        SerialPortName              = $Values.comPort
        LogServerUrl                = [string]$Values.logServerUrl
        TerminalId                  = $Values.terminalId
        ClientSetting               = New-ClientSettingJson $current['ClientSetting'] $Values.terminalId $Values.staticQrId $Values.comPort
    })

    $saved = [ordered]@{
        terminalId          = $Values.terminalId
        staticQrId          = $Values.staticQrId
        comPort             = $Values.comPort
        environment         = $Values.environment
        topmost             = [bool]$Values.topmost
        logServerUrl        = [string]$Values.logServerUrl
    }
    if ($script:PortExplicit) { $saved.remoteDebuggingPort = [int]$Values.remoteDebuggingPort }
    if ($Values.environment -eq 'Custom') { $saved.url = $Values.url }
    $saved.updated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Write-JsonFile $savedPath $saved
}

function Restart-Wrapper {
    if (Test-Path (Join-Path $root 'state\maintenance.flag')) { Write-Note 'Maintenance mode is on; run Start-Kiosk.cmd when ready'; return }
    $running = @(Get-WrapperProcesses $root)
    if ($running.Count -gt 0 -and @(Get-WatchdogProcesses).Count -gt 0) {
        $running | Stop-Process -Force
        Write-Ok 'Wrapper restarted with the new settings'
        return
    }
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    $task = Get-KitConfig 'install.json'
    try {
        Start-ScheduledTask -TaskName $task.taskName
        Write-Ok 'Wrapper started'
    } catch {
        Write-Note 'Start the Wrapper with the "Expressway Wrapper" desktop shortcut (or sign out and in)'
    }
}

$exitCode = 0
try {
    if (-not (Test-Path $configPath)) { throw "Wrapper is not installed ($configPath not found). Run Install.cmd first." }
    $script:Bound = $PSBoundParameters
    $script:PortExplicit = $false
    $values = Get-StartingValues
    $values = Resolve-Values $values
    if (-not $NonInteractive -and -not $ConfigFile) { $values = Request-Values $values }
    $values = Complete-Values $values
    Test-Values $values

    Write-Host ''
    Write-Host 'New settings:' -ForegroundColor Cyan
    Write-Host ('    Terminal ID   : {0}' -f $values.terminalId)
    Write-Host ('    Static QR ID  : {0}' -f $values.staticQrId)
    Write-Host ('    COM port      : {0}' -f $values.comPort)
    Write-Host ('    Environment   : {0}  ({1})' -f $values.environment, $values.url)
    Write-Host ('    Topmost       : {0}' -f $values.topmost)
    Write-Host ('    Log server    : {0}' -f $values.logServerUrl)
    Write-Host ('    Debug port    : {0}' -f $(if ([int]$values.remoteDebuggingPort -eq 0) { 'off' } else { $values.remoteDebuggingPort }))
    if (-not $NonInteractive -and -not $ConfigFile) {
        if ((Read-Host 'Save these settings? (Y/n)') -match '^(n|no)$') { throw 'Cancelled; nothing was changed.' }
    }
    Save-Values $values
    Write-Ok "Saved to the Wrapper config and $savedPath"
    Restart-Wrapper
    Show-MonitorSummary $values
} catch {
    Write-Host ''
    Write-Host "SETTINGS NOT SAVED: $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
}
if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
exit $exitCode
