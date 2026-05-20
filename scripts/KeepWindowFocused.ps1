[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][Int64]$WindowHandle,
    [int]$IntervalMilliseconds = 750,
    [string]$AppRoot
)

$ErrorActionPreference = 'Stop'
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
. (Join-Path $scriptRoot 'FocusLib.ps1')

if ($IntervalMilliseconds -lt 100) {
    $IntervalMilliseconds = 100
}

$paths = Get-FocusPaths -AppRoot $AppRoot
Initialize-FocusWorkspace -Paths $paths

$state = Get-FocusLockState -Paths $paths
if ($state.Status -in @('Running', 'RunningUnverified') -and $state.Pid -ne $PID) {
    Write-FocusLog -Paths $paths -Level 'WARN' -Message "Focus lock already running. Existing PID=$($state.Pid). New PID=$PID exits."
    exit 0
}

Set-FocusLockPid -Paths $paths

try {
    Initialize-FocusNative
    $target = Get-WindowInfoByHandle -WindowHandle $WindowHandle
    if (-not $target) {
        throw "Target window no longer exists. Handle=$WindowHandle"
    }

    Write-FocusLog -Paths $paths -Level 'INFO' -Message "Focus lock started. PID=$PID Handle=$($target.HandleHex) Process=$($target.ProcessName) Title=$($target.Title)"

    while ($true) {
        if (-not [WindowFocusNative]::IsWindow([IntPtr]$WindowHandle)) {
            throw "Target window was closed. Handle=$WindowHandle"
        }

        $foreground = [WindowFocusNative]::GetForegroundWindow()
        if ($foreground.ToInt64() -ne $WindowHandle) {
            [void](Invoke-ForegroundWindow -WindowHandle $WindowHandle)
        }

        Start-Sleep -Milliseconds $IntervalMilliseconds
    }
}
catch {
    Write-FocusLog -Paths $paths -Level 'ERROR' -Message "Focus lock stopped because of an error. Error=$($_.Exception.Message)"
    exit 1
}
finally {
    Remove-FocusLockPid -Paths $paths
    Write-FocusLog -Paths $paths -Level 'INFO' -Message "Focus lock exited. PID=$PID"
}
