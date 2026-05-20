[CmdletBinding()]
param(
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $scriptRoot 'config.json'
}

. (Join-Path $scriptRoot 'scripts\BackupLib.ps1')

$config = Get-BackupConfig -ConfigPath $ConfigPath
Initialize-BackupWorkspace -Config $config

$state = Get-WatcherState -Config $config
if ($state.Status -in @('Running', 'RunningUnverified')) {
    Stop-Process -Id $state.Pid -Force -ErrorAction Stop
    Start-Sleep -Milliseconds 400
    Remove-WatcherPid -Config $config
    Write-BackupLog -Config $config -Level 'INFO' -Message "Watcher stopped by user. PID=$($state.Pid)"
    Write-Host "Watcher stopped. PID=$($state.Pid)"
    exit 0
}

Remove-StaleWatcherPid -Config $config -State $state
Write-Host $state.Message
