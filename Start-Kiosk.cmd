@echo off
rem Expressway kiosk: maintenance mode off (starts the Wrapper again).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Set-Maintenance.ps1" -Off %*
