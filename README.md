# GameSave Guardian

Chinese documentation: [README.zh-CN.md](README.zh-CN.md)

GameSave Guardian is a portable Windows tool for backing up Xbox game saves, running car/key automation workflows, and running an independent Ultimate workflow.

The default save folder is `C:\XboxGames\GameSave\pgs`. Backups are written to the `backups` folder next to the program files, so the tool stays portable after you move it.

## Quick Start

1. Download and unzip the release package.
2. Double-click `GameSaveGuardian.cmd`.
3. Pick a page in the left sidebar. A green dot next to a page name means that subsystem is currently running.
4. Use the Backup page to start auto backup, stop auto backup, or create a backup immediately.
5. Use the Automation page to pick a mode (AutoBuyCar, DeleteCar, FindNewSubaru, Sequence, EnterEvery10s, MacroCombo), set a loop count or tick **Forever**, and start/stop it.
6. Use the Ultimate page for the share-code, OCR target-select, and Sequence workflow. It refreshes itself every 2 seconds while running: a progress bar shows the current workflow loop and ETA, `PAUSED` is shown in red, it also shows which iteration of the current inner phase (Sequence / AutoBuyCar / FindNewSubaru) is running with a per-phase progress bar, and the log preview colours ERROR/WARN lines (with a keyword filter and an auto-scroll toggle).

Windows PowerShell 5.1 is enough. No Python, Node.js, .NET SDK, or installer is required.

## Advanced Script Entrypoints

- `BackupNow.cmd`: create one backup immediately.
- `StartBackup.cmd`: start the background save watcher.
- `StopBackup.cmd`: stop the background save watcher.
- `StatusBackup.cmd`: print backup status.
- `StartAutomation.cmd`: start a mode: `AutoBuyCar`, `DeleteCar`, `FindNewSubaru`, `Sequence`, `EnterEvery10s`, or `MacroCombo`. `-LoopCount 0` means Forever (loop until stopped). Examples: `.\StartAutomation.ps1 -Mode AutoBuyCar -LoopCount 3`, `.\StartAutomation.ps1 -Mode MacroCombo -LoopCount 0`, `.\StartAutomation.ps1 -Mode Sequence -LoopCount 0`.
- `StopAutomation.cmd`: stop the current automation worker and release W.
- `StatusAutomation.cmd`: print automation status and configured defaults.
- `StartUltimate.cmd`: start the independent Ultimate workflow.
- `StopUltimate.cmd`: stop Ultimate and release W.
- `StatusUltimate.cmd`: print Ultimate status and configured defaults.

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
    "inputMethod": "SendInputScanCode",
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
    "inputMethod": "SendInputScanCode",
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
- `automation.startupDelaySeconds`: countdown before automation captures the foreground game window.
- `automation.keyTapHoldMilliseconds`: how long a key tap is held.
- `automation.inputMethod`: key sending backend for Automation. Default is `SendKeys` — **the only backend Forza Horizon actually accepts**; the game ignores raw `SendInput` injection (`SendInputScanCode` / `SendInputVirtualKey` produce no input in-game), so only change this for other games.
- `automation.autoBuyCar.*`: loop count and key steps for the car-buying sequence.
- `automation.deleteCar.*`: loop count, between-loops wait, and editable key steps for the delete-car key sequence (a keyboard macro run for the chosen number of loops).
- `automation.findNewSubaru.*`: loop count, search key, max attempts, badge/text recognition settings, and target keywords.
- `automation.findNewSubaru.afterSelectDelayMilliseconds`: wait time after selecting the matched Subaru before running `MacroCombo`.
- `automation.sequence.*`: timings for the `Sequence` mode (`Enter`, drive wait, `x`, `x`, `Enter`, loop wait).
- `automation.enterEvery10s.delaySeconds`: interval for the `EnterEvery10s` mode.
- `automation.macroCombo.cycleDelaySeconds`: seconds to wait between `MacroCombo` cycles. Use `0` for no extra wait.
- `automation.macroCombo.steps`: editable `MacroCombo` key steps. Each step sends one key, then waits `waitMilliseconds`. Also used as the FindNewSubaru post-select buy macro.
- `ultimate.*`: startup delay, share code, strict OCR target keywords, search behavior, post-select waits, and independent Sequence timings/stuck-recovery.

Logs are written to `logs\backup.log`, `logs\automation.log`, and `logs\ultimate.log`. Runtime state is stored in `runtime\`.

## Automation

Automation sends keys only to the foreground window after the startup countdown, so switch to the game before the countdown ends. It is independent from Backup, but **Automation and Ultimate cannot run at the same time** (both send to the foreground). Pick a mode, set a **Loop count**, or tick **Forever** to loop until you press Stop. The Stop button also sends a `W` key-up as a safety fallback.

`Automation` (and `Ultimate`) default to `SendKeys`. **Forza Horizon ignores keys injected via raw `SendInput`** (`SendInputScanCode` / `SendInputVirtualKey` are not detected by the game at all — verified 2026-06-10), so do not switch the backend for Forza. `SendKeys` can very occasionally drop or double a key (which can shift a menu cursor); Ultimate recovers from that automatically (see ULTIMATE.md "脱格自愈").

Modes:

- `AutoBuyCar`: repeats the configured buy-car sequence. The default loop is `Space`, wait 1 second, `Down`, wait 0.5 seconds, `Enter`, wait 1 second, `Enter`, wait 1 second, `Enter`, then wait 1 second before the next loop.
- `DeleteCar`: a keyboard sequence repeated for the configured loop count. The default loop is `Enter`, wait 0.5 seconds, `S` four times (0.5 seconds each), `Enter`, wait 0.5 seconds, `S`, wait 0.5 seconds, `Enter`, wait 1 second, `S`, wait 0.5 seconds, then wait 1 second before the next loop. Edit the keys and waits under `automation.deleteCar` in `config.json`.
- `FindNewSubaru`: presses `Left` up to `maxSearchAttempts` times, detects the green highlighted card, checks for the yellow `全新` badge, uses Windows OCR to confirm `1998` and `斯巴鲁`, presses `Enter`, waits `afterSelectDelayMilliseconds`, then runs the configured `MacroCombo` buy macro once.
- `Sequence` (former AFK): one cycle is `Enter`, wait `automation.sequence.enterDelaySeconds`, `x`, wait, `x`, wait, `Enter`, wait `loopDelaySeconds`.
- `EnterEvery10s` (former AFK): press `Enter` every `automation.enterEvery10s.delaySeconds` seconds.
- `MacroCombo` (former AFK): run the configured menu macro steps (`Enter`/`Esc`/`S`/`D`/`W`/`A`), then wait `automation.macroCombo.cycleDelaySeconds` before the next cycle.

For the three former-AFK key loops, tick **Forever** (or pass `-LoopCount 0`) to reproduce the old "run until Stop" behavior.

If OCR sees a new non-target car or cannot read the card text, the workflow logs the reason and continues searching. It accepts exact `1998` + `斯巴鲁` matches, plus fuzzy OCR text containing `1998`, `斯`, and `巴`. It stops only after finding the target or reaching `maxSearchAttempts`.

## Ultimate

Ultimate is independent from Backup (but cannot run at the same time as Automation). It sends a fixed setup macro, enters share code `705399298`, searches for the OCR target `1998 + 斯巴 + S1 + 790` (the 1998 Subaru S1 790; it matches `斯巴` rather than the full `斯巴鲁` because Windows OCR often misreads `鲁` as `兽`/`口`, while `斯`/`巴` read reliably and `1998 + S1 + 790` keep the target unambiguous), selects it, waits, then runs its own configured Sequence 80 times.

During each Sequence loop's 40-second wait, Ultimate holds a virtual gamepad's right trigger (throttle) so the car keeps driving forward — Forza ignores injected keyboard while driving, so a held `W` key does not work.

If the car gets stuck and never finishes, the two `X` presses won't open the "重新开始赛事" restart dialog and the loop would stall. Ultimate guards against this: after the two `X` it OCR-checks for that dialog, and if it's missing it releases the throttle, runs a small recovery macro to re-enter the race, keeps the laps already completed, retries the current lap, and raises the lap total by 2. After too many consecutive recoveries it soft-fails the Sequence phase so the outer loop can re-home instead of hanging. Tune or disable via `ultimate.sequenceStuckRecovery` in `config.json`; see "卡死兜底" in `ULTIMATE.md`.

**Pause / Resume:** the `Ultimate` tab has a `Pause / Resume` toggle. Clicking `Pause` halts at the next *safe boundary* (the end of the current race or loop — not instantly), releases the keys, and shows `PAUSED`, so you can alt-tab and use the PC; clicking `Resume` continues from where it stopped after a short countdown (switch back to the game first). Ultimate only; see "暂停 / 继续" in `ULTIMATE.md`.

> **Gamepad throttle dependency (Ultimate only):** the throttle above needs the **ViGEmBus driver** (<https://github.com/nefarius/ViGEmBus/releases>; a modern signed driver, compatible with Windows 11 Memory Integrity, usually no reboot). The bundled `Nefarius.ViGEm.Client.dll` is already in the package. To disable it, set `ultimate.gamepadThrottle.enabled` to `false` in `config.json` and step 10 falls back to a plain wait. See "虚拟手柄油门" in `ULTIMATE.md`.

Ultimate uses the current foreground window after the startup countdown. Automation cannot run at the same time as Ultimate. Backup runs independently.

## Release Packaging

Build a portable zip:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\BuildRelease.ps1 -Version 1.5.0
```

The package is written to `dist\gamesave-guardian-v1.5.0.zip`. It includes the GUI, scripts, config, and docs, and excludes backups, logs, runtime files, `.git`, and old zip files.
