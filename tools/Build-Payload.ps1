<#
.SYNOPSIS
    Builds the private payload zip (apps + debug DLLs) that Install-Kiosk.ps1 downloads.

.DESCRIPTION
    Runs on Windows PowerShell 5.1 or PowerShell 7 (Windows, Linux, macOS).
    - copies the Wrapper and Connector build folders without their log folders
    - adds the 3 x86 debug DLLs the Connector DLL needs (DebugCrt\)
    - resets the Wrapper config to neutral values (Prod URL, no Terminal ID, no QR ID, debug port off)
      so an unconfigured kiosk fails the health check instead of running with test values
    - writes environments.json (Dev URL), manifest.json (SHA-256 of every file), the zip and SHA256SUMS
    The output must stay private: never commit it to the public repo.

.EXAMPLE
    pwsh tools/Build-Payload.ps1 -WrapperDir ~/apps/BCELOnePayTerminal/Debug `
        -ConnectorDir ~/apps/OnePayTerminalConnectorGUI/net7.0-windows -DebugCrtDir ~/apps/debug-crt `
        -DevUrl https://expressway-qr-dev.example.workers.dev/ -OutDir ~/payload-out
#>
param(
    [Parameter(Mandatory)][string]$WrapperDir,
    [Parameter(Mandatory)][string]$ConnectorDir,
    [Parameter(Mandatory)][string]$DebugCrtDir,
    [string]$DevUrl,
    [string]$Version = (Get-Date -Format 'yyyy.MM.dd'),
    [Parameter(Mandatory)][string]$OutDir
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/Kiosk.Common.psm1') -Force -DisableNameChecking

$name = "expressway-payload-$Version"
$stage = Join-Path $OutDir $name
$zip = Join-Path $OutDir "$name.zip"

function Copy-Folder([string]$From, [string]$To, [string[]]$SkipDirs) {
    $fromFull = (Resolve-Path $From).Path.TrimEnd('\', '/')
    foreach ($file in Get-ChildItem -Path $fromFull -Recurse -File) {
        $relative = $file.FullName.Substring($fromFull.Length + 1)
        $top = ($relative -split '[\\/]')[0]
        if ($SkipDirs -contains $top) { continue }
        $target = Join-Path $To $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target
    }
}

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
if (Test-Path $zip) { Remove-Item $zip -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

Write-Step "Staging $name"
foreach ($required in (Join-Path $WrapperDir 'BCELOnePayTerminal.exe'), (Join-Path $ConnectorDir 'OnePayTerminalConnectorGUI.exe')) {
    if (-not (Test-Path $required)) { throw "Not found: $required" }
}
Copy-Folder $WrapperDir (Join-Path $stage 'Wrapper') @('logs')
Copy-Folder $ConnectorDir (Join-Path $stage 'Connector') @('OnePayTerminalConnectorLogs')
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'DebugCrt') | Out-Null
foreach ($dll in 'msvcp140d.dll', 'vcruntime140d.dll', 'ucrtbased.dll') {
    $source = Join-Path $DebugCrtDir $dll
    if (-not (Test-Path $source)) { throw "Debug DLL not found: $source" }
    Copy-Item $source (Join-Path $stage 'DebugCrt')
}
Write-Ok 'Wrapper, Connector and DebugCrt copied'

$prod = (Get-KitConfig 'environments.json').Prod.url
Set-WrapperSettings (Join-Path $stage 'Wrapper/BCELOnePayTerminal.exe.config') ([ordered]@{
    CefSharpUrl                 = $prod
    CefSharpRemoteDebuggingPort = '0'
    Topmost                     = 'False'
    SerialPortName              = ''
    LogServerUrl                = ''
    TerminalId                  = ''
    ClientSetting               = New-ClientSettingJson '' '' '' ''
}) -RemoveComments
Write-Ok "Wrapper config reset to neutral values ($prod)"

if ($DevUrl) {
    Write-JsonFile (Join-Path $stage 'environments.json') ([ordered]@{ Dev = [ordered]@{ url = $DevUrl } })
    Write-Ok 'environments.json written with the Dev URL'
}

Write-JsonFile (Join-Path $stage 'manifest.json') (New-PayloadManifest $stage $Version)
Write-Ok 'manifest.json written'

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
$hash = Get-FileHashHex $zip
Set-Content -Path (Join-Path $OutDir 'SHA256SUMS') -Value "$hash  $name.zip"
Write-Ok ("{0} ({1:N1} MB)" -f $zip, ((Get-Item $zip).Length / 1MB))
Write-Host "    sha256 $hash"
