Set-StrictMode -Version 2.0

function ConvertTo-AbsolutePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$BasePath
    )

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ([System.IO.Path]::IsPathRooted($expanded)) {
        return [System.IO.Path]::GetFullPath($expanded)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $expanded))
}

function Get-BackupConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Config file not found: $ConfigPath"
    }

    $resolvedConfigPath = (Resolve-Path -LiteralPath $ConfigPath).ProviderPath
    $appRoot = Split-Path -Parent $resolvedConfigPath
    $rawConfig = Get-Content -LiteralPath $resolvedConfigPath -Raw -Encoding UTF8
    $json = $rawConfig | ConvertFrom-Json

    $sourcePathValue = if ($json.PSObject.Properties.Name -contains 'sourcePath') { [string]$json.sourcePath } else { '' }
    $backupRootValue = if ($json.PSObject.Properties.Name -contains 'backupRoot') { [string]$json.backupRoot } else { 'backups' }

    if ([string]::IsNullOrWhiteSpace($sourcePathValue)) {
        throw "Config value 'sourcePath' is required."
    }

    $sourcePath = ConvertTo-AbsolutePath -Path $sourcePathValue -BasePath $appRoot
    $backupRoot = ConvertTo-AbsolutePath -Path $backupRootValue -BasePath $appRoot

    $debounceSeconds = 30
    if ($json.PSObject.Properties.Name -contains 'debounceSeconds' -and $null -ne $json.debounceSeconds) {
        $debounceSeconds = [int]$json.debounceSeconds
    }
    if ($debounceSeconds -lt 1) {
        throw "Config value 'debounceSeconds' must be at least 1."
    }

    $maxBackups = 30
    if ($json.PSObject.Properties.Name -contains 'maxBackups' -and $null -ne $json.maxBackups) {
        $maxBackups = [int]$json.maxBackups
    }
    if ($maxBackups -lt 0) {
        throw "Config value 'maxBackups' cannot be negative."
    }

    $sourceFull = $sourcePath.TrimEnd('\')
    $backupFull = $backupRoot.TrimEnd('\')
    if ($backupFull.StartsWith($sourceFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Backup root cannot be inside the source save directory. Source: $sourcePath BackupRoot: $backupRoot"
    }

    $runtimeRoot = Join-Path $appRoot 'runtime'
    $logsRoot = Join-Path $appRoot 'logs'

    [pscustomobject]@{
        ConfigPath      = $resolvedConfigPath
        AppRoot         = $appRoot
        SourcePath      = $sourcePath
        BackupRoot      = $backupRoot
        DebounceSeconds = $debounceSeconds
        MaxBackups      = $maxBackups
        RuntimeRoot     = $runtimeRoot
        LogsRoot        = $logsRoot
        LogPath         = Join-Path $logsRoot 'backup.log'
        PidPath         = Join-Path $runtimeRoot 'watcher.pid'
        StagingRoot     = Join-Path $runtimeRoot 'staging'
    }
}

function Initialize-BackupWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config
    )

    foreach ($path in @($Config.BackupRoot, $Config.RuntimeRoot, $Config.LogsRoot, $Config.StagingRoot)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
    }
}

function Write-BackupLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO',
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not (Test-Path -LiteralPath $Config.LogsRoot -PathType Container)) {
        New-Item -Path $Config.LogsRoot -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $Config.LogPath -Value "[$timestamp] [$Level] $Message" -Encoding UTF8
}

function Test-BackupSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config
    )

    if (-not (Test-Path -LiteralPath $Config.SourcePath -PathType Container)) {
        throw "Source save directory does not exist: $($Config.SourcePath)"
    }
}

function Get-UniqueBackupPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config
    )

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $baseName = "GameSave_$stamp"
    $candidate = Join-Path $Config.BackupRoot "$baseName.zip"
    $index = 1

    while (Test-Path -LiteralPath $candidate) {
        $candidate = Join-Path $Config.BackupRoot ("{0}_{1:D2}.zip" -f $baseName, $index)
        $index++
    }

    return $candidate
}

function Invoke-BackupRetention {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config
    )

    if ($Config.MaxBackups -le 0) {
        Write-BackupLog -Config $Config -Level 'INFO' -Message 'Retention disabled because maxBackups is 0.'
        return
    }

    $backupFiles = @(Get-ChildItem -LiteralPath $Config.BackupRoot -Filter 'GameSave_*.zip' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending)

    if ($backupFiles.Count -le $Config.MaxBackups) {
        return
    }

    $oldFiles = $backupFiles | Select-Object -Skip $Config.MaxBackups
    foreach ($oldFile in $oldFiles) {
        Remove-Item -LiteralPath $oldFile.FullName -Force
        Write-BackupLog -Config $Config -Level 'INFO' -Message "Removed old backup: $($oldFile.FullName)"
    }
}

function Remove-DirectorySafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$AllowedRoot
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return
    }

    $resolvedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $resolvedRoot = [System.IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\')
    if (-not $resolvedPath.StartsWith($resolvedRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove directory outside staging root: $resolvedPath"
    }

    Remove-Item -LiteralPath $resolvedPath -Recurse -Force
}

function Invoke-GameSaveBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config,
        [string]$Reason = 'manual'
    )

    Initialize-BackupWorkspace -Config $Config

    $stageRoot = $null
    $backupPath = $null
    try {
        Test-BackupSource -Config $Config

        $stageRoot = Join-Path $Config.StagingRoot ([guid]::NewGuid().ToString('N'))
        $stageSource = Join-Path $stageRoot 'GameSave'
        New-Item -Path $stageSource -ItemType Directory -Force | Out-Null

        $children = @(Get-ChildItem -LiteralPath $Config.SourcePath -Force -ErrorAction Stop)
        foreach ($child in $children) {
            Copy-Item -LiteralPath $child.FullName -Destination $stageSource -Recurse -Force -ErrorAction Stop
        }

        $backupPath = Get-UniqueBackupPath -Config $Config
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory(
            $stageSource,
            $backupPath,
            [System.IO.Compression.CompressionLevel]::Optimal,
            $false
        )

        Invoke-BackupRetention -Config $Config
        Write-BackupLog -Config $Config -Level 'INFO' -Message "Backup succeeded. Reason=$Reason Path=$backupPath"

        [pscustomobject]@{
            Success    = $true
            BackupPath = $backupPath
            Message    = "Backup created: $backupPath"
        }
    }
    catch {
        $message = $_.Exception.Message
        Write-BackupLog -Config $Config -Level 'ERROR' -Message "Backup failed. Reason=$Reason Error=$message"

        if ($backupPath -and (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }

        [pscustomobject]@{
            Success    = $false
            BackupPath = $null
            Message    = $message
        }
    }
    finally {
        if ($stageRoot) {
            Remove-DirectorySafe -Path $stageRoot -AllowedRoot $Config.StagingRoot
        }
    }
}

function Set-WatcherPid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config
    )

    Initialize-BackupWorkspace -Config $Config
    Set-Content -LiteralPath $Config.PidPath -Value ([string]$PID) -Encoding ASCII
}

function Remove-WatcherPid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config
    )

    if (Test-Path -LiteralPath $Config.PidPath -PathType Leaf) {
        Remove-Item -LiteralPath $Config.PidPath -Force
    }
}

function Get-WatcherState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config
    )

    if (-not (Test-Path -LiteralPath $Config.PidPath -PathType Leaf)) {
        return [pscustomobject]@{
            Status      = 'Stopped'
            Pid         = $null
            Process     = $null
            CommandLine = $null
            Message     = 'Watcher is not running.'
        }
    }

    $pidText = (Get-Content -LiteralPath $Config.PidPath -ErrorAction SilentlyContinue | Select-Object -First 1)
    $watcherPid = 0
    if (-not [int]::TryParse(([string]$pidText).Trim(), [ref]$watcherPid)) {
        return [pscustomobject]@{
            Status      = 'InvalidPid'
            Pid         = $null
            Process     = $null
            CommandLine = $null
            Message     = "PID file is invalid: $($Config.PidPath)"
        }
    }

    $process = Get-Process -Id $watcherPid -ErrorAction SilentlyContinue
    if (-not $process) {
        return [pscustomobject]@{
            Status      = 'Stale'
            Pid         = $watcherPid
            Process     = $null
            CommandLine = $null
            Message     = "PID file is stale. Process $watcherPid is not running."
        }
    }

    $commandLine = $null
    try {
        $cim = Get-CimInstance Win32_Process -Filter "ProcessId = $watcherPid" -ErrorAction Stop
        $commandLine = $cim.CommandLine
    }
    catch {
        try {
            $wmi = Get-WmiObject Win32_Process -Filter "ProcessId = $watcherPid" -ErrorAction Stop
            $commandLine = $wmi.CommandLine
        }
        catch {
            $commandLine = $null
        }
    }

    $normalizedConfig = $Config.ConfigPath.ToLowerInvariant()
    $normalizedCommand = if ($commandLine) { $commandLine.ToLowerInvariant() } else { '' }
    $isWatcher = $normalizedCommand.Contains('watchbackup.ps1') -and $normalizedCommand.Contains($normalizedConfig)

    if ($isWatcher) {
        return [pscustomobject]@{
            Status      = 'Running'
            Pid         = $watcherPid
            Process     = $process
            CommandLine = $commandLine
            Message     = "Watcher is running. PID=$watcherPid"
        }
    }

    if ([string]::IsNullOrWhiteSpace($commandLine) -and $process.ProcessName -like 'powershell*') {
        return [pscustomobject]@{
            Status      = 'RunningUnverified'
            Pid         = $watcherPid
            Process     = $process
            CommandLine = $commandLine
            Message     = "Watcher appears to be running, but process command line could not be verified. PID=$watcherPid"
        }
    }

    [pscustomobject]@{
        Status      = 'PidConflict'
        Pid         = $watcherPid
        Process     = $process
        CommandLine = $commandLine
        Message     = "PID file points to a process that does not look like this watcher. PID=$watcherPid"
    }
}

function Remove-StaleWatcherPid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$State
    )

    if ($State.Status -in @('Stale', 'InvalidPid', 'PidConflict')) {
        Remove-WatcherPid -Config $Config
    }
}

function Get-LatestBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config
    )

    if (-not (Test-Path -LiteralPath $Config.BackupRoot -PathType Container)) {
        return $null
    }

    Get-ChildItem -LiteralPath $Config.BackupRoot -Filter 'GameSave_*.zip' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
}
