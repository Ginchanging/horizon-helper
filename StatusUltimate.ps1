[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
. (Join-Path $scriptRoot 'scripts\AfkLib.ps1')
. (Join-Path $scriptRoot 'scripts\AutomationLib.ps1')
. (Join-Path $scriptRoot 'scripts\UltimateLib.ps1')

$paths = Get-UltimatePaths -AppRoot $scriptRoot
Initialize-UltimateWorkspace -Paths $paths
$config = Get-UltimateConfig -AppRoot $scriptRoot
$options = Resolve-UltimateRuntimeOptions -Config $config
$state = Get-UltimateState -Paths $paths

Write-Host "Status: $($state.Status)"
Write-Host $state.Message
Write-Host "Startup delay: $($options.StartupDelaySeconds) seconds"
Write-Host "Input method: $($options.InputMethod)"
Write-Host "Share code: $($options.ShareCode)"
Write-Host "Digit interval: $($options.DigitIntervalMilliseconds) ms"
Write-Host "Target keywords: $($options.TargetKeywords -join ', ')"
Write-Host "Search key: $($options.SearchKey)"
Write-Host "Max search attempts: $($options.MaxSearchAttempts)"
Write-Host "Vertical scan steps: $($options.VerticalScanSteps)"
Write-Host "After target select delay: $($options.AfterTargetSelectDelayMilliseconds) ms"
Write-Host "After target confirm delay: $($options.AfterTargetConfirmDelayMilliseconds) ms"
Write-Host "Sequence loops: $($options.SequenceLoopCount)"
Write-Host "Sequence timing: EnterDelay=$($options.SequenceEnterDelaySeconds)s XDelay=$($options.SequenceXDelayMilliseconds)ms LoopDelay=$($options.SequenceLoopDelaySeconds)s"
Write-Host "Prelude steps: $(@($options.PreludeSteps).Count)"
Write-Host "After-code steps: $(@($options.AfterCodeSteps).Count)"
Write-Host "Log: $($paths.LogPath)"

if (Test-Path -LiteralPath $paths.LogPath -PathType Leaf) {
    Write-Host ''
    Write-Host 'Recent log:'
    Get-Content -LiteralPath $paths.LogPath -Tail 10 -Encoding UTF8
}
