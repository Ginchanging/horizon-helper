[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
. (Join-Path $scriptRoot 'scripts\AfkLib.ps1')

$paths = Get-AfkPaths -AppRoot $scriptRoot
Initialize-AfkWorkspace -Paths $paths

$state = Get-AfkState -Paths $paths
if ($state.Status -in @('Running', 'RunningUnverified')) {
    Release-AfkKeys
    Stop-Process -Id $state.Pid -Force -ErrorAction Stop
    Start-Sleep -Milliseconds 300
    Release-AfkKeys
    Remove-AfkPid -Paths $paths
    Write-AfkLog -Paths $paths -Level 'INFO' -Message "AFK stopped by user. PID=$($state.Pid) W key released."
    Write-Host "AFK stopped. PID=$($state.Pid)"
    Write-Host 'W key released.'
    exit 0
}

Release-AfkKeys
Remove-StaleAfkPid -Paths $paths -State $state
Write-Host $state.Message
Write-Host 'W key released.'
