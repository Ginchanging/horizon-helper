@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0StartAutomation.ps1" %*
pause
