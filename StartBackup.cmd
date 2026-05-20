@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0StartBackup.ps1" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
pause
exit /b %EXITCODE%
