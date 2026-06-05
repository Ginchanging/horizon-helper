[CmdletBinding()]
param(
    [string]$AppRoot,
    [int]$StartupDelaySeconds = -1,
    [int]$SequenceLoopCount = -1,
    [int]$AutoBuyCarLoopCount = -1,
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
$options = Resolve-UltimateRuntimeOptions -Config $config -StartupDelaySeconds $StartupDelaySeconds -SequenceLoopCount $SequenceLoopCount -AutoBuyCarLoopCount $AutoBuyCarLoopCount
$automationConfig = Get-AutomationConfig -AppRoot $paths.AppRoot
$autoBuyCarOptions = Resolve-AutomationRuntimeOptions -Config $automationConfig -Mode 'AutoBuyCar' -LoopCount $options.AutoBuyCarLoopCount

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

    # Traverse the car grid by pressing the search key (Left) continuously. The game
    # wraps from the leftmost card back to the end of the list, so a steady stream of
    # Left presses eventually visits every card and returns to where we started. We
    # stop after exactly one full loop (the starting card comes back into view), rather
    # than after a fixed number of attempts. We only move vertically (S/W) once a Subaru
    # card is detected, then scan that column for the exact target. Doing the vertical
    # scan unconditionally on every step is what previously drifted the cursor off the
    # list (onto the "Buy Recommended Car" header) and made it bounce between two cards.
    #
    # MaxSearchAttempts is now an optional safety cap on the number of Left presses:
    # 0 (the default) means unlimited / rely purely on the full-loop detection.
    $loopAnchor = $null      # canonical OCR text of the card we started on
    $anchorArmed = $false    # becomes true once we have moved off the starting card
    $seen = @{}              # every distinct card signature we have visited
    $staleStreak = 0         # consecutive presses that only revisited already-seen cards
    $staleLimit = 10         # backstop for a frozen cursor / single-card list
    $leftPresses = 0
    $first = $true

    while ($true) {
        if (-not $first) {
            if ($options.MaxSearchAttempts -gt 0 -and $leftPresses -ge $options.MaxSearchAttempts) {
                throw "Ultimate target was not found within $($options.MaxSearchAttempts) Left presses (safety cap)."
            }
            $searchSendResult = Send-AfkNamedKeyTap -Key $options.SearchKey -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
            Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Search key sent. LeftPresses=$($leftPresses + 1) Key=$($options.SearchKey) InputMethod=$($searchSendResult.Method) DownResult=$($searchSendResult.DownResult) UpResult=$($searchSendResult.UpResult) DryRun=$DryRun"
            Wait-UltimateMilliseconds -Milliseconds $options.SearchSettleMilliseconds
            $leftPresses++
        }
        $first = $false

        $recognition = Test-UltimateCurrentTarget -TargetWindow $TargetWindow -Label "LeftPresses=$leftPresses Row=0"
        if ($recognition.Match) {
            Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Target matched. LeftPresses=$leftPresses Row=0"
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
                throw "Ultimate target was not found after scanning the whole list once (returned to the starting car after $leftPresses Left presses)."
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

        # Not a Subaru card: keep traversing Left, no vertical movement.
        if (-not $recognition.IsFamily) {
            continue
        }

        # Subaru detected but not the exact target yet: scan this column up/down.
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Subaru detected, scanning column. LeftPresses=$leftPresses MaxRows=$($options.VerticalScanSteps)"
        $scannedRows = 0
        $matchedInColumn = $false
        for ($row = 1; $row -le $options.VerticalScanSteps; $row++) {
            $downResult = Send-AfkNamedKeyTap -Key 'S' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
            Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Vertical scan key sent. LeftPresses=$leftPresses Row=$row Key=S InputMethod=$($downResult.Method) DownResult=$($downResult.DownResult) UpResult=$($downResult.UpResult) DryRun=$DryRun"
            Wait-UltimateMilliseconds -Milliseconds $options.SearchSettleMilliseconds
            $scannedRows++

            $rowRecognition = Test-UltimateCurrentTarget -TargetWindow $TargetWindow -Label "LeftPresses=$leftPresses Row=$row"
            if ($rowRecognition.Match) {
                Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Target matched. LeftPresses=$leftPresses Row=$row"
                $matchedInColumn = $true
                break
            }
        }

        if ($matchedInColumn) {
            return
        }

        # No match in this column: step back up so the next Left press resumes from row 0.
        for ($restore = 1; $restore -le $scannedRows; $restore++) {
            $upResult = Send-AfkNamedKeyTap -Key 'W' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
            Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Vertical restore key sent. LeftPresses=$leftPresses Restore=$restore Key=W InputMethod=$($upResult.Method) DownResult=$($upResult.DownResult) UpResult=$($upResult.UpResult) DryRun=$DryRun"
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
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Sequence loop started. Loop=$loop Total=$($options.SequenceLoopCount)"

        $enter1 = Send-AfkNamedKeyTap -Key 'Enter' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Sequence key sent. Loop=$loop Key=Enter WaitSeconds=$($options.SequenceEnterDelaySeconds) InputMethod=$($enter1.Method) DryRun=$DryRun"
        Wait-UltimateSeconds -Seconds $options.SequenceEnterDelaySeconds

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
        Invoke-UltimateKeySteps -Steps $autoBuyCarOptions.AutoBuyCarSteps -Mode 'AutoBuyCar' -LoopIndex $loop
        if ($loop -lt $loopCount) {
            Wait-UltimateMilliseconds -Milliseconds $autoBuyCarOptions.AutoBuyCarBetweenLoopsMilliseconds
        }
    }
    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "AutoBuyCar phase completed. Loops=$loopCount"
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

try {
    Add-Type -AssemblyName System.Windows.Forms
    Initialize-AfkNative

    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Ultimate started. PID=$PID DpiAware=$script:DpiAwareResult StartupDelay=$($options.StartupDelaySeconds) InputMethod=$($options.InputMethod) ShareCode=$($options.ShareCode) SequenceLoops=$($options.SequenceLoopCount) AutoBuyCarLoops=$($autoBuyCarOptions.LoopCount) TargetKeywords='$($options.TargetKeywords -join ', ')' DryRun=$DryRun AssumeTargetFound=$AssumeTargetFound"

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

    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Prelude started. Steps=$(@($options.PreludeSteps).Count)"
    Invoke-UltimateKeySteps -Steps $options.PreludeSteps -Mode 'Prelude'
    Invoke-UltimateShareCodeInput
    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "After-code macro started. Steps=$(@($options.AfterCodeSteps).Count)"
    Invoke-UltimateKeySteps -Steps $options.AfterCodeSteps -Mode 'AfterCode'

    Invoke-UltimateTargetSearch -TargetWindow $targetWindow
    Invoke-UltimateTargetConfirm
    Invoke-UltimateSequenceLoops

    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Post-sequence macro started. Steps=$(@($options.PostSequenceSteps).Count)"
    Invoke-UltimateKeySteps -Steps $options.PostSequenceSteps -Mode 'PostSequence'
    Invoke-UltimateAutoBuyCar

    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Ultimate completed. PID=$PID"
}
catch {
    Write-UltimateLog -Paths $paths -Level 'ERROR' -Message "Ultimate stopped because of an error. Error=$($_.Exception.Message)"
    exit 1
}
finally {
    Release-AfkKeys -DryRun:$DryRun
    Remove-UltimatePid -Paths $paths
    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Ultimate exited. PID=$PID"
}
