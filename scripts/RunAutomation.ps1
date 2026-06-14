[CmdletBinding()]
param(
    [string]$AppRoot,
    [ValidateSet('AutoBuyCar', 'DeleteCar', 'FindNewSubaru', 'Sequence', 'EnterEvery10s', 'MacroCombo')][string]$Mode = 'AutoBuyCar',
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

# Loop-count or Forever (LoopCount 0 = infinite). Returns the effective iteration bound plus a
# display label; under DryRun an infinite loop is capped to a few iterations so dry tests cannot
# spin forever.
function Get-AutomationLoopPlan {
    $isForever = ($options.LoopCount -le 0)
    $total = if ($isForever) { if ($DryRun) { 2 } else { [int]::MaxValue } } else { $options.LoopCount }
    $label = if ($isForever) { 'forever' } else { [string]$options.LoopCount }
    if ($isForever -and $DryRun) {
        Write-AutomationLog -Paths $paths -Level 'WARN' -Message "DryRun with Forever: capping $($options.Mode) to 2 loops."
    }
    [pscustomobject]@{ IsForever = $isForever; Total = $total; Label = $label }
}

# Movement-key waits are skipped under DryRun (no real input is sent, so there is nothing to wait for).
function Wait-AutomationSeconds {
    param([int]$Seconds)
    if ($Seconds -gt 0 -and -not $DryRun) { Start-Sleep -Seconds $Seconds }
}

function Wait-AutomationMilliseconds {
    param([int]$Milliseconds)
    if ($Milliseconds -gt 0 -and -not $DryRun) { Start-Sleep -Milliseconds $Milliseconds }
}

function Invoke-AutoBuyCar {
    $plan = Get-AutomationLoopPlan
    for ($loop = 1; $loop -le $plan.Total; $loop++) {
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "AutoBuyCar loop started. Loop=$loop Total=$($plan.Label)"
        Invoke-AutomationKeySteps -Paths $paths -Steps $options.AutoBuyCarSteps -Mode 'AutoBuyCar' -LoopIndex $loop -KeyTapHoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "AutoBuyCar loop completed. Loop=$loop Total=$($plan.Label)"
        if ($loop -lt $plan.Total) { Wait-AutomationMilliseconds -Milliseconds $options.AutoBuyCarBetweenLoopsMilliseconds }
    }
}

function Invoke-DeleteCar {
    $plan = Get-AutomationLoopPlan
    for ($loop = 1; $loop -le $plan.Total; $loop++) {
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "DeleteCar loop started. Loop=$loop Total=$($plan.Label)"
        Invoke-AutomationKeySteps -Paths $paths -Steps $options.DeleteCarSteps -Mode 'DeleteCar' -LoopIndex $loop -KeyTapHoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "DeleteCar loop completed. Loop=$loop Total=$($plan.Label)"
        if ($loop -lt $plan.Total) { Wait-AutomationMilliseconds -Milliseconds $options.DeleteCarBetweenLoopsMilliseconds }
    }
}

function Invoke-FindNewSubaru {
    # The whole search/recognition/select/buy loop lives in AutomationLib so the Ultimate
    # worker can reuse it verbatim. This wrapper just feeds it this worker's options/paths.
    # Forever (LoopCount 0) is handled inside the shared loop.
    Invoke-AutomationFindNewSubaruLoop -Paths $paths -Options $options -RecognitionImagePath $RecognitionImagePath -DryRun:$DryRun
}

# --- Former AFK key loops, folded into Automation ---

function Invoke-Sequence {
    # One cycle = Enter (start) -> wait -> X -> wait -> X -> wait -> Enter -> wait.
    $plan = Get-AutomationLoopPlan
    for ($loop = 1; $loop -le $plan.Total; $loop++) {
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Sequence loop started. Loop=$loop Total=$($plan.Label)"
        $r = Send-AfkNamedKeyTap -Key 'Enter' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Sequence key sent. Loop=$loop Key=Enter WaitSeconds=$($options.SequenceEnterDelaySeconds) InputMethod=$($r.Method) DryRun=$DryRun"
        Wait-AutomationSeconds -Seconds $options.SequenceEnterDelaySeconds
        $r = Send-AfkNamedKeyTap -Key 'X' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Sequence key sent. Loop=$loop Key=X WaitMs=$($options.SequenceXDelayMilliseconds) InputMethod=$($r.Method) DryRun=$DryRun"
        Wait-AutomationMilliseconds -Milliseconds $options.SequenceXDelayMilliseconds
        $r = Send-AfkNamedKeyTap -Key 'X' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Sequence key sent. Loop=$loop Key=X WaitMs=$($options.SequenceXDelayMilliseconds) InputMethod=$($r.Method) DryRun=$DryRun"
        Wait-AutomationMilliseconds -Milliseconds $options.SequenceXDelayMilliseconds
        $r = Send-AfkNamedKeyTap -Key 'Enter' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Sequence key sent. Loop=$loop Key=Enter WaitSeconds=$($options.SequenceLoopDelaySeconds) InputMethod=$($r.Method) DryRun=$DryRun"
        Wait-AutomationSeconds -Seconds $options.SequenceLoopDelaySeconds
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "Sequence loop completed. Loop=$loop Total=$($plan.Label)"
    }
}

function Invoke-EnterEvery10s {
    # One cycle = Enter -> wait delaySeconds.
    $plan = Get-AutomationLoopPlan
    for ($loop = 1; $loop -le $plan.Total; $loop++) {
        $r = Send-AfkNamedKeyTap -Key 'Enter' -HoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "EnterEvery10s key sent. Loop=$loop Total=$($plan.Label) WaitSeconds=$($options.EnterEvery10sDelaySeconds) InputMethod=$($r.Method) DryRun=$DryRun"
        Wait-AutomationSeconds -Seconds $options.EnterEvery10sDelaySeconds
    }
}

function Invoke-MacroCombo {
    # One cycle = the configured macro-combo step list, then wait cycleDelaySeconds.
    $plan = Get-AutomationLoopPlan
    for ($loop = 1; $loop -le $plan.Total; $loop++) {
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "MacroCombo cycle started. Loop=$loop Total=$($plan.Label) Steps=$(@($options.MacroComboSteps).Count)"
        Invoke-AutomationKeySteps -Paths $paths -Steps $options.MacroComboSteps -Mode 'MacroCombo' -LoopIndex $loop -KeyTapHoldMilliseconds $options.KeyTapHoldMilliseconds -InputMethod $options.InputMethod -DryRun:$DryRun
        Write-AutomationLog -Paths $paths -Level 'INFO' -Message "MacroCombo cycle completed. Loop=$loop Total=$($plan.Label)"
        Wait-AutomationSeconds -Seconds $options.MacroComboCycleDelaySeconds
    }
}

$state = Get-AutomationState -Paths $paths
if ($state.Status -in @('Running', 'RunningUnverified') -and $state.Pid -ne $PID) {
    Write-AutomationLog -Paths $paths -Level 'WARN' -Message "Automation already running. Existing PID=$($state.Pid). New PID=$PID exits."
    exit 0
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

    switch ($Mode) {
        'FindNewSubaru' { Invoke-FindNewSubaru }
        'DeleteCar'     { Invoke-DeleteCar }
        'Sequence'      { Invoke-Sequence }
        'EnterEvery10s' { Invoke-EnterEvery10s }
        'MacroCombo'    { Invoke-MacroCombo }
        default         { Invoke-AutoBuyCar }
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
