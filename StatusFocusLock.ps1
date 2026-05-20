[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
. (Join-Path $scriptRoot 'scripts\FocusLib.ps1')

$paths = Get-FocusPaths -AppRoot $scriptRoot
Initialize-FocusWorkspace -Paths $paths

$state = Get-FocusLockState -Paths $paths
$target = Get-FocusLockTarget -Paths $paths

Write-Host "Status: $($state.Status)"
Write-Host $state.Message

if ($target) {
    Write-Host "Target: [$($target.ProcessId)] $($target.ProcessName) - $($target.Title)"
    Write-Host "Window handle: $($target.HandleHex)"
    Write-Host "Interval: $($target.IntervalMilliseconds) ms"

    $currentWindow = Get-WindowInfoByHandle -WindowHandle ([Int64]$target.Handle)
    Write-Host "Target window exists: $([bool]$currentWindow)"
}
else {
    Write-Host 'Target: none'
}

Write-Host "Log: $($paths.LogPath)"
