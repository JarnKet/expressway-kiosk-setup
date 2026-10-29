# Building and publishing the private payload

The payload is everything the public kit is not allowed to contain: the BCEL apps, the Connector's
debug DLLs and the Dev URL. It is published as a Release asset of the **private** repository
`JarnKet/expressway-kiosk-payload`, and `Install-Kiosk.ps1` downloads the newest release.

## Build

You need the Wrapper build folder, the Connector build folder and a folder with the three x86 debug DLLs
(`msvcp140d.dll`, `vcruntime140d.dll`, `ucrtbased.dll`, all signed by Microsoft).

```powershell
pwsh tools/Build-Payload.ps1 `
    -WrapperDir   <...>\BCELOnePayTerminal\Debug `
    -ConnectorDir <...>\OnePayTerminalConnectorGUI\net7.0-windows `
    -DebugCrtDir  <folder with the 3 DLLs> `
    -DevUrl       https://<dev-ui-host>/ `
    -OutDir       <output folder>
```

Windows PowerShell 5.1 works too (`powershell -File tools\Build-Payload.ps1 ...`). The version defaults to
today's date (`yyyy.MM.dd`); pass `-Version` to choose one.

What it does:

- copies both apps without their `logs` / `OnePayTerminalConnectorLogs` folders
- resets the Wrapper config: Prod URL, empty Terminal ID / Static QR ID / COM port, debug port 0, old comments removed
- writes `environments.json` (Dev URL), `manifest.json` (SHA-256 of every file), the zip and `SHA256SUMS`

## Publish

```sh
gh release create 2026.10.29 --repo JarnKet/expressway-kiosk-payload \
    --title "Payload 2026.10.29" --notes "What changed" \
    out/expressway-payload-2026.10.29.zip out/SHA256SUMS
```

Kiosks pick it up the next time someone runs `Install.cmd` (the latest release wins; `-PayloadVersion <tag>` pins one).
Each kiosk's own settings are kept in `C:\Expressway\kiosk.json` and re-applied after the files are replaced.

## Offline (USB)

Copy the zip next to the kit and run `Install.cmd -PayloadPath D:\expressway-payload-2026.10.29.zip`.
The Microsoft runtimes and the Prolific driver are still downloaded, so the kiosk needs internet for now.
