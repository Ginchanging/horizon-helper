[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
. (Join-Path $scriptRoot 'scripts\AfkLib.ps1')
. (Join-Path $scriptRoot 'scripts\UltimateLib.ps1')

$paths = Get-UltimatePaths -AppRoot $scriptRoot
Initialize-UltimateWorkspace -Paths $paths

$state = Get-UltimateState -Paths $paths
if ($state.Status -in @('Running', 'RunningUnverified')) {
    Release-AfkKeys
    Stop-Process -Id $state.Pid -Force -ErrorAction Stop
    Start-Sleep -Milliseconds 300
    Release-AfkKeys
    Remove-UltimatePid -Paths $paths
    Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Ultimate stopped by user. PID=$($state.Pid)"
    Write-Host "Ultimate stopped. PID=$($state.Pid)"
    exit 0
}

Release-AfkKeys
Remove-StaleUltimatePid -Paths $paths -State $state
Write-Host $state.Message
