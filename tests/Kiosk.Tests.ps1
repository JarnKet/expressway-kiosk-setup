# Pester 5 tests. Run: Invoke-Pester ./tests
# They cover the parts that don't need Windows: config editing, ClientSetting JSON, manifests,
# environments, the payload builder, and Configure-Kiosk.ps1 run non-interactively against a temp folder.

BeforeAll {
    $script:Kit = Split-Path -Parent $PSScriptRoot
    $script:Fixture = Join-Path $PSScriptRoot 'fixtures/BCELOnePayTerminal.exe.config'
    Import-Module (Join-Path $script:Kit 'scripts/Kiosk.Common.psm1') -Force -DisableNameChecking
}

Describe 'ConvertFrom-LenientJson' {
    It 'accepts the trailing comma the Wrapper config uses' {
        $obj = ConvertFrom-LenientJson '{ "a": "x", "b": [1, 2,], }'
        $obj.a | Should -Be 'x'
        $obj.b.Count | Should -Be 2
    }
}

Describe 'Wrapper settings' {
    BeforeEach {
        $script:Config = Join-Path $TestDrive 'BCELOnePayTerminal.exe.config'
        Copy-Item $script:Fixture $script:Config
    }

    It 'reads every setting' {
        $s = Get-WrapperSettings $script:Config
        $s['TerminalId'] | Should -Be 'FAKE-T09'
        $s['SerialPortName'] | Should -Be 'COM2'
        $s['LogServerUrl'] | Should -Be ''
        $s['CefSharpUrl'] | Should -Be 'https://dev.example.invalid/'
        (ConvertFrom-LenientJson $s['ClientSetting']).staticQrId | Should -Be 'fakeqr0001'
    }

    It 'changes only the given settings and keeps the file valid' {
        Set-WrapperSettings $script:Config ([ordered]@{ TerminalId = 'T-NEW'; LogServerUrl = 'https://logs.example.invalid' })
        $s = Get-WrapperSettings $script:Config
        $s['TerminalId'] | Should -Be 'T-NEW'
        $s['LogServerUrl'] | Should -Be 'https://logs.example.invalid'
        $s['SerialPortName'] | Should -Be 'COM2'
        [xml](Get-Content $script:Config -Raw) | Should -Not -BeNullOrEmpty
        (Get-Content $script:Config -Raw) | Should -Match 'http://localhost:5173'   # comments kept by default
    }

    It 'removes comments inside a setting when asked' {
        Set-WrapperSettings $script:Config ([ordered]@{ CefSharpUrl = 'https://prod.example.invalid/' }) -RemoveComments
        (Get-Content $script:Config -Raw) | Should -Not -Match 'localhost:5173'
        (Get-WrapperSettings $script:Config)['CefSharpUrl'] | Should -Be 'https://prod.example.invalid/'
    }

    It 'adds a setting that does not exist yet' {
        Set-WrapperSettings $script:Config ([ordered]@{ NewThing = '42' })
        (Get-WrapperSettings $script:Config)['NewThing'] | Should -Be '42'
    }

    It 'keeps the UTF-8 byte order mark' {
        Set-WrapperSettings $script:Config ([ordered]@{ TerminalId = 'X' })
        $bytes = [System.IO.File]::ReadAllBytes($script:Config)
        ($bytes[0], $bytes[1], $bytes[2]) | Should -Be @(0xEF, 0xBB, 0xBF)
    }
}

Describe 'New-ClientSettingJson' {
    It 'sets the three known keys and keeps unknown ones' {
        $old = '{ "staticQrId": "old", "terminalId": "old", "serialPortName": "COM9", "volume": 7, }'
        $json = New-ClientSettingJson $old 'T01' 'qr1' 'COM3'
        $obj = $json | ConvertFrom-Json
        $obj.staticQrId | Should -Be 'qr1'
        $obj.terminalId | Should -Be 'T01'
        $obj.serialPortName | Should -Be 'COM3'
        $obj.volume | Should -Be 7
        $json | Should -Not -Match "`n"
    }

    It 'starts fresh when the old value is not JSON' {
        $obj = (New-ClientSettingJson 'not json' 'T01' 'qr1' 'COM3') | ConvertFrom-Json
        @($obj.PSObject.Properties).Count | Should -Be 3
    }
}

Describe 'Test-PlaceholderId' {
    It 'flags empty and placeholder values the UI ignores' {
        foreach ($v in '', '  ', 'test', 'Example', 'placeholder', 'EXAMPLE-T01') { Test-PlaceholderId $v | Should -BeTrue }
        Test-PlaceholderId 'itm6abc' | Should -BeFalse
    }
}

Describe 'Payload manifest' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive 'payload'
        New-Item -ItemType Directory -Force -Path (Join-Path $script:Root 'Wrapper/sub') | Out-Null
        Set-Content (Join-Path $script:Root 'Wrapper/a.txt') 'one'
        Set-Content (Join-Path $script:Root 'Wrapper/sub/b.txt') 'two'
        Write-JsonFile (Join-Path $script:Root 'manifest.json') (New-PayloadManifest $script:Root '1.0')
    }

    It 'lists files with forward slashes and passes when nothing changed' {
        $m = Read-JsonFile (Join-Path $script:Root 'manifest.json')
        @($m.files).Count | Should -Be 2
        $m.files.path | Should -Contain 'Wrapper/sub/b.txt'
        @(Test-PayloadManifest $script:Root).Count | Should -Be 0
    }

    It 'reports changed and missing files' {
        Set-Content (Join-Path $script:Root 'Wrapper/a.txt') 'tampered'
        Remove-Item (Join-Path $script:Root 'Wrapper/sub/b.txt')
        $problems = @(Test-PayloadManifest $script:Root)
        $problems | Should -Contain 'changed: Wrapper/a.txt'
        $problems | Should -Contain 'missing: Wrapper/sub/b.txt'
    }
}

Describe 'Environments' {
    It 'takes Prod from the kit and the Dev URL from the private overlay' {
        $overlay = Join-Path $TestDrive 'environments.private.json'
        Set-Content $overlay '{ "Dev": { "url": "https://dev.example.invalid/" } }'
        $envs = Get-KioskEnvironments $overlay
        $envs['Prod'].url | Should -Be 'https://expressway.bcel.one/'
        $envs['Dev'].url | Should -Be 'https://dev.example.invalid/'
        $envs['Dev'].remoteDebuggingPort | Should -Be 9999
    }
}

Describe 'Build-Payload.ps1' {
    It 'builds a zip with a neutral config, the debug DLLs and a valid manifest' {
        $src = Join-Path $TestDrive 'src'
        foreach ($d in 'wrapper/logs', 'connector/OnePayTerminalConnectorLogs', 'crt') { New-Item -ItemType Directory -Force -Path (Join-Path $src $d) | Out-Null }
        Copy-Item $script:Fixture (Join-Path $src 'wrapper/BCELOnePayTerminal.exe.config')
        Set-Content (Join-Path $src 'wrapper/BCELOnePayTerminal.exe') 'exe'
        Set-Content (Join-Path $src 'wrapper/logs/old.log') 'log'
        Set-Content (Join-Path $src 'connector/OnePayTerminalConnectorGUI.exe') 'exe'
        Set-Content (Join-Path $src 'connector/OnePayTerminalConnectorLogs/x.log') 'log'
        foreach ($dll in 'msvcp140d.dll', 'vcruntime140d.dll', 'ucrtbased.dll') { Set-Content (Join-Path $src "crt/$dll") 'dll' }
        $out = Join-Path $TestDrive 'out'

        & (Join-Path $script:Kit 'tools/Build-Payload.ps1') -WrapperDir (Join-Path $src 'wrapper') -ConnectorDir (Join-Path $src 'connector') `
            -DebugCrtDir (Join-Path $src 'crt') -DevUrl 'https://dev.example.invalid/' -Version '9.9.9' -OutDir $out 6>$null

        $zip = Join-Path $out 'expressway-payload-9.9.9.zip'
        Test-Path $zip | Should -BeTrue
        $check = Join-Path $TestDrive 'unzipped'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $check)
        @(Test-PayloadManifest $check).Count | Should -Be 0
        Test-Path (Join-Path $check 'Wrapper/logs') | Should -BeFalse
        Test-Path (Join-Path $check 'Connector/OnePayTerminalConnectorLogs') | Should -BeFalse
        Test-Path (Join-Path $check 'DebugCrt/ucrtbased.dll') | Should -BeTrue
        $s = Get-WrapperSettings (Join-Path $check 'Wrapper/BCELOnePayTerminal.exe.config')
        $s['CefSharpUrl'] | Should -Be 'https://expressway.bcel.one/'
        $s['TerminalId'] | Should -Be ''
        $s['CefSharpRemoteDebuggingPort'] | Should -Be '0'
        (ConvertFrom-LenientJson $s['ClientSetting']).staticQrId | Should -Be ''
        (Get-Content (Join-Path $check 'Wrapper/BCELOnePayTerminal.exe.config') -Raw) | Should -Not -Match 'dev.example.invalid'
        (Read-JsonFile (Join-Path $check 'environments.json')).Dev.url | Should -Be 'https://dev.example.invalid/'
        (Get-Content (Join-Path $out 'SHA256SUMS')) | Should -Match ((Get-FileHashHex $zip) + '  expressway-payload-9.9.9.zip')
    }
}

Describe 'Configure-Kiosk.ps1 (non-interactive)' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive 'Expressway'
        New-Item -ItemType Directory -Force -Path (Join-Path $script:Root 'Wrapper'), (Join-Path $script:Root 'config') | Out-Null
        Copy-Item $script:Fixture (Join-Path $script:Root 'Wrapper/BCELOnePayTerminal.exe.config')
        Set-Content (Join-Path $script:Root 'config/environments.private.json') '{ "Dev": { "url": "https://dev.example.invalid/" } }'
        $env:EXPRESSWAY_ROOT = $script:Root
        $script:Configure = Join-Path $script:Kit 'scripts/Configure-Kiosk.ps1'
    }
    AfterEach { Remove-Item Env:EXPRESSWAY_ROOT -ErrorAction SilentlyContinue }

    It 'writes Prod settings, turns the debug port off and saves kiosk.json' {
        & pwsh -NoProfile -File $script:Configure -TerminalId 'T-77' -StaticQrId 'qr77' -ComPort 'com3' -Environment Prod -NonInteractive -NoPause *> $null
        $LASTEXITCODE | Should -Be 0
        $s = Get-WrapperSettings (Join-Path $script:Root 'Wrapper/BCELOnePayTerminal.exe.config')
        $s['CefSharpUrl'] | Should -Be 'https://expressway.bcel.one/'
        $s['TerminalId'] | Should -Be 'T-77'
        $s['SerialPortName'] | Should -Be 'COM3'
        $s['CefSharpRemoteDebuggingPort'] | Should -Be '0'
        $client = ConvertFrom-LenientJson $s['ClientSetting']
        $client.staticQrId | Should -Be 'qr77'
        $client.serialPortName | Should -Be 'COM3'
        $client.volume | Should -Be 7
        $saved = Read-JsonFile (Join-Path $script:Root 'kiosk.json')
        $saved.environment | Should -Be 'Prod'
        $saved.PSObject.Properties['remoteDebuggingPort'] | Should -BeNullOrEmpty
        @(Get-ChildItem (Join-Path $script:Root 'state/config-backups')).Count | Should -Be 1
    }

    It 'uses the Dev URL and port from the overlay and re-applies kiosk.json later' {
        & pwsh -NoProfile -File $script:Configure -TerminalId 'T-78' -StaticQrId 'qr78' -ComPort 'COM4' -Environment Dev -NonInteractive -NoPause *> $null
        $s = Get-WrapperSettings (Join-Path $script:Root 'Wrapper/BCELOnePayTerminal.exe.config')
        $s['CefSharpUrl'] | Should -Be 'https://dev.example.invalid/'
        $s['CefSharpRemoteDebuggingPort'] | Should -Be '9999'

        # A reinstall resets the config; kiosk.json brings the values back
        Copy-Item $script:Fixture (Join-Path $script:Root 'Wrapper/BCELOnePayTerminal.exe.config') -Force
        & pwsh -NoProfile -File $script:Configure -ConfigFile (Join-Path $script:Root 'kiosk.json') -NonInteractive -NoPause *> $null
        $LASTEXITCODE | Should -Be 0
        $s = Get-WrapperSettings (Join-Path $script:Root 'Wrapper/BCELOnePayTerminal.exe.config')
        $s['TerminalId'] | Should -Be 'T-78'
        $s['CefSharpUrl'] | Should -Be 'https://dev.example.invalid/'
    }

    It 'refuses placeholder IDs and leaves the config alone' {
        $before = Get-Content (Join-Path $script:Root 'Wrapper/BCELOnePayTerminal.exe.config') -Raw
        & pwsh -NoProfile -File $script:Configure -TerminalId 'test' -StaticQrId 'example' -ComPort 'COM3' -Environment Prod -NonInteractive -NoPause *> $null
        $LASTEXITCODE | Should -Be 1
        Get-Content (Join-Path $script:Root 'Wrapper/BCELOnePayTerminal.exe.config') -Raw | Should -Be $before
    }

    It 'accepts a custom URL and keeps an explicit debug port' {
        & pwsh -NoProfile -File $script:Configure -TerminalId 'T-79' -StaticQrId 'qr79' -ComPort 'COM5' -Url 'https://staging.example.invalid/' -RemoteDebuggingPort 9222 -NonInteractive -NoPause *> $null
        $s = Get-WrapperSettings (Join-Path $script:Root 'Wrapper/BCELOnePayTerminal.exe.config')
        $s['CefSharpUrl'] | Should -Be 'https://staging.example.invalid/'
        $s['CefSharpRemoteDebuggingPort'] | Should -Be '9222'
        $saved = Read-JsonFile (Join-Path $script:Root 'kiosk.json')
        $saved.environment | Should -Be 'Custom'
        $saved.url | Should -Be 'https://staging.example.invalid/'
        $saved.remoteDebuggingPort | Should -Be 9222
    }
}
