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
Test-BackupSource -Config $config

$state = Get-WatcherState -Config $config
if ($state.Status -in @('Running', 'RunningUnverified')) {
    Write-Host $state.Message
    exit 0
}

Remove-StaleWatcherPid -Config $config -State $state

$watcherScript = Join-Path $scriptRoot 'scripts\WatchBackup.ps1'
$resolvedConfigPath = (Resolve-Path -LiteralPath $ConfigPath).ProviderPath
$argumentList = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', ('"{0}"' -f $watcherScript),
    '-ConfigPath', ('"{0}"' -f $resolvedConfigPath)
)

$process = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -WindowStyle Hidden -PassThru

for ($attempt = 1; $attempt -le 10; $attempt++) {
    Start-Sleep -Milliseconds 500
    $newState = Get-WatcherState -Config $config
    if ($newState.Status -in @('Running', 'RunningUnverified') -or $process.HasExited) {
        break
    }
}

if ($newState.Status -in @('Running', 'RunningUnverified')) {
    Write-Host "Watcher started. PID=$($newState.Pid)"
    if ($newState.Status -eq 'RunningUnverified') {
        Write-Host "Note: process command line could not be verified in this shell, but the PID file points to a PowerShell watcher process."
    }
    Write-Host "Source: $($config.SourcePath)"
    Write-Host "Backups: $($config.BackupRoot)"
    Write-Host "Log: $($config.LogPath)"
    exit 0
}

if ($process.HasExited) {
    Write-Error "Watcher process exited early. Check log: $($config.LogPath)"
    exit 1
}

Write-Host "Watcher process started. PID=$($process.Id)"
Write-Host "Status is still initializing. Check again with StatusBackup.ps1."
