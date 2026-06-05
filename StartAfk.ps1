[CmdletBinding()]
param(
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
. (Join-Path $scriptRoot 'scripts\AfkLib.ps1')
. (Join-Path $scriptRoot 'scripts\AutomationLib.ps1')
. (Join-Path $scriptRoot 'scripts\UltimateLib.ps1')

$paths = Get-AfkPaths -AppRoot $scriptRoot
Initialize-AfkWorkspace -Paths $paths
$afkConfig = Get-AfkConfig -AppRoot $scriptRoot
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

$automationPaths = Get-AutomationPaths -AppRoot $scriptRoot
Initialize-AutomationWorkspace -Paths $automationPaths
$automationState = Get-AutomationState -Paths $automationPaths
if ($automationState.Status -in @('Running', 'RunningUnverified')) {
    Write-Error "Automation is already running. Stop Automation before starting AFK. Automation PID=$($automationState.Pid)"
    exit 1
}

$ultimatePaths = Get-UltimatePaths -AppRoot $scriptRoot
Initialize-UltimateWorkspace -Paths $ultimatePaths
$ultimateState = Get-UltimateState -Paths $ultimatePaths
if ($ultimateState.Status -in @('Running', 'RunningUnverified')) {
    Write-Error "Ultimate is already running. Stop Ultimate before starting AFK. Ultimate PID=$($ultimateState.Pid)"
    exit 1
}

$state = Get-AfkState -Paths $paths
if ($state.Status -in @('Running', 'RunningUnverified')) {
    Write-Host $state.Message
    exit 0
}
Remove-StaleAfkPid -Paths $paths -State $state

$workerScript = Join-Path $scriptRoot 'scripts\RunAfk.ps1'
$argumentList = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-STA',
    '-File', ('"{0}"' -f $workerScript),
    '-AppRoot', ('"{0}"' -f $scriptRoot),
    '-Mode', $Mode,
    '-StartupDelaySeconds', ([string]$options.StartupDelaySeconds),
    '-EnterDelaySeconds', ([string]$options.EnterDelaySeconds),
    '-XDelayMilliseconds', ([string]$options.XDelayMilliseconds),
    '-LoopDelaySeconds', ([string]$options.LoopDelaySeconds),
    '-EnterOnlyDelaySeconds', ([string]$options.EnterOnlyDelaySeconds),
    '-KeyTapHoldMilliseconds', ([string]$options.KeyTapHoldMilliseconds),
    '-MacroComboCycleDelaySeconds', ([string]$options.MacroComboCycleDelaySeconds),
    '-InputMethod', $options.InputMethod
)
if ($DryRun) {
    $argumentList += '-DryRun'
}

$process = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -WindowStyle Hidden -PassThru
for ($attempt = 1; $attempt -le 10; $attempt++) {
    Start-Sleep -Milliseconds 300
    $newState = Get-AfkState -Paths $paths
    if ($newState.Status -in @('Running', 'RunningUnverified') -or $process.HasExited) {
        break
    }
}

if ($newState.Status -in @('Running', 'RunningUnverified')) {
    Write-Host "AFK started. PID=$($newState.Pid)"
    Write-Host "Mode: $Mode"
    Write-Host "Startup delay: $($options.StartupDelaySeconds) seconds"
    Write-Host "Key tap hold: $($options.KeyTapHoldMilliseconds) ms"
    Write-Host "Input method: $($options.InputMethod)"
    Write-Host "Sequence timing: EnterDelay=$($options.EnterDelaySeconds)s XDelay=$($options.XDelayMilliseconds)ms LoopDelay=$($options.LoopDelaySeconds)s"
    Write-Host "EnterEvery10s delay: $($options.EnterOnlyDelaySeconds) seconds"
    if ($Mode -eq 'MacroCombo') {
        Write-Host "MacroCombo cycle delay: $($options.MacroComboCycleDelaySeconds) seconds"
        Write-Host "MacroCombo steps: $(@($options.MacroComboSteps).Count)"
    }
    if ($options.StartupDelaySeconds -gt 0) {
        Write-Host "Switch to the game window within $($options.StartupDelaySeconds) seconds."
    }
    if ($DryRun) {
        Write-Host 'DryRun is enabled. No keys will be sent.'
    }
    Write-Host "Log: $($paths.LogPath)"
    exit 0
}

if ($process.HasExited) {
    Write-Error "AFK process exited early. Check log: $($paths.LogPath)"
    exit 1
}

Write-Host "AFK process started. PID=$($process.Id)"
Write-Host 'Status is still initializing. Check again with StatusAfk.ps1.'
