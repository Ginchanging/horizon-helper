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

# ---------------------------------------------------------------------------
# Dark theme palette + UI helpers. The whole GUI is themed from this one table;
# tweak a colour here and every tab follows. Colours are parsed once from hex.
# ---------------------------------------------------------------------------
$Theme = @{
    Bg          = [System.Drawing.ColorTranslator]::FromHtml('#1E1F22')  # window / page background
    Card        = [System.Drawing.ColorTranslator]::FromHtml('#26272B')  # section card fill
    LogBg       = [System.Drawing.ColorTranslator]::FromHtml('#15161A')  # log / input background
    Text        = [System.Drawing.ColorTranslator]::FromHtml('#E6E6E6')  # primary text
    Muted       = [System.Drawing.ColorTranslator]::FromHtml('#9AA0A6')  # secondary / hint text
    Accent      = [System.Drawing.ColorTranslator]::FromHtml('#3B82F6')  # primary buttons / selected nav / headers
    AccentHover = [System.Drawing.ColorTranslator]::FromHtml('#5A95F7')
    Neutral     = [System.Drawing.ColorTranslator]::FromHtml('#3A3B40')  # neutral buttons / borders
    NeutralHover= [System.Drawing.ColorTranslator]::FromHtml('#4A4B52')
    Ok          = [System.Drawing.ColorTranslator]::FromHtml('#4CAF50')  # status: running
    Warn        = [System.Drawing.ColorTranslator]::FromHtml('#E5C07B')  # log WARN lines
    Danger      = [System.Drawing.ColorTranslator]::FromHtml('#E0533B')  # stop buttons / bad status
    DangerHover = [System.Drawing.ColorTranslator]::FromHtml('#F06A52')
    Sidebar     = [System.Drawing.ColorTranslator]::FromHtml('#18191C')  # left nav rail
    SidebarHover= [System.Drawing.ColorTranslator]::FromHtml('#222327')  # nav item hover
    SidebarSel  = [System.Drawing.ColorTranslator]::FromHtml('#2B2C31')  # nav item selected fill
    White       = [System.Drawing.Color]::White
}
$MonoFont = New-Object System.Drawing.Font('Consolas', 9)

# System icon font (Segoe MDL2 Assets ships with Win10/11; Fluent Icons supersedes it on
# Win11 but keeps the same codepoints). $null when unavailable -> icons silently skipped.
$script:IconFont = $null
$script:IconFontSmall = $null
try {
    $probe = New-Object System.Drawing.Font('Segoe MDL2 Assets', 11)
    if ($probe.Name -eq 'Segoe MDL2 Assets') {
        $script:IconFont = $probe
        $script:IconFontSmall = New-Object System.Drawing.Font('Segoe MDL2 Assets', 9)
    }
}
catch { $script:IconFont = $null }

function New-AppRoundedPath {
    param(
        [Parameter(Mandatory = $true)][System.Drawing.Rectangle]$Rect,
        [int]$Radius = 6
    )

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $Radius * 2
    $path.AddArc($Rect.X, $Rect.Y, $d, $d, 180, 90)
    $path.AddArc($Rect.Right - $d, $Rect.Y, $d, $d, 270, 90)
    $path.AddArc($Rect.Right - $d, $Rect.Bottom - $d, $d, $d, 0, 90)
    $path.AddArc($Rect.X, $Rect.Bottom - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

# Swap a rounded app button's fill/hover colours at runtime (e.g. Pause <-> Resume).
function Set-AppButtonRole {
    param(
        [Parameter(Mandatory = $true)]$Button,
        [ValidateSet('Primary', 'Danger', 'Neutral')][string]$Role = 'Neutral'
    )

    switch ($Role) {
        'Primary' { $Button.Tag.Fill = $Theme.Accent;  $Button.Tag.Hover = $Theme.AccentHover }
        'Danger'  { $Button.Tag.Fill = $Theme.Danger;  $Button.Tag.Hover = $Theme.DangerHover }
        default   { $Button.Tag.Fill = $Theme.Neutral; $Button.Tag.Hover = $Theme.NeutralHover }
    }
    $Button.Invalidate()
}

# Rounded "button" built on a Panel. A WinForms Button cannot be reliably owner-drawn
# (it repaints its own square chrome), so we paint an anti-aliased rounded rect plus a
# centered optional-icon + text block ourselves. Panels expose the same surface the app
# already uses on buttons (.Text/.Enabled/.Add_Click), so call sites stay unchanged --
# except colour swaps, which must go through Set-AppButtonRole instead of .BackColor.
function New-AppButton {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [ValidateSet('Primary', 'Danger', 'Neutral')][string]$Role = 'Neutral',
        [string]$Icon = ''
    )

    $button = New-Object System.Windows.Forms.Panel
    $button.Text = $Text
    $button.Size = New-Object System.Drawing.Size(150, 34)
    $button.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 10)
    $button.BackColor = $Theme.Bg
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Tag = @{ Fill = $Theme.Neutral; Hover = $Theme.NeutralHover; IsHover = $false; Icon = $Icon }
    Set-AppButtonRole -Button $button -Role $Role

    $button.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $st = $sender.Tag
        $fill = if (-not $sender.Enabled) { $Theme.Card } elseif ($st.IsHover) { $st.Hover } else { $st.Fill }
        $textColor = if ($sender.Enabled) { $Theme.White } else { $Theme.Muted }
        $rect = New-Object System.Drawing.Rectangle(0, 0, ($sender.Width - 1), ($sender.Height - 1))
        $path = New-AppRoundedPath -Rect $rect -Radius 6
        $brush = New-Object System.Drawing.SolidBrush($fill)
        $g.FillPath($brush, $path)
        $brush.Dispose(); $path.Dispose()

        $flags = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::SingleLine
        $bounds = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)
        if ($script:IconFontSmall -and -not [string]::IsNullOrEmpty($st.Icon)) {
            # Centered [icon + 6px + text] block: measure both, then draw side by side.
            $iconSize = [System.Windows.Forms.TextRenderer]::MeasureText($g, $st.Icon, $script:IconFontSmall)
            $textSize = [System.Windows.Forms.TextRenderer]::MeasureText($g, $sender.Text, $sender.Font)
            $total = $iconSize.Width + 2 + $textSize.Width
            $x = [int](($sender.Width - $total) / 2)
            $iconRect = New-Object System.Drawing.Rectangle($x, 0, $iconSize.Width, $sender.Height)
            $textRect = New-Object System.Drawing.Rectangle(($x + $iconSize.Width + 2), 0, $textSize.Width, $sender.Height)
            $vc = [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::SingleLine
            [System.Windows.Forms.TextRenderer]::DrawText($g, $st.Icon, $script:IconFontSmall, $iconRect, $textColor, $vc)
            [System.Windows.Forms.TextRenderer]::DrawText($g, $sender.Text, $sender.Font, $textRect, $textColor, $vc)
        }
        else {
            [System.Windows.Forms.TextRenderer]::DrawText($g, $sender.Text, $sender.Font, $bounds, $textColor, $flags)
        }
    })
    $button.Add_MouseEnter({ param($sender, $e) $sender.Tag.IsHover = $true;  $sender.Invalidate() })
    $button.Add_MouseLeave({ param($sender, $e) $sender.Tag.IsHover = $false; $sender.Invalidate() })
    $button.Add_EnabledChanged({ param($sender, $e) $sender.Invalidate() })
    $button.Add_TextChanged({ param($sender, $e) $sender.Invalidate() })
    return $button
}

# A titled "card": a dark rounded panel with a bold accent header. Child controls are
# positioned below the header (y >= ~36 for absolute children, or set Dock=Fill on the
# single content control -- the card reserves 34px of top padding). The card's own
# BackColor stays Card (children inherit it); the Paint pass knocks the four corners
# back out to Bg and strokes the rounded border, so the card reads as a rounded shape.
function New-AppCard {
    param([string]$Title)

    $card = New-Object System.Windows.Forms.Panel
    $card.BackColor = $Theme.Card
    $card.Dock = [System.Windows.Forms.DockStyle]::Fill
    $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)
    $card.Padding = New-Object System.Windows.Forms.Padding(10, 34, 10, 10)
    $card.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $rect = New-Object System.Drawing.Rectangle(0, 0, ($sender.Width - 1), ($sender.Height - 1))
        $path = New-AppRoundedPath -Rect $rect -Radius 8
        # Repaint everything OUTSIDE the rounded path in the page background colour so the
        # corners look round without touching child controls (which sit well inside).
        $outside = New-Object System.Drawing.Region($sender.ClientRectangle)
        $outside.Exclude($path)
        $bgBrush = New-Object System.Drawing.SolidBrush($Theme.Bg)
        $g.FillRegion($bgBrush, $outside)
        $bgBrush.Dispose(); $outside.Dispose()
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $pen = New-Object System.Drawing.Pen($Theme.Neutral)
        $g.DrawPath($pen, $path)
        $pen.Dispose(); $path.Dispose()
    })
    $card.Add_Resize({ param($sender, $e) $sender.Invalidate() })
    if (-not [string]::IsNullOrEmpty($Title)) {
        $header = New-Object System.Windows.Forms.Label
        $header.Text = $Title
        $header.Font = New-Object System.Drawing.Font('Segoe UI', 9.75, [System.Drawing.FontStyle]::Bold)
        $header.ForeColor = $Theme.Accent
        $header.BackColor = [System.Drawing.Color]::Transparent
        $header.AutoSize = $true
        $header.Location = New-Object System.Drawing.Point(12, 8)
        $header.Tag = 'accent'
        $card.Controls.Add($header)
    }
    return $card
}

# One vertical stack (TableLayoutPanel) per tab: cards added top-to-bottom, the
# last "fill" row (the log / list) stretches to take the remaining height so the
# window resizes cleanly instead of clipping.
function New-AppTabTable {
    param([System.Windows.Forms.Control]$Tab)

    $table = New-Object System.Windows.Forms.TableLayoutPanel
    $table.Dock = [System.Windows.Forms.DockStyle]::Fill
    $table.ColumnCount = 1
    $table.RowCount = 0
    $table.Padding = New-Object System.Windows.Forms.Padding(12, 12, 12, 6)
    $table.BackColor = $Theme.Bg
    [void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $Tab.Controls.Add($table)
    return $table
}

function Add-AppRow {
    param(
        [System.Windows.Forms.TableLayoutPanel]$Table,
        [System.Windows.Forms.Control]$Control,
        [int]$Height = 0,
        [switch]$Fill
    )

    $row = $Table.RowCount
    $Table.RowCount = $row + 1
    if ($Fill) {
        [void]$Table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    }
    else {
        [void]$Table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, $Height)))
    }
    $Table.Controls.Add($Control, 0, $row)
}

# Recursively apply the dark palette to the "plain" controls (labels, inputs,
# combos, containers). TextBoxes/ListViews/Buttons/Panels are themed explicitly
# at construction. Label colour respects an opt-in Tag: 'accent' / 'muted' /
# 'status' (status labels are coloured dynamically by Set-AppStatusLabel).
function Set-AppTheme {
    param([System.Windows.Forms.Control]$Control)

    foreach ($child in $Control.Controls) {
        switch ($child.GetType().Name) {
            'Label' {
                switch ([string]$child.Tag) {
                    'accent' { $child.ForeColor = $Theme.Accent }
                    'muted'  { $child.ForeColor = $Theme.Muted }
                    'status' { }
                    default  { $child.ForeColor = $Theme.Text }
                }
            }
            'NumericUpDown' { $child.BackColor = $Theme.LogBg; $child.ForeColor = $Theme.Text; $child.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle }
            'ComboBox'      { $child.BackColor = $Theme.LogBg; $child.ForeColor = $Theme.Text; $child.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat }
            'CheckBox'      { $child.ForeColor = $Theme.Text }
            'FlowLayoutPanel'  { $child.BackColor = $Theme.Bg }
            'TableLayoutPanel' { $child.BackColor = $Theme.Bg }
            default { }
        }
        if ($child.Controls.Count -gt 0) {
            Set-AppTheme -Control $child
        }
    }
}

# Set a status label's text and colour it by run state: green=running,
# red=stale/conflict, muted=stopped/other.
function Set-AppStatusLabel {
    param(
        [System.Windows.Forms.Label]$Label,
        [string]$Text,
        [string]$Status
    )

    $Label.Text = $Text
    switch -Regex ($Status) {
        'Running'                      { $Label.ForeColor = $Theme.Ok; break }
        'Stale|InvalidPid|PidConflict' { $Label.ForeColor = $Theme.Danger; break }
        default                        { $Label.ForeColor = $Theme.Muted }
    }
}

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
        [string]$Title = 'Horizon6 Helper',
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )

    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon)
}

function Invoke-AppSafely {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [string]$FailureTitle = 'Horizon6 Helper'
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

function Set-AppUltimatePauseState {
    param(
        [Parameter(Mandatory = $true)][bool]$Paused
    )

    $paths = Get-AppUltimatePaths
    Initialize-UltimateWorkspace -Paths $paths
    if ($Paused) {
        Set-UltimatePause -Paths $paths
        Write-UltimateLog -Paths $paths -Level 'INFO' -Message 'Pause requested by GUI.'
        return 'Ultimate pause requested. It will halt at the next safe point (end of the current race/loop).'
    }
    Clear-UltimatePause -Paths $paths
    Write-UltimateLog -Paths $paths -Level 'INFO' -Message 'Resume requested by GUI.'
    return 'Ultimate resume requested. It will continue after a short countdown - switch back to the game.'
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

    Write-Host 'Horizon6 Helper self-test passed.'
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
$form.Text = 'Horizon6 Helper'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1010, 720)
$form.MinimumSize = New-Object System.Drawing.Size(960, 620)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.BackColor = $Theme.Bg
$form.ForeColor = $Theme.Text

# Dark native title bar (DWMWA_USE_IMMERSIVE_DARK_MODE). Attribute id is 20 on
# Win10 1903+/Win11 and 19 on 1809; anything older just ignores it (default bar).
try {
    Add-Type -Namespace GsgUi -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
'@
    $form.Add_HandleCreated({
        try {
            $dark = 1
            if ([GsgUi.Native]::DwmSetWindowAttribute($form.Handle, 20, [ref]$dark, 4) -ne 0) {
                [void][GsgUi.Native]::DwmSetWindowAttribute($form.Handle, 19, [ref]$dark, 4)
            }
        }
        catch { }
    })
}
catch { }

# Runtime-drawn window icon (accent rounded square + "H6") -- no .ico file shipped,
# so the BuildRelease allow-list stays untouched.
try {
    $iconBmp = New-Object System.Drawing.Bitmap(32, 32)
    $iconG = [System.Drawing.Graphics]::FromImage($iconBmp)
    $iconG.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $iconPath = New-AppRoundedPath -Rect (New-Object System.Drawing.Rectangle(1, 1, 30, 30)) -Radius 8
    $iconBrush = New-Object System.Drawing.SolidBrush($Theme.Accent)
    $iconG.FillPath($iconBrush, $iconPath)
    $iconFontH6 = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $iconSf = New-Object System.Drawing.StringFormat
    $iconSf.Alignment = [System.Drawing.StringAlignment]::Center
    $iconSf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $iconTextBrush = New-Object System.Drawing.SolidBrush($Theme.White)
    $iconG.DrawString('H6', $iconFontH6, $iconTextBrush, (New-Object System.Drawing.RectangleF(0, 0, 32, 32)), $iconSf)
    $form.Icon = [System.Drawing.Icon]::FromHandle($iconBmp.GetHicon())
    $iconTextBrush.Dispose(); $iconSf.Dispose(); $iconFontH6.Dispose(); $iconBrush.Dispose(); $iconPath.Dispose(); $iconG.Dispose()
}
catch { }

# ---------------------------------------------------------------------------
# Root layout: fixed left nav rail + content host (replaces the old TabControl).
# Each page's content is one TableLayoutPanel built by New-AppTabTable, exactly as
# before -- only the parent changed from a TabPage to a hidden page Panel, toggled
# by Select-AppPage. Nav items are owner-drawn (icon glyph + label + selected bar
# + a green "running" dot fed by the lightweight pid checks in $script:AppRunningMap).
# ---------------------------------------------------------------------------
$rootLayout = New-Object System.Windows.Forms.TableLayoutPanel
$rootLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$rootLayout.ColumnCount = 2
$rootLayout.RowCount = 1
$rootLayout.BackColor = $Theme.Bg
$rootLayout.Margin = New-Object System.Windows.Forms.Padding(0)
[void]$rootLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 190)))
[void]$rootLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$rootLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))

$sidebar = New-Object System.Windows.Forms.Panel
$sidebar.Dock = [System.Windows.Forms.DockStyle]::Fill
$sidebar.Margin = New-Object System.Windows.Forms.Padding(0)
$sidebar.BackColor = $Theme.Sidebar

$sidebarTitle = New-Object System.Windows.Forms.Label
$sidebarTitle.Text = 'Horizon6 Helper'
$sidebarTitle.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$sidebarTitle.ForeColor = $Theme.Text
$sidebarTitle.BackColor = $Theme.Sidebar
$sidebarTitle.AutoSize = $false
$sidebarTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$sidebarTitle.Location = New-Object System.Drawing.Point(16, 14)
$sidebarTitle.Size = New-Object System.Drawing.Size(170, 28)
$sidebarTitle.Tag = 'accent'
$sidebar.Controls.Add($sidebarTitle)

$contentHost = New-Object System.Windows.Forms.Panel
$contentHost.Dock = [System.Windows.Forms.DockStyle]::Fill
$contentHost.Margin = New-Object System.Windows.Forms.Padding(0)
$contentHost.BackColor = $Theme.Bg

$rootLayout.Controls.Add($sidebar, 0, 0)
$rootLayout.Controls.Add($contentHost, 1, 0)
$form.Controls.Add($rootLayout)

# Page registry: Key -> @{ Nav = nav item panel; Page = content panel }.
# Lightweight running map: Key -> bool, refreshed by the UI timer's heavy tick.
$script:AppPages = [ordered]@{}
$script:AppRunningMap = @{}

function New-AppPage {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Label,
        [string]$Icon = ''
    )

    $page = New-Object System.Windows.Forms.Panel
    $page.Dock = [System.Windows.Forms.DockStyle]::Fill
    $page.BackColor = $Theme.Bg
    $page.Visible = $false
    $contentHost.Controls.Add($page)

    $nav = New-Object System.Windows.Forms.Panel
    $nav.Size = New-Object System.Drawing.Size(190, 40)
    $nav.Location = New-Object System.Drawing.Point(0, (56 + ($script:AppPages.Count * 42)))
    $nav.BackColor = $Theme.Sidebar
    $nav.Cursor = [System.Windows.Forms.Cursors]::Hand
    $nav.Tag = @{ Key = $Key; Label = $Label; Icon = $Icon; Selected = $false; Hover = $false }
    $nav.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $st = $sender.Tag
        $fill = if ($st.Selected) { $Theme.SidebarSel } elseif ($st.Hover) { $Theme.SidebarHover } else { $Theme.Sidebar }
        $brush = New-Object System.Drawing.SolidBrush($fill)
        $g.FillRectangle($brush, 0, 0, $sender.Width, $sender.Height)
        $brush.Dispose()
        if ($st.Selected) {
            $barBrush = New-Object System.Drawing.SolidBrush($Theme.Accent)
            $g.FillRectangle($barBrush, 0, 8, 3, ($sender.Height - 16))
            $barBrush.Dispose()
        }
        $textColor = if ($st.Selected) { $Theme.White } else { $Theme.Muted }
        $vc = [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::SingleLine
        $textX = 16
        if ($script:IconFont -and -not [string]::IsNullOrEmpty($st.Icon)) {
            $iconRect = New-Object System.Drawing.Rectangle(16, 0, 24, $sender.Height)
            [System.Windows.Forms.TextRenderer]::DrawText($g, $st.Icon, $script:IconFont, $iconRect, $textColor, $vc)
            $textX = 46
        }
        $textRect = New-Object System.Drawing.Rectangle($textX, 0, ($sender.Width - $textX - 24), $sender.Height)
        [System.Windows.Forms.TextRenderer]::DrawText($g, $st.Label, $script:NavFont, $textRect, $textColor, $vc)
        if ($script:AppRunningMap[$st.Key]) {
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $dotBrush = New-Object System.Drawing.SolidBrush($Theme.Ok)
            $g.FillEllipse($dotBrush, ($sender.Width - 18), [int](($sender.Height - 8) / 2), 8, 8)
            $dotBrush.Dispose()
        }
    })
    $nav.Add_MouseEnter({ param($sender, $e) $sender.Tag.Hover = $true;  $sender.Invalidate() })
    $nav.Add_MouseLeave({ param($sender, $e) $sender.Tag.Hover = $false; $sender.Invalidate() })
    $nav.Add_Click({ param($sender, $e) Select-AppPage -Key $sender.Tag.Key })
    $sidebar.Controls.Add($nav)

    $script:AppPages[$Key] = @{ Nav = $nav; Page = $page }
    $script:AppRunningMap[$Key] = $false
    return $page
}

function Select-AppPage {
    param([Parameter(Mandatory = $true)][string]$Key)

    foreach ($entry in $script:AppPages.GetEnumerator()) {
        $isSel = ($entry.Key -eq $Key)
        $entry.Value.Page.Visible = $isSel
        $entry.Value.Nav.Tag.Selected = $isSel
        $entry.Value.Nav.Invalidate()
    }
}

$script:NavFont = New-Object System.Drawing.Font('Segoe UI', 10)

# Ultimate is the primary workflow -> first nav item, selected at startup.
# Icon glyphs are Segoe MDL2 Assets codepoints (lightning/save/lock/clock/wrench).
$ultimateTab = New-AppPage -Key 'Ultimate' -Label 'Ultimate' -Icon ([string][char]0xE945)
$backupTab = New-AppPage -Key 'Backup' -Label 'Backup' -Icon ([string][char]0xE74E)
$focusTab = New-AppPage -Key 'Focus' -Label 'Focus Lock' -Icon ([string][char]0xE72E)
$afkTab = New-AppPage -Key 'Afk' -Label 'AFK' -Icon ([string][char]0xE823)
$automationTab = New-AppPage -Key 'Automation' -Label 'Automation' -Icon ([string][char]0xE90F)

# ---------------------------- Backup tab ----------------------------
$anchorTLR = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$backupTable = New-AppTabTable -Tab $backupTab

$backupStatusCard = New-AppCard -Title 'Backup'
$backupStatusLabel = New-Object System.Windows.Forms.Label
$backupStatusLabel.Location = New-Object System.Drawing.Point(14, 40)
$backupStatusLabel.Size = New-Object System.Drawing.Size(790, 22)
$backupStatusLabel.Anchor = $anchorTLR
$backupStatusLabel.Text = 'Status: loading...'
$backupStatusLabel.Tag = 'status'
$backupStatusLabel.ForeColor = $Theme.Muted
$backupStatusCard.Controls.Add($backupStatusLabel)
Add-AppRow -Table $backupTable -Control $backupStatusCard -Height 70

$backupFoldersCard = New-AppCard -Title 'Folders'
$sourceLabel = New-Object System.Windows.Forms.Label
$sourceLabel.Location = New-Object System.Drawing.Point(14, 42)
$sourceLabel.Size = New-Object System.Drawing.Size(100, 22)
$sourceLabel.Text = 'Save folder'
$backupFoldersCard.Controls.Add($sourceLabel)

$sourceBox = New-Object System.Windows.Forms.TextBox
$sourceBox.Location = New-Object System.Drawing.Point(118, 40)
$sourceBox.Size = New-Object System.Drawing.Size(700, 24)
$sourceBox.Anchor = $anchorTLR
$sourceBox.ReadOnly = $true
$sourceBox.BackColor = $Theme.LogBg
$sourceBox.ForeColor = $Theme.Muted
$sourceBox.Font = $MonoFont
$sourceBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$backupFoldersCard.Controls.Add($sourceBox)

$backupRootLabel = New-Object System.Windows.Forms.Label
$backupRootLabel.Location = New-Object System.Drawing.Point(14, 74)
$backupRootLabel.Size = New-Object System.Drawing.Size(100, 22)
$backupRootLabel.Text = 'Backup folder'
$backupFoldersCard.Controls.Add($backupRootLabel)

$backupRootBox = New-Object System.Windows.Forms.TextBox
$backupRootBox.Location = New-Object System.Drawing.Point(118, 72)
$backupRootBox.Size = New-Object System.Drawing.Size(700, 24)
$backupRootBox.Anchor = $anchorTLR
$backupRootBox.ReadOnly = $true
$backupRootBox.BackColor = $Theme.LogBg
$backupRootBox.ForeColor = $Theme.Muted
$backupRootBox.Font = $MonoFont
$backupRootBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$backupFoldersCard.Controls.Add($backupRootBox)

$latestBackupLabel = New-Object System.Windows.Forms.Label
$latestBackupLabel.Location = New-Object System.Drawing.Point(14, 106)
$latestBackupLabel.Size = New-Object System.Drawing.Size(100, 22)
$latestBackupLabel.Text = 'Latest backup'
$backupFoldersCard.Controls.Add($latestBackupLabel)

$latestBackupBox = New-Object System.Windows.Forms.TextBox
$latestBackupBox.Location = New-Object System.Drawing.Point(118, 104)
$latestBackupBox.Size = New-Object System.Drawing.Size(700, 24)
$latestBackupBox.Anchor = $anchorTLR
$latestBackupBox.ReadOnly = $true
$latestBackupBox.BackColor = $Theme.LogBg
$latestBackupBox.ForeColor = $Theme.Muted
$latestBackupBox.Font = $MonoFont
$latestBackupBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$backupFoldersCard.Controls.Add($latestBackupBox)
Add-AppRow -Table $backupTable -Control $backupFoldersCard -Height 142

$backupButtonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$backupButtonPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$backupButtonPanel.Margin = New-Object System.Windows.Forms.Padding(0)
$backupButtonPanel.BackColor = $Theme.Bg
$backupButtonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$backupButtonPanel.WrapContents = $true

$refreshBackupButton = New-AppButton -Text 'Refresh' -Role Neutral -Icon ([string][char]0xE72C)
$backupNowButton = New-AppButton -Text 'Backup Now' -Role Primary -Icon ([string][char]0xE74E)
$startBackupButton = New-AppButton -Text 'Start Auto Backup' -Role Primary -Icon ([string][char]0xE768)
$stopBackupButton = New-AppButton -Text 'Stop Auto Backup' -Role Danger -Icon ([string][char]0xE71A)
$openBackupsButton = New-AppButton -Text 'Open Backups' -Role Neutral -Icon ([string][char]0xE838)
$openBackupLogButton = New-AppButton -Text 'Open Backup Log' -Role Neutral -Icon ([string][char]0xE838)

@($refreshBackupButton, $backupNowButton, $startBackupButton, $stopBackupButton, $openBackupsButton, $openBackupLogButton) |
    ForEach-Object { $backupButtonPanel.Controls.Add($_) }
Add-AppRow -Table $backupTable -Control $backupButtonPanel -Height 92

$backupLogCard = New-AppCard -Title 'Recent log'
$backupLogBox = New-Object System.Windows.Forms.TextBox
$backupLogBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$backupLogBox.Multiline = $true
$backupLogBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$backupLogBox.ReadOnly = $true
$backupLogBox.BackColor = $Theme.LogBg
$backupLogBox.ForeColor = $Theme.Text
$backupLogBox.Font = $MonoFont
$backupLogBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$backupLogCard.Controls.Add($backupLogBox)
Add-AppRow -Table $backupTable -Control $backupLogCard -Fill

# ---------------------------- Focus Lock tab ----------------------------
$focusTable = New-AppTabTable -Tab $focusTab

$focusStatusCard = New-AppCard -Title 'Focus Lock'
$focusStatusLabel = New-Object System.Windows.Forms.Label
$focusStatusLabel.Location = New-Object System.Drawing.Point(14, 40)
$focusStatusLabel.Size = New-Object System.Drawing.Size(790, 22)
$focusStatusLabel.Anchor = $anchorTLR
$focusStatusLabel.Text = 'Status: loading...'
$focusStatusLabel.Tag = 'status'
$focusStatusLabel.ForeColor = $Theme.Muted
$focusStatusCard.Controls.Add($focusStatusLabel)

$focusTargetLabel = New-Object System.Windows.Forms.Label
$focusTargetLabel.Location = New-Object System.Drawing.Point(14, 66)
$focusTargetLabel.Size = New-Object System.Drawing.Size(790, 22)
$focusTargetLabel.Anchor = $anchorTLR
$focusTargetLabel.Text = 'Target: none'
$focusStatusCard.Controls.Add($focusTargetLabel)
Add-AppRow -Table $focusTable -Control $focusStatusCard -Height 96

$focusWindowsCard = New-AppCard -Title 'Windows'
$windowList = New-Object System.Windows.Forms.ListView
$windowList.Dock = [System.Windows.Forms.DockStyle]::Fill
$windowList.View = [System.Windows.Forms.View]::Details
$windowList.FullRowSelect = $true
$windowList.MultiSelect = $false
$windowList.HideSelection = $false
$windowList.BackColor = $Theme.LogBg
$windowList.ForeColor = $Theme.Text
$windowList.BorderStyle = [System.Windows.Forms.BorderStyle]::None
[void]$windowList.Columns.Add('PID', 80)
[void]$windowList.Columns.Add('Process', 150)
[void]$windowList.Columns.Add('Title', 420)
[void]$windowList.Columns.Add('Handle', 110)
$focusWindowsCard.Controls.Add($windowList)
Add-AppRow -Table $focusTable -Control $focusWindowsCard -Fill

$focusButtonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$focusButtonPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$focusButtonPanel.Margin = New-Object System.Windows.Forms.Padding(0)
$focusButtonPanel.BackColor = $Theme.Bg
$focusButtonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$focusButtonPanel.WrapContents = $true

$refreshWindowsButton = New-AppButton -Text 'Refresh Windows' -Role Neutral -Icon ([string][char]0xE72C)
$startFocusButton = New-AppButton -Text 'Start Focus Lock' -Role Primary -Icon ([string][char]0xE768)
$stopFocusButton = New-AppButton -Text 'Stop Focus Lock' -Role Danger -Icon ([string][char]0xE71A)
$refreshFocusButton = New-AppButton -Text 'Refresh Status' -Role Neutral -Icon ([string][char]0xE72C)
$openFocusLogButton = New-AppButton -Text 'Open Focus Log' -Role Neutral -Icon ([string][char]0xE838)
@($refreshWindowsButton, $startFocusButton, $stopFocusButton, $refreshFocusButton, $openFocusLogButton) |
    ForEach-Object { $focusButtonPanel.Controls.Add($_) }
Add-AppRow -Table $focusTable -Control $focusButtonPanel -Height 52

# ---------------------------- AFK tab ----------------------------
$afkTable = New-AppTabTable -Tab $afkTab

$afkStatusCard = New-AppCard -Title 'AFK'
$afkStatusLabel = New-Object System.Windows.Forms.Label
$afkStatusLabel.Location = New-Object System.Drawing.Point(14, 40)
$afkStatusLabel.Size = New-Object System.Drawing.Size(790, 22)
$afkStatusLabel.Anchor = $anchorTLR
$afkStatusLabel.Text = 'Status: loading...'
$afkStatusLabel.Tag = 'status'
$afkStatusLabel.ForeColor = $Theme.Muted
$afkStatusCard.Controls.Add($afkStatusLabel)
Add-AppRow -Table $afkTable -Control $afkStatusCard -Height 70

$afkSettingsCard = New-AppCard -Title 'Mode'
$afkModeLabel = New-Object System.Windows.Forms.Label
$afkModeLabel.Location = New-Object System.Drawing.Point(14, 42)
$afkModeLabel.Size = New-Object System.Drawing.Size(100, 24)
$afkModeLabel.Text = 'AFK mode'
$afkSettingsCard.Controls.Add($afkModeLabel)

$afkModeCombo = New-Object System.Windows.Forms.ComboBox
$afkModeCombo.Location = New-Object System.Drawing.Point(118, 40)
$afkModeCombo.Size = New-Object System.Drawing.Size(260, 24)
$afkModeCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$afkModeCombo.Items.Add('Sequence')
[void]$afkModeCombo.Items.Add('EnterEvery10s')
[void]$afkModeCombo.Items.Add('MacroCombo')
$afkModeCombo.SelectedIndex = 0
$afkSettingsCard.Controls.Add($afkModeCombo)
Add-AppRow -Table $afkTable -Control $afkSettingsCard -Height 64

$afkAboutCard = New-AppCard -Title 'About'
$afkInfoBox = New-Object System.Windows.Forms.TextBox
$afkInfoBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$afkInfoBox.Multiline = $true
$afkInfoBox.ReadOnly = $true
$afkInfoBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$afkInfoBox.BackColor = $Theme.Card
$afkInfoBox.ForeColor = $Theme.Muted
$afkInfoBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$afkInfoBox.Text = "AFK sends keys to the current foreground window. Before starting, switch to the game within the configured countdown.`r`nAFK timing values and input method are read from config.json: startup delay, Sequence waits, EnterEvery10s delay, key tap hold time, MacroCombo steps, MacroCombo cycle delay, and afk.inputMethod.`r`nStop AFK also sends a W key-up as a safety fallback."
$afkAboutCard.Controls.Add($afkInfoBox)
Add-AppRow -Table $afkTable -Control $afkAboutCard -Height 116

$afkButtonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$afkButtonPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$afkButtonPanel.Margin = New-Object System.Windows.Forms.Padding(0)
$afkButtonPanel.BackColor = $Theme.Bg
$afkButtonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$afkButtonPanel.WrapContents = $true

$startAfkButton = New-AppButton -Text 'Start AFK' -Role Primary -Icon ([string][char]0xE768)
$stopAfkButton = New-AppButton -Text 'Stop AFK' -Role Danger -Icon ([string][char]0xE71A)
$refreshAfkButton = New-AppButton -Text 'Refresh Status' -Role Neutral -Icon ([string][char]0xE72C)
$openAfkLogButton = New-AppButton -Text 'Open AFK Log' -Role Neutral -Icon ([string][char]0xE838)
@($startAfkButton, $stopAfkButton, $refreshAfkButton, $openAfkLogButton) |
    ForEach-Object { $afkButtonPanel.Controls.Add($_) }
Add-AppRow -Table $afkTable -Control $afkButtonPanel -Height 52

$afkLogCard = New-AppCard -Title 'Recent log'
$afkLogBox = New-Object System.Windows.Forms.TextBox
$afkLogBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$afkLogBox.Multiline = $true
$afkLogBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$afkLogBox.ReadOnly = $true
$afkLogBox.BackColor = $Theme.LogBg
$afkLogBox.ForeColor = $Theme.Text
$afkLogBox.Font = $MonoFont
$afkLogBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$afkLogCard.Controls.Add($afkLogBox)
Add-AppRow -Table $afkTable -Control $afkLogCard -Fill

# ---------------------------- Automation tab ----------------------------
$automationTable = New-AppTabTable -Tab $automationTab

$automationStatusCard = New-AppCard -Title 'Automation'
$automationStatusLabel = New-Object System.Windows.Forms.Label
$automationStatusLabel.Location = New-Object System.Drawing.Point(14, 40)
$automationStatusLabel.Size = New-Object System.Drawing.Size(790, 22)
$automationStatusLabel.Anchor = $anchorTLR
$automationStatusLabel.Text = 'Status: loading...'
$automationStatusLabel.Tag = 'status'
$automationStatusLabel.ForeColor = $Theme.Muted
$automationStatusCard.Controls.Add($automationStatusLabel)
Add-AppRow -Table $automationTable -Control $automationStatusCard -Height 70

$automationSettingsCard = New-AppCard -Title 'Mode & loops'
$automationModeLabel = New-Object System.Windows.Forms.Label
$automationModeLabel.Location = New-Object System.Drawing.Point(14, 42)
$automationModeLabel.Size = New-Object System.Drawing.Size(48, 24)
$automationModeLabel.Text = 'Mode'
$automationSettingsCard.Controls.Add($automationModeLabel)

$automationModeCombo = New-Object System.Windows.Forms.ComboBox
$automationModeCombo.Location = New-Object System.Drawing.Point(66, 40)
$automationModeCombo.Size = New-Object System.Drawing.Size(220, 24)
$automationModeCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$automationModeCombo.Items.Add('AutoBuyCar')
[void]$automationModeCombo.Items.Add('DeleteCar')
[void]$automationModeCombo.Items.Add('FindNewSubaru')
$automationModeCombo.SelectedIndex = 0
$automationSettingsCard.Controls.Add($automationModeCombo)

$automationLoopLabel = New-Object System.Windows.Forms.Label
$automationLoopLabel.Location = New-Object System.Drawing.Point(316, 42)
$automationLoopLabel.Size = New-Object System.Drawing.Size(80, 24)
$automationLoopLabel.Text = 'Loop count'
$automationSettingsCard.Controls.Add($automationLoopLabel)

$automationLoopInput = New-Object System.Windows.Forms.NumericUpDown
$automationLoopInput.Location = New-Object System.Drawing.Point(400, 40)
$automationLoopInput.Size = New-Object System.Drawing.Size(100, 24)
$automationLoopInput.Minimum = 1
$automationLoopInput.Maximum = 999
$automationLoopInput.Value = 1
$automationSettingsCard.Controls.Add($automationLoopInput)
Add-AppRow -Table $automationTable -Control $automationSettingsCard -Height 64

$automationAboutCard = New-AppCard -Title 'About'
$automationInfoBox = New-Object System.Windows.Forms.TextBox
$automationInfoBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$automationInfoBox.Multiline = $true
$automationInfoBox.ReadOnly = $true
$automationInfoBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$automationInfoBox.BackColor = $Theme.Card
$automationInfoBox.ForeColor = $Theme.Muted
$automationInfoBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$automationInfoBox.Text = "Automation sends keys to the current foreground game window after a countdown.`r`nDefault input method is SendKeys, matching the original simple AFK script more closely. You can change automation.inputMethod in config.json.`r`nAutoBuyCar repeats: Space, Down, Enter, Enter, Enter with configured waits.`r`nDeleteCar repeats the configured Enter/S menu sequence for the chosen loop count.`r`nFindNewSubaru searches left until it finds a new 1998 Subaru, selects it, waits for the configured delay, then runs AFK MacroCombo."
$automationAboutCard.Controls.Add($automationInfoBox)
Add-AppRow -Table $automationTable -Control $automationAboutCard -Height 130

$automationButtonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$automationButtonPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$automationButtonPanel.Margin = New-Object System.Windows.Forms.Padding(0)
$automationButtonPanel.BackColor = $Theme.Bg
$automationButtonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$automationButtonPanel.WrapContents = $true

$startAutomationButton = New-AppButton -Text 'Start Automation' -Role Primary -Icon ([string][char]0xE768)
$stopAutomationButton = New-AppButton -Text 'Stop Automation' -Role Danger -Icon ([string][char]0xE71A)
$refreshAutomationButton = New-AppButton -Text 'Refresh Status' -Role Neutral -Icon ([string][char]0xE72C)
$openAutomationLogButton = New-AppButton -Text 'Open Automation Log' -Role Neutral -Icon ([string][char]0xE838)
@($startAutomationButton, $stopAutomationButton, $refreshAutomationButton, $openAutomationLogButton) |
    ForEach-Object { $automationButtonPanel.Controls.Add($_) }
Add-AppRow -Table $automationTable -Control $automationButtonPanel -Height 52

$automationLogCard = New-AppCard -Title 'Recent log'
$automationLogBox = New-Object System.Windows.Forms.TextBox
$automationLogBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$automationLogBox.Multiline = $true
$automationLogBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$automationLogBox.ReadOnly = $true
$automationLogBox.BackColor = $Theme.LogBg
$automationLogBox.ForeColor = $Theme.Text
$automationLogBox.Font = $MonoFont
$automationLogBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$automationLogCard.Controls.Add($automationLogBox)
Add-AppRow -Table $automationTable -Control $automationLogCard -Fill

# ---------------------------- Ultimate tab ----------------------------
$ultimateTable = New-AppTabTable -Tab $ultimateTab

# Owner-drawn horizontal progress bar. The view hashtable (Fraction/Text/BarColor) is stored on
# the panel's .Tag so Update-UltimateLiveView can mutate it in place and Invalidate() to repaint.
# Fraction $null/0 = no fill (idle / infinite) -- the centered overlay text still describes state.
function New-AppProgressBar {
    param(
        [Parameter(Mandatory = $true)][hashtable]$View,
        [int]$Height = 18
    )

    $bar = New-Object System.Windows.Forms.Panel
    $bar.Size = New-Object System.Drawing.Size(790, $Height)
    $bar.Anchor = $anchorTLR
    $bar.BackColor = $Theme.LogBg
    $bar.Tag = $View
    $bar.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $view = $sender.Tag
        if ($null -ne $view.Fraction -and $view.Fraction -gt 0) {
            $fillWidth = [int]([Math]::Min(1.0, $view.Fraction) * $sender.Width)
            if ($fillWidth -gt 0) {
                $fillBrush = New-Object System.Drawing.SolidBrush($view.BarColor)
                $g.FillRectangle($fillBrush, 0, 0, $fillWidth, $sender.Height)
                $fillBrush.Dispose()
            }
        }
        if (-not [string]::IsNullOrEmpty($view.Text)) {
            $flags = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::SingleLine
            $bounds = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)
            [System.Windows.Forms.TextRenderer]::DrawText($g, $view.Text, $sender.Font, $bounds, $Theme.White, $flags)
        }
    })
    $bar.Add_Resize({ param($sender, $e) $sender.Invalidate() })
    return $bar
}

$ultimateStatusCard = New-AppCard -Title 'Ultimate'

# Big at-a-glance state line: RUNNING - Loop 2/10 / PAUSED / Stopped / Completed.
$ultimateBigStatusLabel = New-Object System.Windows.Forms.Label
$ultimateBigStatusLabel.Location = New-Object System.Drawing.Point(14, 34)
$ultimateBigStatusLabel.Size = New-Object System.Drawing.Size(790, 26)
$ultimateBigStatusLabel.Anchor = $anchorTLR
$ultimateBigStatusLabel.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$ultimateBigStatusLabel.Text = 'Loading...'
$ultimateBigStatusLabel.Tag = 'status'
$ultimateBigStatusLabel.ForeColor = $Theme.Muted
$ultimateStatusCard.Controls.Add($ultimateBigStatusLabel)

# Workflow-loop progress bar (outer loop N/total). View state lives in $script:UltimateProgressView.
$script:UltimateProgressView = @{ Fraction = $null; Text = ''; BarColor = $Theme.Accent }
$ultimateProgressBar = New-AppProgressBar -View $script:UltimateProgressView -Height 18
$ultimateProgressBar.Location = New-Object System.Drawing.Point(14, 62)
$ultimateStatusCard.Controls.Add($ultimateProgressBar)

# Inner-phase label: which Sequence / AutoBuyCar / FindNewSubaru iteration the worker is on now.
$ultimatePhaseLabel = New-Object System.Windows.Forms.Label
$ultimatePhaseLabel.Location = New-Object System.Drawing.Point(14, 84)
$ultimatePhaseLabel.Size = New-Object System.Drawing.Size(790, 20)
$ultimatePhaseLabel.Anchor = $anchorTLR
$ultimatePhaseLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9.75, [System.Drawing.FontStyle]::Bold)
$ultimatePhaseLabel.Text = ''
$ultimatePhaseLabel.Tag = 'status'
$ultimatePhaseLabel.ForeColor = $Theme.Muted
$ultimateStatusCard.Controls.Add($ultimatePhaseLabel)

# Per-phase progress bar (current iteration / phase total).
$script:UltimatePhaseView = @{ Fraction = $null; Text = ''; BarColor = $Theme.Accent }
$ultimatePhaseBar = New-AppProgressBar -View $script:UltimatePhaseView -Height 16
$ultimatePhaseBar.Location = New-Object System.Drawing.Point(14, 106)
$ultimateStatusCard.Controls.Add($ultimatePhaseBar)

# Detail line (muted): worker DisplayText (ETA etc), bought total, config summary. Tall enough to
# wrap onto a second line so the long config summary is never clipped.
$ultimateStatusLabel = New-Object System.Windows.Forms.Label
$ultimateStatusLabel.Location = New-Object System.Drawing.Point(14, 126)
$ultimateStatusLabel.Size = New-Object System.Drawing.Size(790, 38)
$ultimateStatusLabel.Anchor = $anchorTLR
$ultimateStatusLabel.Text = 'Status: loading...'
$ultimateStatusLabel.Tag = 'status'
$ultimateStatusLabel.ForeColor = $Theme.Muted
$ultimateStatusCard.Controls.Add($ultimateStatusLabel)

# These controls are built before the form is laid out, so an Anchor-Right would freeze a wrong
# (over-wide) width against the card's default 200px size -- that pushes centered bar captions to
# the far right and makes the detail label "wrap" past the visible edge (i.e. clip = still looks
# truncated). Anchor Top|Left only and drive the widths from the card's real width on every resize.
$anchorTL = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$ultimateStatusCardChildren = @($ultimateBigStatusLabel, $ultimateProgressBar, $ultimatePhaseLabel, $ultimatePhaseBar, $ultimateStatusLabel)
foreach ($c in $ultimateStatusCardChildren) { $c.Anchor = $anchorTL }
$ultimateStatusCard.Add_Resize({
    param($sender, $e)
    $w = $sender.ClientSize.Width - 28
    if ($w -lt 50) { return }
    $ultimateBigStatusLabel.Width = $w
    $ultimateProgressBar.Width = $w
    $ultimatePhaseLabel.Width = $w
    $ultimatePhaseBar.Width = $w
    $ultimateStatusLabel.Width = $w
    $ultimateProgressBar.Invalidate()
    $ultimatePhaseBar.Invalidate()
})
Add-AppRow -Table $ultimateTable -Control $ultimateStatusCard -Height 174

$ultimateSettingsCard = New-AppCard -Title 'Run settings'
$ultimateLoopLabel = New-Object System.Windows.Forms.Label
$ultimateLoopLabel.Location = New-Object System.Drawing.Point(14, 44)
$ultimateLoopLabel.Size = New-Object System.Drawing.Size(96, 22)
$ultimateLoopLabel.Text = 'Sequence loops'
$ultimateSettingsCard.Controls.Add($ultimateLoopLabel)

$ultimateLoopInput = New-Object System.Windows.Forms.NumericUpDown
$ultimateLoopInput.Location = New-Object System.Drawing.Point(112, 42)
$ultimateLoopInput.Size = New-Object System.Drawing.Size(64, 24)
$ultimateLoopInput.Minimum = 1
$ultimateLoopInput.Maximum = 9999
$ultimateLoopInput.Value = 80
$ultimateSettingsCard.Controls.Add($ultimateLoopInput)

$ultimateAutoBuyLabel = New-Object System.Windows.Forms.Label
$ultimateAutoBuyLabel.Location = New-Object System.Drawing.Point(192, 44)
$ultimateAutoBuyLabel.Size = New-Object System.Drawing.Size(108, 22)
$ultimateAutoBuyLabel.Text = 'AutoBuyCar loops'
$ultimateSettingsCard.Controls.Add($ultimateAutoBuyLabel)

$ultimateAutoBuyInput = New-Object System.Windows.Forms.NumericUpDown
$ultimateAutoBuyInput.Location = New-Object System.Drawing.Point(302, 42)
$ultimateAutoBuyInput.Size = New-Object System.Drawing.Size(64, 24)
$ultimateAutoBuyInput.Minimum = 1
$ultimateAutoBuyInput.Maximum = 9999
$ultimateAutoBuyInput.Value = 1
$ultimateSettingsCard.Controls.Add($ultimateAutoBuyInput)

$ultimateFindLabel = New-Object System.Windows.Forms.Label
$ultimateFindLabel.Location = New-Object System.Drawing.Point(382, 44)
$ultimateFindLabel.Size = New-Object System.Drawing.Size(124, 22)
$ultimateFindLabel.Text = 'FindNewSubaru loops'
$ultimateSettingsCard.Controls.Add($ultimateFindLabel)

$ultimateFindInput = New-Object System.Windows.Forms.NumericUpDown
$ultimateFindInput.Location = New-Object System.Drawing.Point(508, 42)
$ultimateFindInput.Size = New-Object System.Drawing.Size(64, 24)
$ultimateFindInput.Minimum = 1
$ultimateFindInput.Maximum = 9999
$ultimateFindInput.Value = 1
$ultimateSettingsCard.Controls.Add($ultimateFindInput)

$ultimateWorkflowLabel = New-Object System.Windows.Forms.Label
$ultimateWorkflowLabel.Location = New-Object System.Drawing.Point(14, 80)
$ultimateWorkflowLabel.Size = New-Object System.Drawing.Size(88, 22)
$ultimateWorkflowLabel.Text = 'Ultimate loops'
$ultimateSettingsCard.Controls.Add($ultimateWorkflowLabel)

$ultimateWorkflowInput = New-Object System.Windows.Forms.NumericUpDown
$ultimateWorkflowInput.Location = New-Object System.Drawing.Point(104, 78)
$ultimateWorkflowInput.Size = New-Object System.Drawing.Size(58, 24)
$ultimateWorkflowInput.Minimum = 1
$ultimateWorkflowInput.Maximum = 99999
$ultimateWorkflowInput.Value = 1
$ultimateSettingsCard.Controls.Add($ultimateWorkflowInput)

$ultimateWorkflowForever = New-Object System.Windows.Forms.CheckBox
$ultimateWorkflowForever.Location = New-Object System.Drawing.Point(168, 79)
$ultimateWorkflowForever.Size = New-Object System.Drawing.Size(80, 24)
$ultimateWorkflowForever.Text = 'Forever'
$ultimateSettingsCard.Controls.Add($ultimateWorkflowForever)

$ultimateStartStepLabel = New-Object System.Windows.Forms.Label
$ultimateStartStepLabel.Location = New-Object System.Drawing.Point(262, 80)
$ultimateStartStepLabel.Size = New-Object System.Drawing.Size(70, 22)
$ultimateStartStepLabel.Text = 'Debug step'
$ultimateSettingsCard.Controls.Add($ultimateStartStepLabel)

$ultimateStartStepInput = New-Object System.Windows.Forms.NumericUpDown
$ultimateStartStepInput.Location = New-Object System.Drawing.Point(334, 78)
$ultimateStartStepInput.Size = New-Object System.Drawing.Size(50, 24)
$ultimateStartStepInput.Minimum = 5
$ultimateStartStepInput.Maximum = 14
$ultimateStartStepInput.Value = 5
$ultimateSettingsCard.Controls.Add($ultimateStartStepInput)

$ultimateStartStepHint = New-Object System.Windows.Forms.Label
$ultimateStartStepHint.Location = New-Object System.Drawing.Point(392, 80)
$ultimateStartStepHint.Size = New-Object System.Drawing.Size(412, 22)
$ultimateStartStepHint.Anchor = $anchorTLR
$ultimateStartStepHint.Text = 'step 5-14; 5 = full run, 14 = FindNewSubaru. Forever = loop until stopped.'
$ultimateStartStepHint.Tag = 'muted'
$ultimateStartStepHint.ForeColor = $Theme.Muted
$ultimateSettingsCard.Controls.Add($ultimateStartStepHint)
Add-AppRow -Table $ultimateTable -Control $ultimateSettingsCard -Height 116

# Disable the loop-count box while "Forever" is checked (infinite has no count).
$ultimateWorkflowForever.Add_CheckedChanged({
    $ultimateWorkflowInput.Enabled = -not $ultimateWorkflowForever.Checked
})

$ultimateAboutCard = New-AppCard -Title 'About'
$ultimateInfoBox = New-Object System.Windows.Forms.TextBox
$ultimateInfoBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$ultimateInfoBox.Multiline = $true
$ultimateInfoBox.ReadOnly = $true
$ultimateInfoBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$ultimateInfoBox.BackColor = $Theme.Card
$ultimateInfoBox.ForeColor = $Theme.Muted
$ultimateInfoBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$ultimateInfoBox.Text = "Ultimate is an independent workflow. It sends the configured menu macro, enters the share code, searches for the strict OCR target, selects it, runs its own Sequence loops, then a post-sequence macro, the AutoBuyCar sequence, a post-buy macro, and finally the FindNewSubaru search-and-buy loop.`r`nUltimate loops = how many times to repeat the WHOLE workflow; tick Forever for an unlimited loop (runs until you press Stop). The status line shows the current loop and an estimated finish time.`r`nSet Sequence / AutoBuyCar / FindNewSubaru loops above. AutoBuyCar and FindNewSubaru reuse the automation.* steps from config.json.`r`nDebug step (5-14) skips earlier phases for testing - the game must already be at the UI state that step expects. Leave it at 5 for a full run.`r`nThe status line also shows the cumulative cars AutoBuyCar has bought (kept across runs); Clear Count resets it. AFK and Automation cannot run at the same time as Ultimate."
$ultimateAboutCard.Controls.Add($ultimateInfoBox)
Add-AppRow -Table $ultimateTable -Control $ultimateAboutCard -Height 132

$ultimateButtonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$ultimateButtonPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$ultimateButtonPanel.Margin = New-Object System.Windows.Forms.Padding(0)
$ultimateButtonPanel.BackColor = $Theme.Bg
$ultimateButtonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$ultimateButtonPanel.WrapContents = $true

$startUltimateButton = New-AppButton -Text 'Start Ultimate' -Role Primary -Icon ([string][char]0xE768)
$stopUltimateButton = New-AppButton -Text 'Stop Ultimate' -Role Danger -Icon ([string][char]0xE71A)
$pauseUltimateButton = New-AppButton -Text 'Pause' -Role Neutral -Icon ([string][char]0xE769)
$pauseUltimateButton.Enabled = $false
$refreshUltimateButton = New-AppButton -Text 'Refresh Status' -Role Neutral -Icon ([string][char]0xE72C)
$openUltimateLogButton = New-AppButton -Text 'Open Ultimate Log' -Role Neutral -Icon ([string][char]0xE838)
$clearUltimateCountButton = New-AppButton -Text 'Clear Count' -Role Neutral -Icon ([string][char]0xE74D)
@($startUltimateButton, $stopUltimateButton, $pauseUltimateButton, $refreshUltimateButton, $openUltimateLogButton, $clearUltimateCountButton) |
    ForEach-Object { $ultimateButtonPanel.Controls.Add($_) }
# Six buttons wrap to two rows (FlowLayoutPanel WrapContents); give the row enough height for both.
Add-AppRow -Table $ultimateTable -Control $ultimateButtonPanel -Height 96

$ultimateLogCard = New-AppCard -Title 'Recent log'
# RichTextBox so ERROR/WARN lines can be coloured. Content is rebuilt by
# Update-UltimateLogPreview, which caches the raw tail and skips repaints when
# nothing changed (the UI timer calls it every 2s).
$ultimateLogBox = New-Object System.Windows.Forms.RichTextBox
$ultimateLogBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$ultimateLogBox.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$ultimateLogBox.ReadOnly = $true
$ultimateLogBox.BackColor = $Theme.LogBg
$ultimateLogBox.ForeColor = $Theme.Text
$ultimateLogBox.Font = $MonoFont
$ultimateLogBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$ultimateLogCard.Controls.Add($ultimateLogBox)

# Mini toolbar above the log: keyword filter + auto-scroll toggle. Docked AFTER the
# Fill box on purpose -- WinForms docks the most-recently-added control first, so the
# toolbar claims the top strip and the RichTextBox fills the remainder.
$ultimateLogToolbar = New-Object System.Windows.Forms.Panel
$ultimateLogToolbar.Dock = [System.Windows.Forms.DockStyle]::Top
$ultimateLogToolbar.Height = 30
$ultimateLogToolbar.BackColor = $Theme.Card

$ultimateLogFilterLabel = New-Object System.Windows.Forms.Label
$ultimateLogFilterLabel.Location = New-Object System.Drawing.Point(2, 6)
$ultimateLogFilterLabel.Size = New-Object System.Drawing.Size(36, 20)
$ultimateLogFilterLabel.Text = 'Filter'
$ultimateLogFilterLabel.Tag = 'muted'
$ultimateLogFilterLabel.ForeColor = $Theme.Muted
$ultimateLogToolbar.Controls.Add($ultimateLogFilterLabel)

$ultimateLogFilterBox = New-Object System.Windows.Forms.TextBox
$ultimateLogFilterBox.Location = New-Object System.Drawing.Point(40, 3)
$ultimateLogFilterBox.Size = New-Object System.Drawing.Size(180, 22)
$ultimateLogFilterBox.BackColor = $Theme.LogBg
$ultimateLogFilterBox.ForeColor = $Theme.Text
$ultimateLogFilterBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$ultimateLogToolbar.Controls.Add($ultimateLogFilterBox)

$ultimateLogAutoScroll = New-Object System.Windows.Forms.CheckBox
$ultimateLogAutoScroll.Location = New-Object System.Drawing.Point(236, 4)
$ultimateLogAutoScroll.Size = New-Object System.Drawing.Size(110, 22)
$ultimateLogAutoScroll.Text = 'Auto-scroll'
$ultimateLogAutoScroll.Checked = $true
$ultimateLogAutoScroll.ForeColor = $Theme.Text
$ultimateLogToolbar.Controls.Add($ultimateLogAutoScroll)
$ultimateLogCard.Controls.Add($ultimateLogToolbar)
Add-AppRow -Table $ultimateTable -Control $ultimateLogCard -Fill

$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusStrip.RenderMode = [System.Windows.Forms.ToolStripRenderMode]::System
$statusStrip.BackColor = $Theme.LogBg
$statusStrip.ForeColor = $Theme.Muted
$statusStrip.SizingGrip = $false
$statusText = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusText.Text = 'Ready'
$statusText.ForeColor = $Theme.Muted
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

        Set-AppStatusLabel -Label $backupStatusLabel -Status $state.Status -Text "Status: $($state.Status) - Source exists: $sourceExists"
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

        Set-AppStatusLabel -Label $focusStatusLabel -Status $state.Status -Text "Status: $($state.Status) - $($state.Message)"
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

        Set-AppStatusLabel -Label $afkStatusLabel -Status $state.Status -Text "Status: $($state.Status) - Input=$($options.InputMethod), Startup=$($options.StartupDelaySeconds)s Sequence=$($options.EnterDelaySeconds)s/$($options.XDelayMilliseconds)ms/$($options.LoopDelaySeconds)s EnterEvery=$($options.EnterOnlyDelaySeconds)s MacroDelay=$($options.MacroComboCycleDelaySeconds)s"
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

        Set-AppStatusLabel -Label $automationStatusLabel -Status $state.Status -Text "Status: $($state.Status) - Input=$($autoBuyOptions.InputMethod), AutoBuy loops=$($autoBuyOptions.LoopCount), Find loops=$($findOptions.LoopCount), Find max attempts=$($findOptions.FindNewSubaruMaxSearchAttempts), search=$($findOptions.FindNewSubaruSearchKey), after select=$($findOptions.FindNewSubaruAfterSelectDelayMilliseconds)ms"
        Update-AutomationLogPreview -Paths $paths
        Set-AppStatusText 'Automation status refreshed.'
    }
}

$script:UltimateLogCache = $null
function Update-UltimateLogPreview {
    param($Paths)

    $raw = $null
    if (Test-Path -LiteralPath $Paths.LogPath -PathType Leaf) {
        $raw = (Get-Content -LiteralPath $Paths.LogPath -Tail 200 -Encoding UTF8) -join "`n"
    }
    $filter = [string]$ultimateLogFilterBox.Text
    # Skip the (relatively expensive) RichTextBox rebuild when neither the log tail nor
    # the filter changed -- the UI timer calls this every 2 seconds.
    $cacheKey = $filter + [char]1 + $raw
    if ($cacheKey -eq $script:UltimateLogCache) { return }
    $script:UltimateLogCache = $cacheKey

    $lines = if ($null -ne $raw) { $raw -split "`n" } else { @('No ultimate log yet.') }
    if (-not [string]::IsNullOrWhiteSpace($filter)) {
        $pattern = [regex]::Escape($filter.Trim())
        $lines = @($lines | Where-Object { $_ -imatch $pattern })
        if ($lines.Count -eq 0) { $lines = @("(no lines match '$($filter.Trim())')") }
    }

    $ultimateLogBox.SuspendLayout()
    $ultimateLogBox.Clear()
    foreach ($line in $lines) {
        $color = if ($line -match '\[ERROR\]') { $Theme.Danger }
        elseif ($line -match '\[WARN\]') { $Theme.Warn }
        else { $Theme.Text }
        $ultimateLogBox.SelectionStart = $ultimateLogBox.TextLength
        $ultimateLogBox.SelectionColor = $color
        $ultimateLogBox.AppendText($line + "`r`n")
    }
    if ($ultimateLogAutoScroll.Checked) {
        $ultimateLogBox.SelectionStart = $ultimateLogBox.TextLength
        $ultimateLogBox.ScrollToCaret()
    }
    $ultimateLogBox.ResumeLayout()
}

# Cheap "is the worker alive" check for the live view / nav dots: pid file + process
# existence only, no CIM command-line verification (that stays in Get-<X>State, which
# every Start/Stop/Refresh still uses). Good enough for display, and fast enough to
# run from a timer without hitching the UI.
function Test-AppPidAlive {
    param([string]$PidPath)

    if (-not (Test-Path -LiteralPath $PidPath -PathType Leaf)) { return $false }
    try {
        $procId = [int]((Get-Content -LiteralPath $PidPath -TotalCount 1 -Encoding ASCII).Trim())
        return [bool](Get-Process -Id $procId -ErrorAction SilentlyContinue)
    }
    catch { return $false }
}

function Update-AppRunningMap {
    $map = @{
        Ultimate   = (Get-AppUltimatePaths).PidPath
        Backup     = (Get-AppBackupConfig).PidPath
        Focus      = (Get-AppFocusPaths).PidPath
        Afk        = (Get-AppAfkPaths).PidPath
        Automation = (Get-AppAutomationPaths).PidPath
    }
    foreach ($key in $map.Keys) {
        $alive = Test-AppPidAlive -PidPath $map[$key]
        if ($script:AppRunningMap[$key] -ne $alive) {
            $script:AppRunningMap[$key] = $alive
            if ($script:AppPages.Contains($key)) { $script:AppPages[$key].Nav.Invalidate() }
        }
    }
}

# Config summary appended to the detail line; refreshed only by the full Refresh
# (config.json reads stay off the 2-second timer path).
$script:UltimateCfgSummary = ''

# Update everything "live" on the Ultimate page from cheap file reads alone:
# progress JSON -> big status + progress bar, pause flag -> PAUSED banner, log tail.
# Shared by the UI timer (every 2s) and the full Refresh-UltimatePanel.
function Update-UltimateLiveView {
    $paths = Get-AppUltimatePaths
    $progress = Get-UltimateProgress -Paths $paths
    $paused = Test-UltimatePause -Paths $paths
    $isRunning = [bool]$script:AppRunningMap['Ultimate']
    $boughtTotal = Get-UltimateAutoBuyCount -Paths $paths

    $bigText = 'Stopped'
    $bigColor = $Theme.Muted
    $fraction = $null
    $barText = ''
    $barColor = $Theme.Accent

    if ($isRunning -and $paused) {
        $bigText = 'PAUSED - resumes at the next safe point'
        $bigColor = $Theme.Danger
        $barColor = $Theme.Danger
    }
    elseif ($isRunning) {
        $bigText = 'RUNNING'
        $bigColor = $Theme.Ok
    }
    elseif ($progress -and $progress.Status -eq 'completed') {
        $bigText = 'Completed'
        $bigColor = $Theme.Ok
    }

    if ($progress -and $isRunning) {
        if ($progress.TotalLoops -gt 0) {
            $bigText = "$bigText - Loop $($progress.CurrentLoop)/$($progress.TotalLoops)"
            $done = [Math]::Max(0, $progress.CurrentLoop - 1)
            $fraction = [double]$done / [double]$progress.TotalLoops
            $barText = "Loop $($progress.CurrentLoop)/$($progress.TotalLoops) ($([int]($fraction * 100))% done)"
        }
        elseif ($progress.CurrentLoop -gt 0) {
            $bigText = "$bigText - Loop $($progress.CurrentLoop) (infinite)"
            $barText = "Loop $($progress.CurrentLoop) - infinite, runs until Stop"
        }
    }
    elseif ($progress -and $progress.Status -eq 'completed' -and $progress.TotalLoops -gt 0) {
        $fraction = 1.0
        $barText = "All $($progress.TotalLoops) loop(s) done"
    }

    # Never leave the workflow bar blank -- show an idle caption when there is no fill so it
    # always reads as a progress bar, not an empty grey strip.
    if ([string]::IsNullOrEmpty($barText)) {
        $barText = if ($progress -and $progress.Status -eq 'completed') { 'Completed' }
                   elseif ($isRunning) { 'Starting...' }
                   else { 'Stopped - press Start Ultimate' }
    }

    $ultimateBigStatusLabel.Text = $bigText
    $ultimateBigStatusLabel.ForeColor = $bigColor
    $script:UltimateProgressView.Fraction = $fraction
    $script:UltimateProgressView.Text = $barText
    $script:UltimateProgressView.BarColor = $barColor
    $ultimateProgressBar.Invalidate()

    # Inner-phase view: which Sequence / AutoBuyCar / FindNewSubaru iteration is running now.
    $phaseLabelText = ''
    $phaseBarText = ''
    $phaseFraction = $null
    $phaseColor = if ($isRunning -and $paused) { $Theme.Danger } else { $Theme.Accent }
    if ($isRunning -and $progress -and -not [string]::IsNullOrWhiteSpace($progress.Phase) -and $progress.PhaseTotal -gt 0) {
        $phaseLabelText = "$($progress.Phase)   $($progress.PhaseCurrent) / $($progress.PhaseTotal)"
        $phaseFraction = [double]$progress.PhaseCurrent / [double]$progress.PhaseTotal
        $phaseBarText = "$([int]($phaseFraction * 100))%"
    }
    elseif ($isRunning) {
        $phaseLabelText = 'Preparing...'
    }
    $ultimatePhaseLabel.Text = $phaseLabelText
    $ultimatePhaseLabel.ForeColor = if ($isRunning -and $paused) { $Theme.Danger } elseif ($isRunning) { $Theme.Text } else { $Theme.Muted }
    $script:UltimatePhaseView.Fraction = $phaseFraction
    $script:UltimatePhaseView.Text = $phaseBarText
    $script:UltimatePhaseView.BarColor = $phaseColor
    $ultimatePhaseBar.Invalidate()

    $detailText = ''
    if ($progress -and -not [string]::IsNullOrWhiteSpace($progress.DisplayText)) {
        $detailText = if ($isRunning) { $progress.DisplayText } else { "Last run: $($progress.DisplayText)" }
        $detailText += ' | '
    }
    $ultimateStatusLabel.Text = "${detailText}Bought(total)=$boughtTotal$script:UltimateCfgSummary"
    $ultimateStatusLabel.ForeColor = if ($isRunning -and $paused) { $Theme.Danger } else { $Theme.Muted }

    # Keep the Pause/Resume toggle in sync from the timer too (e.g. the worker exits,
    # or the flag changes outside a manual Refresh). Only touch it on actual change.
    if ($pauseUltimateButton.Enabled -ne $isRunning) { $pauseUltimateButton.Enabled = $isRunning }
    $wantText = if ($paused) { 'Resume' } else { 'Pause' }
    if ($pauseUltimateButton.Text -ne $wantText) {
        $pauseUltimateButton.Text = $wantText
        $pauseUltimateButton.Tag.Icon = if ($paused) { [string][char]0xE768 } else { [string][char]0xE769 }
        Set-AppButtonRole -Button $pauseUltimateButton -Role $(if ($paused) { 'Primary' } else { 'Neutral' })
    }

    Update-UltimateLogPreview -Paths $paths
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
        $isRunning = $state.Status -in @('Running', 'RunningUnverified')

        # Feed the verified state into the lightweight map so the live view and the nav
        # dot agree with the authoritative check immediately (not at the next heavy tick).
        if ($script:AppRunningMap['Ultimate'] -ne $isRunning) {
            $script:AppRunningMap['Ultimate'] = $isRunning
            $script:AppPages['Ultimate'].Nav.Invalidate()
        }
        $script:UltimateCfgSummary = " | Status=$($state.Status) Seq=$($options.SequenceLoopCount) Search=$($options.SearchKey)/$($options.MaxSearchAttempts) Input=$($options.InputMethod)"

        # The Pause/Resume toggle, big status, progress bar and log are all owned by the
        # shared live view (also driven by the UI timer).
        Update-UltimateLiveView
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
$pauseUltimateButton.Add_Click({
    Invoke-AppSafely -FailureTitle 'Pause Ultimate' -Action {
        $paths = Get-AppUltimatePaths
        Initialize-UltimateWorkspace -Paths $paths
        $state = Get-UltimateState -Paths $paths
        if ($state.Status -notin @('Running', 'RunningUnverified')) {
            Show-AppMessage -Message 'Ultimate is not running.'
            return
        }
        $currentlyPaused = Test-UltimatePause -Paths $paths
        $message = Set-AppUltimatePauseState -Paused (-not $currentlyPaused)
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

$ultimateLogFilterBox.Add_TextChanged({
    try { Update-UltimateLogPreview -Paths (Get-AppUltimatePaths) } catch { }
})
$ultimateLogAutoScroll.Add_CheckedChanged({
    if ($ultimateLogAutoScroll.Checked) {
        $ultimateLogBox.SelectionStart = $ultimateLogBox.TextLength
        $ultimateLogBox.ScrollToCaret()
    }
})

# UI auto-refresh. Light tick (2s): cheap file reads only (progress JSON, pause flag,
# log tail). Heavy tick (every 5th = 10s): pid-file liveness for the five nav dots.
# A timer handler must stay silent -- no Invoke-AppSafely (it would spam MessageBoxes)
# and no status-bar writes.
$script:AppTickCount = 0
$uiTimer = New-Object System.Windows.Forms.Timer
$uiTimer.Interval = 2000
$uiTimer.Add_Tick({
    try {
        $script:AppTickCount++
        if (($script:AppTickCount % 5) -eq 1) { Update-AppRunningMap }
        Update-UltimateLiveView
    }
    catch { }
})

$form.Add_Shown({
    Select-AppPage -Key 'Ultimate'
    try { Update-AppRunningMap } catch { }
    Refresh-BackupPanel
    Refresh-FocusPanel
    Refresh-AfkPanel
    Refresh-AutomationPanel
    Refresh-UltimatePanel
    Set-AutomationLoopDefault
    Set-UltimateLoopDefault
    Refresh-WindowList
    $uiTimer.Start()
})
$form.Add_FormClosing({ $uiTimer.Stop() })

# Apply the dark palette to every plain control (labels/inputs/combos/containers)
# in one pass, after all controls and handlers are wired.
Set-AppTheme -Control $form

[void][System.Windows.Forms.Application]::Run($form)
