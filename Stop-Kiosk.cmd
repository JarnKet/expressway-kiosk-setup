@echo off
rem Expressway kiosk: maintenance mode on (closes the Wrapper and keeps it closed).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Set-Maintenance.ps1" -On %*
