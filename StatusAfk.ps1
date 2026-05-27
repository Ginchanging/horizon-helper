[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
. (Join-Path $scriptRoot 'scripts\AfkLib.ps1')

$paths = Get-AfkPaths -AppRoot $scriptRoot
Initialize-AfkWorkspace -Paths $paths
$afkConfig = Get-AfkConfig -AppRoot $scriptRoot
$options = Resolve-AfkRuntimeOptions -Config $afkConfig

$state = Get-AfkState -Paths $paths

Write-Host "Status: $($state.Status)"
Write-Host $state.Message
Write-Host "Startup delay: $($options.StartupDelaySeconds) seconds"
Write-Host "Key tap hold: $($options.KeyTapHoldMilliseconds) ms"
Write-Host "Input method: $($options.InputMethod)"
Write-Host "Sequence timing: EnterDelay=$($options.EnterDelaySeconds)s XDelay=$($options.XDelayMilliseconds)ms LoopDelay=$($options.LoopDelaySeconds)s"
Write-Host "EnterEvery10s delay: $($options.EnterOnlyDelaySeconds) seconds"
Write-Host "MacroCombo cycle delay: $($options.MacroComboCycleDelaySeconds) seconds"
Write-Host "MacroCombo steps: $(@($options.MacroComboSteps).Count)"
Write-Host "Log: $($paths.LogPath)"

if (Test-Path -LiteralPath $paths.LogPath -PathType Leaf) {
    Write-Host ''
    Write-Host 'Recent log:'
    Get-Content -LiteralPath $paths.LogPath -Tail 10 -Encoding UTF8
}
