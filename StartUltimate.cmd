@echo off
setlocal
echo Ultimate sends keys to the current foreground window.
echo After start, switch to the game window before the countdown ends.
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0StartUltimate.ps1" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
pause
exit /b %EXITCODE%
