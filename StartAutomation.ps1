[CmdletBinding()]
param(
    [ValidateSet('AutoBuyCar', 'DeleteCar', 'FindNewSubaru', 'Sequence', 'EnterEvery10s', 'MacroCombo')][string]$Mode = 'AutoBuyCar',
    [int]$LoopCount = -1,
    [int]$StartupDelaySeconds = -1,
    [string]$RecognitionImagePath,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
. (Join-Path $scriptRoot 'scripts\AfkLib.ps1')
. (Join-Path $scriptRoot 'scripts\AutomationLib.ps1')
. (Join-Path $scriptRoot 'scripts\UltimateLib.ps1')

$paths = Get-AutomationPaths -AppRoot $scriptRoot
Initialize-AutomationWorkspace -Paths $paths
$config = Get-AutomationConfig -AppRoot $scriptRoot
$options = Resolve-AutomationRuntimeOptions -Config $config -Mode $Mode -LoopCount $LoopCount -StartupDelaySeconds $StartupDelaySeconds

$state = Get-AutomationState -Paths $paths
if ($state.Status -in @('Running', 'RunningUnverified')) {
    Write-Host $state.Message
    exit 0
}
Remove-StaleAutomationPid -Paths $paths -State $state

$ultimatePaths = Get-UltimatePaths -AppRoot $scriptRoot
Initialize-UltimateWorkspace -Paths $ultimatePaths
$ultimateState = Get-UltimateState -Paths $ultimatePaths
if ($ultimateState.Status -in @('Running', 'RunningUnverified')) {
    Write-Error "Ultimate is already running. Stop Ultimate before starting Automation. Ultimate PID=$($ultimateState.Pid)"
    exit 1
}

$workerScript = Join-Path $scriptRoot 'scripts\RunAutomation.ps1'
$argumentList = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-STA',
    '-File', ('"{0}"' -f $workerScript),
    '-AppRoot', ('"{0}"' -f $scriptRoot),
    '-Mode', $Mode,
    '-LoopCount', ([string]$options.LoopCount),
    '-StartupDelaySeconds', ([string]$options.StartupDelaySeconds)
)
if (-not [string]::IsNullOrWhiteSpace($RecognitionImagePath)) {
    $argumentList += @('-RecognitionImagePath', ('"{0}"' -f $RecognitionImagePath))
}
if ($DryRun) {
    $argumentList += '-DryRun'
}

$process = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -WindowStyle Hidden -PassThru
$newState = $null
for ($attempt = 1; $attempt -le 10; $attempt++) {
    Start-Sleep -Milliseconds 300
    $newState = Get-AutomationState -Paths $paths
    if ($newState.Status -in @('Running', 'RunningUnverified') -or $process.HasExited) {
        break
    }
}

if ($newState -and $newState.Status -in @('Running', 'RunningUnverified')) {
    Write-Host "Automation started. PID=$($newState.Pid)"
Write-Host "Mode: $Mode"
Write-Host "Loop count: $($options.LoopCount)"
Write-Host "Startup delay: $($options.StartupDelaySeconds) seconds"
Write-Host "Input method: $($options.InputMethod)"
    if ($Mode -eq 'AutoBuyCar') {
        Write-Host "AutoBuyCar steps: $(@($options.AutoBuyCarSteps).Count)"
        Write-Host "Between loops: $($options.AutoBuyCarBetweenLoopsMilliseconds) ms"
    }
    elseif ($Mode -eq 'DeleteCar') {
        Write-Host "DeleteCar steps: $(@($options.DeleteCarSteps).Count)"
        Write-Host "Between loops: $($options.DeleteCarBetweenLoopsMilliseconds) ms"
    }
    else {
        Write-Host "FindNewSubaru max attempts: $($options.FindNewSubaruMaxSearchAttempts)"
        Write-Host "FindNewSubaru search key: $($options.FindNewSubaruSearchKey)"
        Write-Host "FindNewSubaru after-select delay: $($options.FindNewSubaruAfterSelectDelayMilliseconds) ms"
    }
    if ($DryRun) {
        Write-Host 'DryRun is enabled. No keys will be sent.'
    }
    Write-Host "Log: $($paths.LogPath)"
    exit 0
}

if ($process.HasExited) {
    Write-Error "Automation process exited early. Check log: $($paths.LogPath)"
    exit 1
}

Write-Host "Automation process started. PID=$($process.Id)"
Write-Host 'Status is still initializing. Check again with StatusAutomation.ps1.'
