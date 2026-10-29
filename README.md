# Expressway Kiosk Setup

ສະຄຣິບຕິດຕັ້ງ ແລະ ຕັ້ງຄ່າເຄື່ອງ Kiosk ຂອງລະບົບຈ່າຍເງິນທາງດ່ວນ (BCEL Expressway) ໃນ Windows 10/11 ໂດຍບໍ່ຕ້ອງ Clone OS.
Scripts that install and configure BCEL Expressway payment kiosks on Windows 10/11, without cloning disk images.

> ພາສາອັງກິດຢູ່ລຸ່ມ / [English below](#english)

---

## ພາສາລາວ

### ສະຄຣິບນີ້ຕິດຕັ້ງຫຍັງແດ່

| ສ່ວນ | ໃຊ້ເຮັດຫຍັງ | ມາຈາກໃສ |
|---|---|---|
| **Window Wrapper** (BCELOnePayTerminal) | ໂປຣແກຣມຫຼັກ: ເປີດໜ້າຈໍຈ່າຍເງິນ (UI) ແລະ ລົມກັບລະບົບດ່ານຜ່ານ COM port | Payload ສ່ວນຕົວ (private) |
| **Connector** (OnePayTerminalConnectorGUI) | ເຄື່ອງມືທົດສອບການເຊື່ອມຕໍ່ກັບ OnePay terminal | Payload ສ່ວນຕົວ |
| ໄຟລ໌ 3 ໂຕ `msvcp140d.dll`, `vcruntime140d.dll`, `ucrtbased.dll` | Connector ຕ້ອງໃຊ້ (DLL ຂອງມັນເປັນ Debug build) | Payload ສ່ວນຕົວ, ວາງໄວ້ຂ້າງ Connector ເທົ່ານັ້ນ |
| .NET Desktop Runtime 7.0.20 (x86) | Connector ຕ້ອງໃຊ້ | Microsoft (ກວດ SHA-512 + ລາຍເຊັນ) |
| Visual C++ 2015-2022 (x86) | Wrapper (CefSharp) ຕ້ອງໃຊ້ | Microsoft (ກວດລາຍເຊັນ) |
| .NET Framework 4.6.2 ຂຶ້ນໄປ | Wrapper ຕ້ອງໃຊ້ (Windows 10 1607+ ມີແລ້ວ) | ຕິດຕັ້ງ 4.8 ສະເພາະເຄື່ອງທີ່ບໍ່ມີ |
| Prolific PL2303 driver | ສາຍ USB-to-Serial | Microsoft Update Catalog (Win10: 3.8.43.0, Win11: 3.9.7.2) |

ນອກຈາກນັ້ນ ຍັງຕັ້ງຄ່າເຄື່ອງໃຫ້ເປັນ Kiosk ດ້ວຍ: ເປີດ Wrapper ອັດຕະໂນມັດຕອນ Login (ຖ້າມັນປິດ ຈະເປີດຄືນເອງ),
ບໍ່ໃຫ້ Sleep ແລະ ບໍ່ປິດໜ້າຈໍ, ບໍ່ໃຫ້ USB serial ເຂົ້າໂໝດປະຫຍັດໄຟ, ບໍ່ໃຫ້ Windows Update Restart ເອງ ຕອນມີຄົນ Login ຢູ່,
ຕັ້ງເຂດເວລາເປັນ (UTC+07:00) Bangkok, Hanoi, Jakarta ແລະ ເປີດສຽງລຳໂພງ 80% (ສຽງແຈ້ງຈ່າຍເງິນສຳເລັດ).

### ກ່ອນເລີ່ມ

- Windows 10 ເວີຊັນ 1607 ຂຶ້ນໄປ ຫຼື Windows 11, ມີອິນເຕີເນັດ, ມີ account ທີ່ເປັນ Administrator
- **GitHub token** ສຳລັບດາວໂຫຼດ payload (ສ້າງເທື່ອດຽວ ໃຊ້ໄດ້ທຸກເຄື່ອງ):
  1. GitHub → Settings → Developer settings → Personal access tokens → **Fine-grained tokens** → Generate new token
  2. Repository access: **Only select repositories** → `expressway-kiosk-payload`
  3. Permissions → Repository permissions → **Contents: Read-only** (ບໍ່ຕ້ອງເລືອກອັນອື່ນ)
  4. ຕັ້ງວັນໝົດອາຍຸ, ກົດ Generate ແລ້ວເກັບ token ໄວ້ບ່ອນປອດໄພ. ສະຄຣິບບໍ່ບັນທຶກ token ລົງເຄື່ອງ.

### ຕິດຕັ້ງເຄື່ອງໃໝ່

1. ໜ້ານີ້ → ປຸ່ມ **Code** → **Download ZIP**
2. ຄລິກຂວາທີ່ໄຟລ໌ zip → Properties → ໝາຍ **Unblock** → OK, ແລ້ວ Extract
3. ດັບເບິ້ນຄລິກ **`Install.cmd`** → ກົດ Yes ເມື່ອ Windows ຖາມສິດ Administrator
4. ວາງ GitHub token ເມື່ອຖືກຖາມ (ຕົວໜັງສືຈະບໍ່ສະແດງ)
5. ລໍຖ້າ 5-15 ນາທີ ຈົນມັນຖາມຄ່າຂອງເຄື່ອງ (ເບິ່ງຫົວຂໍ້ຕໍ່ໄປ)
6. ດັບເບິ້ນຄລິກ **Expressway Check** ເທິງ Desktop: ທຸກແຖວຄວນເປັນ PASS
7. ເອົາຂໍ້ມູນທີ່ສະຄຣິບສະແດງ (Terminal ID, Static QR ID, COM port, IP) ໄປລົງທະບຽນໃນ Tollway Kiosk Monitor

ຖ້າສະຄຣິບບອກໃຫ້ Restart ກໍ Restart ເຄື່ອງ ແລ້ວ Wrapper ຈະເປີດເອງຕອນ Login.

### ຕັ້ງຄ່າຂອງແຕ່ລະເຄື່ອງ (Expressway Settings / `Configure.cmd`)

| ຊ່ອງ | ຄວາມໝາຍ |
|---|---|
| Terminal ID | ລະຫັດເຄື່ອງ (ຝັງໃນ QR, ທະນາຄານໃຊ້ອ້າງອີງ) |
| Static QR ID | ລະຫັດປ້າຍ QR ທີ່ຕິດຢູ່ດ່ານ (ຕ້ອງມີ ຖ້າບໍ່ດັ່ງນັ້ນ UI ບໍ່ໃຊ້) |
| COM port | Port ທີ່ສາຍຕໍ່ຢູ່. ສະຄຣິບລາຍຊື່ port ໃຫ້ ແລະ ໝາຍໂຕ Prolific ໄວ້ |
| Environment | `Prod` = https://expressway.bcel.one/, `Dev` = ເຊີບເວີທົດສອບ, `Custom` = ໃສ່ URL ເອງ |
| Keep window on top | ໃຫ້ Wrapper ຢູ່ໜ້າສຸດສະເໝີ |
| Log server URL | ປ່ອຍວ່າງໄດ້ |

- ກົດ Enter = ໃຊ້ຄ່າໃນ [ວົງເລັບ], ພິມ `-` = ລຶບຄ່ານັ້ນ
- ໃນ Prod, CefSharp remote debugging ຖືກປິດ (port 0). Dev ເປີດໄວ້ທີ່ 9999
- ຄ່າຖືກບັນທຶກໃນ `C:\Expressway\kiosk.json`. ຕິດຕັ້ງຄືນ ຫຼື ອັບເດດ ຄ່າຍັງຢູ່
- ຕັ້ງຫຼາຍເຄື່ອງ: ສ້າງໄຟລ໌ JSON ຕໍ່ເຄື່ອງ ຕາມ [`config/kiosk.example.json`](config/kiosk.example.json) ແລ້ວ:
  `Install.cmd -ConfigFile D:\kiosks\T01.json`

### ໃຊ້ງານປະຈຳວັນ

| ສິ່ງທີ່ຢາກເຮັດ | ວິທີ |
|---|---|
| ກວດສຸຂະພາບເຄື່ອງ | **Expressway Check** (ບໍ່ປ່ຽນຫຍັງ, ບັນທຶກລາຍງານໃນ `C:\Expressway\logs`) |
| ປິດ Wrapper ເພື່ອສ້ອມແປງ | Start menu → Expressway → **Stop Kiosk (maintenance)** |
| ເປີດຄືນ | **Start Kiosk** |
| ທົດສອບ terminal | **OnePay Connector (test)**: ປິດ Kiosk ກ່ອນ ເພາະໃຊ້ COM port ດຽວກັນ |
| ອັບເດດໂປຣແກຣມ | ດາວໂຫຼດ repo ໃໝ່ ແລ້ວແລ່ນ `Install.cmd` ອີກເທື່ອ |
| ຖອດອອກ | `C:\Expressway\Uninstall.cmd` |

### ບັນຫາທີ່ພົບເລື້ອຍ

| ອາການ | ແກ້ໄຂ |
|---|---|
| Check: Prolific "error 10" | Chip ເກົ່າ/ປອມ (PL2303HXA) ທີ່ driver ໃໝ່ບໍ່ຮອງຮັບ: ປ່ຽນສາຍ ຫຼື ໃຊ້ driver ເກົ່າ |
| Check: COM port ບໍ່ມີ | ສຽບສາຍ, ເບິ່ງ port ໃນ Device Manager, ແລ້ວແລ່ນ Expressway Settings ໃໝ່ |
| Check: UI URL FAIL | ກວດອິນເຕີເນັດ ຫຼື Firewall |
| Wrapper ເປີດ-ປິດ ຊ້ຳໆ | ເບິ່ງ `C:\Expressway\logs\watchdog-*.log` ແລະ `C:\Expressway\Wrapper\logs` |
| ຕິດຕັ້ງລົ້ມເຫຼວ | ເບິ່ງ `C:\Expressway\logs\setup-*.log` |

---

## English

### What it installs

The table above, in short: the **Window Wrapper** (BCELOnePayTerminal, .NET Framework 4.6.2, x86, CefSharp) that shows the
payment UI and talks to the lane system over a COM port; the **Connector** test tool (OnePayTerminalConnectorGUI, .NET 7, x86)
with the three x86 debug CRT DLLs its Debug-built `OnePayTerminalConnector.dll` needs; .NET Desktop Runtime 7.0.20 x86;
Visual C++ 2015-2022 x86; .NET Framework 4.8 only when missing; and the Prolific PL2303 driver from the Microsoft Update Catalog.

Kiosk settings: auto-start at logon through a watchdog that restarts the Wrapper if it closes, no sleep or screen-off,
USB selective suspend off, no Windows Update restarts while someone is logged on (active hours 06-23), time zone
SE Asia Standard Time, speaker unmuted at 80 % so the payment sound plays.

### Install a kiosk

1. **Code → Download ZIP**, right-click the zip → Properties → **Unblock**, extract.
2. Double-click **`Install.cmd`** and accept the administrator prompt.
3. Paste the GitHub token (fine-grained, *Contents: Read-only* on `expressway-kiosk-payload` only). It is never saved.
4. Answer the kiosk questions, then run **Expressway Check** from the desktop: everything should be PASS.

Options: `-PayloadPath <zip or folder>` (local payload, no token), `-PayloadVersion <tag>`, `-ConfigFile <kiosk.json>`,
`-SkipDriver`, `-NoKioskSettings`, `-NoConfigure`. The installer is safe to run again; it keeps `C:\Expressway\kiosk.json`.

### Configure a kiosk

`Configure.cmd` asks for Terminal ID, Static QR ID, COM port (Prolific port marked), environment (`Prod`, `Dev`, `Custom`),
Topmost and log server URL, then writes `C:\Expressway\Wrapper\BCELOnePayTerminal.exe.config` (backup kept in
`C:\Expressway\state\config-backups`) and restarts the Wrapper. Non-interactive:

```bat
Configure.cmd -TerminalId T01 -StaticQrId itm0000 -ComPort COM3 -Environment Prod -NonInteractive
Configure.cmd -ConfigFile D:\kiosks\T01.json
```

`Prod` turns CefSharp remote debugging off (port 0); `Dev` keeps 9999; `-RemoteDebuggingPort` overrides either.

### Layout on the kiosk

```
C:\Expressway\
  Wrapper\  Connector\     apps (admins write; users can only write the log folders)
  scripts\  config\        copy of this kit, so Settings/Check work after the USB stick is gone
  kiosk.json               this kiosk's values
  payload.json             manifest of the installed payload
  logs\                    setup, watchdog and check logs
  state\                   maintenance flag, config backups
```

### Repository layout

| Path | Purpose |
|---|---|
| `Install.cmd`, `Configure.cmd`, `Check.cmd`, `Stop-Kiosk.cmd`, `Start-Kiosk.cmd`, `Uninstall.cmd` | Double-click launchers |
| `scripts/Install-Kiosk.ps1` | Prerequisites, payload, files, permissions, shortcuts, kiosk settings |
| `scripts/Configure-Kiosk.ps1` | Per-kiosk values in the Wrapper config |
| `scripts/Test-Kiosk.ps1` | Health check (PASS/WARN/FAIL) |
| `scripts/Run-Wrapper.ps1` | Watchdog started at logon |
| `scripts/Set-Maintenance.ps1`, `scripts/Uninstall-Kiosk.ps1` | Maintenance mode, removal |
| `scripts/Kiosk.Common.psm1` | Shared helpers |
| `config/*.json` | Download URLs and hashes, environments, install defaults, kiosk template |
| `tools/Build-Payload.ps1` | Builds the private payload zip ([docs/PAYLOAD.md](docs/PAYLOAD.md)) |
| `tests/` | Pester tests |

### What is not in this repository

No BCEL program files, no debug DLLs, no Terminal IDs or QR IDs, no Dev URL. Those live in the private
`expressway-kiosk-payload` release. Microsoft does not allow redistributing the debug CRT DLLs publicly.

### Known limitations

- `OnePayTerminalConnector.dll` is a Debug build. A Release build from its developer would remove the need for the debug DLLs.
- .NET 7 has been out of support since May 2024. The Connector enables `BinaryFormatter`, which .NET 9 removed, so moving
  to a supported runtime needs a rebuild of the Connector, not just a newer runtime.
- The Prolific packages cover `VID_067B&PID_2303/2304` (PL2303 HXD/EA/RA/SA). PL2303G-series adapters need Prolific's own installer.

### Tests

```sh
pwsh -c 'Invoke-Pester ./tests'
```

Covers config editing against a sample config, ClientSetting JSON, manifests, environments, the payload builder, and
`Configure-Kiosk.ps1` end to end. Windows-only steps (installers, drivers, scheduled task) are tested on a real kiosk.

## License

MIT
