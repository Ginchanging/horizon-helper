[CmdletBinding()]
param(
    [string]$AppRoot,
    [ValidateSet('AutoBuyCar', 'FindNewSubaru')][string]$Mode = 'AutoBuyCar',
    [int]$LoopCount = -1,
    [int]$StartupDelaySeconds = -1,
    [string]$RecognitionImagePath,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
. (Join-Path $scriptRoot 'AfkLib.ps1')
. (Join-Path $scriptRoot 'AutomationLib.ps1')

$paths = Get-AutomationPaths -AppRoot $AppRoot
Initialize-AutomationWorkspace -Paths $paths
$config = Get-AutomationConfig -AppRoot $paths.AppRoot
$options = Resolve-AutomationRuntimeOptions -Config $config -Mode $Mode -LoopCount $LoopCount -StartupDelaySeconds $StartupDelaySeconds

function Invoke-AutoBuyCar {
    for ($loop = 1; $loop -le $options.LoopCount; $loop++) {
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "AutoBuyCar loop started. Loop=$loop Total=$($options.LoopCount)"
        Invoke-AutomationKeySteps -Paths $paths -Steps $options.AutoBuyCarSteps -Mode 'AutoBuyCar' -LoopIndex $loop -KeyTapHoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "AutoBuyCar loop completed. Loop=$loop Total=$($options.LoopCount)"
        if ($loop -lt $options.LoopCount -and $options.AutoBuyCarBetweenLoopsMilliseconds -gt 0) {
            Start-Sleep -Milliseconds $options.AutoBuyCarBetweenLoopsMilliseconds
        }
    }
}

function Invoke-AfkMacroComboOnce {
    param(
        [int]$LoopIndex
    )

    $afkConfig = Get-AfkConfig -AppRoot $paths.AppRoot
    $afkOptions = Resolve-AfkRuntimeOptions -Config $afkConfig
    Write-AutomationLog -Paths $paths -Level 'INFO' -Message "MacroCombo started after match. Loop=$LoopIndex Steps=$(@($afkOptions.MacroComboSteps).Count)"
    Invoke-AutomationKeySteps -Paths $paths -Steps $afkOptions.MacroComboSteps -Mode 'MacroComboAfterMatch' -LoopIndex $LoopIndex -KeyTapHoldMilliseconds $afkOptions.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
    Write-AutomationLog -Paths $paths -Level 'INFO' -Message "MacroCombo completed after match. Loop=$LoopIndex"
}

function Invoke-FindNewSubaru {
    $targetWindow = 0
    if ([string]::IsNullOrWhiteSpace($RecognitionImagePath)) {
        $targetWindow = Get-AutomationForegroundWindowHandle
        if ($targetWindow -eq 0) {
            throw 'Could not find a foreground window for automation.'
        }
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Foreground target captured. Handle=0x$('{0:X}' -f $targetWindow)"
    }
    else {
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Using recognition image path instead of live window. Path=$RecognitionImagePath"
    }

    $tempRoot = Join-Path $paths.RuntimeRoot 'automation-ocr'
    for ($loop = 1; $loop -le $options.LoopCount; $loop++) {
        $matched = $false
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "FindNewSubaru loop started. Loop=$loop Total=$($options.LoopCount)"

        for ($attempt = 1; $attempt -le $options.FindNewSubaruMaxSearchAttempts; $attempt++) {
            $searchSendResult = Send-AfkNamedKeyTap -Key $options.FindNewSubaruSearchKey -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
            Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Search key sent. Loop=$loop Attempt=$attempt Key=$($options.FindNewSubaruSearchKey) InputMethod=$($searchSendResult.Method) Extended=$($searchSendResult.ExtendedKey) DownResult=$($searchSendResult.DownResult) UpResult=$($searchSendResult.UpResult) DryRun=$DryRun"
            if ($options.FindNewSubaruSearchSettleMilliseconds -gt 0) {
                Start-Sleep -Milliseconds $options.FindNewSubaruSearchSettleMilliseconds
            }

            $recognition = Test-AutomationSelectedCar `
                -WindowHandle $targetWindow `
                -ImagePath $RecognitionImagePath `
                -TargetKeywords $options.FindNewSubaruTargetKeywords `
                -NewBadgeText $options.FindNewSubaruNewBadgeText `
                -RequireTargetConfirmation $options.FindNewSubaruRequireTargetConfirmation `
                -TempRoot $tempRoot

            Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Recognition result. Loop=$loop Attempt=$attempt Match=$($recognition.Match) Stop=$($recognition.Stop) New=$($recognition.HasNewBadge) IsTargetWithoutBadge=$($recognition.IsTargetWithoutBadge) OcrSuccess=$($recognition.OcrSuccess) MatchMode=$($recognition.MatchMode) Reason=$($recognition.Reason)"

            if (-not $recognition.Match -and $recognition.IsTargetWithoutBadge -and $options.FindNewSubaruVerticalScanSteps -gt 0) {
                Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Target car found without new badge, scanning down. Loop=$loop Attempt=$attempt MaxRows=$($options.FindNewSubaruVerticalScanSteps)"
                $scanned = 0
                for ($vs = 1; $vs -le $options.FindNewSubaruVerticalScanSteps; $vs++) {
                    $vSendResult = Send-AfkNamedKeyTap -Key 'S' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
                    Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Vertical scan key S sent. Loop=$loop Attempt=$attempt VS=$vs InputMethod=$($vSendResult.Method) DownResult=$($vSendResult.DownResult) UpResult=$($vSendResult.UpResult) DryRun=$DryRun"
                    if ($options.FindNewSubaruSearchSettleMilliseconds -gt 0) {
                        Start-Sleep -Milliseconds $options.FindNewSubaruSearchSettleMilliseconds
                    }
                    $scanned++

                    $vRecognition = Test-AutomationSelectedCar `
                        -WindowHandle $targetWindow `
                        -ImagePath $RecognitionImagePath `
                        -TargetKeywords $options.FindNewSubaruTargetKeywords `
                        -NewBadgeText $options.FindNewSubaruNewBadgeText `
                        -RequireTargetConfirmation $options.FindNewSubaruRequireTargetConfirmation `
                        -TempRoot $tempRoot
                    Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Vertical scan recognition. Loop=$loop Attempt=$attempt VS=$vs Match=$($vRecognition.Match) New=$($vRecognition.HasNewBadge) IsTargetWithoutBadge=$($vRecognition.IsTargetWithoutBadge) OcrSuccess=$($vRecognition.OcrSuccess) MatchMode=$($vRecognition.MatchMode) OcrText='$($vRecognition.OcrText)' Reason=$($vRecognition.Reason)"

                    if ($vRecognition.Match -or $vRecognition.HasNewBadge) {
                        $enterSendResult = Send-AfkNamedKeyTap -Key 'Enter' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
                        $vsSelectMode = if ($vRecognition.Match) { 'FullMatch' } else { 'BadgeOnly' }
                        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Vertical scan matched new target car. Enter sent. Loop=$loop Attempt=$attempt VS=$vs SelectMode=$vsSelectMode InputMethod=$($enterSendResult.Method) DownResult=$($enterSendResult.DownResult) UpResult=$($enterSendResult.UpResult) DryRun=$DryRun"
                        if ($options.FindNewSubaruAfterSelectDelayMilliseconds -gt 0) {
                            Write-AutomationLog -Paths $paths -Level 'INFO' -Message "After-select delay $($options.FindNewSubaruAfterSelectDelayMilliseconds)ms. Loop=$loop Attempt=$attempt VS=$vs"
                            Start-Sleep -Milliseconds $options.FindNewSubaruAfterSelectDelayMilliseconds
                        }
                        Invoke-AfkMacroComboOnce -LoopIndex $loop
                        $matched = $true
                        break
                    }

                    if ($vRecognition.Stop) {
                        throw $vRecognition.Reason
                    }
                }

                if (-not $matched) {
                    for ($i = 0; $i -lt $scanned; $i++) {
                        Send-AfkNamedKeyTap -Key 'W' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun | Out-Null
                        if ($options.FindNewSubaruSearchSettleMilliseconds -gt 0) {
                            Start-Sleep -Milliseconds $options.FindNewSubaruSearchSettleMilliseconds
                        }
                    }
                    Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Vertical scan found no new match. Returned $scanned row(s) up. Loop=$loop Attempt=$attempt"
                }

                if ($matched) { break }
            }

            if ($recognition.Match) {
                $enterSendResult = Send-AfkNamedKeyTap -Key 'Enter' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
                Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Matched new target car. Enter sent. Loop=$loop Attempt=$attempt InputMethod=$($enterSendResult.Method) DownResult=$($enterSendResult.DownResult) UpResult=$($enterSendResult.UpResult) DryRun=$DryRun"
                if ($options.FindNewSubaruAfterSelectDelayMilliseconds -gt 0) {
                    Write-AutomationLog -Paths $paths -Level 'INFO' -Message "After-select delay $($options.FindNewSubaruAfterSelectDelayMilliseconds)ms. Loop=$loop Attempt=$attempt"
                    Start-Sleep -Milliseconds $options.FindNewSubaruAfterSelectDelayMilliseconds
                }
                Invoke-AfkMacroComboOnce -LoopIndex $loop
                $matched = $true
                break
            }

            if ($recognition.Stop) {
                throw $recognition.Reason
            }
        }

        if (-not $matched) {
            throw "FindNewSubaru did not find a confirmed new target car within $($options.FindNewSubaruMaxSearchAttempts) attempts. Loop=$loop"
        }

        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "FindNewSubaru loop completed. Loop=$loop Total=$($options.LoopCount)"
        if ($loop -lt $options.LoopCount -and $options.FindNewSubaruBetweenLoopsMilliseconds -gt 0) {
            Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Between-loop delay $($options.FindNewSubaruBetweenLoopsMilliseconds)ms. Loop=$loop"
            Start-Sleep -Milliseconds $options.FindNewSubaruBetweenLoopsMilliseconds
        }
    }
}

$state = Get-AutomationState -Paths $paths
if ($state.Status -in @('Running', 'RunningUnverified') -and $state.Pid -ne $PID) {
    Write-AutomationLog -Paths $paths -Level 'WARN' -Message "Automation already running. Existing PID=$($state.Pid). New PID=$PID exits."
    exit 0
}

$afkPaths = Get-AfkPaths -AppRoot $paths.AppRoot
Initialize-AfkWorkspace -Paths $afkPaths
$afkState = Get-AfkState -Paths $afkPaths
if ($afkState.Status -in @('Running', 'RunningUnverified')) {
    Write-AutomationLog -Paths $paths -Level 'ERROR' -Message "Cannot start automation while AFK is running. AFK PID=$($afkState.Pid)"
    throw 'AFK is already running. Stop AFK before starting Automation.'
}

Set-AutomationPid -Paths $paths

try {
    Add-Type -AssemblyName System.Windows.Forms
    Initialize-AfkNative
    Initialize-AutomationNative

    Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Automation started. PID=$PID Mode=$Mode LoopCount=$($options.LoopCount) StartupDelay=$($options.StartupDelaySeconds) KeyTapHoldMs=$($options.KeyTapHoldMilliseconds) InputMethod=$($options.InputMethod) DryRun=$DryRun"

    if ($options.StartupDelaySeconds -gt 0) {
        Start-Sleep -Seconds $options.StartupDelaySeconds
    }

    if ($Mode -eq 'FindNewSubaru') {
        Invoke-FindNewSubaru
    }
    else {
        Invoke-AutoBuyCar
    }

    Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Automation completed. PID=$PID Mode=$Mode"
}
catch {
    Write-AutomationLog -Paths $paths -Level 'ERROR' -Message "Automation stopped because of an error. Mode=$Mode Error=$($_.Exception.Message)"
    exit 1
}
finally {
    Release-AfkKeys -DryRun:$DryRun
    Remove-AutomationPid -Paths $paths
    Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Automation exited. PID=$PID"
}
