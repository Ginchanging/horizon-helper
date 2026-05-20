[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
. (Join-Path $scriptRoot 'scripts\FocusLib.ps1')

$paths = Get-FocusPaths -AppRoot $scriptRoot
Initialize-FocusWorkspace -Paths $paths

$state = Get-FocusLockState -Paths $paths
if ($state.Status -in @('Running', 'RunningUnverified')) {
    Stop-Process -Id $state.Pid -Force -ErrorAction Stop
    Start-Sleep -Milliseconds 300
    Remove-FocusLockPid -Paths $paths
    Write-FocusLog -Paths $paths -Level 'INFO' -Message "Focus lock stopped by user. PID=$($state.Pid)"
    Write-Host "Focus lock stopped. PID=$($state.Pid)"
    exit 0
}

Remove-StaleFocusLockPid -Paths $paths -State $state
Write-Host $state.Message
