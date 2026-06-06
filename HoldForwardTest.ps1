[CmdletBinding()]
param(
    [int]$HoldSeconds = 5,
    [int]$CountdownSeconds = 5,
    [ValidateRange(0, 255)]   [int]$RightTrigger = 255,    # throttle / "accelerate" (= holding W on keyboard)
    [ValidateRange(-32768, 32767)] [int]$LeftStickY = 0,   # optional: push left stick up (forward) too; 0 = off
    [int]$ResubmitMilliseconds = 1000, # re-push the same report on this cadence (ViGEm holds state; this is just liveness/robustness)
    [string]$DllPath,
    [switch]$DryRun
)

# Standalone test for the ViGEm route: spin up a virtual Xbox 360 controller and HOLD the throttle
# (right trigger) for N seconds, so a driving game (Forza Horizon) drives forward continuously. Forza
# reads XInput natively, so this is far more reliable than injecting keyboard. NOT wired into
# Ultimate/AFK yet -- it is a probe to confirm the car moves. If it works, the same calls get folded
# into AfkLib as a new "ViGEmGamepad" input path.
#
# Requires: the ViGEmBus driver installed once (https://github.com/nefarius/ViGEmBus/releases -- modern
# signed driver, installs with Memory Integrity ON, usually no reboot), and Nefarius.ViGEm.Client.dll
# next to this script (already placed at repo root). See HoldForwardTest.cmd.

$ErrorActionPreference = 'Stop'
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }

$sliderType = 'Nefarius.ViGEm.Client.Targets.Xbox360.Xbox360Slider'
$axisType   = 'Nefarius.ViGEm.Client.Targets.Xbox360.Xbox360Axis'

Write-Host "=== ViGEm Hold-Forward Test ===" -ForegroundColor Cyan
$stickLabel = if ($LeftStickY -ne 0) { "$LeftStickY" } else { 'off' }
Write-Host ("RightTrigger(throttle)={0}/255  LeftStickY={1}  Hold={2}s  Countdown={3}s  Resubmit={4}ms  DryRun={5}" -f `
    $RightTrigger, $stickLabel, $HoldSeconds, $CountdownSeconds, $ResubmitMilliseconds, [bool]$DryRun)

# --- locate the ViGEm client DLL ---------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($DllPath)) {
    $candidates = @(
        (Join-Path $scriptRoot 'Nefarius.ViGEm.Client.dll'),
        (Join-Path $scriptRoot 'lib\Nefarius.ViGEm.Client.dll')
    )
    $DllPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($DllPath) -or -not (Test-Path $DllPath)) {
    Write-Error @"
Nefarius.ViGEm.Client.dll not found next to this script.
Expected: $scriptRoot\Nefarius.ViGEm.Client.dll
(get it from NuGet 'Nefarius.ViGEm.Client', or pass -DllPath <path>)
"@
    exit 1
}
$DllPath = (Resolve-Path $DllPath).Path
try { Unblock-File -Path $DllPath -ErrorAction SilentlyContinue } catch { }
Write-Host "DLL: $DllPath"

if ($DryRun) {
    Write-Host ''
    Write-Host "[DryRun] Would load $DllPath"
    Write-Host "[DryRun] Would plug in a virtual Xbox 360 controller (Connect)"
    Write-Host ("[DryRun] Would hold RightTrigger={0}/255{1} for {2}s, re-submitting every {3}ms" -f `
        $RightTrigger, $(if ($LeftStickY -ne 0) { " + LeftStickY=$LeftStickY" } else { '' }), $HoldSeconds, $ResubmitMilliseconds)
    Write-Host "[DryRun] Would zero the report and unplug the controller"
    Write-Host "[DryRun] No driver call made."
    return
}

[void][Reflection.Assembly]::LoadFrom($DllPath)

# --- create client + virtual controller --------------------------------------------------------------
$client = $null
try {
    $client = New-Object Nefarius.ViGEm.Client.ViGEmClient
}
catch {
    $ex = $_.Exception; if ($ex.InnerException) { $ex = $ex.InnerException }
    if ($ex.GetType().Name -eq 'VigemBusNotFoundException') {
        Write-Error @"
ViGEmBus driver is not installed.
1. Download: https://github.com/nefarius/ViGEmBus/releases  (ViGEmBus_Setup_x64.msi / .exe)
2. Run the installer (admin). It installs with Memory Integrity ON; usually no reboot needed.
3. Re-run this test.
"@
        exit 1
    }
    throw
}

$pad = $client.CreateXbox360Controller()
$rt = [type]$sliderType
$ax = [type]$axisType

try {
    $pad.Connect()
    Write-Host "Virtual Xbox 360 controller plugged in." -ForegroundColor Green

    Write-Host ''
    Write-Host "Switch to the GAME window now." -ForegroundColor Yellow
    for ($i = $CountdownSeconds; $i -gt 0; $i--) {
        Write-Host ("  throttle in {0}..." -f $i)
        Start-Sleep -Seconds 1
    }

    Write-Host ("HOLD throttle (RightTrigger={0}/255{1})" -f $RightTrigger, $(if ($LeftStickY -ne 0) { ", LeftThumbY=$LeftStickY" } else { '' })) -ForegroundColor Green
    $pad.SetSliderValue([Nefarius.ViGEm.Client.Targets.Xbox360.Xbox360Slider]::RightTrigger, [byte]$RightTrigger)
    if ($LeftStickY -ne 0) { $pad.SetAxisValue([Nefarius.ViGEm.Client.Targets.Xbox360.Xbox360Axis]::LeftThumbY, [short]$LeftStickY) }
    $pad.SubmitReport()

    $deadline = (Get-Date).AddSeconds($HoldSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds $ResubmitMilliseconds
        $pad.SubmitReport()  # ViGEm holds the last report; resubmit is just belt-and-suspenders + liveness
        Write-Host ("  ...still on throttle ({0:0.0}s left)" -f (($deadline - (Get-Date)).TotalSeconds))
    }
}
finally {
    Write-Host "RELEASE throttle + unplug controller" -ForegroundColor Green
    try {
        $pad.SetSliderValue([Nefarius.ViGEm.Client.Targets.Xbox360.Xbox360Slider]::RightTrigger, [byte]0)
        $pad.SetAxisValue([Nefarius.ViGEm.Client.Targets.Xbox360.Xbox360Axis]::LeftThumbY, [short]0)
        $pad.SubmitReport()
        $pad.Disconnect()
    } catch { }
    if ($client) { $client.Dispose() }
}

Write-Host ''
Write-Host "Done. Did the car drive forward the whole ${HoldSeconds}s? If yes, the ViGEm route works and I can fold it into Ultimate/AFK." -ForegroundColor Cyan
