Set-StrictMode -Version 2.0

function Get-FocusAppRoot {
    [CmdletBinding()]
    param(
        [string]$AppRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($AppRoot)) {
        return [System.IO.Path]::GetFullPath($AppRoot)
    }

    return [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
}

function Get-FocusPaths {
    [CmdletBinding()]
    param(
        [string]$AppRoot
    )

    $root = Get-FocusAppRoot -AppRoot $AppRoot
    $runtimeRoot = Join-Path $root 'runtime'
    $logsRoot = Join-Path $root 'logs'

    [pscustomobject]@{
        AppRoot    = $root
        RuntimeRoot = $runtimeRoot
        LogsRoot    = $logsRoot
        LogPath     = Join-Path $logsRoot 'focus-lock.log'
        PidPath     = Join-Path $runtimeRoot 'focus-lock.pid'
        TargetPath  = Join-Path $runtimeRoot 'focus-lock.target.json'
    }
}

function Initialize-FocusWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths
    )

    foreach ($path in @($Paths.RuntimeRoot, $Paths.LogsRoot)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
    }
}

function Write-FocusLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO',
        [Parameter(Mandatory = $true)][string]$Message
    )

    Initialize-FocusWorkspace -Paths $Paths
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $Paths.LogPath -Value "[$timestamp] [$Level] $Message" -Encoding UTF8
}

function Initialize-FocusNative {
    if ('WindowFocusNative' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public class WindowFocusNative
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr SetActiveWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr SetFocus(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();
}
'@
}

function Get-WindowTitle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][IntPtr]$Handle
    )

    Initialize-FocusNative
    $length = [WindowFocusNative]::GetWindowTextLength($Handle)
    if ($length -le 0) {
        return ''
    }

    $builder = New-Object System.Text.StringBuilder ($length + 1)
    [void][WindowFocusNative]::GetWindowText($Handle, $builder, $builder.Capacity)
    return $builder.ToString()
}

function Get-WindowInfoByHandle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Int64]$WindowHandle
    )

    Initialize-FocusNative
    $handle = [IntPtr]$WindowHandle
    if (-not [WindowFocusNative]::IsWindow($handle)) {
        return $null
    }

    $pidValue = [uint32]0
    [void][WindowFocusNative]::GetWindowThreadProcessId($handle, [ref]$pidValue)
    $process = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
    $title = Get-WindowTitle -Handle $handle

    [pscustomobject]@{
        Handle      = $WindowHandle
        HandleHex   = ('0x{0:X}' -f $WindowHandle)
        ProcessId   = [int]$pidValue
        ProcessName = if ($process) { $process.ProcessName } else { 'unknown' }
        Title       = $title
    }
}

function Get-FocusWindowList {
    [CmdletBinding()]
    param()

    Initialize-FocusNative
    $windows = New-Object System.Collections.Generic.List[object]
    $callback = [WindowFocusNative+EnumWindowsProc]{
        param([IntPtr]$hWnd, [IntPtr]$lParam)

        if (-not [WindowFocusNative]::IsWindowVisible($hWnd)) {
            return $true
        }

        $title = Get-WindowTitle -Handle $hWnd
        if ([string]::IsNullOrWhiteSpace($title)) {
            return $true
        }

        $pidValue = [uint32]0
        [void][WindowFocusNative]::GetWindowThreadProcessId($hWnd, [ref]$pidValue)
        $process = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue

        $windows.Add([pscustomobject]@{
            Handle      = $hWnd.ToInt64()
            HandleHex   = ('0x{0:X}' -f $hWnd.ToInt64())
            ProcessId   = [int]$pidValue
            ProcessName = if ($process) { $process.ProcessName } else { 'unknown' }
            Title       = $title
        })

        return $true
    }

    [void][WindowFocusNative]::EnumWindows($callback, [IntPtr]::Zero)
    $windows | Sort-Object ProcessName, Title
}

function Select-FocusWindow {
    [CmdletBinding()]
    param(
        [object[]]$Windows
    )

    $windowList = @($Windows)
    if ($windowList.Count -eq 0) {
        throw 'No selectable visible windows were found.'
    }

    for ($i = 0; $i -lt $windowList.Count; $i++) {
        $window = $windowList[$i]
        '{0,3}. [{1}] {2} - {3}' -f ($i + 1), $window.ProcessId, $window.ProcessName, $window.Title | Write-Host
    }

    $selection = Read-Host 'Enter the window number to keep focused'
    $selectedIndex = 0
    if (-not [int]::TryParse($selection, [ref]$selectedIndex)) {
        throw "Invalid selection: $selection"
    }

    if ($selectedIndex -lt 1 -or $selectedIndex -gt $windowList.Count) {
        throw "Selection out of range: $selectedIndex"
    }

    return $windowList[$selectedIndex - 1]
}

function Set-FocusLockPid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths
    )

    Initialize-FocusWorkspace -Paths $Paths
    Set-Content -LiteralPath $Paths.PidPath -Value ([string]$PID) -Encoding ASCII
}

function Remove-FocusLockPid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths
    )

    if (Test-Path -LiteralPath $Paths.PidPath -PathType Leaf) {
        Remove-Item -LiteralPath $Paths.PidPath -Force
    }
}

function Set-FocusLockTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)]$Target,
        [Parameter(Mandatory = $true)][int]$IntervalMilliseconds
    )

    Initialize-FocusWorkspace -Paths $Paths
    [pscustomobject]@{
        Handle               = [Int64]$Target.Handle
        HandleHex            = $Target.HandleHex
        ProcessId            = [int]$Target.ProcessId
        ProcessName          = [string]$Target.ProcessName
        Title                = [string]$Target.Title
        IntervalMilliseconds = $IntervalMilliseconds
        SelectedAt           = (Get-Date).ToString('s')
    } | ConvertTo-Json | Set-Content -LiteralPath $Paths.TargetPath -Encoding UTF8
}

function Get-FocusLockTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths
    )

    if (-not (Test-Path -LiteralPath $Paths.TargetPath -PathType Leaf)) {
        return $null
    }

    Get-Content -LiteralPath $Paths.TargetPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-FocusLockState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths
    )

    if (-not (Test-Path -LiteralPath $Paths.PidPath -PathType Leaf)) {
        return [pscustomobject]@{
            Status      = 'Stopped'
            Pid         = $null
            Process     = $null
            CommandLine = $null
            Message     = 'Focus lock is not running.'
        }
    }

    $pidText = (Get-Content -LiteralPath $Paths.PidPath -ErrorAction SilentlyContinue | Select-Object -First 1)
    $focusPid = 0
    if (-not [int]::TryParse(([string]$pidText).Trim(), [ref]$focusPid)) {
        return [pscustomobject]@{
            Status      = 'InvalidPid'
            Pid         = $null
            Process     = $null
            CommandLine = $null
            Message     = "PID file is invalid: $($Paths.PidPath)"
        }
    }

    $process = Get-Process -Id $focusPid -ErrorAction SilentlyContinue
    if (-not $process) {
        return [pscustomobject]@{
            Status      = 'Stale'
            Pid         = $focusPid
            Process     = $null
            CommandLine = $null
            Message     = "PID file is stale. Process $focusPid is not running."
        }
    }

    $commandLine = $null
    try {
        $cim = Get-CimInstance Win32_Process -Filter "ProcessId = $focusPid" -ErrorAction Stop
        $commandLine = $cim.CommandLine
    }
    catch {
        try {
            $wmi = Get-WmiObject Win32_Process -Filter "ProcessId = $focusPid" -ErrorAction Stop
            $commandLine = $wmi.CommandLine
        }
        catch {
            $commandLine = $null
        }
    }

    $normalizedCommand = if ($commandLine) { $commandLine.ToLowerInvariant() } else { '' }
    $isFocusLock = $normalizedCommand.Contains('keepwindowfocused.ps1')

    if ($isFocusLock) {
        return [pscustomobject]@{
            Status      = 'Running'
            Pid         = $focusPid
            Process     = $process
            CommandLine = $commandLine
            Message     = "Focus lock is running. PID=$focusPid"
        }
    }

    if ([string]::IsNullOrWhiteSpace($commandLine) -and $process.ProcessName -like 'powershell*') {
        return [pscustomobject]@{
            Status      = 'RunningUnverified'
            Pid         = $focusPid
            Process     = $process
            CommandLine = $commandLine
            Message     = "Focus lock appears to be running, but process command line could not be verified. PID=$focusPid"
        }
    }

    [pscustomobject]@{
        Status      = 'PidConflict'
        Pid         = $focusPid
        Process     = $process
        CommandLine = $commandLine
        Message     = "PID file points to a process that does not look like focus lock. PID=$focusPid"
    }
}

function Remove-StaleFocusLockPid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)]$State
    )

    if ($State.Status -in @('Stale', 'InvalidPid', 'PidConflict')) {
        Remove-FocusLockPid -Paths $Paths
    }
}

function Invoke-ForegroundWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Int64]$WindowHandle
    )

    Initialize-FocusNative
    $handle = [IntPtr]$WindowHandle
    if (-not [WindowFocusNative]::IsWindow($handle)) {
        return $false
    }

    if ([WindowFocusNative]::IsIconic($handle)) {
        [void][WindowFocusNative]::ShowWindowAsync($handle, 9)
    }
    else {
        [void][WindowFocusNative]::ShowWindowAsync($handle, 5)
    }

    $foreground = [WindowFocusNative]::GetForegroundWindow()
    $targetPid = [uint32]0
    $foregroundPid = [uint32]0
    $targetThread = [WindowFocusNative]::GetWindowThreadProcessId($handle, [ref]$targetPid)
    $foregroundThread = if ($foreground -ne [IntPtr]::Zero) {
        [WindowFocusNative]::GetWindowThreadProcessId($foreground, [ref]$foregroundPid)
    }
    else {
        0
    }
    $currentThread = [WindowFocusNative]::GetCurrentThreadId()

    $attachedForeground = $false
    $attachedTarget = $false
    try {
        if ($foregroundThread -ne 0 -and $foregroundThread -ne $currentThread) {
            $attachedForeground = [WindowFocusNative]::AttachThreadInput($currentThread, $foregroundThread, $true)
        }
        if ($targetThread -ne 0 -and $targetThread -ne $currentThread) {
            $attachedTarget = [WindowFocusNative]::AttachThreadInput($currentThread, $targetThread, $true)
        }

        [void][WindowFocusNative]::BringWindowToTop($handle)
        [void][WindowFocusNative]::SetActiveWindow($handle)
        [void][WindowFocusNative]::SetFocus($handle)
        return [WindowFocusNative]::SetForegroundWindow($handle)
    }
    finally {
        if ($attachedTarget) {
            [void][WindowFocusNative]::AttachThreadInput($currentThread, $targetThread, $false)
        }
        if ($attachedForeground) {
            [void][WindowFocusNative]::AttachThreadInput($currentThread, $foregroundThread, $false)
        }
    }
}
