[CmdletBinding()]
param(
    [string]$AppRoot,
    [int]$StartupDelaySeconds = -1,
    [int]$SequenceLoopCount = -1,
    [int]$AutoBuyCarLoopCount = -1,
    [int]$FindNewSubaruLoopCount = -1,
    [int]$StartFromStep = -1,
    [int]$WorkflowLoopCount = -1,
    [string]$RecognitionImagePath,
    [switch]$AssumeTargetFound,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Make this process DPI-aware BEFORE any WinForms/GDI+ code loads. On a scaled display
# (e.g. 125%), establishing awareness late lets Graphics.CopyFromScreen capture only the
# logical-resolution region into the top-left of the bitmap, leaving the bottom of the
# screen empty. That truncates the bottom row of the car grid, so a target car in row 3
# (its S1/790 badge) is never captured and never matches. This call must run before the
# AfkLib dot-source, because SendKeys/WinForms locks the process DPI context on first use.
$script:DpiAwareResult = $false
try {
    Add-Type -Namespace GsgDpi -Name Awareness -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetProcessDPIAware();
'@
    $script:DpiAwareResult = [GsgDpi.Awareness]::SetProcessDPIAware()
}
catch {
    $script:DpiAwareResult = $false
}

$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
. (Join-Path $scriptRoot 'AfkLib.ps1')
. (Join-Path $scriptRoot 'AutomationLib.ps1')
. (Join-Path $scriptRoot 'UltimateLib.ps1')

$paths = Get-UltimatePaths -AppRoot $AppRoot
Initialize-UltimateWorkspace -Paths $paths
$config = Get-UltimateConfig -AppRoot $paths.AppRoot
$options = Resolve-UltimateRuntimeOptions -Config $config -StartupDelaySeconds $StartupDelaySeconds -SequenceLoopCount $SequenceLoopCount -AutoBuyCarLoopCount $AutoBuyCarLoopCount -FindNewSubaruLoopCount $FindNewSubaruLoopCount -StartFromStep $StartFromStep -WorkflowLoopCount $WorkflowLoopCount
$automationConfig = Get-AutomationConfig -AppRoot $paths.AppRoot
$autoBuyCarOptions = Resolve-AutomationRuntimeOptions -Config $automationConfig -Mode 'AutoBuyCar' -LoopCount $options.AutoBuyCarLoopCount
$findNewSubaruOptions = Resolve-AutomationRuntimeOptions -Config $automationConfig -Mode 'FindNewSubaru' -LoopCount $options.FindNewSubaruLoopCount

# Outer-loop context carried into inner-phase progress writes. The inner loops (Sequence /
# AutoBuyCar / FindNewSubaru) report which iteration they are on, but the progress JSON also
# needs the current workflow loop + ETA text so the GUI's two-bar view stays consistent. These
# are set once at the top of each workflow loop (see the main loop below).
$script:UltimateLoopIteration = 0
$script:UltimateLoopTotal = 0
$script:UltimateLoopText = ''

function Set-UltimatePhaseProgress {
    # Write an inner-phase snapshot (Sequence/AutoBuyCar/FindNewSubaru + its iteration counter)
    # while preserving the outer workflow loop context. The GUI reads phase/phaseCurrent/phaseTotal
    # to show "第几次 <phase>" plus a per-phase progress bar.
    param(
        [Parameter(Mandatory = $true)][string]$Phase,
        [int]$Current = 0,
        [int]$Total = 0
    )

    Set-UltimateProgress -Paths $paths -Status 'running' `
        -CurrentLoop $script:UltimateLoopIteration -TotalLoops $script:UltimateLoopTotal `
        -DisplayText $script:UltimateLoopText `
        -Phase $Phase -PhaseCurrent $Current -PhaseTotal $Total `
        -Updated (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
}

function Wait-UltimateMilliseconds {
    param(
        [int]$Milliseconds
    )

    if ($Milliseconds -gt 0 -and -not $DryRun) {
        Start-Sleep -Milliseconds $Milliseconds
    }
}

function Wait-UltimateSeconds {
    param(
        [int]$Seconds
    )

    if ($Seconds -gt 0 -and -not $DryRun) {
        Start-Sleep -Seconds $Seconds
    }
}

function Wait-UltimatePauseGate {
    # Block here while the GUI's pause flag (runtime/ultimate.pause) is present, so the worker
    # halts at a SAFE boundary (between races / loops) rather than mid-keystroke -- pausing in the
    # middle of a menu macro would desync the game UI. Called at the top of the workflow loop,
    # each Sequence iteration, each AutoBuyCar loop, and each FindNewSubaru loop. No-op under
    # DryRun so dry-run tests never block.
    param(
        [string]$Context = ''
    )

    if ($DryRun) { return }
    if (-not (Test-UltimatePause -Paths $paths)) { return }

    # Entering pause: make the game state safe -- release any held movement key (W) and zero the
    # gamepad throttle so nothing is stuck forward while we sit idle.
    Release-AfkKeys -DryRun:$DryRun
    if ($options.GamepadThrottleEnabled) {
        try { Set-AfkGamepadRightTrigger -Value 0 } catch { }
    }
    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Paused by GUI. Context=$Context Waiting for Resume (delete runtime/ultimate.pause)."
    Set-UltimateProgress -Paths $paths -Status 'paused' -CurrentLoop 0 -TotalLoops 0 -DisplayText "Paused - $Context (press Resume)" -Updated (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

    while (Test-UltimatePause -Paths $paths) {
        Start-Sleep -Milliseconds 500
    }

    # Resumed: give the user a few seconds to switch back to the game window before keys fly again,
    # just like the initial startup countdown.
    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Resumed by GUI. Context=$Context Re-focus countdown $($options.StartupDelaySeconds)s before continuing."
    Set-UltimateProgress -Paths $paths -Status 'running' -CurrentLoop 0 -TotalLoops 0 -DisplayText "Resuming - $Context (switch to the game)" -Updated (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    Wait-UltimateSeconds -Seconds $options.StartupDelaySeconds
}

function Invoke-UltimateThrottleWait {
    # The Sequence loop presses Enter to start the in-race drive, then waits SequenceEnterDelaySeconds.
    # During that wait, hold the virtual-gamepad throttle (right trigger) so the car drives forward the
    # whole time, then release it before the menu keys. Falls back to a plain wait when the gamepad is
    # not active (DryRun, gamepad throttle disabled, or driver/DLL unavailable). The controller itself
    # is connected once at startup and kept plugged in for the whole run -- only the trigger value
    # changes here -- so the game never sees a disconnect between drives.
    param(
        [Parameter(Mandatory = $true)][int]$Seconds,
        [int]$LoopIndex = 0
    )

    if ($DryRun) {
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Throttle wait skipped (DryRun). Loop=$LoopIndex Seconds=$Seconds"
        return
    }
    if (-not (Test-AfkGamepadConnected)) {
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Gamepad throttle not active; plain wait. Loop=$LoopIndex Seconds=$Seconds"
        Wait-UltimateSeconds -Seconds $Seconds
        return
    }

    $triggerValue = $options.GamepadRightTriggerValue
    Set-AfkGamepadRightTrigger -Value $triggerValue
    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Throttle ON (RT=$triggerValue/255) for ${Seconds}s. Loop=$LoopIndex"
    try {
        $deadline = (Get-Date).AddSeconds($Seconds)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 1000
            # ViGEm holds the last report, but re-submitting each second guards against a game that
            # times out an idle controller, and keeps the input alive across the whole drive.
            Set-AfkGamepadRightTrigger -Value $triggerValue
        }
    }
    finally {
        Set-AfkGamepadRightTrigger -Value 0
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Throttle OFF. Loop=$LoopIndex"
    }
}

function Test-UltimateShouldRunStep {
    # Debug aid: when StartFromStep > N, top-level phase N is skipped so a later phase can be
    # tested in isolation. StartFromStep numbering matches the step table in ULTIMATE.md
    # (5=Prelude ... 14=FindNewSubaru). The infrastructure steps (0-4: DPI, mutual-exclusion,
    # foreground-window capture, startup countdown) are NOT gated here and always run.
    param(
        [Parameter(Mandatory = $true)][int]$StepNumber,
        [Parameter(Mandatory = $true)][string]$StepName
    )

    if ($options.StartFromStep -le $StepNumber) {
        return $true
    }
    Write-UltimateLog -Paths $paths -Level 'WARN' -Message "Step $StepNumber ($StepName) skipped because StartFromStep=$($options.StartFromStep) (debug)."
    return $false
}

function Invoke-UltimateKeySteps {
    param(
        [Parameter(Mandatory = $true)]$Steps,
        [Parameter(Mandatory = $true)][string]$Mode,
        [int]$LoopIndex = 0
    )

    $stepIndex = 0
    foreach ($step in @($Steps)) {
        $stepIndex++
        $sendResult = Send-AfkNamedKeyTap -Key $step.Key -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Sent key. Mode=$Mode Loop=$LoopIndex Step=$stepIndex Key=$($step.Key) WaitMs=$($step.WaitMilliseconds) InputMethod=$($sendResult.Method) Extended=$($sendResult.ExtendedKey) DownResult=$($sendResult.DownResult) UpResult=$($sendResult.UpResult) DryRun=$DryRun"
        Wait-UltimateMilliseconds -Milliseconds $step.WaitMilliseconds
    }
}

function Invoke-UltimateShareCodeInput {
    $chars = @($options.ShareCode.ToCharArray())
    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Share code input started. Digits=$($chars.Count) IntervalMs=$($options.DigitIntervalMilliseconds)"
    for ($i = 0; $i -lt $chars.Count; $i++) {
        $digit = [string]$chars[$i]
        $sendResult = Send-AfkDigitKeyTap -Digit $digit -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Sent share-code digit. Index=$($i + 1) Digit=$digit InputMethod=$($sendResult.Method) DownResult=$($sendResult.DownResult) UpResult=$($sendResult.UpResult) DryRun=$DryRun"
        if ($i -lt ($chars.Count - 1)) {
            Wait-UltimateMilliseconds -Milliseconds $options.DigitIntervalMilliseconds
        }
    }
    Write-UltimateLog -Paths $paths -Level 'INFO' -Message 'Share code input completed.'
}

function Test-UltimateCurrentTarget {
    param(
        [Int64]$TargetWindow,
        [string]$Label
    )

    $recognition = Test-UltimateSelectedCar `
        -WindowHandle $TargetWindow `
        -ImagePath $RecognitionImagePath `
        -TargetKeywords $options.TargetKeywords `
        -FamilyKeywords $options.FamilyKeywords `
        -TempRoot (Join-Path $paths.RuntimeRoot 'ultimate-ocr')

    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Recognition result. Label=$Label Match=$($recognition.Match) IsFamily=$($recognition.IsFamily) OcrSuccess=$($recognition.OcrSuccess) MatchMode=$($recognition.MatchMode) Bitmap=$($recognition.BitmapWidth)x$($recognition.BitmapHeight) CardRect=[$($recognition.Rect.X),$($recognition.Rect.Y),$($recognition.Rect.Width),$($recognition.Rect.Height)] OcrText='$($recognition.OcrText)' Reason=$($recognition.Reason)"
    return $recognition
}

function Invoke-UltimateTargetSearch {
    param(
        [Int64]$TargetWindow
    )

    if ($AssumeTargetFound) {
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message 'Target search skipped because AssumeTargetFound is enabled.'
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($RecognitionImagePath)) {
        $staticRecognition = Test-UltimateCurrentTarget -TargetWindow $TargetWindow -Label 'StaticImage'
        if ($staticRecognition.Match) {
            Write-UltimateLog -Paths $paths -Level 'INFO' -Message 'Target matched from static recognition image.'
            return
        }
        throw "Ultimate target was not matched in static image. Reason=$($staticRecognition.Reason)"
    }

    # Traverse the car grid by pressing the search key ($options.SearchKey, default Right)
    # continuously. The game wraps from the end of the row back around the list, so a steady
    # stream of presses eventually visits every card and returns to where we started. We
    # stop after exactly one full loop (the starting card comes back into view), rather
    # than after a fixed number of attempts. We only move vertically (S/W) once a Subaru
    # card is detected, then scan that column for the exact target. Doing the vertical
    # scan unconditionally on every step is what previously drifted the cursor off the
    # list (onto the "Buy Recommended Car" header) and made it bounce between two cards.
    #
    # MaxSearchAttempts is now an optional safety cap on the number of search presses:
    # 0 (the default) means unlimited / rely purely on the full-loop detection.
    $loopAnchor = $null      # canonical OCR text of the card we started on
    $anchorArmed = $false    # becomes true once we have moved off the starting card
    $seen = @{}              # every distinct card signature we have visited
    $staleStreak = 0         # consecutive presses that only revisited already-seen cards
    $staleLimit = 10         # backstop for a frozen cursor / single-card list
    $searchPresses = 0
    $first = $true

    while ($true) {
        if (-not $first) {
            if ($options.MaxSearchAttempts -gt 0 -and $searchPresses -ge $options.MaxSearchAttempts) {
                throw "Ultimate target was not found within $($options.MaxSearchAttempts) search presses (safety cap)."
            }
            $searchSendResult = Send-AfkNamedKeyTap -Key $options.SearchKey -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
            Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Search key sent. SearchPresses=$($searchPresses + 1) Key=$($options.SearchKey) InputMethod=$($searchSendResult.Method) DownResult=$($searchSendResult.DownResult) UpResult=$($searchSendResult.UpResult) DryRun=$DryRun"
            Wait-UltimateMilliseconds -Milliseconds $options.SearchSettleMilliseconds
            $searchPresses++
        }
        $first = $false

        $recognition = Test-UltimateCurrentTarget -TargetWindow $TargetWindow -Label "SearchPresses=$searchPresses Row=0"
        if ($recognition.Match) {
            Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Target matched. SearchPresses=$searchPresses Row=0"
            return
        }

        # One-full-loop detection on the top-row card. Use the OCR-tolerant canonical
        # key so small OCR jitter on the same card does not look like a different card.
        $signature = ConvertTo-UltimateMatchKey -Value ([string]$recognition.OcrText)
        if (-not [string]::IsNullOrEmpty($signature)) {
            if ($null -eq $loopAnchor) {
                $loopAnchor = $signature
                Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Loop anchor set. Signature='$signature'"
            }
            elseif ($anchorArmed -and $signature -eq $loopAnchor) {
                throw "Ultimate target was not found after scanning the whole list once (returned to the starting car after $searchPresses search presses)."
            }
            elseif (-not $anchorArmed -and $signature -ne $loopAnchor) {
                $anchorArmed = $true
            }

            # Backstop: in degenerate cases (single-card list, frozen cursor, all cards
            # identical) the anchor can never re-trigger. If we only keep revisiting
            # already-seen cards for a stretch, give up instead of looping forever.
            if ($seen.ContainsKey($signature)) {
                $staleStreak++
                if ($staleStreak -ge $staleLimit) {
                    throw "Ultimate target was not found; the search kept revisiting already-seen cars ($staleLimit in a row) without finding a new one. The cursor may be stuck."
                }
            }
            else {
                $seen[$signature] = $true
                $staleStreak = 0
            }
        }

        # Not a Subaru card: keep traversing horizontally, no vertical movement.
        if (-not $recognition.IsFamily) {
            continue
        }

        # Subaru detected but not the exact target yet: scan this column up/down.
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Subaru detected, scanning column. SearchPresses=$searchPresses MaxRows=$($options.VerticalScanSteps)"
        $scannedRows = 0
        $matchedInColumn = $false
        for ($row = 1; $row -le $options.VerticalScanSteps; $row++) {
            $downResult = Send-AfkNamedKeyTap -Key 'S' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
            Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Vertical scan key sent. SearchPresses=$searchPresses Row=$row Key=S InputMethod=$($downResult.Method) DownResult=$($downResult.DownResult) UpResult=$($downResult.UpResult) DryRun=$DryRun"
            Wait-UltimateMilliseconds -Milliseconds $options.SearchSettleMilliseconds
            $scannedRows++

            $rowRecognition = Test-UltimateCurrentTarget -TargetWindow $TargetWindow -Label "SearchPresses=$searchPresses Row=$row"
            if ($rowRecognition.Match) {
                Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Target matched. SearchPresses=$searchPresses Row=$row"
                $matchedInColumn = $true
                break
            }
        }

        if ($matchedInColumn) {
            return
        }

        # No match in this column: step back up so the next search press resumes from row 0.
        for ($restore = 1; $restore -le $scannedRows; $restore++) {
            $upResult = Send-AfkNamedKeyTap -Key 'W' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
            Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Vertical restore key sent. SearchPresses=$searchPresses Restore=$restore Key=W InputMethod=$($upResult.Method) DownResult=$($upResult.DownResult) UpResult=$($upResult.UpResult) DryRun=$DryRun"
            Wait-UltimateMilliseconds -Milliseconds $options.SearchSettleMilliseconds
        }
    }
}

function Invoke-UltimateTargetConfirm {
    $selectResult = Send-AfkNamedKeyTap -Key 'Enter' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Target matched. Enter sent. InputMethod=$($selectResult.Method) DownResult=$($selectResult.DownResult) UpResult=$($selectResult.UpResult) DryRun=$DryRun"
    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "After target select delay started. WaitMs=$($options.AfterTargetSelectDelayMilliseconds)"
    Wait-UltimateMilliseconds -Milliseconds $options.AfterTargetSelectDelayMilliseconds

    $confirmResult = Send-AfkNamedKeyTap -Key 'Enter' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Target confirmation Enter sent. InputMethod=$($confirmResult.Method) DownResult=$($confirmResult.DownResult) UpResult=$($confirmResult.UpResult) DryRun=$DryRun"
    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "After target confirm delay started. WaitMs=$($options.AfterTargetConfirmDelayMilliseconds)"
    Wait-UltimateMilliseconds -Milliseconds $options.AfterTargetConfirmDelayMilliseconds
}

function Invoke-UltimateSequenceLoops {
    for ($loop = 1; $loop -le $options.SequenceLoopCount; $loop++) {
        # Safe pause point: halt before starting this race, not mid-drive (the dominant grind).
        Wait-UltimatePauseGate -Context "sequence $loop/$($options.SequenceLoopCount)"
        Set-UltimatePhaseProgress -Phase 'Sequence' -Current $loop -Total $options.SequenceLoopCount
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Sequence loop started. Loop=$loop Total=$($options.SequenceLoopCount)"

        $enter1 = Send-AfkNamedKeyTap -Key 'Enter' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Sequence key sent. Loop=$loop Key=Enter WaitSeconds=$($options.SequenceEnterDelaySeconds) Throttle=$($options.GamepadThrottleEnabled) InputMethod=$($enter1.Method) DryRun=$DryRun"
        # Hold the gamepad throttle (RT) during this Enter-wait so the car drives forward the whole time.
        Invoke-UltimateThrottleWait -Seconds $options.SequenceEnterDelaySeconds -LoopIndex $loop

        $x1 = Send-AfkNamedKeyTap -Key 'X' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Sequence key sent. Loop=$loop Key=X WaitMs=$($options.SequenceXDelayMilliseconds) InputMethod=$($x1.Method) DryRun=$DryRun"
        Wait-UltimateMilliseconds -Milliseconds $options.SequenceXDelayMilliseconds

        $x2 = Send-AfkNamedKeyTap -Key 'X' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Sequence key sent. Loop=$loop Key=X WaitMs=$($options.SequenceXDelayMilliseconds) InputMethod=$($x2.Method) DryRun=$DryRun"
        Wait-UltimateMilliseconds -Milliseconds $options.SequenceXDelayMilliseconds

        $enter2 = Send-AfkNamedKeyTap -Key 'Enter' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Sequence key sent. Loop=$loop Key=Enter WaitSeconds=$($options.SequenceLoopDelaySeconds) InputMethod=$($enter2.Method) DryRun=$DryRun"
        Wait-UltimateSeconds -Seconds $options.SequenceLoopDelaySeconds

        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Sequence loop completed. Loop=$loop Total=$($options.SequenceLoopCount)"
    }
}

function Invoke-UltimateAutoBuyCar {
    $loopCount = $autoBuyCarOptions.LoopCount
    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "AutoBuyCar phase started. Loops=$loopCount Steps=$(@($autoBuyCarOptions.AutoBuyCarSteps).Count) BetweenLoopsMs=$($autoBuyCarOptions.AutoBuyCarBetweenLoopsMilliseconds) InputMethod=$($options.InputMethod)"
    for ($loop = 1; $loop -le $loopCount; $loop++) {
        Wait-UltimatePauseGate -Context "autobuy $loop/$loopCount"
        Set-UltimatePhaseProgress -Phase 'AutoBuyCar' -Current $loop -Total $loopCount
        Invoke-UltimateKeySteps -Steps $autoBuyCarOptions.AutoBuyCarSteps -Mode 'AutoBuyCar' -LoopIndex $loop
        # One AutoBuyCar loop buys exactly one (recommended) car. Bump the persisted
        # cumulative total per loop so a mid-phase Stop still records what was bought.
        # DryRun buys nothing, so it must not touch the real stat.
        if (-not $DryRun) {
            $cumulativeTotal = Add-UltimateAutoBuyCount -Paths $paths -Count 1
            Write-UltimateLog -Paths $paths -Level 'INFO' -Message "AutoBuyCar bought a car. Loop=$loop/$loopCount CumulativeTotal=$cumulativeTotal"
        }
        if ($loop -lt $loopCount) {
            Wait-UltimateMilliseconds -Milliseconds $autoBuyCarOptions.AutoBuyCarBetweenLoopsMilliseconds
        }
    }
    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "AutoBuyCar phase completed. Loops=$loopCount CumulativeTotal=$(Get-UltimateAutoBuyCount -Paths $paths)"
}

function Invoke-UltimateFindNewSubaru {
    $loopCount = $findNewSubaruOptions.LoopCount
    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "FindNewSubaru phase started. Loops=$loopCount MaxAttempts=$($findNewSubaruOptions.FindNewSubaruMaxSearchAttempts) SearchKey=$($findNewSubaruOptions.FindNewSubaruSearchKey) InputMethod=$($findNewSubaruOptions.InputMethod)"
    # Reuses the Automation subsystem's FindNewSubaru CV loop verbatim (shared lib function).
    # Logs flow to the Ultimate log because we pass Ultimate's $paths.
    # -SoftFailOnExhaust: in the Ultimate workflow a single input desync (the cursor getting
    # bumped off the car grid) must NOT exit(1) the whole run. The lib ends this phase with a
    # WARN instead of throwing, and the outer workflow loop's next Prelude re-homes the menu.
    Invoke-AutomationFindNewSubaruLoop -Paths $paths -Options $findNewSubaruOptions -RecognitionImagePath $RecognitionImagePath -DryRun:$DryRun -SoftFailOnExhaust -PauseCheck { Wait-UltimatePauseGate -Context 'findnewsubaru' } -ProgressCallback { param($c, $t) Set-UltimatePhaseProgress -Phase 'FindNewSubaru' -Current $c -Total $t }
    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "FindNewSubaru phase finished. Loops=$loopCount (may end early on input desync; see any WARN above)"
}

$state = Get-UltimateState -Paths $paths
if ($state.Status -in @('Running', 'RunningUnverified') -and $state.Pid -ne $PID) {
    Write-UltimateLog -Paths $paths -Level 'WARN' -Message "Ultimate already running. Existing PID=$($state.Pid). New PID=$PID exits."
    exit 0
}

$afkPaths = Get-AfkPaths -AppRoot $paths.AppRoot
Initialize-AfkWorkspace -Paths $afkPaths
$afkState = Get-AfkState -Paths $afkPaths
if ($afkState.Status -in @('Running', 'RunningUnverified')) {
    Write-UltimateLog -Paths $paths -Level 'ERROR' -Message "Cannot start Ultimate while AFK is running. AFK PID=$($afkState.Pid)"
    throw 'AFK is already running. Stop AFK before starting Ultimate.'
}

$automationPaths = Get-AutomationPaths -AppRoot $paths.AppRoot
Initialize-AutomationWorkspace -Paths $automationPaths
$automationState = Get-AutomationState -Paths $automationPaths
if ($automationState.Status -in @('Running', 'RunningUnverified')) {
    Write-UltimateLog -Paths $paths -Level 'ERROR' -Message "Cannot start Ultimate while Automation is running. Automation PID=$($automationState.Pid)"
    throw 'Automation is already running. Stop Automation before starting Ultimate.'
}

Set-UltimatePid -Paths $paths
# Clear any pause flag left over from a previous run/Stop so this fresh run does not pause instantly.
Clear-UltimatePause -Paths $paths

try {
    Add-Type -AssemblyName System.Windows.Forms
    Initialize-AfkNative

    # Plug in the virtual Xbox 360 controller ONCE and keep it for the whole run. Only the right
    # trigger is toggled later (held during each Sequence Enter-wait). Connecting once -- rather than
    # per drive -- is what stops the game flashing a "controller disconnected" popup between loops.
    # A connect failure here (driver/DLL missing) aborts the run via the surrounding try/catch so the
    # problem is visible instead of silently running 40s drives that never move.
    if ($options.GamepadThrottleEnabled -and -not $DryRun) {
        [void](Connect-AfkGamepad -AppRoot $paths.AppRoot -DllPath $options.GamepadDllPath)
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Gamepad connected (virtual Xbox 360); kept plugged in for the whole run. RT during Sequence Enter-wait = $($options.GamepadRightTriggerValue)/255."
    }
    elseif ($options.GamepadThrottleEnabled) {
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message 'Gamepad throttle enabled but DryRun: skipping virtual controller connect; Sequence Enter-wait will log only.'
    }
    else {
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message 'Gamepad throttle disabled (ultimate.gamepadThrottle.enabled=false); Sequence Enter-wait uses a plain wait.'
    }

    $effectiveWorkflowLoops = $options.WorkflowLoopCount
    $isInfiniteWorkflow = ($effectiveWorkflowLoops -le 0)
    if ($DryRun -and $isInfiniteWorkflow) {
        Write-UltimateLog -Paths $paths -Level 'WARN' -Message 'DryRun with an infinite workflow loop: capping to 1 iteration to avoid a runaway dry loop.'
        $isInfiniteWorkflow = $false
        $effectiveWorkflowLoops = 1
    }
    $workflowLoopLabel = if ($isInfiniteWorkflow) { 'infinite' } else { [string]$effectiveWorkflowLoops }
    $estLoopSeconds = Get-UltimateEstimatedLoopSeconds -Options $options -AutoBuyCarOptions $autoBuyCarOptions -FindNewSubaruOptions $findNewSubaruOptions

    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Ultimate started. PID=$PID DpiAware=$script:DpiAwareResult StartupDelay=$($options.StartupDelaySeconds) InputMethod=$($options.InputMethod) ShareCode=$($options.ShareCode) WorkflowLoops=$workflowLoopLabel EstPerLoop=$(Format-UltimateDuration -Seconds $estLoopSeconds) SequenceLoops=$($options.SequenceLoopCount) AutoBuyCarLoops=$($autoBuyCarOptions.LoopCount) FindNewSubaruLoops=$($findNewSubaruOptions.LoopCount) StartFromStep=$($options.StartFromStep) TargetKeywords='$($options.TargetKeywords -join ', ')' DryRun=$DryRun AssumeTargetFound=$AssumeTargetFound"
    Set-UltimateProgress -Paths $paths -Status 'running' -CurrentLoop 0 -TotalLoops $effectiveWorkflowLoops -DisplayText "Starting - $workflowLoopLabel loop(s), ~$(Format-UltimateDuration -Seconds $estLoopSeconds)/loop (estimate)" -Updated (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

    Wait-UltimateSeconds -Seconds $options.StartupDelaySeconds

    $targetWindow = 0
    if ($AssumeTargetFound) {
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message 'Foreground target capture skipped because AssumeTargetFound is enabled.'
    }
    elseif ([string]::IsNullOrWhiteSpace($RecognitionImagePath)) {
        $targetWindow = Get-AutomationForegroundWindowHandle
        if ($targetWindow -eq 0) {
            throw 'Could not find a foreground window for Ultimate.'
        }
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Foreground target captured. Handle=0x$('{0:X}' -f $targetWindow)"
    }
    else {
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Using recognition image path instead of live window. Path=$RecognitionImagePath"
    }

    if ($options.StartFromStep -gt 5) {
        Write-UltimateLog -Paths $paths -Level 'WARN' -Message "Debug StartFromStep=$($options.StartFromStep): steps before $($options.StartFromStep) are skipped. The game must already be in the UI state that step $($options.StartFromStep) expects."
    }

    # Outer workflow loop: repeat the WHOLE flow (steps 5-14) $effectiveWorkflowLoops times, or
    # forever when infinite. Each iteration is timed so the ETA is refined from the upfront
    # estimate to the measured per-loop average. The foreground window is captured once (above)
    # and reused every iteration; the Prelude (Esc x4 ...) re-homes the menu state each loop.
    $overallStart = Get-Date
    $measuredLoopSeconds = @()
    $iteration = 0
    while ($isInfiniteWorkflow -or $iteration -lt $effectiveWorkflowLoops) {
        $iteration++
        # Safe pause point between whole-workflow iterations (paused time is excluded from loop timing).
        Wait-UltimatePauseGate -Context "before loop $iteration"
        $loopStart = Get-Date
        $perLoopSeconds = if ($measuredLoopSeconds.Count -gt 0) { [double](($measuredLoopSeconds | Measure-Object -Average).Average) } else { $estLoopSeconds }

        if ($isInfiniteWorkflow) {
            $startText = "Loop $iteration (infinite) - ~$(Format-UltimateDuration -Seconds $perLoopSeconds)/loop, running $(Format-UltimateDuration -Seconds (((Get-Date) - $overallStart).TotalSeconds))"
        }
        else {
            $remainingSeconds = ($effectiveWorkflowLoops - ($iteration - 1)) * $perLoopSeconds
            $etaFinish = $loopStart.AddSeconds($remainingSeconds)
            $etaClock = if ($etaFinish.Date -eq (Get-Date).Date) { $etaFinish.ToString('HH:mm') } else { $etaFinish.ToString('MM-dd HH:mm') }
            $startText = "Loop $iteration/$effectiveWorkflowLoops - ~$(Format-UltimateDuration -Seconds $perLoopSeconds)/loop, ETA finish ~$etaClock (in $(Format-UltimateDuration -Seconds $remainingSeconds))"
        }
        # Stash this loop's context so inner-phase progress writes keep the right loop + ETA text.
        $script:UltimateLoopIteration = $iteration
        $script:UltimateLoopTotal = $effectiveWorkflowLoops
        $script:UltimateLoopText = $startText
        Set-UltimateProgress -Paths $paths -Status 'running' -CurrentLoop $iteration -TotalLoops $effectiveWorkflowLoops -DisplayText $startText -Updated (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Ultimate loop started. $startText"

        if (Test-UltimateShouldRunStep -StepNumber 5 -StepName 'Prelude') {
            Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Prelude started. Steps=$(@($options.PreludeSteps).Count)"
            Invoke-UltimateKeySteps -Steps $options.PreludeSteps -Mode 'Prelude'
        }
        if (Test-UltimateShouldRunStep -StepNumber 6 -StepName 'ShareCode') {
            Invoke-UltimateShareCodeInput
        }
        if (Test-UltimateShouldRunStep -StepNumber 7 -StepName 'AfterCode') {
            Write-UltimateLog -Paths $paths -Level 'INFO' -Message "After-code macro started. Steps=$(@($options.AfterCodeSteps).Count)"
            Invoke-UltimateKeySteps -Steps $options.AfterCodeSteps -Mode 'AfterCode'
        }

        if (Test-UltimateShouldRunStep -StepNumber 8 -StepName 'TargetSearch') {
            Invoke-UltimateTargetSearch -TargetWindow $targetWindow
        }
        if (Test-UltimateShouldRunStep -StepNumber 9 -StepName 'TargetConfirm') {
            Invoke-UltimateTargetConfirm
        }
        if (Test-UltimateShouldRunStep -StepNumber 10 -StepName 'Sequence') {
            Invoke-UltimateSequenceLoops
        }

        if (Test-UltimateShouldRunStep -StepNumber 11 -StepName 'PostSequence') {
            Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Post-sequence macro started. Steps=$(@($options.PostSequenceSteps).Count)"
            Invoke-UltimateKeySteps -Steps $options.PostSequenceSteps -Mode 'PostSequence'
        }
        if (Test-UltimateShouldRunStep -StepNumber 12 -StepName 'AutoBuyCar') {
            Invoke-UltimateAutoBuyCar
        }

        # Configurable settle delay between AutoBuyCar (step 12) and the Post-buy macro (step 13).
        # Only waits when step 12 actually ran (StartFromStep <= 12); jumping straight to step 13+
        # for debugging skips the wait. Tune via config.json ultimate.afterAutoBuyCarDelayMilliseconds.
        if ($options.StartFromStep -le 12 -and $options.AfterAutoBuyCarDelayMilliseconds -gt 0) {
            Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Delay between AutoBuyCar and Post-buy macro. WaitMs=$($options.AfterAutoBuyCarDelayMilliseconds)"
            Wait-UltimateMilliseconds -Milliseconds $options.AfterAutoBuyCarDelayMilliseconds
        }

        if (Test-UltimateShouldRunStep -StepNumber 13 -StepName 'PostBuy') {
            Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Post-buy macro started. Steps=$(@($options.PostBuySteps).Count)"
            Invoke-UltimateKeySteps -Steps $options.PostBuySteps -Mode 'PostBuy'
        }
        if (Test-UltimateShouldRunStep -StepNumber 14 -StepName 'FindNewSubaru') {
            Invoke-UltimateFindNewSubaru
        }

        $loopElapsed = ((Get-Date) - $loopStart).TotalSeconds
        $measuredLoopSeconds += $loopElapsed
        $avgSeconds = [double](($measuredLoopSeconds | Measure-Object -Average).Average)
        if ($isInfiniteWorkflow) {
            $doneText = "Loop $iteration done (infinite) - took $(Format-UltimateDuration -Seconds $loopElapsed), avg $(Format-UltimateDuration -Seconds $avgSeconds)/loop, running $(Format-UltimateDuration -Seconds (((Get-Date) - $overallStart).TotalSeconds))"
        }
        else {
            $loopsLeft = $effectiveWorkflowLoops - $iteration
            if ($loopsLeft -le 0) {
                $doneText = "All $effectiveWorkflowLoops loop(s) done - total $(Format-UltimateDuration -Seconds (((Get-Date) - $overallStart).TotalSeconds))"
            }
            else {
                $remainingAfter = $loopsLeft * $avgSeconds
                $etaFinish2 = (Get-Date).AddSeconds($remainingAfter)
                $etaClock2 = if ($etaFinish2.Date -eq (Get-Date).Date) { $etaFinish2.ToString('HH:mm') } else { $etaFinish2.ToString('MM-dd HH:mm') }
                $doneText = "Loop $iteration/$effectiveWorkflowLoops done - avg $(Format-UltimateDuration -Seconds $avgSeconds)/loop, $loopsLeft left, ETA finish ~$etaClock2 (in $(Format-UltimateDuration -Seconds $remainingAfter))"
            }
        }
        Set-UltimateProgress -Paths $paths -Status 'running' -CurrentLoop $iteration -TotalLoops $effectiveWorkflowLoops -DisplayText $doneText -Updated (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Ultimate loop completed. $doneText"

        # Settle pause between two consecutive whole-workflow iterations: only when another
        # loop will follow (infinite, or finite with iterations left). Skipped after the final
        # loop so the run ends promptly. Wait-UltimateMilliseconds is a no-op under DryRun.
        $moreLoopsToGo = $isInfiniteWorkflow -or ($iteration -lt $effectiveWorkflowLoops)
        if ($moreLoopsToGo -and $options.BetweenWorkflowLoopsMilliseconds -gt 0) {
            Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Delay between Ultimate loops. WaitMs=$($options.BetweenWorkflowLoopsMilliseconds)"
            Wait-UltimateMilliseconds -Milliseconds $options.BetweenWorkflowLoopsMilliseconds
        }
    }

    $completedText = "All $effectiveWorkflowLoops loop(s) completed - total $(Format-UltimateDuration -Seconds (((Get-Date) - $overallStart).TotalSeconds))"
    Set-UltimateProgress -Paths $paths -Status 'completed' -CurrentLoop $iteration -TotalLoops $effectiveWorkflowLoops -DisplayText $completedText -Updated (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Ultimate completed. PID=$PID Iterations=$iteration"
}
catch {
    Write-UltimateLog -Paths $paths -Level 'ERROR' -Message "Ultimate stopped because of an error. Error=$($_.Exception.Message)"
    exit 1
}
finally {
    Release-AfkKeys -DryRun:$DryRun
    # Zero the throttle and unplug the virtual controller on a clean exit/error. (On a force-Stop the
    # finally does not run, but the OS auto-unplugs the pad when this process dies, so it still cleans up.)
    Disconnect-AfkGamepad
    # Clear the pause flag so it never outlives the worker. (On a force-Stop the GUI's Stop-AppUltimate
    # clears it instead, and a fresh run clears stale flags at startup.)
    Clear-UltimatePause -Paths $paths
    Remove-UltimatePid -Paths $paths
    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Ultimate exited. PID=$PID"
}
