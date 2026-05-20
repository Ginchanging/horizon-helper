[CmdletBinding()]
param(
    [Int64]$WindowHandle = 0,
    [string]$TitlePattern,
    [int]$ProcessId = 0,
    [int]$IntervalMilliseconds = 750
)

$ErrorActionPreference = 'Stop'
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
. (Join-Path $scriptRoot 'scripts\FocusLib.ps1')

if ($IntervalMilliseconds -lt 100) {
    $IntervalMilliseconds = 100
}

$paths = Get-FocusPaths -AppRoot $scriptRoot
Initialize-FocusWorkspace -Paths $paths

$state = Get-FocusLockState -Paths $paths
if ($state.Status -in @('Running', 'RunningUnverified')) {
    Write-Host $state.Message
    Write-Host 'Run StopFocusLock.cmd first if you want to choose a different window.'
    exit 0
}
Remove-StaleFocusLockPid -Paths $paths -State $state

$target = $null
if ($WindowHandle -ne 0) {
    $target = Get-WindowInfoByHandle -WindowHandle $WindowHandle
    if (-not $target) {
        throw "Window handle was not found: $WindowHandle"
    }
}
else {
    $windows = @(Get-FocusWindowList)
    if ($ProcessId -gt 0) {
        $windows = @($windows | Where-Object { $_.ProcessId -eq $ProcessId })
    }
    if (-not [string]::IsNullOrWhiteSpace($TitlePattern)) {
        $windows = @($windows | Where-Object { $_.Title -like "*$TitlePattern*" })
    }

    if ($windows.Count -eq 1) {
        $target = $windows[0]
        Write-Host "Selected only matching window: [$($target.ProcessId)] $($target.ProcessName) - $($target.Title)"
    }
    else {
        if ($windows.Count -eq 0) {
            throw 'No matching visible windows were found.'
        }

        Write-Host 'Choose a window to keep focused:'
        $target = Select-FocusWindow -Windows $windows
    }
}

Set-FocusLockTarget -Paths $paths -Target $target -IntervalMilliseconds $IntervalMilliseconds

$workerScript = Join-Path $scriptRoot 'scripts\KeepWindowFocused.ps1'
$argumentList = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', ('"{0}"' -f $workerScript),
    '-WindowHandle', ([string]$target.Handle),
    '-IntervalMilliseconds', ([string]$IntervalMilliseconds),
    '-AppRoot', ('"{0}"' -f $scriptRoot)
)

$process = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -WindowStyle Hidden -PassThru
for ($attempt = 1; $attempt -le 10; $attempt++) {
    Start-Sleep -Milliseconds 300
    $newState = Get-FocusLockState -Paths $paths
    if ($newState.Status -in @('Running', 'RunningUnverified') -or $process.HasExited) {
        break
    }
}

if ($newState.Status -in @('Running', 'RunningUnverified')) {
    Write-Host "Focus lock started. PID=$($newState.Pid)"
    if ($newState.Status -eq 'RunningUnverified') {
        Write-Host 'Note: process command line could not be verified in this shell, but the PID file points to a PowerShell process.'
    }
    Write-Host "Target: [$($target.ProcessId)] $($target.ProcessName) - $($target.Title)"
    Write-Host "Interval: $IntervalMilliseconds ms"
    Write-Host "Log: $($paths.LogPath)"
    exit 0
}

if ($process.HasExited) {
    Write-Error "Focus lock process exited early. Check log: $($paths.LogPath)"
    exit 1
}

Write-Host "Focus lock process started. PID=$($process.Id)"
Write-Host 'Status is still initializing. Check again with StatusFocusLock.ps1.'
