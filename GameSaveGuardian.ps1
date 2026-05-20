[CmdletBinding()]
param(
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }

. (Join-Path $scriptRoot 'scripts\BackupLib.ps1')
. (Join-Path $scriptRoot 'scripts\FocusLib.ps1')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$configPath = Join-Path $scriptRoot 'config.json'

function Get-AppBackupConfig {
    Get-BackupConfig -ConfigPath $configPath
}

function Get-AppFocusPaths {
    Get-FocusPaths -AppRoot $scriptRoot
}

function Show-AppMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Title = 'GameSave Guardian',
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )

    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon)
}

function Invoke-AppSafely {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [string]$FailureTitle = 'GameSave Guardian'
    )

    try {
        & $Action
    }
    catch {
        Show-AppMessage -Title $FailureTitle -Message $_.Exception.Message -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Open-AppPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$EnsureFile
    )

    if ($EnsureFile -and -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $parent = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -Path $parent -ItemType Directory -Force | Out-Null
        }
        New-Item -Path $Path -ItemType File -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }

    Start-Process -FilePath $Path
}

function Start-AppBackupWatcher {
    $config = Get-AppBackupConfig
    Initialize-BackupWorkspace -Config $config
    Test-BackupSource -Config $config

    $state = Get-WatcherState -Config $config
    if ($state.Status -in @('Running', 'RunningUnverified')) {
        return $state.Message
    }

    Remove-StaleWatcherPid -Config $config -State $state

    $watcherScript = Join-Path $scriptRoot 'scripts\WatchBackup.ps1'
    $argumentList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $watcherScript),
        '-ConfigPath', ('"{0}"' -f $config.ConfigPath)
    )

    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -WindowStyle Hidden -PassThru
    $newState = $null
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        Start-Sleep -Milliseconds 500
        $newState = Get-WatcherState -Config $config
        if ($newState.Status -in @('Running', 'RunningUnverified') -or $process.HasExited) {
            break
        }
    }

    if ($newState -and $newState.Status -in @('Running', 'RunningUnverified')) {
        return "Auto backup started. PID=$($newState.Pid)"
    }

    if ($process.HasExited) {
        throw "Auto backup exited early. Check log: $($config.LogPath)"
    }

    return "Auto backup process started. PID=$($process.Id)"
}

function Stop-AppBackupWatcher {
    $config = Get-AppBackupConfig
    Initialize-BackupWorkspace -Config $config
    $state = Get-WatcherState -Config $config

    if ($state.Status -in @('Running', 'RunningUnverified')) {
        Stop-Process -Id $state.Pid -Force -ErrorAction Stop
        Start-Sleep -Milliseconds 300
        Remove-WatcherPid -Config $config
        Write-BackupLog -Config $config -Level 'INFO' -Message "Watcher stopped by GUI. PID=$($state.Pid)"
        return "Auto backup stopped. PID=$($state.Pid)"
    }

    Remove-StaleWatcherPid -Config $config -State $state
    return $state.Message
}

function Start-AppFocusLock {
    param(
        [Parameter(Mandatory = $true)]$Target,
        [int]$IntervalMilliseconds = 750
    )

    $paths = Get-AppFocusPaths
    Initialize-FocusWorkspace -Paths $paths

    $state = Get-FocusLockState -Paths $paths
    if ($state.Status -in @('Running', 'RunningUnverified')) {
        return $state.Message
    }

    Remove-StaleFocusLockPid -Paths $paths -State $state
    Set-FocusLockTarget -Paths $paths -Target $Target -IntervalMilliseconds $IntervalMilliseconds

    $workerScript = Join-Path $scriptRoot 'scripts\KeepWindowFocused.ps1'
    $argumentList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $workerScript),
        '-WindowHandle', ([string]$Target.Handle),
        '-IntervalMilliseconds', ([string]$IntervalMilliseconds),
        '-AppRoot', ('"{0}"' -f $scriptRoot)
    )

    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -WindowStyle Hidden -PassThru
    $newState = $null
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        Start-Sleep -Milliseconds 300
        $newState = Get-FocusLockState -Paths $paths
        if ($newState.Status -in @('Running', 'RunningUnverified') -or $process.HasExited) {
            break
        }
    }

    if ($newState -and $newState.Status -in @('Running', 'RunningUnverified')) {
        return "Focus lock started. PID=$($newState.Pid)"
    }

    if ($process.HasExited) {
        throw "Focus lock exited early. Check log: $($paths.LogPath)"
    }

    return "Focus lock process started. PID=$($process.Id)"
}

function Stop-AppFocusLock {
    $paths = Get-AppFocusPaths
    Initialize-FocusWorkspace -Paths $paths
    $state = Get-FocusLockState -Paths $paths

    if ($state.Status -in @('Running', 'RunningUnverified')) {
        Stop-Process -Id $state.Pid -Force -ErrorAction Stop
        Start-Sleep -Milliseconds 300
        Remove-FocusLockPid -Paths $paths
        Write-FocusLog -Paths $paths -Level 'INFO' -Message "Focus lock stopped by GUI. PID=$($state.Pid)"
        return "Focus lock stopped. PID=$($state.Pid)"
    }

    Remove-StaleFocusLockPid -Paths $paths -State $state
    return $state.Message
}

if ($SelfTest) {
    $config = Get-AppBackupConfig
    Initialize-BackupWorkspace -Config $config
    $backupState = Get-WatcherState -Config $config
    $focusPaths = Get-AppFocusPaths
    Initialize-FocusWorkspace -Paths $focusPaths
    $focusState = Get-FocusLockState -Paths $focusPaths
    $windowCount = @(Get-FocusWindowList).Count

    Write-Host 'GameSave Guardian self-test passed.'
    Write-Host "Source: $($config.SourcePath)"
    Write-Host "Backups: $($config.BackupRoot)"
    Write-Host "Auto backup status: $($backupState.Status)"
    Write-Host "Focus lock status: $($focusState.Status)"
    Write-Host "Visible windows: $windowCount"
    exit 0
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'GameSave Guardian'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(820, 640)
$form.MinimumSize = New-Object System.Drawing.Size(760, 560)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = [System.Windows.Forms.DockStyle]::Fill
$form.Controls.Add($tabs)

$backupTab = New-Object System.Windows.Forms.TabPage
$backupTab.Text = 'Backup'
$tabs.TabPages.Add($backupTab)

$focusTab = New-Object System.Windows.Forms.TabPage
$focusTab.Text = 'Focus Lock'
$tabs.TabPages.Add($focusTab)

$backupStatusLabel = New-Object System.Windows.Forms.Label
$backupStatusLabel.Location = New-Object System.Drawing.Point(16, 16)
$backupStatusLabel.Size = New-Object System.Drawing.Size(760, 22)
$backupStatusLabel.Text = 'Status: loading...'
$backupTab.Controls.Add($backupStatusLabel)

$sourceLabel = New-Object System.Windows.Forms.Label
$sourceLabel.Location = New-Object System.Drawing.Point(16, 52)
$sourceLabel.Size = New-Object System.Drawing.Size(110, 22)
$sourceLabel.Text = 'Save folder'
$backupTab.Controls.Add($sourceLabel)

$sourceBox = New-Object System.Windows.Forms.TextBox
$sourceBox.Location = New-Object System.Drawing.Point(132, 50)
$sourceBox.Size = New-Object System.Drawing.Size(630, 24)
$sourceBox.ReadOnly = $true
$backupTab.Controls.Add($sourceBox)

$backupRootLabel = New-Object System.Windows.Forms.Label
$backupRootLabel.Location = New-Object System.Drawing.Point(16, 88)
$backupRootLabel.Size = New-Object System.Drawing.Size(110, 22)
$backupRootLabel.Text = 'Backup folder'
$backupTab.Controls.Add($backupRootLabel)

$backupRootBox = New-Object System.Windows.Forms.TextBox
$backupRootBox.Location = New-Object System.Drawing.Point(132, 86)
$backupRootBox.Size = New-Object System.Drawing.Size(630, 24)
$backupRootBox.ReadOnly = $true
$backupTab.Controls.Add($backupRootBox)

$latestBackupLabel = New-Object System.Windows.Forms.Label
$latestBackupLabel.Location = New-Object System.Drawing.Point(16, 124)
$latestBackupLabel.Size = New-Object System.Drawing.Size(110, 22)
$latestBackupLabel.Text = 'Latest backup'
$backupTab.Controls.Add($latestBackupLabel)

$latestBackupBox = New-Object System.Windows.Forms.TextBox
$latestBackupBox.Location = New-Object System.Drawing.Point(132, 122)
$latestBackupBox.Size = New-Object System.Drawing.Size(630, 24)
$latestBackupBox.ReadOnly = $true
$backupTab.Controls.Add($latestBackupBox)

$backupButtonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$backupButtonPanel.Location = New-Object System.Drawing.Point(16, 170)
$backupButtonPanel.Size = New-Object System.Drawing.Size(760, 86)
$backupButtonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$backupButtonPanel.WrapContents = $true
$backupTab.Controls.Add($backupButtonPanel)

function New-AppButton {
    param(
        [Parameter(Mandatory = $true)][string]$Text
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Size = New-Object System.Drawing.Size(140, 32)
    $button.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 10)
    return $button
}

$refreshBackupButton = New-AppButton -Text 'Refresh'
$backupNowButton = New-AppButton -Text 'Backup Now'
$startBackupButton = New-AppButton -Text 'Start Auto Backup'
$stopBackupButton = New-AppButton -Text 'Stop Auto Backup'
$openBackupsButton = New-AppButton -Text 'Open Backups'
$openBackupLogButton = New-AppButton -Text 'Open Backup Log'

@($refreshBackupButton, $backupNowButton, $startBackupButton, $stopBackupButton, $openBackupsButton, $openBackupLogButton) |
    ForEach-Object { $backupButtonPanel.Controls.Add($_) }

$backupLogBox = New-Object System.Windows.Forms.TextBox
$backupLogBox.Location = New-Object System.Drawing.Point(16, 278)
$backupLogBox.Size = New-Object System.Drawing.Size(746, 250)
$backupLogBox.Multiline = $true
$backupLogBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$backupLogBox.ReadOnly = $true
$backupTab.Controls.Add($backupLogBox)

$focusStatusLabel = New-Object System.Windows.Forms.Label
$focusStatusLabel.Location = New-Object System.Drawing.Point(16, 16)
$focusStatusLabel.Size = New-Object System.Drawing.Size(760, 22)
$focusStatusLabel.Text = 'Status: loading...'
$focusTab.Controls.Add($focusStatusLabel)

$focusTargetLabel = New-Object System.Windows.Forms.Label
$focusTargetLabel.Location = New-Object System.Drawing.Point(16, 46)
$focusTargetLabel.Size = New-Object System.Drawing.Size(760, 22)
$focusTargetLabel.Text = 'Target: none'
$focusTab.Controls.Add($focusTargetLabel)

$windowList = New-Object System.Windows.Forms.ListView
$windowList.Location = New-Object System.Drawing.Point(16, 82)
$windowList.Size = New-Object System.Drawing.Size(746, 300)
$windowList.View = [System.Windows.Forms.View]::Details
$windowList.FullRowSelect = $true
$windowList.MultiSelect = $false
$windowList.HideSelection = $false
[void]$windowList.Columns.Add('PID', 80)
[void]$windowList.Columns.Add('Process', 150)
[void]$windowList.Columns.Add('Title', 390)
[void]$windowList.Columns.Add('Handle', 110)
$focusTab.Controls.Add($windowList)

$focusButtonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$focusButtonPanel.Location = New-Object System.Drawing.Point(16, 402)
$focusButtonPanel.Size = New-Object System.Drawing.Size(760, 86)
$focusButtonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$focusButtonPanel.WrapContents = $true
$focusTab.Controls.Add($focusButtonPanel)

$refreshWindowsButton = New-AppButton -Text 'Refresh Windows'
$startFocusButton = New-AppButton -Text 'Start Focus Lock'
$stopFocusButton = New-AppButton -Text 'Stop Focus Lock'
$refreshFocusButton = New-AppButton -Text 'Refresh Status'
$openFocusLogButton = New-AppButton -Text 'Open Focus Log'
@($refreshWindowsButton, $startFocusButton, $stopFocusButton, $refreshFocusButton, $openFocusLogButton) |
    ForEach-Object { $focusButtonPanel.Controls.Add($_) }

$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusText = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusText.Text = 'Ready'
[void]$statusStrip.Items.Add($statusText)
$form.Controls.Add($statusStrip)

function Set-AppStatusText {
    param([string]$Text)
    $statusText.Text = $Text
}

function Update-BackupLogPreview {
    param($Config)

    if (Test-Path -LiteralPath $Config.LogPath -PathType Leaf) {
        $backupLogBox.Text = ((Get-Content -LiteralPath $Config.LogPath -Tail 80 -Encoding UTF8) -join [Environment]::NewLine)
    }
    else {
        $backupLogBox.Text = 'No backup log yet.'
    }
}

function Refresh-BackupPanel {
    Invoke-AppSafely -FailureTitle 'Backup Status' -Action {
        $config = Get-AppBackupConfig
        Initialize-BackupWorkspace -Config $config
        $state = Get-WatcherState -Config $config
        $latestBackup = Get-LatestBackup -Config $config
        $sourceExists = Test-Path -LiteralPath $config.SourcePath -PathType Container

        $backupStatusLabel.Text = "Status: $($state.Status) - Source exists: $sourceExists"
        $sourceBox.Text = $config.SourcePath
        $backupRootBox.Text = $config.BackupRoot
        if ($latestBackup) {
            $latestBackupBox.Text = "$($latestBackup.FullName) ($($latestBackup.LastWriteTime))"
        }
        else {
            $latestBackupBox.Text = 'none'
        }

        Update-BackupLogPreview -Config $config
        Set-AppStatusText 'Backup status refreshed.'
    }
}

function Refresh-FocusPanel {
    Invoke-AppSafely -FailureTitle 'Focus Status' -Action {
        $paths = Get-AppFocusPaths
        Initialize-FocusWorkspace -Paths $paths
        $state = Get-FocusLockState -Paths $paths
        $target = Get-FocusLockTarget -Paths $paths

        $focusStatusLabel.Text = "Status: $($state.Status) - $($state.Message)"
        if ($target) {
            $windowExists = [bool](Get-WindowInfoByHandle -WindowHandle ([Int64]$target.Handle))
            $focusTargetLabel.Text = "Target: [$($target.ProcessId)] $($target.ProcessName) - $($target.Title) - Exists: $windowExists"
        }
        else {
            $focusTargetLabel.Text = 'Target: none'
        }

        Set-AppStatusText 'Focus status refreshed.'
    }
}

function Refresh-WindowList {
    Invoke-AppSafely -FailureTitle 'Window List' -Action {
        $windowList.Items.Clear()
        $windows = @(Get-FocusWindowList)
        foreach ($window in $windows) {
            $item = New-Object System.Windows.Forms.ListViewItem([string]$window.ProcessId)
            [void]$item.SubItems.Add([string]$window.ProcessName)
            [void]$item.SubItems.Add([string]$window.Title)
            [void]$item.SubItems.Add([string]$window.HandleHex)
            $item.Tag = $window
            [void]$windowList.Items.Add($item)
        }

        Set-AppStatusText "Loaded $($windows.Count) visible windows."
    }
}

$refreshBackupButton.Add_Click({ Refresh-BackupPanel })
$backupNowButton.Add_Click({
    Invoke-AppSafely -FailureTitle 'Backup Now' -Action {
        $config = Get-AppBackupConfig
        $result = Invoke-GameSaveBackup -Config $config -Reason 'gui-manual'
        if (-not $result.Success) {
            throw $result.Message
        }
        Set-AppStatusText $result.Message
        Refresh-BackupPanel
        Show-AppMessage -Message $result.Message
    }
})
$startBackupButton.Add_Click({
    Invoke-AppSafely -FailureTitle 'Start Auto Backup' -Action {
        $message = Start-AppBackupWatcher
        Set-AppStatusText $message
        Refresh-BackupPanel
        Show-AppMessage -Message $message
    }
})
$stopBackupButton.Add_Click({
    Invoke-AppSafely -FailureTitle 'Stop Auto Backup' -Action {
        $message = Stop-AppBackupWatcher
        Set-AppStatusText $message
        Refresh-BackupPanel
        Show-AppMessage -Message $message
    }
})
$openBackupsButton.Add_Click({
    Invoke-AppSafely -FailureTitle 'Open Backups' -Action {
        $config = Get-AppBackupConfig
        Initialize-BackupWorkspace -Config $config
        Open-AppPath -Path $config.BackupRoot
    }
})
$openBackupLogButton.Add_Click({
    Invoke-AppSafely -FailureTitle 'Open Backup Log' -Action {
        $config = Get-AppBackupConfig
        Initialize-BackupWorkspace -Config $config
        Open-AppPath -Path $config.LogPath -EnsureFile
    }
})

$refreshWindowsButton.Add_Click({ Refresh-WindowList })
$refreshFocusButton.Add_Click({ Refresh-FocusPanel })
$startFocusButton.Add_Click({
    Invoke-AppSafely -FailureTitle 'Start Focus Lock' -Action {
        if ($windowList.SelectedItems.Count -lt 1) {
            throw 'Select a window first.'
        }

        $target = $windowList.SelectedItems[0].Tag
        $message = Start-AppFocusLock -Target $target
        Set-AppStatusText $message
        Refresh-FocusPanel
        Show-AppMessage -Message $message
    }
})
$stopFocusButton.Add_Click({
    Invoke-AppSafely -FailureTitle 'Stop Focus Lock' -Action {
        $message = Stop-AppFocusLock
        Set-AppStatusText $message
        Refresh-FocusPanel
        Show-AppMessage -Message $message
    }
})
$openFocusLogButton.Add_Click({
    Invoke-AppSafely -FailureTitle 'Open Focus Log' -Action {
        $paths = Get-AppFocusPaths
        Initialize-FocusWorkspace -Paths $paths
        Open-AppPath -Path $paths.LogPath -EnsureFile
    }
})

$form.Add_Shown({
    Refresh-BackupPanel
    Refresh-FocusPanel
    Refresh-WindowList
})

[void][System.Windows.Forms.Application]::Run($form)
