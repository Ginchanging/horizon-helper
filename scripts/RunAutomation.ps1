[CmdletBinding()]
param(
    [string]$AppRoot,
    [ValidateSet('AutoBuyCar', 'DeleteCar', 'FindNewSubaru')][string]$Mode = 'AutoBuyCar',
    [int]$LoopCount = -1,
    [int]$StartupDelaySeconds = -1,
    [string]$RecognitionImagePath,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Make this process DPI-aware BEFORE any WinForms/GDI+ code loads. On a scaled display
# (e.g. 125%), establishing awareness late lets Graphics.CopyFromScreen capture only the
# logical-resolution region into the top-left of the bitmap, leaving the bottom of the
# screen empty. That truncates the bottom row of the car grid, so a target car in row 3
# (its new-badge) is never captured and never matches. This call must run before the
# AfkLib dot-source, because SendKeys/WinForms locks the process DPI context on first use.
$script:DpiAwareResult = $false
try {
    Add-Type -Namespace GsgDpi -Name Awareness -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetProcessDPIAware();
'@
    $script:DpiAwareResult = [GsgDpi.Awareness]::SetProcessDPIAware()
}
catch {
    $script:DpiAwareResult = $false
}

$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
. (Join-Path $scriptRoot 'AfkLib.ps1')
. (Join-Path $scriptRoot 'AutomationLib.ps1')

$paths = Get-AutomationPaths -AppRoot $AppRoot
Initialize-AutomationWorkspace -Paths $paths
$config = Get-AutomationConfig -AppRoot $paths.AppRoot
$options = Resolve-AutomationRuntimeOptions -Config $config -Mode $Mode -LoopCount $LoopCount -StartupDelaySeconds $StartupDelaySeconds

function Invoke-AutoBuyCar {
    for ($loop = 1; $loop -le $options.LoopCount; $loop++) {
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "AutoBuyCar loop started. Loop=$loop Total=$($options.LoopCount)"
        Invoke-AutomationKeySteps -Paths $paths -Steps $options.AutoBuyCarSteps -Mode 'AutoBuyCar' -LoopIndex $loop -KeyTapHoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "AutoBuyCar loop completed. Loop=$loop Total=$($options.LoopCount)"
        if ($loop -lt $options.LoopCount -and $options.AutoBuyCarBetweenLoopsMilliseconds -gt 0) {
            Start-Sleep -Milliseconds $options.AutoBuyCarBetweenLoopsMilliseconds
        }
    }
}

function Invoke-DeleteCar {
    for ($loop = 1; $loop -le $options.LoopCount; $loop++) {
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "DeleteCar loop started. Loop=$loop Total=$($options.LoopCount)"
        Invoke-AutomationKeySteps -Paths $paths -Steps $options.DeleteCarSteps -Mode 'DeleteCar' -LoopIndex $loop -KeyTapHoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "DeleteCar loop completed. Loop=$loop Total=$($options.LoopCount)"
        if ($loop -lt $options.LoopCount -and $options.DeleteCarBetweenLoopsMilliseconds -gt 0) {
            Start-Sleep -Milliseconds $options.DeleteCarBetweenLoopsMilliseconds
        }
    }
}

function Invoke-FindNewSubaru {
    # The whole search/recognition/select/buy loop lives in AutomationLib so the Ultimate
    # worker can reuse it verbatim. This wrapper just feeds it this worker's options/paths.
    Invoke-AutomationFindNewSubaruLoop -Paths $paths -Options $options -RecognitionImagePath $RecognitionImagePath -DryRun:$DryRun
}

$state = Get-AutomationState -Paths $paths
if ($state.Status -in @('Running', 'RunningUnverified') -and $state.Pid -ne $PID) {
    Write-AutomationLog -Paths $paths -Level 'WARN' -Message "Automation already running. Existing PID=$($state.Pid). New PID=$PID exits."
    exit 0
}

$afkPaths = Get-AfkPaths -AppRoot $paths.AppRoot
Initialize-AfkWorkspace -Paths $afkPaths
$afkState = Get-AfkState -Paths $afkPaths
if ($afkState.Status -in @('Running', 'RunningUnverified')) {
    Write-AutomationLog -Paths $paths -Level 'ERROR' -Message "Cannot start automation while AFK is running. AFK PID=$($afkState.Pid)"
    throw 'AFK is already running. Stop AFK before starting Automation.'
}

Set-AutomationPid -Paths $paths

try {
    Add-Type -AssemblyName System.Windows.Forms
    Initialize-AfkNative
    Initialize-AutomationNative

    Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Automation started. PID=$PID DpiAware=$script:DpiAwareResult Mode=$Mode LoopCount=$($options.LoopCount) StartupDelay=$($options.StartupDelaySeconds) KeyTapHoldMs=$($options.KeyTapHoldMilliseconds) InputMethod=$($options.InputMethod) DryRun=$DryRun"

    if ($options.StartupDelaySeconds -gt 0) {
        Start-Sleep -Seconds $options.StartupDelaySeconds
    }

    if ($Mode -eq 'FindNewSubaru') {
        Invoke-FindNewSubaru
    }
    elseif ($Mode -eq 'DeleteCar') {
        Invoke-DeleteCar
    }
    else {
        Invoke-AutoBuyCar
    }

    Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Automation completed. PID=$PID Mode=$Mode"
}
catch {
    Write-AutomationLog -Paths $paths -Level 'ERROR' -Message "Automation stopped because of an error. Mode=$Mode Error=$($_.Exception.Message)"
    exit 1
}
finally {
    Release-AfkKeys -DryRun:$DryRun
    Remove-AutomationPid -Paths $paths
    Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Automation exited. PID=$PID"
}
