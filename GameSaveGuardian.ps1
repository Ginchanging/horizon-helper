[CmdletBinding()]
param(
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }

. (Join-Path $scriptRoot 'scripts\BackupLib.ps1')
. (Join-Path $scriptRoot 'scripts\FocusLib.ps1')
. (Join-Path $scriptRoot 'scripts\AfkLib.ps1')
. (Join-Path $scriptRoot 'scripts\AutomationLib.ps1')
. (Join-Path $scriptRoot 'scripts\UltimateLib.ps1')

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

function Get-AppAfkPaths {
    Get-AfkPaths -AppRoot $scriptRoot
}

function Get-AppAfkConfig {
    Get-AfkConfig -AppRoot $scriptRoot
}

function Get-AppAutomationPaths {
    Get-AutomationPaths -AppRoot $scriptRoot
}

function Get-AppAutomationConfig {
    Get-AutomationConfig -AppRoot $scriptRoot
}

function Get-AppUltimatePaths {
    Get-UltimatePaths -AppRoot $scriptRoot
}

function Get-AppUltimateConfig {
    Get-UltimateConfig -AppRoot $scriptRoot
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

function Start-AppAfk {
    param(
        [ValidateSet('Sequence', 'EnterEvery10s', 'MacroCombo')][string]$Mode = 'Sequence'
    )

    $paths = Get-AppAfkPaths
    Initialize-AfkWorkspace -Paths $paths
    $afkConfig = Get-AppAfkConfig
    $options = Resolve-AfkRuntimeOptions -Config $afkConfig

    $automationPaths = Get-AppAutomationPaths
    Initialize-AutomationWorkspace -Paths $automationPaths
    $automationState = Get-AutomationState -Paths $automationPaths
    if ($automationState.Status -in @('Running', 'RunningUnverified')) {
        throw "Automation is already running. Stop Automation before starting AFK. Automation PID=$($automationState.Pid)"
    }

    $ultimatePaths = Get-AppUltimatePaths
    Initialize-UltimateWorkspace -Paths $ultimatePaths
    $ultimateState = Get-UltimateState -Paths $ultimatePaths
    if ($ultimateState.Status -in @('Running', 'RunningUnverified')) {
        throw "Ultimate is already running. Stop Ultimate before starting AFK. Ultimate PID=$($ultimateState.Pid)"
    }

    $state = Get-AfkState -Paths $paths
    if ($state.Status -in @('Running', 'RunningUnverified')) {
        return $state.Message
    }

    Remove-StaleAfkPid -Paths $paths -State $state

    $workerScript = Join-Path $scriptRoot 'scripts\RunAfk.ps1'
    $argumentList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-STA',
        '-File', ('"{0}"' -f $workerScript),
        '-AppRoot', ('"{0}"' -f $scriptRoot),
        '-Mode', $Mode,
        '-StartupDelaySeconds', ([string]$options.StartupDelaySeconds),
        '-EnterDelaySeconds', ([string]$options.EnterDelaySeconds),
        '-XDelayMilliseconds', ([string]$options.XDelayMilliseconds),
        '-LoopDelaySeconds', ([string]$options.LoopDelaySeconds),
        '-EnterOnlyDelaySeconds', ([string]$options.EnterOnlyDelaySeconds),
        '-KeyTapHoldMilliseconds', ([string]$options.KeyTapHoldMilliseconds),
        '-MacroComboCycleDelaySeconds', ([string]$options.MacroComboCycleDelaySeconds),
        '-InputMethod', $options.InputMethod
    )

    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -WindowStyle Hidden -PassThru
    $newState = $null
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        Start-Sleep -Milliseconds 300
        $newState = Get-AfkState -Paths $paths
        if ($newState.Status -in @('Running', 'RunningUnverified') -or $process.HasExited) {
            break
        }
    }

    if ($newState -and $newState.Status -in @('Running', 'RunningUnverified')) {
        return "AFK started. PID=$($newState.Pid). Mode=$Mode. InputMethod=$($options.InputMethod). Switch to the game window within $($options.StartupDelaySeconds) seconds."
    }

    if ($process.HasExited) {
        throw "AFK exited early. Check log: $($paths.LogPath)"
    }

    return "AFK process started. PID=$($process.Id)"
}

function Stop-AppAfk {
    $paths = Get-AppAfkPaths
    Initialize-AfkWorkspace -Paths $paths
    $state = Get-AfkState -Paths $paths

    if ($state.Status -in @('Running', 'RunningUnverified')) {
        Release-AfkKeys
        Stop-Process -Id $state.Pid -Force -ErrorAction Stop
        Start-Sleep -Milliseconds 300
        Release-AfkKeys
        Remove-AfkPid -Paths $paths
        Write-AfkLog -Paths $paths -Level 'INFO' -Message "AFK stopped by GUI. PID=$($state.Pid) W key released."
        return "AFK stopped. PID=$($state.Pid). W key released."
    }

    Release-AfkKeys
    Remove-StaleAfkPid -Paths $paths -State $state
    return "$($state.Message) W key released."
}

function Start-AppAutomation {
    param(
        [ValidateSet('AutoBuyCar', 'DeleteCar', 'FindNewSubaru')][string]$Mode = 'AutoBuyCar',
        [int]$LoopCount = -1
    )

    $paths = Get-AppAutomationPaths
    Initialize-AutomationWorkspace -Paths $paths
    $config = Get-AppAutomationConfig
    $options = Resolve-AutomationRuntimeOptions -Config $config -Mode $Mode -LoopCount $LoopCount

    $afkPaths = Get-AppAfkPaths
    Initialize-AfkWorkspace -Paths $afkPaths
    $afkState = Get-AfkState -Paths $afkPaths
    if ($afkState.Status -in @('Running', 'RunningUnverified')) {
        throw "AFK is already running. Stop AFK before starting Automation. AFK PID=$($afkState.Pid)"
    }

    $ultimatePaths = Get-AppUltimatePaths
    Initialize-UltimateWorkspace -Paths $ultimatePaths
    $ultimateState = Get-UltimateState -Paths $ultimatePaths
    if ($ultimateState.Status -in @('Running', 'RunningUnverified')) {
        throw "Ultimate is already running. Stop Ultimate before starting Automation. Ultimate PID=$($ultimateState.Pid)"
    }

    $state = Get-AutomationState -Paths $paths
    if ($state.Status -in @('Running', 'RunningUnverified')) {
        return $state.Message
    }

    Remove-StaleAutomationPid -Paths $paths -State $state

    $workerScript = Join-Path $scriptRoot 'scripts\RunAutomation.ps1'
    $argumentList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-STA',
        '-File', ('"{0}"' -f $workerScript),
        '-AppRoot', ('"{0}"' -f $scriptRoot),
        '-Mode', $Mode,
        '-LoopCount', ([string]$options.LoopCount),
        '-StartupDelaySeconds', ([string]$options.StartupDelaySeconds)
    )

    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -WindowStyle Hidden -PassThru
    $newState = $null
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        Start-Sleep -Milliseconds 300
        $newState = Get-AutomationState -Paths $paths
        if ($newState.Status -in @('Running', 'RunningUnverified') -or $process.HasExited) {
            break
        }
    }

    if ($newState -and $newState.Status -in @('Running', 'RunningUnverified')) {
        return "Automation started. PID=$($newState.Pid). Mode=$Mode. LoopCount=$($options.LoopCount). InputMethod=$($options.InputMethod). Switch to the game window within $($options.StartupDelaySeconds) seconds."
    }

    if ($process.HasExited) {
        throw "Automation exited early. Check log: $($paths.LogPath)"
    }

    return "Automation process started. PID=$($process.Id)"
}

function Stop-AppAutomation {
    $paths = Get-AppAutomationPaths
    Initialize-AutomationWorkspace -Paths $paths
    $state = Get-AutomationState -Paths $paths

    if ($state.Status -in @('Running', 'RunningUnverified')) {
        Release-AfkKeys
        Stop-Process -Id $state.Pid -Force -ErrorAction Stop
        Start-Sleep -Milliseconds 300
        Release-AfkKeys
        Remove-AutomationPid -Paths $paths
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Automation stopped by GUI. PID=$($state.Pid)"
        return "Automation stopped. PID=$($state.Pid)"
    }

    Release-AfkKeys
    Remove-StaleAutomationPid -Paths $paths -State $state
    return $state.Message
}

function Start-AppUltimate {
    param(
        [int]$SequenceLoopCount = -1,
        [int]$AutoBuyCarLoopCount = -1,
        [int]$FindNewSubaruLoopCount = -1,
        [int]$StartFromStep = -1,
        [int]$WorkflowLoopCount = -1
    )

    $paths = Get-AppUltimatePaths
    Initialize-UltimateWorkspace -Paths $paths
    $config = Get-AppUltimateConfig
    $options = Resolve-UltimateRuntimeOptions -Config $config -SequenceLoopCount $SequenceLoopCount -AutoBuyCarLoopCount $AutoBuyCarLoopCount -FindNewSubaruLoopCount $FindNewSubaruLoopCount -StartFromStep $StartFromStep -WorkflowLoopCount $WorkflowLoopCount

    $afkPaths = Get-AppAfkPaths
    Initialize-AfkWorkspace -Paths $afkPaths
    $afkState = Get-AfkState -Paths $afkPaths
    if ($afkState.Status -in @('Running', 'RunningUnverified')) {
        throw "AFK is already running. Stop AFK before starting Ultimate. AFK PID=$($afkState.Pid)"
    }

    $automationPaths = Get-AppAutomationPaths
    Initialize-AutomationWorkspace -Paths $automationPaths
    $automationState = Get-AutomationState -Paths $automationPaths
    if ($automationState.Status -in @('Running', 'RunningUnverified')) {
        throw "Automation is already running. Stop Automation before starting Ultimate. Automation PID=$($automationState.Pid)"
    }

    $state = Get-UltimateState -Paths $paths
    if ($state.Status -in @('Running', 'RunningUnverified')) {
        return $state.Message
    }

    Remove-StaleUltimatePid -Paths $paths -State $state

    $workerScript = Join-Path $scriptRoot 'scripts\RunUltimate.ps1'
    $argumentList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-STA',
        '-File', ('"{0}"' -f $workerScript),
        '-AppRoot', ('"{0}"' -f $scriptRoot),
        '-StartupDelaySeconds', ([string]$options.StartupDelaySeconds),
        '-SequenceLoopCount', ([string]$options.SequenceLoopCount),
        '-AutoBuyCarLoopCount', ([string]$options.AutoBuyCarLoopCount),
        '-FindNewSubaruLoopCount', ([string]$options.FindNewSubaruLoopCount),
        '-StartFromStep', ([string]$options.StartFromStep),
        '-WorkflowLoopCount', ([string]$options.WorkflowLoopCount)
    )

    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -WindowStyle Hidden -PassThru
    $newState = $null
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        Start-Sleep -Milliseconds 300
        $newState = Get-UltimateState -Paths $paths
        if ($newState.Status -in @('Running', 'RunningUnverified') -or $process.HasExited) {
            break
        }
    }

    if ($newState -and $newState.Status -in @('Running', 'RunningUnverified')) {
        return "Ultimate started. PID=$($newState.Pid). SequenceLoops=$($options.SequenceLoopCount). InputMethod=$($options.InputMethod). Switch to the game window within $($options.StartupDelaySeconds) seconds."
    }

    if ($process.HasExited) {
        throw "Ultimate exited early. Check log: $($paths.LogPath)"
    }

    return "Ultimate process started. PID=$($process.Id)"
}

function Stop-AppUltimate {
    $paths = Get-AppUltimatePaths
    Initialize-UltimateWorkspace -Paths $paths
    $state = Get-UltimateState -Paths $paths

    if ($state.Status -in @('Running', 'RunningUnverified')) {
        Release-AfkKeys
        Stop-Process -Id $state.Pid -Force -ErrorAction Stop
        Start-Sleep -Milliseconds 300
        Release-AfkKeys
        Remove-UltimatePid -Paths $paths
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message "Ultimate stopped by GUI. PID=$($state.Pid)"
        return "Ultimate stopped. PID=$($state.Pid)"
    }

    Release-AfkKeys
    Remove-StaleUltimatePid -Paths $paths -State $state
    return $state.Message
}

if ($SelfTest) {
    $config = Get-AppBackupConfig
    Initialize-BackupWorkspace -Config $config
    $backupState = Get-WatcherState -Config $config
    $focusPaths = Get-AppFocusPaths
    Initialize-FocusWorkspace -Paths $focusPaths
    $focusState = Get-FocusLockState -Paths $focusPaths
    $afkPaths = Get-AppAfkPaths
    Initialize-AfkWorkspace -Paths $afkPaths
    $afkConfig = Get-AppAfkConfig
    $afkOptions = Resolve-AfkRuntimeOptions -Config $afkConfig
    $afkState = Get-AfkState -Paths $afkPaths
    $automationPaths = Get-AppAutomationPaths
    Initialize-AutomationWorkspace -Paths $automationPaths
    $automationConfig = Get-AppAutomationConfig
    $autoBuyOptions = Resolve-AutomationRuntimeOptions -Config $automationConfig -Mode 'AutoBuyCar'
    $deleteCarOptions = Resolve-AutomationRuntimeOptions -Config $automationConfig -Mode 'DeleteCar'
    $findOptions = Resolve-AutomationRuntimeOptions -Config $automationConfig -Mode 'FindNewSubaru'
    $automationState = Get-AutomationState -Paths $automationPaths
    $ultimatePaths = Get-AppUltimatePaths
    Initialize-UltimateWorkspace -Paths $ultimatePaths
    $ultimateConfig = Get-AppUltimateConfig
    $ultimateOptions = Resolve-UltimateRuntimeOptions -Config $ultimateConfig
    $ultimateState = Get-UltimateState -Paths $ultimatePaths
    $windowCount = @(Get-FocusWindowList).Count

    Write-Host 'GameSave Guardian self-test passed.'
    Write-Host "Source: $($config.SourcePath)"
    Write-Host "Backups: $($config.BackupRoot)"
    Write-Host "Auto backup status: $($backupState.Status)"
    Write-Host "Focus lock status: $($focusState.Status)"
    Write-Host "AFK status: $($afkState.Status)"
    Write-Host "AFK startup delay: $($afkOptions.StartupDelaySeconds)"
    Write-Host "AFK input method: $($afkOptions.InputMethod)"
    Write-Host "AFK MacroCombo steps: $(@($afkOptions.MacroComboSteps).Count)"
    Write-Host "Automation status: $($automationState.Status)"
    Write-Host "AutoBuyCar loop count: $($autoBuyOptions.LoopCount)"
    Write-Host "Automation input method: $($autoBuyOptions.InputMethod)"
    Write-Host "DeleteCar loop count: $($deleteCarOptions.LoopCount)"
    Write-Host "DeleteCar steps: $(@($deleteCarOptions.DeleteCarSteps).Count)"
    Write-Host "FindNewSubaru max attempts: $($findOptions.FindNewSubaruMaxSearchAttempts)"
    Write-Host "FindNewSubaru after-select delay: $($findOptions.FindNewSubaruAfterSelectDelayMilliseconds) ms"
    Write-Host "Ultimate status: $($ultimateState.Status)"
    Write-Host "Ultimate share code: $($ultimateOptions.ShareCode)"
    Write-Host "Ultimate sequence loops: $($ultimateOptions.SequenceLoopCount)"
    Write-Host "Ultimate target keywords: $($ultimateOptions.TargetKeywords -join ', ')"
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

$afkTab = New-Object System.Windows.Forms.TabPage
$afkTab.Text = 'AFK'
$tabs.TabPages.Add($afkTab)

$automationTab = New-Object System.Windows.Forms.TabPage
$automationTab.Text = 'Automation'
$tabs.TabPages.Add($automationTab)

$ultimateTab = New-Object System.Windows.Forms.TabPage
$ultimateTab.Text = 'Ultimate'
$tabs.TabPages.Add($ultimateTab)

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

$afkStatusLabel = New-Object System.Windows.Forms.Label
$afkStatusLabel.Location = New-Object System.Drawing.Point(16, 16)
$afkStatusLabel.Size = New-Object System.Drawing.Size(760, 22)
$afkStatusLabel.Text = 'Status: loading...'
$afkTab.Controls.Add($afkStatusLabel)

$afkModeLabel = New-Object System.Windows.Forms.Label
$afkModeLabel.Location = New-Object System.Drawing.Point(16, 50)
$afkModeLabel.Size = New-Object System.Drawing.Size(110, 24)
$afkModeLabel.Text = 'AFK mode'
$afkTab.Controls.Add($afkModeLabel)

$afkModeCombo = New-Object System.Windows.Forms.ComboBox
$afkModeCombo.Location = New-Object System.Drawing.Point(132, 48)
$afkModeCombo.Size = New-Object System.Drawing.Size(260, 24)
$afkModeCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$afkModeCombo.Items.Add('Sequence')
[void]$afkModeCombo.Items.Add('EnterEvery10s')
[void]$afkModeCombo.Items.Add('MacroCombo')
$afkModeCombo.SelectedIndex = 0
$afkTab.Controls.Add($afkModeCombo)

$afkInfoBox = New-Object System.Windows.Forms.TextBox
$afkInfoBox.Location = New-Object System.Drawing.Point(16, 86)
$afkInfoBox.Size = New-Object System.Drawing.Size(746, 120)
$afkInfoBox.Multiline = $true
$afkInfoBox.ReadOnly = $true
$afkInfoBox.Text = "AFK sends keys to the current foreground window. Before starting, switch to the game within the configured countdown.`r`nAFK timing values and input method are read from config.json: startup delay, Sequence waits, EnterEvery10s delay, key tap hold time, MacroCombo steps, MacroCombo cycle delay, and afk.inputMethod.`r`nStop AFK also sends a W key-up as a safety fallback."
$afkTab.Controls.Add($afkInfoBox)

$afkButtonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$afkButtonPanel.Location = New-Object System.Drawing.Point(16, 224)
$afkButtonPanel.Size = New-Object System.Drawing.Size(760, 86)
$afkButtonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$afkButtonPanel.WrapContents = $true
$afkTab.Controls.Add($afkButtonPanel)

$startAfkButton = New-AppButton -Text 'Start AFK'
$stopAfkButton = New-AppButton -Text 'Stop AFK'
$refreshAfkButton = New-AppButton -Text 'Refresh Status'
$openAfkLogButton = New-AppButton -Text 'Open AFK Log'
@($startAfkButton, $stopAfkButton, $refreshAfkButton, $openAfkLogButton) |
    ForEach-Object { $afkButtonPanel.Controls.Add($_) }

$afkLogBox = New-Object System.Windows.Forms.TextBox
$afkLogBox.Location = New-Object System.Drawing.Point(16, 332)
$afkLogBox.Size = New-Object System.Drawing.Size(746, 196)
$afkLogBox.Multiline = $true
$afkLogBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$afkLogBox.ReadOnly = $true
$afkTab.Controls.Add($afkLogBox)

$automationStatusLabel = New-Object System.Windows.Forms.Label
$automationStatusLabel.Location = New-Object System.Drawing.Point(16, 16)
$automationStatusLabel.Size = New-Object System.Drawing.Size(760, 22)
$automationStatusLabel.Text = 'Status: loading...'
$automationTab.Controls.Add($automationStatusLabel)

$automationModeLabel = New-Object System.Windows.Forms.Label
$automationModeLabel.Location = New-Object System.Drawing.Point(16, 50)
$automationModeLabel.Size = New-Object System.Drawing.Size(110, 24)
$automationModeLabel.Text = 'Mode'
$automationTab.Controls.Add($automationModeLabel)

$automationModeCombo = New-Object System.Windows.Forms.ComboBox
$automationModeCombo.Location = New-Object System.Drawing.Point(132, 48)
$automationModeCombo.Size = New-Object System.Drawing.Size(220, 24)
$automationModeCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$automationModeCombo.Items.Add('AutoBuyCar')
[void]$automationModeCombo.Items.Add('DeleteCar')
[void]$automationModeCombo.Items.Add('FindNewSubaru')
$automationModeCombo.SelectedIndex = 0
$automationTab.Controls.Add($automationModeCombo)

$automationLoopLabel = New-Object System.Windows.Forms.Label
$automationLoopLabel.Location = New-Object System.Drawing.Point(382, 50)
$automationLoopLabel.Size = New-Object System.Drawing.Size(90, 24)
$automationLoopLabel.Text = 'Loop count'
$automationTab.Controls.Add($automationLoopLabel)

$automationLoopInput = New-Object System.Windows.Forms.NumericUpDown
$automationLoopInput.Location = New-Object System.Drawing.Point(478, 48)
$automationLoopInput.Size = New-Object System.Drawing.Size(100, 24)
$automationLoopInput.Minimum = 1
$automationLoopInput.Maximum = 999
$automationLoopInput.Value = 1
$automationTab.Controls.Add($automationLoopInput)

$automationInfoBox = New-Object System.Windows.Forms.TextBox
$automationInfoBox.Location = New-Object System.Drawing.Point(16, 86)
$automationInfoBox.Size = New-Object System.Drawing.Size(746, 134)
$automationInfoBox.Multiline = $true
$automationInfoBox.ReadOnly = $true
$automationInfoBox.Text = "Automation sends keys to the current foreground game window after a countdown.`r`nDefault input method is SendKeys, matching the original simple AFK script more closely. You can change automation.inputMethod in config.json.`r`nAutoBuyCar repeats: Space, Down, Enter, Enter, Enter with configured waits.`r`nDeleteCar repeats the configured Enter/S menu sequence for the chosen loop count.`r`nFindNewSubaru searches left until it finds a new 1998 Subaru, selects it, waits for the configured delay, then runs AFK MacroCombo."
$automationTab.Controls.Add($automationInfoBox)

$automationButtonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$automationButtonPanel.Location = New-Object System.Drawing.Point(16, 238)
$automationButtonPanel.Size = New-Object System.Drawing.Size(760, 86)
$automationButtonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$automationButtonPanel.WrapContents = $true
$automationTab.Controls.Add($automationButtonPanel)

$startAutomationButton = New-AppButton -Text 'Start Automation'
$stopAutomationButton = New-AppButton -Text 'Stop Automation'
$refreshAutomationButton = New-AppButton -Text 'Refresh Status'
$openAutomationLogButton = New-AppButton -Text 'Open Automation Log'
@($startAutomationButton, $stopAutomationButton, $refreshAutomationButton, $openAutomationLogButton) |
    ForEach-Object { $automationButtonPanel.Controls.Add($_) }

$automationLogBox = New-Object System.Windows.Forms.TextBox
$automationLogBox.Location = New-Object System.Drawing.Point(16, 346)
$automationLogBox.Size = New-Object System.Drawing.Size(746, 182)
$automationLogBox.Multiline = $true
$automationLogBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$automationLogBox.ReadOnly = $true
$automationTab.Controls.Add($automationLogBox)

$ultimateStatusLabel = New-Object System.Windows.Forms.Label
$ultimateStatusLabel.Location = New-Object System.Drawing.Point(16, 16)
$ultimateStatusLabel.Size = New-Object System.Drawing.Size(760, 22)
$ultimateStatusLabel.Text = 'Status: loading...'
$ultimateTab.Controls.Add($ultimateStatusLabel)

$ultimateLoopLabel = New-Object System.Windows.Forms.Label
$ultimateLoopLabel.Location = New-Object System.Drawing.Point(16, 46)
$ultimateLoopLabel.Size = New-Object System.Drawing.Size(100, 24)
$ultimateLoopLabel.Text = 'Sequence loops'
$ultimateTab.Controls.Add($ultimateLoopLabel)

$ultimateLoopInput = New-Object System.Windows.Forms.NumericUpDown
$ultimateLoopInput.Location = New-Object System.Drawing.Point(120, 44)
$ultimateLoopInput.Size = New-Object System.Drawing.Size(72, 24)
$ultimateLoopInput.Minimum = 1
$ultimateLoopInput.Maximum = 9999
$ultimateLoopInput.Value = 80
$ultimateTab.Controls.Add($ultimateLoopInput)

$ultimateAutoBuyLabel = New-Object System.Windows.Forms.Label
$ultimateAutoBuyLabel.Location = New-Object System.Drawing.Point(210, 46)
$ultimateAutoBuyLabel.Size = New-Object System.Drawing.Size(130, 24)
$ultimateAutoBuyLabel.Text = 'AutoBuyCar loops'
$ultimateTab.Controls.Add($ultimateAutoBuyLabel)

$ultimateAutoBuyInput = New-Object System.Windows.Forms.NumericUpDown
$ultimateAutoBuyInput.Location = New-Object System.Drawing.Point(344, 44)
$ultimateAutoBuyInput.Size = New-Object System.Drawing.Size(72, 24)
$ultimateAutoBuyInput.Minimum = 1
$ultimateAutoBuyInput.Maximum = 9999
$ultimateAutoBuyInput.Value = 1
$ultimateTab.Controls.Add($ultimateAutoBuyInput)

$ultimateFindLabel = New-Object System.Windows.Forms.Label
$ultimateFindLabel.Location = New-Object System.Drawing.Point(430, 46)
$ultimateFindLabel.Size = New-Object System.Drawing.Size(140, 24)
$ultimateFindLabel.Text = 'FindNewSubaru loops'
$ultimateTab.Controls.Add($ultimateFindLabel)

$ultimateFindInput = New-Object System.Windows.Forms.NumericUpDown
$ultimateFindInput.Location = New-Object System.Drawing.Point(574, 44)
$ultimateFindInput.Size = New-Object System.Drawing.Size(72, 24)
$ultimateFindInput.Minimum = 1
$ultimateFindInput.Maximum = 9999
$ultimateFindInput.Value = 1
$ultimateTab.Controls.Add($ultimateFindInput)

$ultimateWorkflowLabel = New-Object System.Windows.Forms.Label
$ultimateWorkflowLabel.Location = New-Object System.Drawing.Point(16, 74)
$ultimateWorkflowLabel.Size = New-Object System.Drawing.Size(92, 24)
$ultimateWorkflowLabel.Text = 'Ultimate loops'
$ultimateTab.Controls.Add($ultimateWorkflowLabel)

$ultimateWorkflowInput = New-Object System.Windows.Forms.NumericUpDown
$ultimateWorkflowInput.Location = New-Object System.Drawing.Point(110, 72)
$ultimateWorkflowInput.Size = New-Object System.Drawing.Size(58, 24)
$ultimateWorkflowInput.Minimum = 1
$ultimateWorkflowInput.Maximum = 99999
$ultimateWorkflowInput.Value = 1
$ultimateTab.Controls.Add($ultimateWorkflowInput)

$ultimateWorkflowForever = New-Object System.Windows.Forms.CheckBox
$ultimateWorkflowForever.Location = New-Object System.Drawing.Point(174, 73)
$ultimateWorkflowForever.Size = New-Object System.Drawing.Size(80, 24)
$ultimateWorkflowForever.Text = 'Forever'
$ultimateTab.Controls.Add($ultimateWorkflowForever)

$ultimateStartStepLabel = New-Object System.Windows.Forms.Label
$ultimateStartStepLabel.Location = New-Object System.Drawing.Point(262, 74)
$ultimateStartStepLabel.Size = New-Object System.Drawing.Size(72, 24)
$ultimateStartStepLabel.Text = 'Debug step'
$ultimateTab.Controls.Add($ultimateStartStepLabel)

$ultimateStartStepInput = New-Object System.Windows.Forms.NumericUpDown
$ultimateStartStepInput.Location = New-Object System.Drawing.Point(336, 72)
$ultimateStartStepInput.Size = New-Object System.Drawing.Size(50, 24)
$ultimateStartStepInput.Minimum = 5
$ultimateStartStepInput.Maximum = 14
$ultimateStartStepInput.Value = 5
$ultimateTab.Controls.Add($ultimateStartStepInput)

$ultimateStartStepHint = New-Object System.Windows.Forms.Label
$ultimateStartStepHint.Location = New-Object System.Drawing.Point(394, 74)
$ultimateStartStepHint.Size = New-Object System.Drawing.Size(368, 24)
$ultimateStartStepHint.Text = 'step 5-14; 5 = full run, 14 = FindNewSubaru. Forever = loop until stopped.'
$ultimateTab.Controls.Add($ultimateStartStepHint)

# Disable the loop-count box while "Forever" is checked (infinite has no count).
$ultimateWorkflowForever.Add_CheckedChanged({
    $ultimateWorkflowInput.Enabled = -not $ultimateWorkflowForever.Checked
})

$ultimateInfoBox = New-Object System.Windows.Forms.TextBox
$ultimateInfoBox.Location = New-Object System.Drawing.Point(16, 108)
$ultimateInfoBox.Size = New-Object System.Drawing.Size(746, 118)
$ultimateInfoBox.Multiline = $true
$ultimateInfoBox.ReadOnly = $true
$ultimateInfoBox.Text = "Ultimate is an independent workflow. It sends the configured menu macro, enters the share code, searches for the strict OCR target, selects it, runs its own Sequence loops, then a post-sequence macro, the AutoBuyCar sequence, a post-buy macro, and finally the FindNewSubaru search-and-buy loop.`r`nUltimate loops = how many times to repeat the WHOLE workflow; tick Forever for an unlimited loop (runs until you press Stop). The status line shows the current loop and an estimated finish time.`r`nSet Sequence / AutoBuyCar / FindNewSubaru loops above. AutoBuyCar and FindNewSubaru reuse the automation.* steps from config.json.`r`nDebug step (5-14) skips earlier phases for testing - the game must already be at the UI state that step expects. Leave it at 5 for a full run.`r`nThe status line also shows the cumulative cars AutoBuyCar has bought (kept across runs); Clear Count resets it. AFK and Automation cannot run at the same time as Ultimate."
$ultimateTab.Controls.Add($ultimateInfoBox)

$ultimateButtonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$ultimateButtonPanel.Location = New-Object System.Drawing.Point(16, 244)
$ultimateButtonPanel.Size = New-Object System.Drawing.Size(760, 86)
$ultimateButtonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$ultimateButtonPanel.WrapContents = $true
$ultimateTab.Controls.Add($ultimateButtonPanel)

$startUltimateButton = New-AppButton -Text 'Start Ultimate'
$stopUltimateButton = New-AppButton -Text 'Stop Ultimate'
$refreshUltimateButton = New-AppButton -Text 'Refresh Status'
$openUltimateLogButton = New-AppButton -Text 'Open Ultimate Log'
$clearUltimateCountButton = New-AppButton -Text 'Clear Count'
@($startUltimateButton, $stopUltimateButton, $refreshUltimateButton, $openUltimateLogButton, $clearUltimateCountButton) |
    ForEach-Object { $ultimateButtonPanel.Controls.Add($_) }

$ultimateLogBox = New-Object System.Windows.Forms.TextBox
$ultimateLogBox.Location = New-Object System.Drawing.Point(16, 348)
$ultimateLogBox.Size = New-Object System.Drawing.Size(746, 180)
$ultimateLogBox.Multiline = $true
$ultimateLogBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$ultimateLogBox.ReadOnly = $true
$ultimateTab.Controls.Add($ultimateLogBox)

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

function Update-AfkLogPreview {
    param($Paths)

    if (Test-Path -LiteralPath $Paths.LogPath -PathType Leaf) {
        $afkLogBox.Text = ((Get-Content -LiteralPath $Paths.LogPath -Tail 80 -Encoding UTF8) -join [Environment]::NewLine)
    }
    else {
        $afkLogBox.Text = 'No AFK log yet.'
    }
}

function Refresh-AfkPanel {
    Invoke-AppSafely -FailureTitle 'AFK Status' -Action {
        $paths = Get-AppAfkPaths
        Initialize-AfkWorkspace -Paths $paths
        $afkConfig = Get-AppAfkConfig
        $options = Resolve-AfkRuntimeOptions -Config $afkConfig
        $state = Get-AfkState -Paths $paths

        $afkStatusLabel.Text = "Status: $($state.Status) - Input=$($options.InputMethod), Startup=$($options.StartupDelaySeconds)s Sequence=$($options.EnterDelaySeconds)s/$($options.XDelayMilliseconds)ms/$($options.LoopDelaySeconds)s EnterEvery=$($options.EnterOnlyDelaySeconds)s MacroDelay=$($options.MacroComboCycleDelaySeconds)s"
        Update-AfkLogPreview -Paths $paths
        Set-AppStatusText 'AFK status refreshed.'
    }
}

function Update-AutomationLogPreview {
    param($Paths)

    if (Test-Path -LiteralPath $Paths.LogPath -PathType Leaf) {
        $automationLogBox.Text = ((Get-Content -LiteralPath $Paths.LogPath -Tail 80 -Encoding UTF8) -join [Environment]::NewLine)
    }
    else {
        $automationLogBox.Text = 'No automation log yet.'
    }
}

function Set-AutomationLoopDefault {
    Invoke-AppSafely -FailureTitle 'Automation Mode' -Action {
        $mode = [string]$automationModeCombo.SelectedItem
        if ([string]::IsNullOrWhiteSpace($mode)) {
            $mode = 'AutoBuyCar'
        }

        $config = Get-AppAutomationConfig
        $options = Resolve-AutomationRuntimeOptions -Config $config -Mode $mode
        $value = [Math]::Min([decimal]$automationLoopInput.Maximum, [Math]::Max([decimal]$automationLoopInput.Minimum, [decimal]$options.LoopCount))
        $automationLoopInput.Value = $value
    }
}

function Refresh-AutomationPanel {
    Invoke-AppSafely -FailureTitle 'Automation Status' -Action {
        $paths = Get-AppAutomationPaths
        Initialize-AutomationWorkspace -Paths $paths
        $config = Get-AppAutomationConfig
        $autoBuyOptions = Resolve-AutomationRuntimeOptions -Config $config -Mode 'AutoBuyCar'
        $findOptions = Resolve-AutomationRuntimeOptions -Config $config -Mode 'FindNewSubaru'
        $state = Get-AutomationState -Paths $paths

        $automationStatusLabel.Text = "Status: $($state.Status) - Input=$($autoBuyOptions.InputMethod), AutoBuy loops=$($autoBuyOptions.LoopCount), Find loops=$($findOptions.LoopCount), Find max attempts=$($findOptions.FindNewSubaruMaxSearchAttempts), search=$($findOptions.FindNewSubaruSearchKey), after select=$($findOptions.FindNewSubaruAfterSelectDelayMilliseconds)ms"
        Update-AutomationLogPreview -Paths $paths
        Set-AppStatusText 'Automation status refreshed.'
    }
}

function Update-UltimateLogPreview {
    param($Paths)

    if (Test-Path -LiteralPath $Paths.LogPath -PathType Leaf) {
        $ultimateLogBox.Text = ((Get-Content -LiteralPath $Paths.LogPath -Tail 80 -Encoding UTF8) -join [Environment]::NewLine)
    }
    else {
        $ultimateLogBox.Text = 'No ultimate log yet.'
    }
}

function Set-UltimateLoopDefault {
    Invoke-AppSafely -FailureTitle 'Ultimate Loops' -Action {
        $config = Get-AppUltimateConfig
        $options = Resolve-UltimateRuntimeOptions -Config $config
        $value = [Math]::Min([decimal]$ultimateLoopInput.Maximum, [Math]::Max([decimal]$ultimateLoopInput.Minimum, [decimal]$options.SequenceLoopCount))
        $ultimateLoopInput.Value = $value

        # workflowLoopCount of 0 = infinite -> tick Forever; otherwise seed the count box.
        if ($options.WorkflowLoopCount -le 0) {
            $ultimateWorkflowForever.Checked = $true
        }
        else {
            $ultimateWorkflowForever.Checked = $false
            $workflowValue = [Math]::Min([decimal]$ultimateWorkflowInput.Maximum, [Math]::Max([decimal]$ultimateWorkflowInput.Minimum, [decimal]$options.WorkflowLoopCount))
            $ultimateWorkflowInput.Value = $workflowValue
        }
        $ultimateWorkflowInput.Enabled = -not $ultimateWorkflowForever.Checked

        $autoConfig = Get-AppAutomationConfig
        $autoOptions = Resolve-AutomationRuntimeOptions -Config $autoConfig -Mode 'AutoBuyCar'
        $autoValue = [Math]::Min([decimal]$ultimateAutoBuyInput.Maximum, [Math]::Max([decimal]$ultimateAutoBuyInput.Minimum, [decimal]$autoOptions.LoopCount))
        $ultimateAutoBuyInput.Value = $autoValue

        $findOptions = Resolve-AutomationRuntimeOptions -Config $autoConfig -Mode 'FindNewSubaru'
        $findValue = [Math]::Min([decimal]$ultimateFindInput.Maximum, [Math]::Max([decimal]$ultimateFindInput.Minimum, [decimal]$findOptions.LoopCount))
        $ultimateFindInput.Value = $findValue
    }
}

function Refresh-UltimatePanel {
    Invoke-AppSafely -FailureTitle 'Ultimate Status' -Action {
        $paths = Get-AppUltimatePaths
        Initialize-UltimateWorkspace -Paths $paths
        $config = Get-AppUltimateConfig
        $options = Resolve-UltimateRuntimeOptions -Config $config
        $state = Get-UltimateState -Paths $paths
        $boughtTotal = Get-UltimateAutoBuyCount -Paths $paths
        $progress = Get-UltimateProgress -Paths $paths
        $isRunning = $state.Status -in @('Running', 'RunningUnverified')

        $progressText = ''
        if ($progress -and -not [string]::IsNullOrWhiteSpace($progress.DisplayText)) {
            if ($isRunning) { $progressText = " | $($progress.DisplayText)" }
            elseif ($progress.Status -eq 'completed') { $progressText = " | Last run: $($progress.DisplayText)" }
            else { $progressText = " | (stopped) $($progress.DisplayText)" }
        }

        $ultimateStatusLabel.Text = "Status: $($state.Status)$progressText | Bought(total)=$boughtTotal | Seq=$($options.SequenceLoopCount) Search=$($options.SearchKey)/$($options.MaxSearchAttempts) Input=$($options.InputMethod)"
        Update-UltimateLogPreview -Paths $paths
        Set-AppStatusText 'Ultimate status refreshed.'
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

$refreshAfkButton.Add_Click({ Refresh-AfkPanel })
$startAfkButton.Add_Click({
    Invoke-AppSafely -FailureTitle 'Start AFK' -Action {
        $mode = [string]$afkModeCombo.SelectedItem
        if ([string]::IsNullOrWhiteSpace($mode)) {
            $mode = 'Sequence'
        }
        $afkConfig = Get-AppAfkConfig
        $options = Resolve-AfkRuntimeOptions -Config $afkConfig
        if ($mode -eq 'EnterEvery10s') {
            $sequenceText = "Sequence: Enter every $($options.EnterOnlyDelaySeconds) seconds. Input=$($options.InputMethod)."
        }
        elseif ($mode -eq 'MacroCombo') {
            $sequenceText = "Sequence: compressed menu macro. Steps=$(@($options.MacroComboSteps).Count), tap hold=$($options.KeyTapHoldMilliseconds)ms, cycle delay=$($options.MacroComboCycleDelaySeconds)s, input=$($options.InputMethod)."
        }
        else {
            $sequenceText = "Sequence: Enter, wait $($options.EnterDelaySeconds)s, x, wait $($options.XDelayMilliseconds)ms, x, wait $($options.XDelayMilliseconds)ms, Enter, wait $($options.LoopDelaySeconds)s, repeat. Input=$($options.InputMethod)."
        }
        $confirmation = [System.Windows.Forms.MessageBox]::Show(
            "AFK will send keys to the current foreground window.`r`n`r`nAfter clicking OK, switch to the game window within $($options.StartupDelaySeconds) seconds.`r`n`r`nMode: $mode`r`n$sequenceText",
            'Start AFK',
            [System.Windows.Forms.MessageBoxButtons]::OKCancel,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirmation -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }

        $message = Start-AppAfk -Mode $mode
        Set-AppStatusText $message
        Refresh-AfkPanel
        Show-AppMessage -Message $message
    }
})
$stopAfkButton.Add_Click({
    Invoke-AppSafely -FailureTitle 'Stop AFK' -Action {
        $message = Stop-AppAfk
        Set-AppStatusText $message
        Refresh-AfkPanel
        Show-AppMessage -Message $message
    }
})
$openAfkLogButton.Add_Click({
    Invoke-AppSafely -FailureTitle 'Open AFK Log' -Action {
        $paths = Get-AppAfkPaths
        Initialize-AfkWorkspace -Paths $paths
        Open-AppPath -Path $paths.LogPath -EnsureFile
    }
})

$automationModeCombo.Add_SelectedIndexChanged({
    Set-AutomationLoopDefault
})
$refreshAutomationButton.Add_Click({ Refresh-AutomationPanel })
$startAutomationButton.Add_Click({
    Invoke-AppSafely -FailureTitle 'Start Automation' -Action {
        $mode = [string]$automationModeCombo.SelectedItem
        if ([string]::IsNullOrWhiteSpace($mode)) {
            $mode = 'AutoBuyCar'
        }

        $config = Get-AppAutomationConfig
        $options = Resolve-AutomationRuntimeOptions -Config $config -Mode $mode -LoopCount ([int]$automationLoopInput.Value)
        if ($mode -eq 'AutoBuyCar') {
            $sequenceText = "AutoBuyCar will run $($options.LoopCount) loop(s). Steps=$(@($options.AutoBuyCarSteps).Count), between loops=$($options.AutoBuyCarBetweenLoopsMilliseconds)ms, input=$($options.InputMethod)."
        }
        elseif ($mode -eq 'DeleteCar') {
            $sequenceText = "DeleteCar will run $($options.LoopCount) loop(s). Steps=$(@($options.DeleteCarSteps).Count), between loops=$($options.DeleteCarBetweenLoopsMilliseconds)ms, input=$($options.InputMethod)."
        }
        else {
            $sequenceText = "FindNewSubaru will run $($options.LoopCount) loop(s). Search key=$($options.FindNewSubaruSearchKey), max attempts=$($options.FindNewSubaruMaxSearchAttempts), input=$($options.InputMethod), after-select delay=$($options.FindNewSubaruAfterSelectDelayMilliseconds)ms. OCR confirmation=$($options.FindNewSubaruRequireTargetConfirmation)."
        }

        $confirmation = [System.Windows.Forms.MessageBox]::Show(
            "Automation will send keys to the current foreground window.`r`n`r`nAfter clicking OK, switch to the game window within $($options.StartupDelaySeconds) seconds.`r`n`r`nMode: $mode`r`n$sequenceText",
            'Start Automation',
            [System.Windows.Forms.MessageBoxButtons]::OKCancel,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirmation -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }

        $message = Start-AppAutomation -Mode $mode -LoopCount ([int]$automationLoopInput.Value)
        Set-AppStatusText $message
        Refresh-AutomationPanel
        Show-AppMessage -Message $message
    }
})
$stopAutomationButton.Add_Click({
    Invoke-AppSafely -FailureTitle 'Stop Automation' -Action {
        $message = Stop-AppAutomation
        Set-AppStatusText $message
        Refresh-AutomationPanel
        Show-AppMessage -Message $message
    }
})
$openAutomationLogButton.Add_Click({
    Invoke-AppSafely -FailureTitle 'Open Automation Log' -Action {
        $paths = Get-AppAutomationPaths
        Initialize-AutomationWorkspace -Paths $paths
        Open-AppPath -Path $paths.LogPath -EnsureFile
    }
})

$refreshUltimateButton.Add_Click({ Refresh-UltimatePanel })
$startUltimateButton.Add_Click({
    Invoke-AppSafely -FailureTitle 'Start Ultimate' -Action {
        $config = Get-AppUltimateConfig
        $ultimateLoops = [int]$ultimateLoopInput.Value
        $ultimateAutoBuyLoops = [int]$ultimateAutoBuyInput.Value
        $ultimateFindLoops = [int]$ultimateFindInput.Value
        $ultimateStartStep = [int]$ultimateStartStepInput.Value
        $ultimateWorkflowLoops = if ($ultimateWorkflowForever.Checked) { 0 } else { [int]$ultimateWorkflowInput.Value }
        $options = Resolve-UltimateRuntimeOptions -Config $config -SequenceLoopCount $ultimateLoops -WorkflowLoopCount $ultimateWorkflowLoops
        $workflowText = if ($options.WorkflowLoopCount -le 0) { 'Repeat the whole workflow forever (until Stop).' } else { "Repeat the whole workflow $($options.WorkflowLoopCount) time(s)." }
        $sequenceText = "$workflowText Each run: enter share code $($options.ShareCode), search target [$($options.TargetKeywords -join ', ')], run $($options.SequenceLoopCount) Sequence loop(s), the post-sequence macro, $ultimateAutoBuyLoops AutoBuyCar loop(s), the post-buy macro, then $ultimateFindLoops FindNewSubaru loop(s). Input=$($options.InputMethod)."
        if ($ultimateStartStep -gt 5) {
            $sequenceText = "[DEBUG] Starting at step $ultimateStartStep - all earlier steps are skipped. Make sure the game is already at the UI state step $ultimateStartStep expects.`r`n`r`n$sequenceText"
        }

        $confirmation = [System.Windows.Forms.MessageBox]::Show(
            "Ultimate will send keys to the current foreground window.`r`n`r`nAfter clicking OK, switch to the game window within $($options.StartupDelaySeconds) seconds.`r`n`r`n$sequenceText",
            'Start Ultimate',
            [System.Windows.Forms.MessageBoxButtons]::OKCancel,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirmation -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }

        $message = Start-AppUltimate -SequenceLoopCount $ultimateLoops -AutoBuyCarLoopCount $ultimateAutoBuyLoops -FindNewSubaruLoopCount $ultimateFindLoops -StartFromStep $ultimateStartStep -WorkflowLoopCount $ultimateWorkflowLoops
        Set-AppStatusText $message
        Refresh-UltimatePanel
        Show-AppMessage -Message $message
    }
})
$stopUltimateButton.Add_Click({
    Invoke-AppSafely -FailureTitle 'Stop Ultimate' -Action {
        $message = Stop-AppUltimate
        Set-AppStatusText $message
        Refresh-UltimatePanel
        Show-AppMessage -Message $message
    }
})
$openUltimateLogButton.Add_Click({
    Invoke-AppSafely -FailureTitle 'Open Ultimate Log' -Action {
        $paths = Get-AppUltimatePaths
        Initialize-UltimateWorkspace -Paths $paths
        Open-AppPath -Path $paths.LogPath -EnsureFile
    }
})
$clearUltimateCountButton.Add_Click({
    Invoke-AppSafely -FailureTitle 'Clear AutoBuyCar Count' -Action {
        $paths = Get-AppUltimatePaths
        $current = Get-UltimateAutoBuyCount -Paths $paths
        $confirmation = [System.Windows.Forms.MessageBox]::Show(
            "Reset the cumulative AutoBuyCar bought count to 0?`r`n`r`nCurrent total: $current",
            'Clear Count',
            [System.Windows.Forms.MessageBoxButtons]::OKCancel,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($confirmation -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }
        Reset-UltimateAutoBuyCount -Paths $paths | Out-Null
        Refresh-UltimatePanel
        Set-AppStatusText 'AutoBuyCar bought count cleared.'
    }
})

$form.Add_Shown({
    Refresh-BackupPanel
    Refresh-FocusPanel
    Refresh-AfkPanel
    Refresh-AutomationPanel
    Refresh-UltimatePanel
    Set-AutomationLoopDefault
    Set-UltimateLoopDefault
    Refresh-WindowList
})

[void][System.Windows.Forms.Application]::Run($form)
