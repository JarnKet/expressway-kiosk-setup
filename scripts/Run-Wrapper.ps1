<#
.SYNOPSIS
    Watchdog: starts the Expressway Wrapper and starts it again whenever it closes.

.DESCRIPTION
    Started at logon by the "Expressway Wrapper" scheduled task and by the desktop shortcut.
    Only one watchdog runs per session; a second copy just exits. While state\maintenance.flag
    exists (Stop-Kiosk.cmd) the watchdog does not start the Wrapper and quits.
    Restarts are logged to logs\watchdog-YYYYMMDD.log.
#>
param([int]$DelaySeconds = 5)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Kiosk.Common.psm1') -Force -DisableNameChecking

$root = Get-InstallRoot
$exe = Join-Path $root 'Wrapper\BCELOnePayTerminal.exe'
$flag = Join-Path $root 'state\maintenance.flag'
$log = Join-Path $root ('logs\watchdog-' + (Get-Date -Format 'yyyyMMdd') + '.log')

$mutex = New-Object System.Threading.Mutex($false, 'Local\ExpresswayWrapperWatchdog')
if (-not $mutex.WaitOne(0)) { exit 0 }

try {
    $recent = New-Object System.Collections.Generic.List[datetime]
    while (-not (Test-Path $flag)) {
        $process = @(Get-WrapperProcesses $root) | Select-Object -First 1
        if ($null -eq $process) {
            $process = Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -PassThru
            Write-KioskLog $log "started Wrapper (pid $($process.Id))"
        } else {
            Write-KioskLog $log "watching running Wrapper (pid $($process.Id))"
        }
        $process.WaitForExit()
        $code = 'unknown'
        try { $code = $process.ExitCode } catch { }
        Write-KioskLog $log "Wrapper exited (code $code)"
        if (Test-Path $flag) { break }

        # Back off when it keeps crashing: more than 5 exits in 2 minutes -> wait a minute
        $now = Get-Date
        $recent.Add($now)
        $null = $recent.RemoveAll({ param($t) ($now - $t).TotalSeconds -gt 120 })
        $wait = $DelaySeconds
        if ($recent.Count -gt 5) { $wait = 60; Write-KioskLog $log 'Wrapper keeps closing; waiting 60 s' }
        Start-Sleep -Seconds $wait
    }
    Write-KioskLog $log 'maintenance mode: watchdog stopped'
} finally {
    $mutex.ReleaseMutex()
}
