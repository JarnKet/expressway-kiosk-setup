@echo off
rem Expressway kiosk: health check. Changes nothing.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Test-Kiosk.ps1" %*
