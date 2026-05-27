@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0StopAutomation.ps1" %*
pause
