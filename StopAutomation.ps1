[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
. (Join-Path $scriptRoot 'scripts\AfkLib.ps1')
. (Join-Path $scriptRoot 'scripts\AutomationLib.ps1')

$paths = Get-AutomationPaths -AppRoot $scriptRoot
Initialize-AutomationWorkspace -Paths $paths

$state = Get-AutomationState -Paths $paths
if ($state.Status -in @('Running', 'RunningUnverified')) {
    Release-AfkKeys
    Stop-Process -Id $state.Pid -Force -ErrorAction Stop
    Start-Sleep -Milliseconds 300
    Release-AfkKeys
    Remove-AutomationPid -Paths $paths
    Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Automation stopped by user. PID=$($state.Pid)"
    Write-Host "Automation stopped. PID=$($state.Pid)"
    exit 0
}

Release-AfkKeys
Remove-StaleAutomationPid -Paths $paths -State $state
Write-Host $state.Message
