@echo off
rem Expressway kiosk: remove the apps, auto-start task and shortcuts (asks for admin rights).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Uninstall-Kiosk.ps1" %*
