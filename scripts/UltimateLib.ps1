function Get-UltimateAppRoot {
    [CmdletBinding()]
    param(
        [string]$AppRoot
    )

    if ([string]::IsNullOrWhiteSpace($AppRoot)) {
        return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath
    }

    return (Resolve-Path -LiteralPath $AppRoot).ProviderPath
}

function Get-UltimatePaths {
    [CmdletBinding()]
    param(
        [string]$AppRoot
    )

    $root = Get-UltimateAppRoot -AppRoot $AppRoot
    $runtimeRoot = Join-Path $root 'runtime'
    $logsRoot = Join-Path $root 'logs'

    [pscustomobject]@{
        AppRoot          = $root
        RuntimeRoot      = $runtimeRoot
        LogsRoot         = $logsRoot
        PidPath          = Join-Path $runtimeRoot 'ultimate.pid'
        LogPath          = Join-Path $logsRoot 'ultimate.log'
        AutoBuyCountPath = Join-Path $runtimeRoot 'ultimate-autobuy-count.txt'
        ProgressPath     = Join-Path $runtimeRoot 'ultimate-progress.json'
        PausePath        = Join-Path $runtimeRoot 'ultimate.pause'
    }
}

function Initialize-UltimateWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths
    )

    foreach ($path in @($Paths.RuntimeRoot, $Paths.LogsRoot)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
    }
}

function Write-UltimateLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO',
        [Parameter(Mandatory = $true)][string]$Message
    )

    Initialize-UltimateWorkspace -Paths $Paths
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $Paths.LogPath -Value "[$timestamp] [$Level] $Message" -Encoding UTF8
}

function Test-UltimateConfigProperty {
    param(
        $Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    return ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name)
}

function Get-UltimateConfigIntValue {
    param(
        $Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [int]$DefaultValue
    )

    if ((Test-UltimateConfigProperty -Object $Object -Name $Name) -and $null -ne $Object.$Name) {
        return [int]$Object.$Name
    }

    return $DefaultValue
}

function Get-UltimateConfigStringValue {
    param(
        $Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$DefaultValue
    )

    if ((Test-UltimateConfigProperty -Object $Object -Name $Name) -and $null -ne $Object.$Name) {
        return [string]$Object.$Name
    }

    return $DefaultValue
}

function Get-DefaultUltimatePreludeSteps {
    @(
        [pscustomobject]@{ Key = 'Esc'; WaitMilliseconds = 2000 },
        [pscustomobject]@{ Key = 'Esc'; WaitMilliseconds = 2000 },
        [pscustomobject]@{ Key = 'Esc'; WaitMilliseconds = 20000 },
        [pscustomobject]@{ Key = 'Esc'; WaitMilliseconds = 2000 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 1500 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 1500 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 1500 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 1500 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 1500 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 1500 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 1500 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 1500 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 1500 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 1500 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 1500 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 1500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 10000 },
        [pscustomobject]@{ Key = 'Backspace'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'W'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 }
    )
}

function Get-DefaultUltimateAfterCodeSteps {
    @(
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 5000 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 2000 },
        [pscustomobject]@{ Key = 'Backspace'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 }
    )
}

function Get-DefaultUltimatePostSequenceSteps {
    @(
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 10000 },
        [pscustomobject]@{ Key = 'Esc'; WaitMilliseconds = 7000 },
        [pscustomobject]@{ Key = 'Esc'; WaitMilliseconds = 2000 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 1500 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 1500 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 1500 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 1500 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 1500 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 1500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 20000 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 1500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'Backspace'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 }
    )
}

function Get-DefaultUltimatePostBuySteps {
    # Runs after the AutoBuyCar tail, to back out of the purchase screens and navigate
    # to the autoshow grid so the FindNewSubaru phase can start scanning. Hard-coded here
    # (not read from config.json), like the other Ultimate macros.
    @(
        [pscustomobject]@{ Key = 'Esc'; WaitMilliseconds = 2000 },
        [pscustomobject]@{ Key = 'Esc'; WaitMilliseconds = 2000 },
        [pscustomobject]@{ Key = 'Esc'; WaitMilliseconds = 2000 },
        [pscustomobject]@{ Key = 'Esc'; WaitMilliseconds = 2000 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 }
    )
}

function Get-UltimateConfig {
    [CmdletBinding()]
    param(
        [string]$AppRoot
    )

    $root = Get-UltimateAppRoot -AppRoot $AppRoot
    $configPath = Join-Path $root 'config.json'

    $startupDelaySeconds = 5
    $inputMethod = 'SendKeys'
    $keyTapHoldMilliseconds = 50
    $shareCode = '705399298'
    $digitIntervalMilliseconds = 500
    $afterTargetSelectDelayMilliseconds = 20000
    $afterTargetConfirmDelayMilliseconds = 2000
    # Pause inserted between the AutoBuyCar phase (step 12) and the Post-buy macro (step 13)
    # so the purchase screens have time to settle before the macro backs out of them.
    $afterAutoBuyCarDelayMilliseconds = 2000
    # How many times the WHOLE Ultimate workflow repeats. 0 = infinite (run until stopped).
    $workflowLoopCount = 1
    # Pause inserted between two consecutive whole-workflow iterations (after step 14
    # FindNewSubaru of one loop, before step 5 Prelude of the next) so the menu state
    # settles before the next loop re-homes it. Not applied after the final loop.
    $betweenWorkflowLoopsMilliseconds = 2000
    $sequenceLoopCount = 80
    $sequenceEnterDelaySeconds = 40
    $sequenceXDelayMilliseconds = 500
    $sequenceLoopDelaySeconds = 10
    # Use the first two characters of the Subaru name (斯巴) instead of the full
    # 斯巴鲁. Windows OCR reliably reads 斯 and 巴 but frequently mangles the third
    # character 鲁 into 兽, 口, etc., which would otherwise fail both the family
    # check (skipping the whole target column) and the final target confirmation.
    # 1998 + S1 + 790 keep the target unambiguous; 斯巴 won't match 三菱/日产 cards.
    $targetKeywords = @(
        '1998',
        ([string]([char]0x65AF) + [string]([char]0x5DF4)),
        'S1',
        '790'
    )
    $familyKeywords = @(
        ([string]([char]0x65AF) + [string]([char]0x5DF4))
    )
    $searchKey = 'Right'
    $searchSettleMilliseconds = 500
    $maxSearchAttempts = 50
    $verticalScanSteps = 2
    # Virtual-gamepad throttle: during the Sequence loop's Enter-wait (the in-race drive), hold the
    # controller right trigger so the car drives forward. Needs the ViGEmBus driver + the client DLL.
    # The controller stays plugged in for the whole run so the game never flashes a disconnect popup.
    $gamepadThrottleEnabled = $true
    $gamepadRightTriggerValue = 255
    $gamepadDllPath = ''

    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $rawConfig = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
        $json = $rawConfig | ConvertFrom-Json
        if ((Test-UltimateConfigProperty -Object $json -Name 'ultimate') -and $null -ne $json.ultimate) {
            $ultimate = $json.ultimate
            $startupDelaySeconds = Get-UltimateConfigIntValue -Object $ultimate -Name 'startupDelaySeconds' -DefaultValue $startupDelaySeconds
            $inputMethod = Get-UltimateConfigStringValue -Object $ultimate -Name 'inputMethod' -DefaultValue $inputMethod
            $keyTapHoldMilliseconds = Get-UltimateConfigIntValue -Object $ultimate -Name 'keyTapHoldMilliseconds' -DefaultValue $keyTapHoldMilliseconds
            $shareCode = Get-UltimateConfigStringValue -Object $ultimate -Name 'shareCode' -DefaultValue $shareCode
            $digitIntervalMilliseconds = Get-UltimateConfigIntValue -Object $ultimate -Name 'digitIntervalMilliseconds' -DefaultValue $digitIntervalMilliseconds
            $afterTargetSelectDelayMilliseconds = Get-UltimateConfigIntValue -Object $ultimate -Name 'afterTargetSelectDelayMilliseconds' -DefaultValue $afterTargetSelectDelayMilliseconds
            $afterTargetConfirmDelayMilliseconds = Get-UltimateConfigIntValue -Object $ultimate -Name 'afterTargetConfirmDelayMilliseconds' -DefaultValue $afterTargetConfirmDelayMilliseconds
            $afterAutoBuyCarDelayMilliseconds = Get-UltimateConfigIntValue -Object $ultimate -Name 'afterAutoBuyCarDelayMilliseconds' -DefaultValue $afterAutoBuyCarDelayMilliseconds
            $workflowLoopCount = Get-UltimateConfigIntValue -Object $ultimate -Name 'workflowLoopCount' -DefaultValue $workflowLoopCount
            $betweenWorkflowLoopsMilliseconds = Get-UltimateConfigIntValue -Object $ultimate -Name 'betweenWorkflowLoopsMilliseconds' -DefaultValue $betweenWorkflowLoopsMilliseconds
            $sequenceLoopCount = Get-UltimateConfigIntValue -Object $ultimate -Name 'sequenceLoopCount' -DefaultValue $sequenceLoopCount
            $searchKey = Normalize-AfkKeyName -Key (Get-UltimateConfigStringValue -Object $ultimate -Name 'searchKey' -DefaultValue $searchKey)
            $searchSettleMilliseconds = Get-UltimateConfigIntValue -Object $ultimate -Name 'searchSettleMilliseconds' -DefaultValue $searchSettleMilliseconds
            $maxSearchAttempts = Get-UltimateConfigIntValue -Object $ultimate -Name 'maxSearchAttempts' -DefaultValue $maxSearchAttempts
            $verticalScanSteps = Get-UltimateConfigIntValue -Object $ultimate -Name 'verticalScanSteps' -DefaultValue $verticalScanSteps

            if ((Test-UltimateConfigProperty -Object $ultimate -Name 'targetKeywords') -and $null -ne $ultimate.targetKeywords) {
                $targetKeywords = @($ultimate.targetKeywords | ForEach-Object { [string]$_ })
            }

            if ((Test-UltimateConfigProperty -Object $ultimate -Name 'familyKeywords') -and $null -ne $ultimate.familyKeywords) {
                $familyKeywords = @($ultimate.familyKeywords | ForEach-Object { [string]$_ })
            }

            if ((Test-UltimateConfigProperty -Object $ultimate -Name 'sequence') -and $null -ne $ultimate.sequence) {
                $sequence = $ultimate.sequence
                $sequenceEnterDelaySeconds = Get-UltimateConfigIntValue -Object $sequence -Name 'enterDelaySeconds' -DefaultValue $sequenceEnterDelaySeconds
                $sequenceXDelayMilliseconds = Get-UltimateConfigIntValue -Object $sequence -Name 'xDelayMilliseconds' -DefaultValue $sequenceXDelayMilliseconds
                $sequenceLoopDelaySeconds = Get-UltimateConfigIntValue -Object $sequence -Name 'loopDelaySeconds' -DefaultValue $sequenceLoopDelaySeconds
            }

            if ((Test-UltimateConfigProperty -Object $ultimate -Name 'gamepadThrottle') -and $null -ne $ultimate.gamepadThrottle) {
                $gamepad = $ultimate.gamepadThrottle
                if ((Test-UltimateConfigProperty -Object $gamepad -Name 'enabled') -and $null -ne $gamepad.enabled) {
                    $gamepadThrottleEnabled = [bool]$gamepad.enabled
                }
                $gamepadRightTriggerValue = Get-UltimateConfigIntValue -Object $gamepad -Name 'rightTriggerValue' -DefaultValue $gamepadRightTriggerValue
                $gamepadDllPath = Get-UltimateConfigStringValue -Object $gamepad -Name 'dllPath' -DefaultValue $gamepadDllPath
            }
        }
    }

    $nonNegativeChecks = @(
        @{ Name = 'ultimate.startupDelaySeconds'; Value = $startupDelaySeconds },
        @{ Name = 'ultimate.keyTapHoldMilliseconds'; Value = $keyTapHoldMilliseconds },
        @{ Name = 'ultimate.digitIntervalMilliseconds'; Value = $digitIntervalMilliseconds },
        @{ Name = 'ultimate.afterTargetSelectDelayMilliseconds'; Value = $afterTargetSelectDelayMilliseconds },
        @{ Name = 'ultimate.afterTargetConfirmDelayMilliseconds'; Value = $afterTargetConfirmDelayMilliseconds },
        @{ Name = 'ultimate.afterAutoBuyCarDelayMilliseconds'; Value = $afterAutoBuyCarDelayMilliseconds },
        @{ Name = 'ultimate.betweenWorkflowLoopsMilliseconds'; Value = $betweenWorkflowLoopsMilliseconds },
        @{ Name = 'ultimate.sequence.enterDelaySeconds'; Value = $sequenceEnterDelaySeconds },
        @{ Name = 'ultimate.sequence.xDelayMilliseconds'; Value = $sequenceXDelayMilliseconds },
        @{ Name = 'ultimate.sequence.loopDelaySeconds'; Value = $sequenceLoopDelaySeconds },
        @{ Name = 'ultimate.searchSettleMilliseconds'; Value = $searchSettleMilliseconds },
        @{ Name = 'ultimate.verticalScanSteps'; Value = $verticalScanSteps }
    )
    foreach ($check in $nonNegativeChecks) {
        if ($check.Value -lt 0) {
            throw "Config value '$($check.Name)' cannot be negative."
        }
    }

    if ($sequenceLoopCount -lt 1) { throw "Config value 'ultimate.sequenceLoopCount' must be at least 1." }
    if ($workflowLoopCount -lt 0) { throw "Config value 'ultimate.workflowLoopCount' cannot be negative (0 = infinite; >=1 = number of full Ultimate runs)." }
    if ($maxSearchAttempts -lt 0) { throw "Config value 'ultimate.maxSearchAttempts' cannot be negative (0 = unlimited; the search stops after one full loop of the list)." }
    if ($targetKeywords.Count -lt 1) { throw "Config value 'ultimate.targetKeywords' must contain at least one item." }
    if ($familyKeywords.Count -lt 1) { throw "Config value 'ultimate.familyKeywords' must contain at least one item." }
    if (@('SendKeys', 'SendInputScanCode', 'SendInputVirtualKey') -notcontains $inputMethod) {
        throw "Config value 'ultimate.inputMethod' must be SendKeys, SendInputScanCode, or SendInputVirtualKey."
    }
    if ($shareCode -notmatch '^\d+$') {
        throw "Config value 'ultimate.shareCode' must contain digits only."
    }
    if ($gamepadRightTriggerValue -lt 0 -or $gamepadRightTriggerValue -gt 255) {
        throw "Config value 'ultimate.gamepadThrottle.rightTriggerValue' must be between 0 and 255."
    }

    [pscustomobject]@{
        ConfigPath                           = $configPath
        StartupDelaySeconds                  = $startupDelaySeconds
        InputMethod                          = $inputMethod
        KeyTapHoldMilliseconds               = $keyTapHoldMilliseconds
        PreludeSteps                         = @(Get-DefaultUltimatePreludeSteps)
        AfterCodeSteps                       = @(Get-DefaultUltimateAfterCodeSteps)
        PostSequenceSteps                    = @(Get-DefaultUltimatePostSequenceSteps)
        PostBuySteps                         = @(Get-DefaultUltimatePostBuySteps)
        ShareCode                            = $shareCode
        DigitIntervalMilliseconds            = $digitIntervalMilliseconds
        AfterTargetSelectDelayMilliseconds   = $afterTargetSelectDelayMilliseconds
        AfterTargetConfirmDelayMilliseconds  = $afterTargetConfirmDelayMilliseconds
        AfterAutoBuyCarDelayMilliseconds     = $afterAutoBuyCarDelayMilliseconds
        WorkflowLoopCount                    = $workflowLoopCount
        BetweenWorkflowLoopsMilliseconds     = $betweenWorkflowLoopsMilliseconds
        SequenceLoopCount                    = $sequenceLoopCount
        SequenceEnterDelaySeconds            = $sequenceEnterDelaySeconds
        SequenceXDelayMilliseconds           = $sequenceXDelayMilliseconds
        SequenceLoopDelaySeconds             = $sequenceLoopDelaySeconds
        TargetKeywords                       = @($targetKeywords)
        FamilyKeywords                       = @($familyKeywords)
        SearchKey                            = $searchKey
        SearchSettleMilliseconds             = $searchSettleMilliseconds
        MaxSearchAttempts                    = $maxSearchAttempts
        VerticalScanSteps                    = $verticalScanSteps
        GamepadThrottleEnabled               = $gamepadThrottleEnabled
        GamepadRightTriggerValue             = $gamepadRightTriggerValue
        GamepadDllPath                       = $gamepadDllPath
    }
}

function Resolve-UltimateRuntimeOptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config,
        [int]$StartupDelaySeconds = -1,
        [int]$SequenceLoopCount = -1,
        [int]$AutoBuyCarLoopCount = -1,
        [int]$FindNewSubaruLoopCount = -1,
        [int]$StartFromStep = -1,
        [int]$WorkflowLoopCount = -1
    )

    $resolvedStartupDelaySeconds = if ($StartupDelaySeconds -ge 0) { $StartupDelaySeconds } else { $Config.StartupDelaySeconds }
    $resolvedSequenceLoopCount = if ($SequenceLoopCount -ge 1) { $SequenceLoopCount } else { $Config.SequenceLoopCount }
    # Whole-workflow repeat count. 0 = infinite, >=1 = fixed runs. -1 (CLI default) means
    # "not supplied" -> fall back to config. 0 IS a valid supplied value, so guard on -ge 0.
    $resolvedWorkflowLoopCount = if ($WorkflowLoopCount -ge 0) { $WorkflowLoopCount } else { $Config.WorkflowLoopCount }

    if ($resolvedStartupDelaySeconds -lt 0) { throw 'Ultimate startup delay cannot be negative.' }
    if ($resolvedSequenceLoopCount -lt 1) { throw 'Ultimate sequence loop count must be at least 1.' }
    if ($resolvedWorkflowLoopCount -lt 0) { throw 'Ultimate workflow loop count cannot be negative (0 = infinite).' }

    # Debug aid: StartFromStep lets a later phase be tested in isolation. It matches the
    # top-level step numbers in ULTIMATE.md (5=Prelude ... 14=FindNewSubaru); steps 0-4 are
    # infrastructure (DPI, mutual-exclusion, window capture, startup countdown) and always
    # run. -1/0/<5 means "no skipping" -> start from the first phase (full run).
    $resolvedStartFromStep = if ($StartFromStep -ge 5) { $StartFromStep } else { 5 }
    if ($resolvedStartFromStep -gt 14) { throw 'Ultimate StartFromStep must be between 5 and 14 (matches the ULTIMATE.md step table).' }

    [pscustomobject]@{
        StartupDelaySeconds                 = $resolvedStartupDelaySeconds
        InputMethod                         = $Config.InputMethod
        KeyTapHoldMilliseconds              = $Config.KeyTapHoldMilliseconds
        PreludeSteps                        = @($Config.PreludeSteps)
        AfterCodeSteps                      = @($Config.AfterCodeSteps)
        PostSequenceSteps                   = @($Config.PostSequenceSteps)
        PostBuySteps                        = @($Config.PostBuySteps)
        AutoBuyCarLoopCount                 = $AutoBuyCarLoopCount
        FindNewSubaruLoopCount              = $FindNewSubaruLoopCount
        StartFromStep                       = $resolvedStartFromStep
        ShareCode                           = $Config.ShareCode
        DigitIntervalMilliseconds           = $Config.DigitIntervalMilliseconds
        AfterTargetSelectDelayMilliseconds  = $Config.AfterTargetSelectDelayMilliseconds
        AfterTargetConfirmDelayMilliseconds = $Config.AfterTargetConfirmDelayMilliseconds
        AfterAutoBuyCarDelayMilliseconds    = $Config.AfterAutoBuyCarDelayMilliseconds
        WorkflowLoopCount                   = $resolvedWorkflowLoopCount
        BetweenWorkflowLoopsMilliseconds    = $Config.BetweenWorkflowLoopsMilliseconds
        SequenceLoopCount                   = $resolvedSequenceLoopCount
        SequenceEnterDelaySeconds           = $Config.SequenceEnterDelaySeconds
        SequenceXDelayMilliseconds          = $Config.SequenceXDelayMilliseconds
        SequenceLoopDelaySeconds            = $Config.SequenceLoopDelaySeconds
        TargetKeywords                      = @($Config.TargetKeywords)
        FamilyKeywords                      = @($Config.FamilyKeywords)
        SearchKey                           = $Config.SearchKey
        SearchSettleMilliseconds            = $Config.SearchSettleMilliseconds
        MaxSearchAttempts                   = $Config.MaxSearchAttempts
        VerticalScanSteps                   = $Config.VerticalScanSteps
        GamepadThrottleEnabled              = $Config.GamepadThrottleEnabled
        GamepadRightTriggerValue            = $Config.GamepadRightTriggerValue
        GamepadDllPath                      = $Config.GamepadDllPath
    }
}

function Set-UltimatePid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths
    )

    Initialize-UltimateWorkspace -Paths $Paths
    Set-Content -LiteralPath $Paths.PidPath -Value ([string]$PID) -Encoding ASCII
}

function Remove-UltimatePid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths
    )

    if (Test-Path -LiteralPath $Paths.PidPath -PathType Leaf) {
        Remove-Item -LiteralPath $Paths.PidPath -Force
    }
}

function Get-UltimateAutoBuyCount {
    # Cumulative number of cars the Ultimate AutoBuyCar phase has bought, persisted in
    # runtime/ so it survives across runs and GUI restarts. Reset only via the GUI Clear
    # button (Reset-UltimateAutoBuyCount). Returns 0 when the file is missing/unreadable.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths
    )

    if (-not (Test-Path -LiteralPath $Paths.AutoBuyCountPath -PathType Leaf)) {
        return 0
    }

    $text = (Get-Content -LiteralPath $Paths.AutoBuyCountPath -ErrorAction SilentlyContinue | Select-Object -First 1)
    $value = 0
    if ([int]::TryParse(([string]$text).Trim(), [ref]$value) -and $value -ge 0) {
        return $value
    }
    return 0
}

function Set-UltimateAutoBuyCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)][int]$Count
    )

    Initialize-UltimateWorkspace -Paths $Paths
    if ($Count -lt 0) { $Count = 0 }
    Set-Content -LiteralPath $Paths.AutoBuyCountPath -Value ([string]$Count) -Encoding ASCII
    return $Count
}

function Add-UltimateAutoBuyCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [int]$Count = 1
    )

    $current = Get-UltimateAutoBuyCount -Paths $Paths
    return (Set-UltimateAutoBuyCount -Paths $Paths -Count ($current + $Count))
}

function Reset-UltimateAutoBuyCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths
    )

    return (Set-UltimateAutoBuyCount -Paths $Paths -Count 0)
}

function Format-UltimateDuration {
    # Human-friendly duration. e.g. 3725 -> "1h 2m 5s", 65 -> "1m 5s", 8 -> "8s".
    [CmdletBinding()]
    param(
        [double]$Seconds
    )

    if ($Seconds -lt 0) { $Seconds = 0 }
    $total = [int][Math]::Round($Seconds)
    $h = [int][Math]::Floor($total / 3600)
    $m = [int][Math]::Floor(($total % 3600) / 60)
    $s = $total % 60
    $parts = @()
    if ($h -gt 0) { $parts += ("{0}h" -f $h) }
    if ($m -gt 0) { $parts += ("{0}m" -f $m) }
    if ($s -gt 0 -or $parts.Count -eq 0) { $parts += ("{0}s" -f $s) }
    return ($parts -join ' ')
}

function Get-UltimateEstimatedLoopSeconds {
    # Rough estimate of ONE full Ultimate iteration (steps 5-14) in seconds, from the
    # deterministic waits. The vision phases (target search, FindNewSubaru) are not
    # time-deterministic, so they get coarse fixed allowances. The result is approximate and
    # gets refined by measured per-loop timing once the first loop completes. Assumes a full
    # run (StartFromStep=5); a debug StartFromStep>5 makes this an overestimate (measured fixes it).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Options,
        [Parameter(Mandatory = $true)]$AutoBuyCarOptions,
        [Parameter(Mandatory = $true)]$FindNewSubaruOptions
    )

    $ms = 0.0

    # Macro phases (5 Prelude, 7 AfterCode, 11 PostSequence, 13 PostBuy): sum of waits.
    foreach ($stepSet in @($Options.PreludeSteps, $Options.AfterCodeSteps, $Options.PostSequenceSteps, $Options.PostBuySteps)) {
        foreach ($step in @($stepSet)) { $ms += [double]$step.WaitMilliseconds }
    }

    # Step 6 share code: gaps between digits.
    $digits = ([string]$Options.ShareCode).Length
    if ($digits -gt 1) { $ms += ($digits - 1) * [double]$Options.DigitIntervalMilliseconds }

    # Step 9 target confirm: the two post-select waits.
    $ms += [double]$Options.AfterTargetSelectDelayMilliseconds
    $ms += [double]$Options.AfterTargetConfirmDelayMilliseconds

    # Step 10 Sequence loops: N * (Enter wait + 2*X wait + loop wait).
    $perSequenceMs = ([double]$Options.SequenceEnterDelaySeconds * 1000) + (2 * [double]$Options.SequenceXDelayMilliseconds) + ([double]$Options.SequenceLoopDelaySeconds * 1000)
    $ms += [double]$Options.SequenceLoopCount * $perSequenceMs

    # Step 12->13 inter-phase settle delay.
    $ms += [double]$Options.AfterAutoBuyCarDelayMilliseconds

    # Step 12 AutoBuyCar: M loops of its steps + between-loop gaps.
    $autoSteps = 0.0
    foreach ($step in @($AutoBuyCarOptions.AutoBuyCarSteps)) { $autoSteps += [double]$step.WaitMilliseconds }
    $m = [int]$AutoBuyCarOptions.LoopCount
    if ($m -lt 1) { $m = 1 }
    $ms += $m * $autoSteps
    if ($m -gt 1) { $ms += ($m - 1) * [double]$AutoBuyCarOptions.AutoBuyCarBetweenLoopsMilliseconds }

    # Coarse allowances for the vision phases (8 target search, 14 FindNewSubaru) - ~45s each.
    $ms += 45000.0
    $k = [int]$FindNewSubaruOptions.LoopCount
    if ($k -lt 1) { $k = 1 }
    $ms += $k * 45000.0

    return ($ms / 1000.0)
}

function Set-UltimateProgress {
    # Snapshot of outer-loop progress, written by the worker and read by the GUI to display
    # the running loop count / ETA. Lives in runtime/ultimate-progress.json.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)][string]$Status,
        [int]$CurrentLoop = 0,
        [int]$TotalLoops = 0,
        [string]$DisplayText = '',
        [string]$Updated = ''
    )

    Initialize-UltimateWorkspace -Paths $Paths
    $obj = [pscustomobject]@{
        status      = $Status
        currentLoop = $CurrentLoop
        totalLoops  = $TotalLoops
        displayText = $DisplayText
        updated     = $Updated
    }
    Set-Content -LiteralPath $Paths.ProgressPath -Value ($obj | ConvertTo-Json -Compress) -Encoding UTF8
}

function Get-UltimateProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths
    )

    if (-not (Test-Path -LiteralPath $Paths.ProgressPath -PathType Leaf)) {
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $Paths.ProgressPath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $obj = $raw | ConvertFrom-Json
        return [pscustomobject]@{
            Status      = if (Test-UltimateConfigProperty -Object $obj -Name 'status') { [string]$obj.status } else { '' }
            CurrentLoop = if (Test-UltimateConfigProperty -Object $obj -Name 'currentLoop') { [int]$obj.currentLoop } else { 0 }
            TotalLoops  = if (Test-UltimateConfigProperty -Object $obj -Name 'totalLoops') { [int]$obj.totalLoops } else { 0 }
            DisplayText = if (Test-UltimateConfigProperty -Object $obj -Name 'displayText') { [string]$obj.displayText } else { '' }
            Updated     = if (Test-UltimateConfigProperty -Object $obj -Name 'updated') { [string]$obj.updated } else { '' }
        }
    }
    catch {
        return $null
    }
}

function Clear-UltimateProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths
    )

    if (Test-Path -LiteralPath $Paths.ProgressPath -PathType Leaf) {
        Remove-Item -LiteralPath $Paths.ProgressPath -Force -ErrorAction SilentlyContinue
    }
}

# Pause flag file (runtime/ultimate.pause). The GUI writes it to request a pause and deletes
# it to resume; the detached worker polls it at safe loop boundaries (see Wait-UltimatePauseGate
# in RunUltimate.ps1). This is the same file-based control channel as the pid/progress files --
# the only way the GUI can signal the separate worker process.
function Set-UltimatePause {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths
    )

    Initialize-UltimateWorkspace -Paths $Paths
    Set-Content -LiteralPath $Paths.PausePath -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Encoding ASCII
}

function Clear-UltimatePause {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths
    )

    if (Test-Path -LiteralPath $Paths.PausePath -PathType Leaf) {
        Remove-Item -LiteralPath $Paths.PausePath -Force -ErrorAction SilentlyContinue
    }
}

function Test-UltimatePause {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths
    )

    return [bool](Test-Path -LiteralPath $Paths.PausePath -PathType Leaf)
}

function Get-UltimateState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths
    )

    if (-not (Test-Path -LiteralPath $Paths.PidPath -PathType Leaf)) {
        return [pscustomobject]@{
            Status      = 'Stopped'
            Pid         = $null
            Process     = $null
            CommandLine = $null
            Message     = 'Ultimate is not running.'
        }
    }

    $pidText = (Get-Content -LiteralPath $Paths.PidPath -ErrorAction SilentlyContinue | Select-Object -First 1)
    $ultimatePid = 0
    if (-not [int]::TryParse(([string]$pidText).Trim(), [ref]$ultimatePid)) {
        return [pscustomobject]@{
            Status      = 'InvalidPid'
            Pid         = $null
            Process     = $null
            CommandLine = $null
            Message     = "PID file is invalid: $($Paths.PidPath)"
        }
    }

    $process = Get-Process -Id $ultimatePid -ErrorAction SilentlyContinue
    if (-not $process) {
        return [pscustomobject]@{
            Status      = 'Stale'
            Pid         = $ultimatePid
            Process     = $null
            CommandLine = $null
            Message     = "PID file is stale. Process $ultimatePid is not running."
        }
    }

    $commandLine = $null
    try {
        $cim = Get-CimInstance Win32_Process -Filter "ProcessId = $ultimatePid" -ErrorAction Stop
        $commandLine = $cim.CommandLine
    }
    catch {
        try {
            $wmi = Get-WmiObject Win32_Process -Filter "ProcessId = $ultimatePid" -ErrorAction Stop
            $commandLine = $wmi.CommandLine
        }
        catch {
            $commandLine = $null
        }
    }

    $normalizedCommand = if ($commandLine) { $commandLine.ToLowerInvariant() } else { '' }
    $isUltimate = $normalizedCommand.Contains('runultimate.ps1')

    if ($isUltimate) {
        return [pscustomobject]@{
            Status      = 'Running'
            Pid         = $ultimatePid
            Process     = $process
            CommandLine = $commandLine
            Message     = "Ultimate is running. PID=$ultimatePid"
        }
    }

    if ([string]::IsNullOrWhiteSpace($commandLine)) {
        return [pscustomobject]@{
            Status      = 'RunningUnverified'
            Pid         = $ultimatePid
            Process     = $process
            CommandLine = $commandLine
            Message     = "Ultimate appears to be running, but process command line could not be verified. PID=$ultimatePid"
        }
    }

    [pscustomobject]@{
        Status      = 'ForeignPid'
        Pid         = $ultimatePid
        Process     = $process
        CommandLine = $commandLine
        Message     = "PID file points to a process that does not look like Ultimate. PID=$ultimatePid"
    }
}

function Remove-StaleUltimatePid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths,
        $State
    )

    if ($State.Status -in @('Stale', 'InvalidPid', 'ForeignPid')) {
        Remove-UltimatePid -Paths $Paths
    }
}

function ConvertTo-UltimateMatchKey {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Value
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    $text = $Value.ToLowerInvariant()
    # Fold the glyphs Windows OCR most often confuses BEFORE dropping punctuation,
    # so that e.g. the digit "1" read back as "i", "l", "|" or "!" still compares
    # equal. This is what makes the keyword "S1" match an OCR result of "SI'", and the
    # performance value "790" match an OCR result of "7g0" (9 misread as g/q). Only
    # letter->digit lookalikes are folded — never digit->digit — so two distinct numbers
    # (e.g. 790 vs 990, 1998 vs 1990) never collapse into each other.
    $text = $text -replace '[il|!]', '1'
    $text = $text -replace '[o]', '0'
    $text = $text -replace '[gq]', '9'
    # Keep only letters (incl. CJK) and digits; OCR stray spaces, apostrophes and
    # other punctuation must never break a match.
    $text = $text -replace '[^\p{L}\p{Nd}]', ''
    return $text
}

function Test-UltimateTargetTextMatch {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string[]]$Keywords
    )

    # Exact substring match after normalization. OCR tolerance is handled entirely by the
    # glyph folding in ConvertTo-UltimateMatchKey (letter-shaped digits -> digits, e.g.
    # 7g0 -> 790). We deliberately do NOT do edit-distance/fuzzy matching here: a numeric
    # value like 790 is only 1 edit from 990 (inside "1990") and 1998 is 1 edit from 1990,
    # so fuzzy matching falsely selected a 1990 Legacy. Folding only fixes genuine
    # letter<->digit OCR confusion without bridging two different numbers.
    $normalizedText = ConvertTo-UltimateMatchKey -Value $Text
    $missingKeywords = @()
    foreach ($keyword in $Keywords) {
        $normalizedKeyword = ConvertTo-UltimateMatchKey -Value ([string]$keyword)
        if ([string]::IsNullOrEmpty($normalizedKeyword)) {
            continue
        }
        if (-not $normalizedText.Contains($normalizedKeyword)) {
            $missingKeywords += [string]$keyword
        }
    }

    [pscustomobject]@{
        Match   = ($missingKeywords.Count -eq 0)
        Mode    = if ($missingKeywords.Count -eq 0) { 'Strict' } else { 'None' }
        Missing = @($missingKeywords)
        Text    = $Text
        Reason  = if ($missingKeywords.Count -eq 0) { 'All target keywords matched.' } else { "Missing target keywords: $($missingKeywords -join ', ')" }
    }
}

function Test-UltimateSelectedCar {
    [CmdletBinding()]
    param(
        [Int64]$WindowHandle = 0,
        [string]$ImagePath,
        [Parameter(Mandatory = $true)][string[]]$TargetKeywords,
        [string[]]$FamilyKeywords = @(),
        [Parameter(Mandatory = $true)][string]$TempRoot
    )

    $bitmap = $null
    $cropPath = $null
    try {
        if (-not [string]::IsNullOrWhiteSpace($ImagePath)) {
            $bitmap = Get-AutomationBitmapFromPath -ImagePath $ImagePath
        }
        else {
            if ($WindowHandle -eq 0) {
                throw 'Window handle is required when RecognitionImagePath is not provided.'
            }
            $bitmap = New-AutomationWindowBitmap -WindowHandle $WindowHandle
        }

        $bitmapWidth = $bitmap.Width
        $bitmapHeight = $bitmap.Height

        $highlight = Find-AutomationHighlightedCard -Bitmap $bitmap
        if (-not $highlight.Found) {
            return [pscustomobject]@{
                Match        = $false
                Reason       = 'Highlighted card was not found.'
                OcrSuccess   = $false
                OcrText      = ''
                MatchMode    = 'NoHighlight'
                IsFamily     = $false
                Rect         = $highlight
                BitmapWidth  = $bitmapWidth
                BitmapHeight = $bitmapHeight
            }
        }

        if (-not (Test-Path -LiteralPath $TempRoot -PathType Container)) {
            New-Item -Path $TempRoot -ItemType Directory -Force | Out-Null
        }
        $cropPath = Join-Path $TempRoot ("ultimate-card-{0}.png" -f ([guid]::NewGuid().ToString('N')))
        Save-AutomationBitmapCrop -Bitmap $bitmap -Rect $highlight -Path $cropPath
        $ocr = Invoke-AutomationOcrImagePath -ImagePath $cropPath
        if (-not $ocr.Success) {
            return [pscustomobject]@{
                Match        = $false
                Reason       = "OCR failed. Error=$($ocr.Error)"
                OcrSuccess   = $false
                OcrText      = ''
                MatchMode    = 'OcrFailed'
                IsFamily     = $false
                Rect         = $highlight
                BitmapWidth  = $bitmapWidth
                BitmapHeight = $bitmapHeight
            }
        }

        $match = Test-UltimateTargetTextMatch -Text ([string]$ocr.Text) -Keywords $TargetKeywords
        $isFamily = $false
        if ($FamilyKeywords -and $FamilyKeywords.Count -gt 0) {
            $isFamily = (Test-UltimateTargetTextMatch -Text ([string]$ocr.Text) -Keywords $FamilyKeywords).Match
        }
        return [pscustomobject]@{
            Match        = [bool]$match.Match
            Reason       = $match.Reason
            OcrSuccess   = $true
            OcrText      = [string]$ocr.Text
            MatchMode    = $match.Mode
            Missing      = @($match.Missing)
            IsFamily     = [bool]$isFamily
            Rect         = $highlight
            BitmapWidth  = $bitmapWidth
            BitmapHeight = $bitmapHeight
        }
    }
    finally {
        if ($bitmap) {
            $bitmap.Dispose()
        }
        if ($cropPath -and (Test-Path -LiteralPath $cropPath -PathType Leaf)) {
            Remove-Item -LiteralPath $cropPath -Force -ErrorAction SilentlyContinue
        }
    }
}
