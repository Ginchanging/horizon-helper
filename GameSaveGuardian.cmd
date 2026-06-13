@echo off
rem Launch the GUI detached so this launcher's console host does not stay open behind the app for
rem the whole session. The GUI itself already runs hidden (-WindowStyle Hidden); `start` hands it
rem off and lets cmd exit immediately, so the console only flashes briefly instead of lingering.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0GameSaveGuardian.ps1" %*
