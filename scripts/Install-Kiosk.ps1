<#
.SYNOPSIS
    Installs everything an Expressway kiosk needs on Windows 10/11.

.DESCRIPTION
    1. Checks Windows and installs missing prerequisites: .NET Framework 4.6.2+, Visual C++ x86 runtime,
       .NET Desktop Runtime 7 (x86) and the Prolific PL2303 driver.
    2. Downloads the private payload (Wrapper, Connector, debug DLLs) from GitHub, or uses -PayloadPath.
    3. Copies the apps to C:\Expressway, sets permissions and shortcuts.
    4. Applies kiosk settings: auto-start with a watchdog, no sleep, no update reboots in active hours,
       Laos time zone, speaker volume.
    5. Runs Configure-Kiosk.ps1 for this kiosk's Terminal ID, COM port and environment.
    Safe to run again: it skips what is already in place and keeps the kiosk's saved settings.

.EXAMPLE
    .\Install.cmd
.EXAMPLE
    .\Install.cmd -PayloadPath D:\expressway-payload-2026.10.29.zip -ConfigFile D:\kiosks\T01.json
#>
[CmdletBinding()]
param(
    [string]$PayloadPath,
    [string]$PayloadVersion = 'latest',
    [string]$Token,
    [string]$ConfigFile,
    [switch]$SkipDriver,
    [switch]$NoKioskSettings,
    [switch]$NoConfigure,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Kiosk.Common.psm1') -Force -DisableNameChecking

if (Invoke-SelfElevation $PSCommandPath $PSBoundParameters) { exit 0 }

$kit = Get-KitRoot
$install = Get-KitConfig 'install.json'
$prereq = Get-KitConfig 'prerequisites.json'
$root = Get-InstallRoot
$work = Join-Path $env:TEMP ('expressway-setup-' + (Get-Date -Format 'yyyyMMddHHmmss'))
$script:RebootNeeded = $false

New-Item -ItemType Directory -Force -Path $work, (Join-Path $root 'logs') | Out-Null
$transcript = Join-Path $root ('logs\setup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
Start-Transcript -Path $transcript | Out-Null

function Step-CheckWindows {
    Write-Step 'Checking Windows'
    $win = Get-WindowsInfo
    if ($win.Build -lt 14393) { throw "$($win.Name) build $($win.Build) is too old. Windows 10 version 1607 or newer is required." }
    Write-Ok ("{0} {1} (build {2}, {3})" -f $win.Name, $win.Release, $win.Build, $(if ($win.Is64Bit) { '64-bit' } else { '32-bit' }))
    Get-ChildItem -Path $kit -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
    $win
}

function Step-NetFramework {
    Write-Step '.NET Framework (Wrapper)'
    $release = Get-NetFrameworkRelease
    if ($release -ge $prereq.netFramework.minRelease) { Write-Ok ".NET Framework release $release is new enough"; return }
    $item = $prereq.netFramework.installer
    $file = Join-Path $work $item.fileName
    Write-Note "Downloading $($item.name)"
    Save-WebFile -Url $item.url -Destination $file -RequireMicrosoftSignature
    Write-Note "Installing $($item.name) (this takes a few minutes)"
    if ((Invoke-Installer $file $item.arguments $item.name) -eq 'reboot') { $script:RebootNeeded = $true }
    Write-Ok "$($item.name) installed"
}

function Step-VcRedist {
    Write-Step 'Visual C++ runtime x86 (CefSharp)'
    $item = $prereq.vcRedistX86
    $file = Join-Path $work $item.fileName
    Write-Note "Downloading $($item.name)"
    Save-WebFile -Url $item.url -Destination $file -RequireMicrosoftSignature
    if ((Invoke-Installer $file $item.arguments $item.name) -eq 'reboot') { $script:RebootNeeded = $true }
    Write-Ok "$($item.name): $(Get-VcRedistX86Version)"
}

function Step-DotnetDesktop {
    Write-Step '.NET Desktop Runtime x86 (Connector)'
    $item = $prereq.dotnetDesktop
    $found = Get-DotnetDesktopX86Versions $item.major
    if ($found.Count -gt 0) { Write-Ok ("Already installed: {0}" -f ($found -join ', ')); return }
    $file = Join-Path $work $item.fileName
    Write-Note "Downloading $($item.name)"
    Save-WebFile -Url $item.url -Destination $file -Sha512 $item.sha512 -RequireMicrosoftSignature
    if ((Invoke-Installer $file $item.arguments $item.name) -eq 'reboot') { $script:RebootNeeded = $true }
    Write-Ok "$($item.name) installed"
}

function Step-ProlificDriver($Win) {
    Write-Step 'Prolific USB-to-Serial driver'
    if ($SkipDriver) { Write-Note 'Skipped (-SkipDriver)'; return }
    $item = $prereq.prolific.windows10
    if ($Win.Build -ge $prereq.prolific.windows11.minBuild) { $item = $prereq.prolific.windows11 }
    $cab = Join-Path $work $item.fileName
    $dir = Join-Path $work 'prolific'
    Write-Note "Downloading Prolific driver $($item.version) from the Microsoft Update Catalog"
    Save-WebFile -Url $item.url -Destination $cab -Sha256 $item.sha256
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    & expand.exe -F:* $cab $dir | Out-Null
    $inf = Get-ChildItem -Path $dir -Filter '*.inf' | Select-Object -First 1
    if ($null -eq $inf) { throw 'The Prolific driver package has no .inf file' }
    # Windows PowerShell turns native stderr into errors under 'Stop'; pnputil's exit code is what counts
    $ErrorActionPreference = 'Continue'
    $output = & pnputil.exe /add-driver $inf.FullName /install 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    # 259 = added to the driver store, but no adapter is plugged in right now
    if ($code -notin 0, 259, 3010) { throw "pnputil failed ($code): $($output -join ' ')" }
    if ($code -eq 3010) { $script:RebootNeeded = $true }
    Write-Ok "Prolific driver $($item.version) is in the driver store"
}

function Step-Payload {
    Write-Step 'Getting the Expressway apps (private payload)'
    $zip = $null
    $folder = $null
    if ($PayloadPath) {
        if (Test-Path $PayloadPath -PathType Container) { $folder = (Resolve-Path $PayloadPath).Path }
        else { $zip = (Resolve-Path $PayloadPath).Path }
        Write-Note "Using $PayloadPath"
    } else {
        $tok = $Token
        if (-not $tok) { $tok = $env:EXPRESSWAY_PAYLOAD_TOKEN }
        if (-not $tok) {
            Write-Host '    Paste the GitHub token for the payload (input is hidden):'
            $secure = Read-Host -AsSecureString '    Token'
            $tok = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
        }
        try {
            $release = Get-PayloadRelease $install.payloadRepo $PayloadVersion $tok $install.payloadAssetPattern
        } catch {
            throw (("Could not read the payload release from GitHub ({0}). Check that the token is valid, not expired, " +
                    "and has Contents: Read-only on {1}.") -f $_.Exception.Message, $install.payloadRepo)
        }
        Write-Note ("Downloading {0} ({1:N0} MB) from release {2}" -f $release.Name, ($release.Size / 1MB), $release.Tag)
        $zip = Join-Path $work $release.Name
        Save-GitHubAsset $release.ApiUrl $tok $zip
        if ($release.Sha256 -and (Get-FileHashHex $zip) -ne $release.Sha256) { throw 'The payload zip does not match its GitHub checksum' }
    }
    if ($zip) {
        $folder = Join-Path $work 'payload'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $folder)
    }
    $problems = @(Test-PayloadManifest $folder)
    if ($problems.Count -gt 0) { throw ('The payload is damaged: ' + (($problems | Select-Object -First 5) -join '; ')) }
    $manifest = Read-JsonFile (Join-Path $folder 'manifest.json')
    Write-Ok ("Payload {0}: {1} files checked" -f $manifest.version, @($manifest.files).Count)
    $folder
}

function Stop-Kiosk {
    $flag = Join-Path $root 'state\maintenance.flag'
    if (Test-Path (Join-Path $root 'state')) { Set-Content -Path $flag -Value 'install' }
    foreach ($p in Get-WatchdogProcesses) { Invoke-CimMethod -InputObject $p -MethodName Terminate | Out-Null }
    Get-Process -Name 'BCELOnePayTerminal', 'CefSharp.BrowserSubprocess', 'OnePayTerminalConnectorGUI' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Copy-Tree([string]$From, [string]$To, [string[]]$KeepDirs) {
    $robocopyArgs = @($From, $To, '/MIR', '/R:2', '/W:2', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    if ($KeepDirs) { $robocopyArgs += '/XD'; $robocopyArgs += $KeepDirs }
    & robocopy.exe @robocopyArgs | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Copying $From failed (robocopy $LASTEXITCODE)" }
}

function Step-InstallFiles([string]$Payload) {
    Write-Step "Installing files to $root"
    Stop-Kiosk
    $wrapper = Join-Path $root 'Wrapper'
    $connector = Join-Path $root 'Connector'
    Copy-Tree (Join-Path $Payload 'Wrapper') $wrapper @('logs')
    Copy-Tree (Join-Path $Payload 'Connector') $connector @('OnePayTerminalConnectorLogs')
    Copy-Item -Path (Join-Path $Payload 'DebugCrt\*.dll') -Destination $connector -Force
    Write-Ok 'Wrapper, Connector and the 3 debug DLLs copied'

    # The kit itself, so Configure/Check keep working after the USB stick or zip is gone
    if ((Resolve-Path $kit).Path.TrimEnd('\') -ne (Resolve-Path $root).Path.TrimEnd('\')) {
        foreach ($dir in 'scripts', 'config') { Copy-Tree (Join-Path $kit $dir) (Join-Path $root $dir) $null }
        Get-ChildItem -Path $kit -Filter '*.cmd' | Copy-Item -Destination $root -Force
    }
    Copy-Item -Path (Join-Path $Payload 'manifest.json') -Destination (Join-Path $root 'payload.json') -Force
    $overlay = Join-Path $Payload 'environments.json'
    if (Test-Path $overlay) { Copy-Item $overlay (Join-Path $root 'config\environments.private.json') -Force }

    # Admins and SYSTEM own the apps; users only write logs and the maintenance flag
    foreach ($dir in 'logs', 'state', 'Wrapper\logs', 'Connector\OnePayTerminalConnectorLogs') {
        New-Item -ItemType Directory -Force -Path (Join-Path $root $dir) | Out-Null
    }
    & icacls.exe $root /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' /Q | Out-Null
    foreach ($dir in 'logs', 'state', 'Wrapper\logs', 'Connector\OnePayTerminalConnectorLogs') {
        & icacls.exe (Join-Path $root $dir) /grant '*S-1-5-32-545:(OI)(CI)M' /Q | Out-Null
    }
    Remove-Item (Join-Path $root 'state\maintenance.flag') -ErrorAction SilentlyContinue
    Write-Ok 'Permissions set (users can write logs only)'
}

function New-Shortcut([string]$Path, [string]$Target, [string]$Arguments, [string]$WorkDir, [string]$Icon) {
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($Path)
    $link.TargetPath = $Target
    if ($Arguments) { $link.Arguments = $Arguments }
    if ($WorkDir) { $link.WorkingDirectory = $WorkDir }
    if ($Icon) { $link.IconLocation = $Icon }
    $link.Save()
}

function Step-Shortcuts {
    Write-Step 'Shortcuts'
    $desktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
    $menu = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'Expressway'
    New-Item -ItemType Directory -Force -Path $menu | Out-Null
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $imageres = Join-Path $env:SystemRoot 'System32\imageres.dll'
    $runWrapper = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $root 'scripts\Run-Wrapper.ps1')
    $wrapperExe = Join-Path $root 'Wrapper\BCELOnePayTerminal.exe'
    $connectorExe = Join-Path $root 'Connector\OnePayTerminalConnectorGUI.exe'
    foreach ($place in $desktop, $menu) {
        New-Shortcut (Join-Path $place 'Expressway Wrapper.lnk') $ps $runWrapper (Join-Path $root 'Wrapper') $wrapperExe
        New-Shortcut (Join-Path $place 'OnePay Connector (test).lnk') $connectorExe '' (Join-Path $root 'Connector') $connectorExe
        New-Shortcut (Join-Path $place 'Expressway Settings.lnk') (Join-Path $root 'Configure.cmd') '' $root "$imageres,109"
        New-Shortcut (Join-Path $place 'Expressway Check.lnk') (Join-Path $root 'Check.cmd') '' $root "$imageres,76"
    }
    New-Shortcut (Join-Path $menu 'Stop Kiosk (maintenance).lnk') (Join-Path $root 'Stop-Kiosk.cmd') '' $root "$imageres,100"
    New-Shortcut (Join-Path $menu 'Start Kiosk.lnk') (Join-Path $root 'Start-Kiosk.cmd') '' $root "$imageres,101"
    Write-Ok 'Desktop and Start menu shortcuts created'
}

function Step-KioskSettings {
    Write-Step 'Kiosk settings'
    if ($NoKioskSettings) { Write-Note 'Skipped (-NoKioskSettings)'; return }

    # Start the Wrapper (through the watchdog) for whoever logs on
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $action = New-ScheduledTaskAction -Execute $ps -WorkingDirectory (Join-Path $root 'Wrapper') `
        -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $root 'scripts\Run-Wrapper.ps1'))
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $users = (New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-545').Translate([Security.Principal.NTAccount]).Value
    $principal = New-ScheduledTaskPrincipal -GroupId $users -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $install.taskName -Action $action -Trigger $trigger -Principal $principal `
        -Settings $settings -Description 'Starts the Expressway Wrapper at logon and restarts it if it closes.' -Force | Out-Null
    Write-Ok "Auto-start task '$($install.taskName)' registered"

    # Never sleep, never blank the screen, keep USB serial adapters awake
    $usb = '2a737441-1930-4402-8d77-b2bebba308a3'
    $usbSuspend = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
    foreach ($cmd in @('/change standby-timeout-ac 0', '/change standby-timeout-dc 0', '/change monitor-timeout-ac 0',
                       '/change monitor-timeout-dc 0', '/change hibernate-timeout-ac 0', '/change hibernate-timeout-dc 0',
                       '/hibernate off', "/setacvalueindex SCHEME_CURRENT $usb $usbSuspend 0",
                       "/setdcvalueindex SCHEME_CURRENT $usb $usbSuspend 0", '/setactive SCHEME_CURRENT')) {
        Start-Process powercfg.exe -ArgumentList $cmd -NoNewWindow -Wait
    }
    Write-Ok 'Power: no sleep, screen always on, USB selective suspend off'

    # Windows Update: no automatic restart while someone is logged on, plus active hours
    $au = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    New-Item -Path $au -Force | Out-Null
    New-ItemProperty -Path $au -Name NoAutoRebootWithLoggedOnUsers -Value 1 -PropertyType DWord -Force | Out-Null
    $ux = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
    New-Item -Path $ux -Force | Out-Null
    New-ItemProperty -Path $ux -Name ActiveHoursStart -Value ([int]$install.activeHoursStart) -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $ux -Name ActiveHoursEnd -Value ([int]$install.activeHoursEnd) -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $ux -Name SmartActiveHoursState -Value 0 -PropertyType DWord -Force | Out-Null
    Write-Ok ("Windows Update: no auto-restart while logged on; active hours {0}:00-{1}:00" -f $install.activeHoursStart, $install.activeHoursEnd)

    Set-TimeZone -Id $install.timeZone
    Write-Ok "Time zone: $($install.timeZone)"

    try {
        Set-SpeakerVolume ([int]$install.volumePercent)
        Write-Ok "Speaker unmuted, volume $($install.volumePercent)%"
    } catch {
        Write-Problem 'No speaker found; payment sounds will not play until one is connected'
    }
}

function Step-Configure {
    Write-Step 'Kiosk values (Terminal ID, COM port, environment)'
    if ($NoConfigure) { Write-Note 'Skipped (-NoConfigure). Run Configure.cmd later.'; return }
    $configure = Join-Path $root 'scripts\Configure-Kiosk.ps1'
    $saved = Join-Path $root 'kiosk.json'
    if ($ConfigFile) {
        & $configure -ConfigFile $ConfigFile -NoPause
    } elseif (Test-Path $saved) {
        Write-Note 'Re-applying the saved settings in kiosk.json'
        & $configure -ConfigFile $saved -NonInteractive -NoPause
    } else {
        & $configure -NoPause
    }
    if ($LASTEXITCODE -ne 0) { Write-Problem 'Kiosk values are not set yet. Run "Expressway Settings" on the desktop.' }
}

try {
    Enable-ModernTls
    $win = Step-CheckWindows
    Step-NetFramework
    Step-VcRedist
    Step-DotnetDesktop
    Step-ProlificDriver $win
    $payload = Step-Payload
    Step-InstallFiles $payload
    Step-Shortcuts
    Step-KioskSettings
    Step-Configure
    Write-Host ''
    Write-Host 'Installation finished.' -ForegroundColor Green
    if ($script:RebootNeeded) { Write-Host 'Restart the PC to finish installing the runtimes or driver.' -ForegroundColor Yellow }
    Write-Host "Log: $transcript"
    $exitCode = 0
} catch {
    Write-Host ''
    Write-Host "INSTALL FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Log: $transcript"
    $exitCode = 1
} finally {
    Stop-Transcript | Out-Null
    Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
}
if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
exit $exitCode
