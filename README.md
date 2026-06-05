# GameSave Guardian

Chinese documentation: [README.zh-CN.md](README.zh-CN.md)

GameSave Guardian is a portable Windows tool for backing up Xbox game saves, optionally recovering focus for a selected window, running AFK key loops, launching car automation workflows, and running an independent Ultimate workflow.

The default save folder is `C:\XboxGames\GameSave\pgs`. Backups are written to the `backups` folder next to the program files, so the tool stays portable after you move it.

## Quick Start

1. Download and unzip the release package.
2. Double-click `GameSaveGuardian.cmd`.
3. Use the Backup tab to start auto backup, stop auto backup, or create a backup immediately.
4. Use the Focus Lock tab to refresh visible windows, select one, and keep it focused.
5. Use the AFK tab to choose a mode and start or stop the game AFK key loop.
6. Use the Automation tab for AutoBuyCar, DeleteCar, or FindNewSubaru workflows.
7. Use the Ultimate tab for the share-code, OCR target-select, and 80-loop Sequence workflow.

Windows PowerShell 5.1 is enough. No Python, Node.js, .NET SDK, or installer is required.

## Advanced Script Entrypoints

- `BackupNow.cmd`: create one backup immediately.
- `StartBackup.cmd`: start the background save watcher.
- `StopBackup.cmd`: stop the background save watcher.
- `StatusBackup.cmd`: print backup status.
- `StartAfk.cmd`: start the AFK key loop after a short countdown. Use `-Mode EnterEvery10s` for Enter-only mode or `-Mode MacroCombo` for the menu macro mode.
- `StopAfk.cmd`: stop AFK and release W.
- `StatusAfk.cmd`: print AFK status.
- `StartAutomation.cmd`: start `AutoBuyCar`, `DeleteCar`, or `FindNewSubaru`. Examples: `.\StartAutomation.ps1 -Mode AutoBuyCar -LoopCount 3`, `.\StartAutomation.ps1 -Mode DeleteCar -LoopCount 5`, `.\StartAutomation.ps1 -Mode FindNewSubaru -LoopCount 1`.
- `StopAutomation.cmd`: stop the current automation worker.
- `StatusAutomation.cmd`: print automation status and configured defaults.
- `StartUltimate.cmd`: start the independent Ultimate workflow.
- `StopUltimate.cmd`: stop Ultimate and release W.
- `StatusUltimate.cmd`: print Ultimate status and configured defaults.
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
  "maxBackups": 30,
  "afk": {
    "startupDelaySeconds": 5,
    "keyTapHoldMilliseconds": 50,
    "inputMethod": "SendKeys",
    "sequence": {
      "enterDelaySeconds": 55,
      "xDelayMilliseconds": 500,
      "loopDelaySeconds": 10
    },
    "enterEvery10s": {
      "delaySeconds": 10
    },
    "macroCombo": {
      "cycleDelaySeconds": 20,
      "steps": [
        { "key": "Esc", "waitMilliseconds": 2000 },
        { "key": "W", "waitMilliseconds": 500 },
        { "key": "Enter", "waitMilliseconds": 500 }
      ]
    }
  },
  "automation": {
    "startupDelaySeconds": 5,
    "keyTapHoldMilliseconds": 50,
    "inputMethod": "SendKeys",
    "autoBuyCar": {
      "loopCount": 1,
      "betweenLoopsMilliseconds": 1000,
      "steps": [
        { "key": "Space", "waitMilliseconds": 1000 },
        { "key": "Down", "waitMilliseconds": 500 },
        { "key": "Enter", "waitMilliseconds": 1000 },
        { "key": "Enter", "waitMilliseconds": 1000 },
        { "key": "Enter", "waitMilliseconds": 0 }
      ]
    },
    "deleteCar": {
      "loopCount": 1,
      "betweenLoopsMilliseconds": 1000,
      "steps": [
        { "key": "Enter", "waitMilliseconds": 500 },
        { "key": "S", "waitMilliseconds": 500 },
        { "key": "S", "waitMilliseconds": 500 },
        { "key": "S", "waitMilliseconds": 500 },
        { "key": "S", "waitMilliseconds": 500 },
        { "key": "Enter", "waitMilliseconds": 500 },
        { "key": "S", "waitMilliseconds": 500 },
        { "key": "Enter", "waitMilliseconds": 1000 },
        { "key": "S", "waitMilliseconds": 500 }
      ]
    },
    "findNewSubaru": {
      "loopCount": 1,
      "maxSearchAttempts": 50,
      "searchKey": "Left",
      "searchSettleMilliseconds": 500,
      "afterSelectDelayMilliseconds": 2000,
      "targetKeywords": ["1998", "斯巴鲁"],
      "newBadgeText": "全新",
      "requireTargetConfirmation": true
    }
  }
}
```

- `sourcePath`: save folder to back up.
- `backupRoot`: backup output folder. The default `backups` is resolved relative to the program folder.
- `debounceSeconds`: seconds to wait after the last save change before backing up.
- `maxBackups`: number of newest backups to keep. Use `0` to keep all backups.
- `afk.startupDelaySeconds`: countdown before keys start sending.
- `afk.keyTapHoldMilliseconds`: how long a key tap is held.
- `afk.inputMethod`: key sending backend for AFK. Default is `SendKeys`; alternatives are `SendInputScanCode` and `SendInputVirtualKey`.
- `afk.sequence.*`: timings for `Sequence` mode.
- `afk.enterEvery10s.delaySeconds`: interval for `EnterEvery10s` mode.
- `afk.macroCombo.cycleDelaySeconds`: seconds to wait between `MacroCombo` cycles. Use `0` for no extra wait.
- `afk.macroCombo.steps`: editable `MacroCombo` key steps. Each step sends one key, then waits `waitMilliseconds`.
- `automation.startupDelaySeconds`: countdown before automation captures the foreground game window.
- `automation.inputMethod`: key sending backend for Automation. Default is `SendKeys`; alternatives are `SendInputScanCode` and `SendInputVirtualKey`.
- `automation.autoBuyCar.*`: loop count and key steps for the car-buying sequence.
- `automation.deleteCar.*`: loop count, between-loops wait, and editable key steps for the delete-car key sequence (an AFK-style keyboard macro run for the chosen number of loops).
- `automation.findNewSubaru.*`: loop count, search key, max attempts, badge/text recognition settings, and target keywords.
- `automation.findNewSubaru.afterSelectDelayMilliseconds`: wait time after selecting the matched Subaru before running `MacroCombo`.
- `ultimate.*`: startup delay, share code, strict OCR target keywords, search behavior, post-select waits, and independent 80-loop Sequence timings.

Logs are written to `logs\backup.log`, `logs\focus-lock.log`, `logs\afk.log`, `logs\automation.log`, and `logs\ultimate.log`. Runtime state is stored in `runtime\`.

## Game AFK

The AFK feature sends keys to the current foreground window. Before starting it, switch to the game window during the 5-second countdown.

AFK defaults to `SendKeys`, matching the original simple PowerShell script more closely. If a game or menu does not respond, try changing `afk.inputMethod` in `config.json` to `SendInputScanCode` or `SendInputVirtualKey`, then stop and start AFK again.

Modes:

- `Sequence`: `Enter`, wait 55 seconds, `x`, wait 0.5 seconds, `x`, wait 0.5 seconds, `Enter`, wait 10 seconds.
- `EnterEvery10s`: press `Enter` every 10 seconds.
- `MacroCombo`: run the configured menu macro steps using keys such as `Enter`, `Esc`, `S`, `D`, `W`, and `A`, then wait `afk.macroCombo.cycleDelaySeconds` before the next cycle.
- `StopAfk.cmd` and the GUI Stop button also send a `W` key-up as a safety fallback for older runs.

Important: AFK does not prevent games from pausing when they lose focus. If you click another app, keys may be sent to that app.

## Automation

Automation is independent from Backup, Focus Lock, and AFK. It sends keys only to the foreground window after the startup countdown, so switch to the game before the countdown ends. Automation and AFK cannot run at the same time.

Modes:

- `AutoBuyCar`: repeats the configured buy-car sequence. The default loop is `Space`, wait 1 second, `Down`, wait 0.5 seconds, `Enter`, wait 1 second, `Enter`, wait 1 second, `Enter`, then wait 1 second before the next loop.
- `DeleteCar`: an AFK-style keyboard sequence repeated for the configured loop count. The default loop is `Enter`, wait 0.5 seconds, `S` four times (0.5 seconds each), `Enter`, wait 0.5 seconds, `S`, wait 0.5 seconds, `Enter`, wait 1 second, `S`, wait 0.5 seconds, then wait 1 second before the next loop. Edit the keys and waits under `automation.deleteCar` in `config.json`.
- `FindNewSubaru`: presses `Left` up to `maxSearchAttempts` times, detects the green highlighted card, checks for the yellow `全新` badge, uses Windows OCR to confirm `1998` and `斯巴鲁`, presses `Enter`, waits `afterSelectDelayMilliseconds`, then runs the configured AFK `MacroCombo` once.

If OCR sees a new non-target car or cannot read the card text, the workflow logs the reason and continues searching. It accepts exact `1998` + `斯巴鲁` matches, plus fuzzy OCR text containing `1998`, `斯`, and `巴`. It stops only after finding the target or reaching `maxSearchAttempts`.

## Ultimate

Ultimate is independent from Backup, Focus Lock, AFK, and Automation. It sends a fixed setup macro, enters share code `705399298`, searches for the OCR target `1998 + 斯巴 + S1 + 790` (the 1998 Subaru S1 790; it matches `斯巴` rather than the full `斯巴鲁` because Windows OCR often misreads `鲁` as `兽`/`口`, while `斯`/`巴` read reliably and `1998 + S1 + 790` keep the target unambiguous), selects it, waits, then runs its own configured Sequence 80 times.

Ultimate uses the current foreground window after the startup countdown. AFK and Automation cannot run at the same time as Ultimate. Focus Lock is not blocked, but it may interfere with normal focus behavior.

## Release Packaging

Build a portable zip:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\BuildRelease.ps1 -Version 1.5.0
```

The package is written to `dist\gamesave-guardian-v1.5.0.zip`. It includes the GUI, scripts, config, and docs, and excludes backups, logs, runtime files, `.git`, and old zip files.
