[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
. (Join-Path $scriptRoot 'scripts\AfkLib.ps1')
. (Join-Path $scriptRoot 'scripts\AutomationLib.ps1')

$paths = Get-AutomationPaths -AppRoot $scriptRoot
Initialize-AutomationWorkspace -Paths $paths
$config = Get-AutomationConfig -AppRoot $scriptRoot
$autoBuyOptions = Resolve-AutomationRuntimeOptions -Config $config -Mode 'AutoBuyCar'
$deleteCarOptions = Resolve-AutomationRuntimeOptions -Config $config -Mode 'DeleteCar'
$findOptions = Resolve-AutomationRuntimeOptions -Config $config -Mode 'FindNewSubaru'
$state = Get-AutomationState -Paths $paths

Write-Host "Status: $($state.Status)"
Write-Host $state.Message
Write-Host "AutoBuyCar loop count: $($autoBuyOptions.LoopCount)"
Write-Host "Automation input method: $($autoBuyOptions.InputMethod)"
Write-Host "AutoBuyCar steps: $(@($autoBuyOptions.AutoBuyCarSteps).Count)"
Write-Host "AutoBuyCar between loops: $($autoBuyOptions.AutoBuyCarBetweenLoopsMilliseconds) ms"
Write-Host "DeleteCar loop count: $($deleteCarOptions.LoopCount)"
Write-Host "DeleteCar steps: $(@($deleteCarOptions.DeleteCarSteps).Count)"
Write-Host "DeleteCar between loops: $($deleteCarOptions.DeleteCarBetweenLoopsMilliseconds) ms"
Write-Host "FindNewSubaru loop count: $($findOptions.LoopCount)"
Write-Host "FindNewSubaru max attempts: $($findOptions.FindNewSubaruMaxSearchAttempts)"
Write-Host "FindNewSubaru search key: $($findOptions.FindNewSubaruSearchKey)"
Write-Host "FindNewSubaru after-select delay: $($findOptions.FindNewSubaruAfterSelectDelayMilliseconds) ms"
Write-Host "FindNewSubaru target keywords: $($findOptions.FindNewSubaruTargetKeywords -join ', ')"
Write-Host "Log: $($paths.LogPath)"

if (Test-Path -LiteralPath $paths.LogPath -PathType Leaf) {
    Write-Host ''
    Write-Host 'Recent log:'
    Get-Content -LiteralPath $paths.LogPath -Tail 10 -Encoding UTF8
}
