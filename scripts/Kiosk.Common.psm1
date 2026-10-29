# Shared helpers for the Expressway kiosk scripts.
# Works on Windows PowerShell 5.1 (the kiosks) and PowerShell 7 (tests and payload builds).

Set-StrictMode -Version 2.0

$script:KitRoot = Split-Path -Parent $PSScriptRoot
$script:WrapperSection = 'BCELOnePayTerminal.Properties.Settings'
# Tests run these scripts on Linux; Windows-only lookups return nothing there.
$script:OnWindows = ($PSVersionTable.PSEdition -ne 'Core') -or $IsWindows
$script:PlaceholderIds = @('', 'example', 'test', 'demo', 'placeholder', 'example-t01', 'your-static-qr-id')

# ---------------------------------------------------------------- console output

function Write-Step([string]$Message) { Write-Host ''; Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "    [ OK ] $Message" -ForegroundColor Green }
function Write-Note([string]$Message) { Write-Host "    [ .. ] $Message" -ForegroundColor Gray }
function Write-Problem([string]$Message) { Write-Host "    [WARN] $Message" -ForegroundColor Yellow }

# ---------------------------------------------------------------- paths and JSON

function Get-KitRoot { $script:KitRoot }

function Get-KitConfig([string]$Name) {
    Read-JsonFile (Join-Path (Join-Path $script:KitRoot 'config') $Name)
}

function Get-InstallRoot {
    if ($env:EXPRESSWAY_ROOT) { return $env:EXPRESSWAY_ROOT }
    (Get-KitConfig 'install.json').installRoot
}

function ConvertFrom-LenientJson([string]$Text) {
    # The Wrapper's ClientSetting has a trailing comma ({"a": 1,}); Newtonsoft accepts that, ConvertFrom-Json does not.
    $clean = [regex]::Replace($Text, ',(\s*[}\]])', '$1')
    $clean | ConvertFrom-Json
}

function Read-JsonFile([string]$Path) {
    ConvertFrom-LenientJson ([System.IO.File]::ReadAllText($Path))
}

function Write-JsonFile([string]$Path, $Object) {
    $json = $Object | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
}

function ConvertTo-OrderedHashtable($Object) {
    $result = [ordered]@{}
    if ($null -eq $Object) { return $result }
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) { $result[$key] = $Object[$key] }
    } else {
        foreach ($prop in $Object.PSObject.Properties) { $result[$prop.Name] = $prop.Value }
    }
    $result
}

function Get-JsonValue($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    $prop.Value
}

# ---------------------------------------------------------------- elevation

function Test-IsAdministrator {
    if (-not $script:OnWindows) { return $true }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Re-runs a script as administrator with the same parameters. Returns $true when the caller should exit.
function Invoke-SelfElevation([string]$ScriptPath, $BoundParameters) {
    if (Test-IsAdministrator) { return $false }
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $ScriptPath))
    foreach ($entry in $BoundParameters.GetEnumerator()) {
        $value = $entry.Value
        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) { $arguments += "-$($entry.Key)" }
        } elseif ($value -is [bool]) {
            $arguments += ('-{0}:${1}' -f $entry.Key, $value.ToString().ToLower())
        } else {
            $arguments += "-$($entry.Key)"
            $arguments += ('"{0}"' -f ([string]$value -replace '"', '\"'))
        }
    }
    Write-Host 'Asking for administrator rights...'
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList ($arguments -join ' ') | Out-Null
    $true
}

# ---------------------------------------------------------------- system facts

function Get-WindowsInfo {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = [int]$cv.CurrentBuildNumber
    $name = $cv.ProductName
    if ($build -ge 22000) { $name = $name -replace 'Windows 10', 'Windows 11' }
    $release = Get-JsonValue $cv 'DisplayVersion' (Get-JsonValue $cv 'ReleaseId' '')
    [pscustomobject]@{
        Name    = $name
        Build   = $build
        Release = $release
        Is64Bit = [Environment]::Is64BitOperatingSystem
    }
}

function Get-ProgramFilesX86 {
    $x86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($x86) { return $x86 }
    $env:ProgramFiles
}

function Get-NetFrameworkRelease {
    $key = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue
    if ($null -eq $key) { return 0 }
    [int](Get-JsonValue $key 'Release' 0)
}

function Get-VcRedistX86Version {
    foreach ($path in @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\X86',
                        'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X86')) {
        $key = Get-ItemProperty $path -ErrorAction SilentlyContinue
        if ($key -and (Get-JsonValue $key 'Installed' 0) -eq 1) { return [string](Get-JsonValue $key 'Version' 'installed') }
    }
    $null
}

function Get-DotnetDesktopX86Versions([int]$Major) {
    $dir = Join-Path (Get-ProgramFilesX86) 'dotnet\shared\Microsoft.WindowsDesktop.App'
    if (-not (Test-Path $dir)) { return @() }
    @(Get-ChildItem $dir -Directory | Where-Object { $_.Name -like "$Major.*" } | ForEach-Object { $_.Name })
}

function Get-PrimaryIPv4 {
    if (-not $script:OnWindows) { return '' }
    try {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Sort-Object RouteMetric | Select-Object -First 1
        $ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.InterfaceIndex -ErrorAction Stop | Select-Object -First 1
        return $ip.IPAddress
    } catch {
        $any = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
        if ($any) { return $any.IPAddress }
    }
    ''
}

# Lists COM ports with their device names; marks Prolific adapters.
function Get-ComPortList {
    if (-not $script:OnWindows) { return @() }
    $ports = @{}
    $devices = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\((COM\d+)\)' })
    foreach ($device in $devices) {
        $null = $device.Name -match '\((COM\d+)\)'
        $port = $Matches[1]
        $ports[$port] = [pscustomobject]@{
            Port      = $port
            Name      = ($device.Name -replace '\s*\(COM\d+\)', '')
            Prolific  = ($device.PNPDeviceID -like 'USB\VID_067B*')
            ErrorCode = [int]$device.ConfigManagerErrorCode
        }
    }
    foreach ($port in [System.IO.Ports.SerialPort]::GetPortNames()) {
        if (-not $ports.ContainsKey($port)) {
            $ports[$port] = [pscustomobject]@{ Port = $port; Name = 'Serial port'; Prolific = $false; ErrorCode = 0 }
        }
    }
    @($ports.Values | Sort-Object { [int]($_.Port -replace '\D', '') })
}

# ---------------------------------------------------------------- downloads and signatures

function Enable-ModernTls {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $global:ProgressPreference = 'SilentlyContinue'
}

function Get-FileHashHex([string]$Path, [string]$Algorithm = 'SHA256') {
    (Get-FileHash -Path $Path -Algorithm $Algorithm).Hash.ToLowerInvariant()
}

function Test-MicrosoftSignature([string]$Path) {
    $sig = Get-AuthenticodeSignature -FilePath $Path
    ($sig.Status -eq 'Valid') -and ($sig.SignerCertificate.Subject -match 'O=Microsoft Corporation')
}

# Downloads a file (with retries) and checks it. Throws when the file is wrong.
function Save-WebFile {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination,
        [string]$Sha256,
        [string]$Sha512,
        [switch]$RequireMicrosoftSignature
    )
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            $client = New-Object System.Net.WebClient
            $client.Headers['User-Agent'] = 'expressway-kiosk-setup'
            $client.DownloadFile($Url, $Destination)
            break
        } catch {
            if ($attempt -ge 3) { throw "Download failed: $Url ($($_.Exception.Message))" }
            Start-Sleep -Seconds (5 * $attempt)
        }
    }
    if ($Sha256 -and (Get-FileHashHex $Destination 'SHA256') -ne $Sha256.ToLowerInvariant()) {
        Remove-Item $Destination -Force
        throw "SHA-256 mismatch for $Url"
    }
    if ($Sha512 -and (Get-FileHashHex $Destination 'SHA512') -ne $Sha512.ToLowerInvariant()) {
        Remove-Item $Destination -Force
        throw "SHA-512 mismatch for $Url"
    }
    if ($RequireMicrosoftSignature -and -not (Test-MicrosoftSignature $Destination)) {
        Remove-Item $Destination -Force
        throw "$Destination is not signed by Microsoft"
    }
}

# Runs an installer and returns 'ok' or 'reboot'. Throws on failure.
function Invoke-Installer([string]$Path, [string]$Arguments, [string]$Name) {
    $process = Start-Process -FilePath $Path -ArgumentList $Arguments -Wait -PassThru
    switch ($process.ExitCode) {
        0 { return 'ok' }
        1638 { return 'ok' }      # a newer version is already installed
        3010 { return 'reboot' }
        1641 { return 'reboot' }
        default { throw "$Name failed with exit code $($process.ExitCode)" }
    }
}

# ---------------------------------------------------------------- GitHub release download

function Invoke-GitHubApi([string]$Url, [string]$Token) {
    $headers = @{
        'Authorization'        = "Bearer $Token"
        'Accept'               = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent'           = 'expressway-kiosk-setup'
    }
    Invoke-RestMethod -Uri $Url -Headers $headers -UseBasicParsing
}

function Get-PayloadRelease([string]$Repo, [string]$Version, [string]$Token, [string]$AssetPattern) {
    $url = "https://api.github.com/repos/$Repo/releases/latest"
    if ($Version -and $Version -ne 'latest') { $url = "https://api.github.com/repos/$Repo/releases/tags/$Version" }
    $release = Invoke-GitHubApi $url $Token
    $asset = @($release.assets | Where-Object { $_.name -like $AssetPattern }) | Select-Object -First 1
    if ($null -eq $asset) { throw "Release $($release.tag_name) of $Repo has no asset matching $AssetPattern" }
    [pscustomobject]@{
        Tag    = $release.tag_name
        Name   = $asset.name
        ApiUrl = $asset.url
        Size   = [long]$asset.size
        Sha256 = ([string](Get-JsonValue $asset 'digest' '') -replace '^sha256:', '')
    }
}

# Asset downloads redirect to a signed storage URL that must NOT receive the token,
# so follow the redirect by hand.
function Save-GitHubAsset([string]$ApiUrl, [string]$Token, [string]$Destination) {
    $request = [System.Net.WebRequest]::Create($ApiUrl)
    $request.AllowAutoRedirect = $false
    $request.UserAgent = 'expressway-kiosk-setup'
    $request.Accept = 'application/octet-stream'
    $request.Headers['Authorization'] = "Bearer $Token"
    $response = $request.GetResponse()
    try {
        $code = [int]$response.StatusCode
        if ($code -ge 300 -and $code -lt 400) {
            $location = $response.Headers['Location']
            $response.Close()
            Save-WebFile -Url $location -Destination $Destination
            return
        }
        $stream = $response.GetResponseStream()
        $file = [System.IO.File]::Create($Destination)
        try { $stream.CopyTo($file) } finally { $file.Close(); $stream.Close() }
    } finally {
        $response.Close()
    }
}

# ---------------------------------------------------------------- payload manifest

function New-PayloadManifest([string]$Root, [string]$Version) {
    $rootFull = (Resolve-Path $Root).Path.TrimEnd('\', '/')
    $files = @(Get-ChildItem -Path $rootFull -Recurse -File | Where-Object { $_.Name -ne 'manifest.json' } |
        Sort-Object FullName | ForEach-Object {
            [ordered]@{
                path   = $_.FullName.Substring($rootFull.Length + 1).Replace('\', '/')
                size   = $_.Length
                sha256 = Get-FileHashHex $_.FullName
            }
        })
    [ordered]@{
        name    = 'expressway-payload'
        version = $Version
        created = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        files   = $files
    }
}

# Returns a list of problems; empty means every file matches the manifest.
function Test-PayloadManifest([string]$Root) {
    $manifestPath = Join-Path $Root 'manifest.json'
    if (-not (Test-Path $manifestPath)) { return @('manifest.json is missing') }
    $manifest = Read-JsonFile $manifestPath
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $manifest.files) {
        $path = Join-Path $Root ($entry.path -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $path)) { $problems.Add("missing: $($entry.path)"); continue }
        if ((Get-FileHashHex $path) -ne $entry.sha256) { $problems.Add("changed: $($entry.path)") }
    }
    $problems.ToArray()
}

# ---------------------------------------------------------------- Wrapper settings (BCELOnePayTerminal.exe.config)

function Get-WrapperConfigDocument([string]$ConfigPath) {
    $doc = New-Object System.Xml.XmlDocument
    $doc.PreserveWhitespace = $true
    $doc.Load($ConfigPath)
    $doc
}

function Get-WrapperSettingsNode($Document) {
    $node = $Document.SelectSingleNode("/configuration/applicationSettings/$script:WrapperSection")
    if ($null -eq $node) { throw "applicationSettings/$script:WrapperSection not found in the Wrapper config" }
    $node
}

function Get-WrapperSettings([string]$ConfigPath) {
    $section = Get-WrapperSettingsNode (Get-WrapperConfigDocument $ConfigPath)
    $result = [ordered]@{}
    foreach ($setting in $section.SelectNodes('setting')) {
        $value = $setting.SelectSingleNode('value')
        if ($value) { $result[$setting.GetAttribute('name')] = $value.InnerText.Trim() } else { $result[$setting.GetAttribute('name')] = '' }
    }
    $result
}

# Sets <setting name="X"><value>...</value></setting> entries; adds missing ones.
function Set-WrapperSettings([string]$ConfigPath, [System.Collections.IDictionary]$Values, [switch]$RemoveComments) {
    $doc = Get-WrapperConfigDocument $ConfigPath
    $section = Get-WrapperSettingsNode $doc
    foreach ($name in $Values.Keys) {
        $setting = $section.SelectSingleNode("setting[@name='$name']")
        if ($null -eq $setting) {
            $setting = $doc.CreateElement('setting')
            $setting.SetAttribute('name', $name)
            $setting.SetAttribute('serializeAs', 'String')
            $null = $section.AppendChild($setting)
        }
        if ($RemoveComments) {
            foreach ($comment in @($setting.SelectNodes('comment()'))) { $null = $setting.RemoveChild($comment) }
        }
        $value = $setting.SelectSingleNode('value')
        if ($null -eq $value) {
            $value = $doc.CreateElement('value')
            $null = $setting.AppendChild($value)
        }
        $value.InnerText = [string]$Values[$name]
    }
    $doc.Save($ConfigPath)
}

# Builds the ClientSetting JSON the web UI reads through getClientSetting(); keeps keys it doesn't know.
function New-ClientSettingJson([string]$Existing, [string]$TerminalId, [string]$StaticQrId, [string]$SerialPortName) {
    $merged = [ordered]@{ staticQrId = $StaticQrId; terminalId = $TerminalId; serialPortName = $SerialPortName }
    if ($Existing -and $Existing.Trim()) {
        try {
            $old = ConvertFrom-LenientJson $Existing
            foreach ($prop in $old.PSObject.Properties) {
                if (-not $merged.Contains($prop.Name)) { $merged[$prop.Name] = $prop.Value }
            }
        } catch {
            Write-Problem 'The old ClientSetting was not valid JSON; writing a fresh one.'
        }
    }
    $merged | ConvertTo-Json -Compress
}

function Test-PlaceholderId([string]$Value) {
    $script:PlaceholderIds -contains ([string]$Value).Trim().ToLowerInvariant()
}

# Environments from the kit, overlaid by the private payload copy (which holds the Dev URL).
function Get-KioskEnvironments([string]$OverlayPath) {
    $envs = ConvertTo-OrderedHashtable (Get-KitConfig 'environments.json')
    if ($OverlayPath -and (Test-Path $OverlayPath)) {
        $overlay = Read-JsonFile $OverlayPath
        foreach ($prop in $overlay.PSObject.Properties) {
            $base = ConvertTo-OrderedHashtable $envs[$prop.Name]
            foreach ($inner in $prop.Value.PSObject.Properties) { $base[$inner.Name] = $inner.Value }
            $envs[$prop.Name] = [pscustomobject]$base
        }
    }
    $envs
}

# ---------------------------------------------------------------- audio (payment sounds must be audible)

$script:AudioTypeLoaded = $false
function Initialize-AudioType {
    if ($script:AudioTypeLoaded) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace ExpresswayKiosk {
  [Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioEndpointVolume {
    int f(); int g(); int h(); int i();
    int SetMasterVolumeLevelScalar(float level, Guid context);
    int j();
    int GetMasterVolumeLevelScalar(out float level);
    int k(); int l(); int m(); int n();
    int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, Guid context);
    int GetMute(out bool mute);
  }
  [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDevice { int Activate(ref Guid id, int clsCtx, int activationParams, out IAudioEndpointVolume volume); }
  [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDeviceEnumerator { int f(); int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device); }
  [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorComObject { }
  public static class Speaker {
    static IAudioEndpointVolume Endpoint() {
      var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
      IMMDevice device;
      Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(0, 1, out device));
      IAudioEndpointVolume volume;
      Guid id = typeof(IAudioEndpointVolume).GUID;
      Marshal.ThrowExceptionForHR(device.Activate(ref id, 23, 0, out volume));
      return volume;
    }
    public static float Volume {
      get { float v; Marshal.ThrowExceptionForHR(Endpoint().GetMasterVolumeLevelScalar(out v)); return v; }
      set { Marshal.ThrowExceptionForHR(Endpoint().SetMasterVolumeLevelScalar(value, Guid.Empty)); }
    }
    public static bool Mute {
      get { bool m; Marshal.ThrowExceptionForHR(Endpoint().GetMute(out m)); return m; }
      set { Marshal.ThrowExceptionForHR(Endpoint().SetMute(value, Guid.Empty)); }
    }
  }
}
'@
    $script:AudioTypeLoaded = $true
}

# Returns $null when there is no speaker.
function Get-SpeakerState {
    try {
        Initialize-AudioType
        [pscustomobject]@{ Percent = [int][math]::Round([ExpresswayKiosk.Speaker]::Volume * 100); Muted = [ExpresswayKiosk.Speaker]::Mute }
    } catch { $null }
}

function Set-SpeakerVolume([int]$Percent) {
    Initialize-AudioType
    [ExpresswayKiosk.Speaker]::Mute = $false
    [ExpresswayKiosk.Speaker]::Volume = [float]($Percent / 100.0)
}

# ---------------------------------------------------------------- Wrapper process

function Get-WrapperProcesses([string]$InstallRoot) {
    $exe = Join-Path $InstallRoot 'Wrapper\BCELOnePayTerminal.exe'
    @(Get-Process -Name 'BCELOnePayTerminal' -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -eq $exe } catch { $true }
    })
}

function Get-WatchdogProcesses {
    if (-not $script:OnWindows) { return @() }
    @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*Run-Wrapper.ps1*' })
}

function Write-KioskLog([string]$LogFile, [string]$Message) {
    $line = '{0}  {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch { }
}

function Show-MonitorSummary($Settings) {
    Write-Host ''
    Write-Host 'Register this kiosk in Tollway Kiosk Monitor with:' -ForegroundColor Cyan
    Write-Host ('    Terminal ID  : {0}' -f $Settings.terminalId)
    Write-Host ('    Static QR ID : {0}' -f $Settings.staticQrId)
    Write-Host ('    COM port     : {0}' -f $Settings.comPort)
    Write-Host ('    Environment  : {0}' -f $Settings.monitorEnvironment)
    Write-Host ('    IP address   : {0}' -f (Get-PrimaryIPv4))
    Write-Host ('    Computer     : {0}' -f $env:COMPUTERNAME)
}

Export-ModuleMember -Function *
