@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0StatusAutomation.ps1" %*
pause
