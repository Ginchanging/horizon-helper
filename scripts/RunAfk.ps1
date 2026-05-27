[CmdletBinding()]
param(
    [string]$AppRoot,
    [ValidateSet('Sequence', 'EnterEvery10s', 'MacroCombo')][string]$Mode = 'Sequence',
    [int]$StartupDelaySeconds = -1,
    [int]$EnterDelaySeconds = -1,
    [int]$XDelayMilliseconds = -1,
    [int]$LoopDelaySeconds = -1,
    [int]$EnterOnlyDelaySeconds = -1,
    [int]$KeyTapHoldMilliseconds = -1,
    [int]$MacroComboCycleDelaySeconds = -1,
    [ValidateSet('', 'SendKeys', 'SendInputScanCode', 'SendInputVirtualKey')][string]$InputMethod = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
. (Join-Path $scriptRoot 'AfkLib.ps1')

$paths = Get-AfkPaths -AppRoot $AppRoot
Initialize-AfkWorkspace -Paths $paths
$afkConfig = Get-AfkConfig -AppRoot $paths.AppRoot
$options = Resolve-AfkRuntimeOptions `
    -Config $afkConfig `
    -StartupDelaySeconds $StartupDelaySeconds `
    -EnterDelaySeconds $EnterDelaySeconds `
    -XDelayMilliseconds $XDelayMilliseconds `
    -LoopDelaySeconds $LoopDelaySeconds `
    -EnterOnlyDelaySeconds $EnterOnlyDelaySeconds `
    -KeyTapHoldMilliseconds $KeyTapHoldMilliseconds `
    -MacroComboCycleDelaySeconds $MacroComboCycleDelaySeconds `
    -InputMethod $InputMethod

function Invoke-AfkKeyStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$WaitMilliseconds,
        [Parameter(Mandatory = $true)][string]$StepMode
    )

    $sendResult = Send-AfkNamedKeyTap -Key $Key -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
    Write-AfkLog -Paths $paths -Level 'INFO' -Message "Sent $Name. Mode=$StepMode WaitMs=$WaitMilliseconds InputMethod=$($sendResult.Method) DryRun=$DryRun"
    if ($WaitMilliseconds -gt 0) {
        Start-Sleep -Milliseconds $WaitMilliseconds
    }
}

function Invoke-MacroComboCycle {
    $steps = @($options.MacroComboSteps)

    Write-AfkLog -Paths $paths -Level 'INFO' -Message "MacroCombo cycle started. Steps=$($steps.Count)"
    foreach ($step in $steps) {
        Invoke-AfkKeyStep -Key $step.Key -Name $step.Key -WaitMilliseconds $step.WaitMilliseconds -StepMode 'MacroCombo'
    }
    Write-AfkLog -Paths $paths -Level 'INFO' -Message 'MacroCombo cycle completed.'
}

$state = Get-AfkState -Paths $paths
if ($state.Status -in @('Running', 'RunningUnverified') -and $state.Pid -ne $PID) {
    Write-AfkLog -Paths $paths -Level 'WARN' -Message "AFK already running. Existing PID=$($state.Pid). New PID=$PID exits."
    exit 0
}

Set-AfkPid -Paths $paths

try {
    Add-Type -AssemblyName System.Windows.Forms
    Initialize-AfkNative

    Write-AfkLog -Paths $paths -Level 'INFO' -Message "AFK started. PID=$PID Mode=$Mode StartupDelay=$($options.StartupDelaySeconds) EnterDelay=$($options.EnterDelaySeconds) XDelayMs=$($options.XDelayMilliseconds) LoopDelay=$($options.LoopDelaySeconds) EnterOnlyDelay=$($options.EnterOnlyDelaySeconds) KeyTapHoldMs=$($options.KeyTapHoldMilliseconds) InputMethod=$($options.InputMethod) MacroComboCycleDelay=$($options.MacroComboCycleDelaySeconds) MacroComboSteps=$(@($options.MacroComboSteps).Count) DryRun=$DryRun"

    if ($options.StartupDelaySeconds -gt 0) {
        Start-Sleep -Seconds $options.StartupDelaySeconds
    }

    while ($true) {
        if ($Mode -eq 'EnterEvery10s') {
            $sendResult = Send-AfkNamedKeyTap -Key 'Enter' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
            Write-AfkLog -Paths $paths -Level 'INFO' -Message "Sent Enter. Mode=EnterEvery10s InputMethod=$($sendResult.Method) DryRun=$DryRun"
            Start-Sleep -Seconds $options.EnterOnlyDelaySeconds
            continue
        }

        if ($Mode -eq 'MacroCombo') {
            Invoke-MacroComboCycle
            Write-AfkLog -Paths $paths -Level 'INFO' -Message "MacroCombo cycle delay started. WaitSeconds=$($options.MacroComboCycleDelaySeconds)"
            if ($options.MacroComboCycleDelaySeconds -gt 0) {
                Start-Sleep -Seconds $options.MacroComboCycleDelaySeconds
            }
            continue
        }

        $sendResult = Send-AfkNamedKeyTap -Key 'Enter' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-AfkLog -Paths $paths -Level 'INFO' -Message "Sent Enter. Mode=Sequence InputMethod=$($sendResult.Method) DryRun=$DryRun"
        if ($options.EnterDelaySeconds -gt 0) {
            Start-Sleep -Seconds $options.EnterDelaySeconds
        }

        $sendResult = Send-AfkNamedKeyTap -Key 'X' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-AfkLog -Paths $paths -Level 'INFO' -Message "Sent x #1. Mode=Sequence InputMethod=$($sendResult.Method) DryRun=$DryRun"
        if ($options.XDelayMilliseconds -gt 0) {
            Start-Sleep -Milliseconds $options.XDelayMilliseconds
        }

        $sendResult = Send-AfkNamedKeyTap -Key 'X' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-AfkLog -Paths $paths -Level 'INFO' -Message "Sent x #2. Mode=Sequence InputMethod=$($sendResult.Method) DryRun=$DryRun"
        if ($options.XDelayMilliseconds -gt 0) {
            Start-Sleep -Milliseconds $options.XDelayMilliseconds
        }

        $sendResult = Send-AfkNamedKeyTap -Key 'Enter' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-AfkLog -Paths $paths -Level 'INFO' -Message "Sent Enter. Mode=Sequence InputMethod=$($sendResult.Method) DryRun=$DryRun"
        if ($options.LoopDelaySeconds -gt 0) {
            Start-Sleep -Seconds $options.LoopDelaySeconds
        }
    }
}
catch {
    Write-AfkLog -Paths $paths -Level 'ERROR' -Message "AFK stopped because of an error. Error=$($_.Exception.Message)"
    exit 1
}
finally {
    Release-AfkKeys -DryRun:$DryRun
    Remove-AfkPid -Paths $paths
    Write-AfkLog -Paths $paths -Level 'INFO' -Message "AFK exited. PID=$PID"
}
