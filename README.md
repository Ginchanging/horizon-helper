# GameSave Guardian

Chinese documentation(中文说明文档): [README.zh-CN.md](README.zh-CN.md)

GameSave Guardian is a portable Windows tool for backing up Xbox game saves and optionally keeping a selected window focused.

The default save folder is `C:\XboxGames\GameSave\pgs`. Backups are written to the `backups` folder next to the program files, so the tool stays portable after you move it.

## Quick Start

1. Download and unzip the release package.
2. Double-click `GameSaveGuardian.cmd`.
3. Use the Backup tab to start auto backup, stop auto backup, or create a backup immediately.
4. Use the Focus Lock tab to refresh visible windows, select one, and keep it focused.

Windows PowerShell 5.1 is enough. No Python, Node.js, .NET SDK, or installer is required.

## Advanced Script Entrypoints

- `BackupNow.cmd`: create one backup immediately.
- `StartBackup.cmd`: start the background save watcher.
- `StopBackup.cmd`: stop the background save watcher.
- `StatusBackup.cmd`: print backup status.
- `StartFocusLock.cmd`: choose a visible window and keep it focused.
- `StopFocusLock.cmd`: stop forcing focus.
- `StatusFocusLock.cmd`: print focus lock status.

## Configuration

Edit `config.json`:

```json
{
  "sourcePath": "C:\\XboxGames\\GameSave\\pgs",
  "backupRoot": "backups",
  "debounceSeconds": 30,
  "maxBackups": 30
}
```

- `sourcePath`: save folder to back up.
- `backupRoot`: backup output folder. The default `backups` is resolved relative to the program folder.
- `debounceSeconds`: seconds to wait after the last save change before backing up.
- `maxBackups`: number of newest backups to keep. Use `0` to keep all backups.

Logs are written to `logs\backup.log` and `logs\focus-lock.log`. Runtime state is stored in `runtime\`.

## Release Packaging

Build a portable zip:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\BuildRelease.ps1 -Version 1.1.0
```

The package is written to `dist\gamesave-guardian-v1.1.0.zip`. It includes the GUI, scripts, config, and docs, and excludes backups, logs, runtime files, `.git`, and old zip files.
