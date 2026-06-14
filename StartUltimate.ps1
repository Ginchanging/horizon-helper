[CmdletBinding()]
param(
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
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
. (Join-Path $scriptRoot 'scripts\AfkLib.ps1')
. (Join-Path $scriptRoot 'scripts\AutomationLib.ps1')
. (Join-Path $scriptRoot 'scripts\UltimateLib.ps1')

$paths = Get-UltimatePaths -AppRoot $scriptRoot
Initialize-UltimateWorkspace -Paths $paths
$config = Get-UltimateConfig -AppRoot $scriptRoot
$options = Resolve-UltimateRuntimeOptions -Config $config -StartupDelaySeconds $StartupDelaySeconds -SequenceLoopCount $SequenceLoopCount -AutoBuyCarLoopCount $AutoBuyCarLoopCount -FindNewSubaruLoopCount $FindNewSubaruLoopCount -StartFromStep $StartFromStep -WorkflowLoopCount $WorkflowLoopCount

$state = Get-UltimateState -Paths $paths
if ($state.Status -in @('Running', 'RunningUnverified')) {
    Write-Host $state.Message
    exit 0
}
Remove-StaleUltimatePid -Paths $paths -State $state

$automationPaths = Get-AutomationPaths -AppRoot $scriptRoot
Initialize-AutomationWorkspace -Paths $automationPaths
$automationState = Get-AutomationState -Paths $automationPaths
if ($automationState.Status -in @('Running', 'RunningUnverified')) {
    Write-Error "Automation is already running. Stop Automation before starting Ultimate. Automation PID=$($automationState.Pid)"
    exit 1
}

$workerScript = Join-Path $scriptRoot 'scripts\RunUltimate.ps1'
$argumentList = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-STA',
    '-File', ('"{0}"' -f $workerScript),
    '-AppRoot', ('"{0}"' -f $scriptRoot),
    '-StartupDelaySeconds', ([string]$options.StartupDelaySeconds),
    '-SequenceLoopCount', ([string]$options.SequenceLoopCount),
    '-AutoBuyCarLoopCount', ([string]$options.AutoBuyCarLoopCount),
    '-FindNewSubaruLoopCount', ([string]$options.FindNewSubaruLoopCount),
    '-StartFromStep', ([string]$options.StartFromStep),
    '-WorkflowLoopCount', ([string]$options.WorkflowLoopCount)
)
if (-not [string]::IsNullOrWhiteSpace($RecognitionImagePath)) {
    $argumentList += @('-RecognitionImagePath', ('"{0}"' -f $RecognitionImagePath))
}
if ($AssumeTargetFound) {
    $argumentList += '-AssumeTargetFound'
}
if ($DryRun) {
    $argumentList += '-DryRun'
}

$process = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -WindowStyle Hidden -PassThru
$newState = $null
for ($attempt = 1; $attempt -le 10; $attempt++) {
    Start-Sleep -Milliseconds 300
    $newState = Get-UltimateState -Paths $paths
    $process.Refresh()
    if ($newState.Status -in @('Running', 'RunningUnverified') -or $process.HasExited) {
        break
    }
}

if ($newState -and $newState.Status -in @('Running', 'RunningUnverified')) {
    Write-Host "Ultimate started. PID=$($newState.Pid)"
    Write-Host "Startup delay: $($options.StartupDelaySeconds) seconds"
    Write-Host "Input method: $($options.InputMethod)"
    Write-Host "Share code: $($options.ShareCode)"
    Write-Host "Target keywords: $($options.TargetKeywords -join ', ')"
    Write-Host "Workflow loops: $(if ($options.WorkflowLoopCount -le 0) { 'infinite (run until stopped)' } else { $options.WorkflowLoopCount })"
    Write-Host "Sequence loops: $($options.SequenceLoopCount)"
    Write-Host "Sequence timing: EnterDelay=$($options.SequenceEnterDelaySeconds)s XDelay=$($options.SequenceXDelayMilliseconds)ms LoopDelay=$($options.SequenceLoopDelaySeconds)s"
    if ($options.StartFromStep -gt 5) {
        Write-Host "Debug: starting at step $($options.StartFromStep) (earlier steps skipped)."
    }
    if ($DryRun) {
        Write-Host 'DryRun is enabled. No keys will be sent and waits are skipped.'
    }
    Write-Host "Log: $($paths.LogPath)"
    exit 0
}

$process.Refresh()
if ($process.HasExited) {
    if ($process.ExitCode -eq 0) {
        Write-Host "Ultimate completed quickly. ExitCode=0"
        Write-Host "Log: $($paths.LogPath)"
        exit 0
    }

    Write-Error "Ultimate process exited early. ExitCode=$($process.ExitCode). Check log: $($paths.LogPath)"
    exit 1
}

Write-Host "Ultimate process started. PID=$($process.Id)"
Write-Host 'Status is still initializing. Check again with StatusUltimate.ps1.'
