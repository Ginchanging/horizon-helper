# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

GameSave Guardian is a **portable Windows PowerShell 5.1 application** — no compilation, no package manager, no SDK. It backs up Xbox game saves and automates keyboard input for Forza Horizon (AFK loops, car-buying menus, share-code car acquisition). The whole thing is WinForms + PowerShell + a few small C# P/Invoke blocks compiled at runtime via `Add-Type`. Everything must stay runnable by double-clicking a `.cmd` on a stock Windows box.

## Commands

```powershell
# Smoke test: loads config + computes state for all five subsystems, prints a summary, exits 0.
# This is the closest thing to a test suite — run it after touching any *Lib.ps1 or config.json.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\GameSaveGuardian.ps1 -SelfTest

# Launch the GUI (manual testing)
.\GameSaveGuardian.cmd

# Build a release zip -> dist\gamesave-guardian-v<Version>.zip
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\BuildRelease.ps1 -Version 1.5.0

# Dry-run a worker (logs every key step WITHOUT sending real input) — safe way to test input logic
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\scripts\RunAfk.ps1 -AppRoot . -Mode MacroCombo -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\scripts\RunUltimate.ps1 -AppRoot . -DryRun -AssumeTargetFound
```

There is no lint/unit-test framework. Verification = `-SelfTest`, `-DryRun` workers, and reading `logs\*.log`.

## Architecture

### Five independent subsystems, one shared shape

| Subsystem | Library (`scripts/`) | Background worker (`scripts/`) | PID / log |
|-----------|---------------------|-------------------------------|-----------|
| Backup    | `BackupLib.ps1`     | `WatchBackup.ps1`             | `watcher.pid` / `backup.log` |
| Focus Lock| `FocusLib.ps1`      | `KeepWindowFocused.ps1`       | `focus-lock.*` |
| AFK       | `AfkLib.ps1`        | `RunAfk.ps1`                  | `afk.pid` / `afk.log` |
| Automation| `AutomationLib.ps1` | `RunAutomation.ps1`           | `automation.pid` / `automation.log` |
| Ultimate  | `UltimateLib.ps1`   | `RunUltimate.ps1`             | `ultimate.pid` / `ultimate.log` |

Every subsystem repeats the **same function set** in its `*Lib.ps1` — learn it once and you know all five:

- `Get-<X>Paths -AppRoot` → pscustomobject of resolved `runtime/`, `logs/`, pid, log paths.
- `Initialize-<X>Workspace` → create runtime/logs dirs on demand.
- `Get-<X>Config -AppRoot` → read `config.json`, apply **hard-coded defaults for every field**, validate (throw on bad values). Config is an *overlay* on defaults, never the source of truth for defaults.
- `Resolve-<X>RuntimeOptions -Config [...overrides]` → merge config with CLI overrides (convention: `-1`/`''` means "not supplied, use config value").
- `Write-<X>Log`, `Set-<X>Pid`, `Remove-<X>Pid`, `Get-<X>State`, `Remove-Stale<X>Pid`.

### Process model: detached workers + PID-file state machine

Launchers never run the loop in-process. They `Start-Process powershell.exe -WindowStyle Hidden -PassThru` pointing at the worker script, then poll `Get-<X>State` up to ~10× for confirmation. Workers run an infinite loop until killed; `Stop*` finds the PID and `Stop-Process -Force`.

`Get-<X>State` is the heart of single-instance safety. It reads the pid file, confirms the process exists, then **verifies the process command line contains the worker script name** (e.g. `runafk.ps1`) via `Get-CimInstance Win32_Process`. Possible `Status` values you'll branch on everywhere: `Stopped`, `Running`, `RunningUnverified` (process alive but command line unreadable), `Stale` (pid file points at a dead process), `InvalidPid`, `PidConflict` (pid reused by an unrelated process). Treat `Running` and `RunningUnverified` together as "is running".

### Three entry layers (all thin wrappers over the libs)

1. **GUI** — `GameSaveGuardian.ps1` dot-sources all five libs, exposes one tab per subsystem, and wraps each operation in `Start-App<X>` / `Stop-App<X>` + `Invoke-AppSafely` (catches → MessageBox).
2. **CLI launchers** (repo root) — `Start<X>.ps1` / `Stop<X>.ps1` / `Status<X>.ps1`, each with a `.cmd` twin that just calls the `.ps1` with `-NoProfile -ExecutionPolicy Bypass [-STA]` and `pause`s.
3. **Workers** — the actual loops in `scripts/`.

The GUI's `Start-App*` and the corresponding `Start*.ps1` contain **near-duplicate launch logic** (build arg list → `Start-Process` → poll state). When you change how a worker is launched, update **both** the GUI function and the root launcher script.

### Input sending — all routed through AfkLib

`AfkLib.ps1` owns keyboard input for *every* subsystem (Automation and Ultimate dot-source it). Key facts:

- `Send-AfkNamedKeyTap` / `Send-AfkDigitKeyTap` dispatch over three `inputMethod`s: `SendKeys` (default, WinForms `SendWait`), `SendInputScanCode`, `SendInputVirtualKey` (both via the runtime-compiled `GameAfkNative` C# class doing `SendInput` P/Invoke). **Forza Horizon ignores the raw `SendInput` backends entirely** (no keys detected in-game — verified 2026-06-10; same mechanism as it ignoring injected keyboard while driving), so for this game `inputMethod` must stay `SendKeys`. Its rare dropped/doubled key is handled by FindNewSubaru's desync soft-fail recovery, not by switching backends.
- Input goes to the **current foreground window** after a startup countdown — there is no window targeting for key sends. Hence AFK / Automation / Ultimate are **mutually exclusive** (each checks the other two's state at startup and refuses to start). Backup and Focus Lock are independent and may run alongside anything.
- `Release-AfkKeys` (a `W` key-up) is fired on every stop/exit as a safety net against a stuck movement key.

### Computer vision (AutomationLib) — for the car-finding modes

`FindNewSubaru` (Automation) and Ultimate locate a specific car in the in-game grid by screen-scraping:

- `Initialize-AutomationNative` compiles `AutomationImageTools` (C#): flood-fill to find the green highlighted card rect, and yellow-pixel counting to detect the "新/全新" badge.
- `Invoke-AutomationOcrImagePath` uses the **WinRT `Windows.Media.Ocr`** engine (zh-Hans) to read card text and confirm keywords like `1998` + `斯巴鲁`. OCR matching is fuzzy-tolerant (see `Test-AutomationTargetTextMatch`).
- These paths require `-STA` (set in the launchers) and a real desktop session; they fail headless. Ultimate's `RunUltimate.ps1` adds full-grid traversal logic (press Left until the list loops back to the anchor card) documented inline.

## Conventions

- Each `*Lib.ps1` starts with `Set-StrictMode -Version 2.0`; each entry script sets `$ErrorActionPreference = 'Stop'`.
- The `$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {...}` idiom appears at the top of every script — keep it so scripts work whether dot-sourced or invoked directly.
- All paths resolve relative to app root so the tool stays portable; `runtime/`, `logs/`, `backups/`, `dist/` are gitignored and created on demand. Never hard-code absolute paths.
- Config/log I/O uses `-Encoding UTF8`; pid files use `-Encoding ASCII`. Config reads guard every field with `Test-*ConfigProperty` before access (StrictMode will throw otherwise).
- All runtime file writes (log, pid, progress, counters, pause/target flags) go through each lib's `Write-<X>FileWithRetry`, never bare `Set-Content`/`Add-Content`. PS 5.1 `Set-Content` needs the target momentarily free of *any* other open handle — a GUI poll or antivirus scan at the wrong instant throws (mostly `ArgumentException` "stream was not readable", sometimes `IOException` "in use by another process"; this killed a real Ultimate run 2026-06-10). The helper retries 5×60 ms with an untyped catch, then drops the write (log/progress/count) or throws only for `-ThrowOnFailure` callers (pid, pause, focus target).
- Functions return `[pscustomobject]`. Config presence is checked via `$obj.PSObject.Properties.Name -contains 'x'`, not `$obj.x -ne $null`.
- AFK/Automation/Ultimate workers must be launched `-STA` (SendKeys + WinForms + OCR need it); the Backup watcher does not.

## Gotchas

- **`BuildRelease.ps1` ships from an explicit allow-list** (`$rootFiles`, `$scriptFiles`) and throws if a listed file is missing. A new script you add will **not** be in the release zip until you add its name to that list.
- Adding a new subsystem means touching all three layers (lib + worker + Start/Stop/Status launchers + `.cmd` twins), wiring a GUI tab, adding a `config.json` section with defaults in `Get-<X>Config`, adding the mutual-exclusion checks, and extending `BuildRelease.ps1` and `-SelfTest`.
- `config.json` is read fresh on every operation, so edits take effect on the next Start without restarting the GUI.
- Docs are bilingual: keep `README.md` / `README.zh-CN.md` (and `BLOG.zh-CN.md`) in sync when behavior changes.
- `ULTIMATE.md` (repo root) is the source-of-truth doc for the Ultimate workflow's full execution flow — the three hard-coded macros (`Get-DefaultUltimate{Prelude,AfterCode,PostSequence}Steps`), timings, step order, search/recognition, and the AutoBuyCar tail. **Whenever you change any Ultimate execution step, update the matching section of `ULTIMATE.md` in the same change.**
- Screen-capture workers (`RunUltimate.ps1`, `RunAutomation.ps1`) call `SetProcessDPIAware()` at the very top, before any WinForms/GDI+ load. Setting it late on a scaled display (e.g. 125%) makes `CopyFromScreen` capture only the logical region into the top-left of the bitmap, truncating the bottom grid row (breaks row-3 car detection). Do **not** move this into `AfkLib.ps1` — the GUI also dot-sources it and would get its layout distorted.
