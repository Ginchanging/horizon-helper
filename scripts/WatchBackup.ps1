[CmdletBinding()]
param(
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path (Split-Path -Parent $scriptRoot) 'config.json'
}

. (Join-Path $scriptRoot 'BackupLib.ps1')

$config = Get-BackupConfig -ConfigPath $ConfigPath
Initialize-BackupWorkspace -Config $config

$state = Get-WatcherState -Config $config
if ($state.Status -in @('Running', 'RunningUnverified') -and $state.Pid -ne $PID) {
    Write-BackupLog -Config $config -Level 'WARN' -Message "Watcher already running. Existing PID=$($state.Pid). New PID=$PID exits."
    exit 0
}
Remove-StaleWatcherPid -Config $config -State $state
Set-WatcherPid -Config $config

$watcher = $null
$subscriptions = @()
$sourcePrefix = "GameSaveBackup.$PID"
$pending = $false
$lastChange = Get-Date

try {
    Test-BackupSource -Config $config
    Write-BackupLog -Config $config -Level 'INFO' -Message "Watcher started. PID=$PID Source=$($config.SourcePath)"

    $startupBackup = Invoke-GameSaveBackup -Config $config -Reason 'startup'
    if (-not $startupBackup.Success) {
        Write-BackupLog -Config $config -Level 'WARN' -Message "Startup backup failed, watcher continues. Error=$($startupBackup.Message)"
    }

    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = $config.SourcePath
    $watcher.IncludeSubdirectories = $true
    $watcher.Filter = '*'
    $watcher.NotifyFilter = [System.IO.NotifyFilters]'FileName, DirectoryName, LastWrite, Size, CreationTime'

    foreach ($eventName in @('Created', 'Changed', 'Deleted', 'Renamed')) {
        $subscriptions += Register-ObjectEvent -InputObject $watcher -EventName $eventName -SourceIdentifier "$sourcePrefix.$eventName"
    }

    $watcher.EnableRaisingEvents = $true

    while ($true) {
        $event = Wait-Event -Timeout 1
        while ($null -ne $event) {
            if ($event.SourceIdentifier -like "$sourcePrefix.*") {
                $pending = $true
                $lastChange = Get-Date

                $changedPath = $null
                try {
                    $changedPath = $event.SourceEventArgs.FullPath
                }
                catch {
                    $changedPath = 'unknown'
                }

                Write-BackupLog -Config $config -Level 'INFO' -Message "Detected save change. Event=$($event.SourceIdentifier) Path=$changedPath"
            }

            Remove-Event -EventIdentifier $event.EventIdentifier -ErrorAction SilentlyContinue
            $event = Get-Event -ErrorAction SilentlyContinue |
                Where-Object { $_.SourceIdentifier -like "$sourcePrefix.*" } |
                Select-Object -First 1
        }

        if ($pending -and ((Get-Date) - $lastChange).TotalSeconds -ge $config.DebounceSeconds) {
            $pending = $false
            $backupResult = Invoke-GameSaveBackup -Config $config -Reason 'change'
            if (-not $backupResult.Success) {
                Write-BackupLog -Config $config -Level 'WARN' -Message "Change backup failed, watcher continues. Error=$($backupResult.Message)"
            }
        }
    }
}
catch {
    Write-BackupLog -Config $config -Level 'ERROR' -Message "Watcher stopped because of an error. Error=$($_.Exception.Message)"
    exit 1
}
finally {
    if ($watcher) {
        $watcher.EnableRaisingEvents = $false
    }

    foreach ($subscription in $subscriptions) {
        Unregister-Event -SubscriptionId $subscription.Id -ErrorAction SilentlyContinue
    }

    Get-Event -ErrorAction SilentlyContinue |
        Where-Object { $_.SourceIdentifier -like "$sourcePrefix.*" } |
        ForEach-Object { Remove-Event -EventIdentifier $_.EventIdentifier -ErrorAction SilentlyContinue }

    if ($watcher) {
        $watcher.Dispose()
    }

    Remove-WatcherPid -Config $config
    Write-BackupLog -Config $config -Level 'INFO' -Message "Watcher exited. PID=$PID"
}
