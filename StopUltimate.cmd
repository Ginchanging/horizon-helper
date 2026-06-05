@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0StopUltimate.ps1" %*
pause
