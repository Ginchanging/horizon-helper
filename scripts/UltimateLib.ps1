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
        AppRoot     = $root
        RuntimeRoot = $runtimeRoot
        LogsRoot    = $logsRoot
        PidPath     = Join-Path $runtimeRoot 'ultimate.pid'
        LogPath     = Join-Path $logsRoot 'ultimate.log'
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
        [pscustomobject]@{ Key = 'A'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'A'; WaitMilliseconds = 500 }
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
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 15000 },
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
    $searchKey = 'Left'
    $searchSettleMilliseconds = 500
    $maxSearchAttempts = 50
    $verticalScanSteps = 2

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
        }
    }

    $nonNegativeChecks = @(
        @{ Name = 'ultimate.startupDelaySeconds'; Value = $startupDelaySeconds },
        @{ Name = 'ultimate.keyTapHoldMilliseconds'; Value = $keyTapHoldMilliseconds },
        @{ Name = 'ultimate.digitIntervalMilliseconds'; Value = $digitIntervalMilliseconds },
        @{ Name = 'ultimate.afterTargetSelectDelayMilliseconds'; Value = $afterTargetSelectDelayMilliseconds },
        @{ Name = 'ultimate.afterTargetConfirmDelayMilliseconds'; Value = $afterTargetConfirmDelayMilliseconds },
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
    if ($maxSearchAttempts -lt 0) { throw "Config value 'ultimate.maxSearchAttempts' cannot be negative (0 = unlimited; the search stops after one full loop of the list)." }
    if ($targetKeywords.Count -lt 1) { throw "Config value 'ultimate.targetKeywords' must contain at least one item." }
    if ($familyKeywords.Count -lt 1) { throw "Config value 'ultimate.familyKeywords' must contain at least one item." }
    if (@('SendKeys', 'SendInputScanCode', 'SendInputVirtualKey') -notcontains $inputMethod) {
        throw "Config value 'ultimate.inputMethod' must be SendKeys, SendInputScanCode, or SendInputVirtualKey."
    }
    if ($shareCode -notmatch '^\d+$') {
        throw "Config value 'ultimate.shareCode' must contain digits only."
    }

    [pscustomobject]@{
        ConfigPath                           = $configPath
        StartupDelaySeconds                  = $startupDelaySeconds
        InputMethod                          = $inputMethod
        KeyTapHoldMilliseconds               = $keyTapHoldMilliseconds
        PreludeSteps                         = @(Get-DefaultUltimatePreludeSteps)
        AfterCodeSteps                       = @(Get-DefaultUltimateAfterCodeSteps)
        PostSequenceSteps                    = @(Get-DefaultUltimatePostSequenceSteps)
        ShareCode                            = $shareCode
        DigitIntervalMilliseconds            = $digitIntervalMilliseconds
        AfterTargetSelectDelayMilliseconds   = $afterTargetSelectDelayMilliseconds
        AfterTargetConfirmDelayMilliseconds  = $afterTargetConfirmDelayMilliseconds
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
    }
}

function Resolve-UltimateRuntimeOptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config,
        [int]$StartupDelaySeconds = -1,
        [int]$SequenceLoopCount = -1,
        [int]$AutoBuyCarLoopCount = -1
    )

    $resolvedStartupDelaySeconds = if ($StartupDelaySeconds -ge 0) { $StartupDelaySeconds } else { $Config.StartupDelaySeconds }
    $resolvedSequenceLoopCount = if ($SequenceLoopCount -ge 1) { $SequenceLoopCount } else { $Config.SequenceLoopCount }

    if ($resolvedStartupDelaySeconds -lt 0) { throw 'Ultimate startup delay cannot be negative.' }
    if ($resolvedSequenceLoopCount -lt 1) { throw 'Ultimate sequence loop count must be at least 1.' }

    [pscustomobject]@{
        StartupDelaySeconds                 = $resolvedStartupDelaySeconds
        InputMethod                         = $Config.InputMethod
        KeyTapHoldMilliseconds              = $Config.KeyTapHoldMilliseconds
        PreludeSteps                        = @($Config.PreludeSteps)
        AfterCodeSteps                      = @($Config.AfterCodeSteps)
        PostSequenceSteps                   = @($Config.PostSequenceSteps)
        AutoBuyCarLoopCount                 = $AutoBuyCarLoopCount
        ShareCode                           = $Config.ShareCode
        DigitIntervalMilliseconds           = $Config.DigitIntervalMilliseconds
        AfterTargetSelectDelayMilliseconds  = $Config.AfterTargetSelectDelayMilliseconds
        AfterTargetConfirmDelayMilliseconds = $Config.AfterTargetConfirmDelayMilliseconds
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
