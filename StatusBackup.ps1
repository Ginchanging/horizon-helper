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

$sourceExists = Test-Path -LiteralPath $config.SourcePath -PathType Container
$state = Get-WatcherState -Config $config
$latestBackup = Get-LatestBackup -Config $config

Write-Host "Status: $($state.Status)"
Write-Host $state.Message
Write-Host "Source: $($config.SourcePath)"
Write-Host "Source exists: $sourceExists"
Write-Host "Backups: $($config.BackupRoot)"
Write-Host "Debounce seconds: $($config.DebounceSeconds)"
Write-Host "Max backups: $($config.MaxBackups)"

if ($latestBackup) {
    Write-Host "Latest backup: $($latestBackup.FullName)"
    Write-Host "Latest backup time: $($latestBackup.LastWriteTime)"
}
else {
    Write-Host "Latest backup: none"
}

Write-Host "Log: $($config.LogPath)"
