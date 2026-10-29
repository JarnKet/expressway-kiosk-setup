@echo off
rem Expressway kiosk: install apps, runtimes, driver and kiosk settings (asks for admin rights).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install-Kiosk.ps1" %*
