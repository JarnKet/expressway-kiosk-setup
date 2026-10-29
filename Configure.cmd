@echo off
rem Expressway kiosk: set Terminal ID, static QR ID, COM port and environment (asks for admin rights).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Configure-Kiosk.ps1" %*
