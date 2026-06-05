Set-StrictMode -Version 2.0

function Get-AfkAppRoot {
    [CmdletBinding()]
    param(
        [string]$AppRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($AppRoot)) {
        return [System.IO.Path]::GetFullPath($AppRoot)
    }

    return [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
}

function Get-AfkPaths {
    [CmdletBinding()]
    param(
        [string]$AppRoot
    )

    $root = Get-AfkAppRoot -AppRoot $AppRoot
    $runtimeRoot = Join-Path $root 'runtime'
    $logsRoot = Join-Path $root 'logs'

    [pscustomobject]@{
        AppRoot     = $root
        RuntimeRoot = $runtimeRoot
        LogsRoot    = $logsRoot
        LogPath     = Join-Path $logsRoot 'afk.log'
        PidPath     = Join-Path $runtimeRoot 'afk.pid'
    }
}

function Initialize-AfkWorkspace {
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

function Test-AfkConfigProperty {
    param(
        $Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    return ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name)
}

function Get-AfkConfigIntValue {
    param(
        $Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$DefaultValue
    )

    if ((Test-AfkConfigProperty -Object $Object -Name $Name) -and $null -ne $Object.$Name) {
        return [int]$Object.$Name
    }

    return $DefaultValue
}

function Get-AfkConfigStringValue {
    param(
        $Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$DefaultValue
    )

    if ((Test-AfkConfigProperty -Object $Object -Name $Name) -and $null -ne $Object.$Name) {
        return [string]$Object.$Name
    }

    return $DefaultValue
}

function Normalize-AfkKeyName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Key
    )

    switch ($Key.Trim().ToLowerInvariant()) {
        'enter' { return 'Enter' }
        'return' { return 'Enter' }
        'esc' { return 'Esc' }
        'escape' { return 'Esc' }
        'a' { return 'A' }
        'd' { return 'D' }
        's' { return 'S' }
        'w' { return 'W' }
        'x' { return 'X' }
        'space' { return 'Space' }
        'backspace' { return 'Backspace' }
        'bksp' { return 'Backspace' }
        'bs' { return 'Backspace' }
        'left' { return 'Left' }
        'right' { return 'Right' }
        'up' { return 'Up' }
        'down' { return 'Down' }
        default { throw "Unsupported AFK key: $Key" }
    }
}

function Get-DefaultAfkMacroComboSteps {
    @(
        [pscustomobject]@{ Key = 'Esc'; WaitMilliseconds = 2000 },
        [pscustomobject]@{ Key = 'W'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 200 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 200 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 200 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 200 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 200 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 200 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'D'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'W'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'W'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'W'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'A'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'Esc'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'Esc'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 200 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 200 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 200 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 200 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 200 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 200 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 0 }
    )
}

function ConvertTo-AfkMacroComboSteps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Steps
    )

    $converted = @()
    foreach ($step in @($Steps)) {
        if (-not (Test-AfkConfigProperty -Object $step -Name 'key')) {
            throw "Config value 'afk.macroCombo.steps[].key' is required."
        }
        if (-not (Test-AfkConfigProperty -Object $step -Name 'waitMilliseconds')) {
            throw "Config value 'afk.macroCombo.steps[].waitMilliseconds' is required."
        }

        $key = Normalize-AfkKeyName -Key ([string]$step.key)
        $waitMilliseconds = [int]$step.waitMilliseconds
        if ($waitMilliseconds -lt 0) {
            throw "Config value 'afk.macroCombo.steps[].waitMilliseconds' cannot be negative."
        }

        $converted += [pscustomobject]@{
            Key              = $key
            WaitMilliseconds = $waitMilliseconds
        }
    }

    if ($converted.Count -lt 1) {
        throw "Config value 'afk.macroCombo.steps' must contain at least one step."
    }

    return $converted
}

function Get-AfkConfig {
    [CmdletBinding()]
    param(
        [string]$AppRoot
    )

    $root = Get-AfkAppRoot -AppRoot $AppRoot
    $configPath = Join-Path $root 'config.json'
    $startupDelaySeconds = 5
    $keyTapHoldMilliseconds = 50
    $inputMethod = 'SendKeys'
    $sequenceEnterDelaySeconds = 55
    $sequenceXDelayMilliseconds = 500
    $sequenceLoopDelaySeconds = 10
    $enterEveryDelaySeconds = 10
    $macroComboCycleDelaySeconds = 20
    $macroComboSteps = @(Get-DefaultAfkMacroComboSteps)

    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $rawConfig = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
        $json = $rawConfig | ConvertFrom-Json
        if ((Test-AfkConfigProperty -Object $json -Name 'afk') -and $null -ne $json.afk) {
            $afk = $json.afk
            $startupDelaySeconds = Get-AfkConfigIntValue -Object $afk -Name 'startupDelaySeconds' -DefaultValue $startupDelaySeconds
            $keyTapHoldMilliseconds = Get-AfkConfigIntValue -Object $afk -Name 'keyTapHoldMilliseconds' -DefaultValue $keyTapHoldMilliseconds
            $inputMethod = Get-AfkConfigStringValue -Object $afk -Name 'inputMethod' -DefaultValue $inputMethod

            if ((Test-AfkConfigProperty -Object $afk -Name 'sequence') -and $null -ne $afk.sequence) {
                $sequenceEnterDelaySeconds = Get-AfkConfigIntValue -Object $afk.sequence -Name 'enterDelaySeconds' -DefaultValue $sequenceEnterDelaySeconds
                $sequenceXDelayMilliseconds = Get-AfkConfigIntValue -Object $afk.sequence -Name 'xDelayMilliseconds' -DefaultValue $sequenceXDelayMilliseconds
                $sequenceLoopDelaySeconds = Get-AfkConfigIntValue -Object $afk.sequence -Name 'loopDelaySeconds' -DefaultValue $sequenceLoopDelaySeconds
            }

            if ((Test-AfkConfigProperty -Object $afk -Name 'enterEvery10s') -and $null -ne $afk.enterEvery10s) {
                $enterEveryDelaySeconds = Get-AfkConfigIntValue -Object $afk.enterEvery10s -Name 'delaySeconds' -DefaultValue $enterEveryDelaySeconds
            }

            if ((Test-AfkConfigProperty -Object $afk -Name 'macroComboCycleDelaySeconds') -and $null -ne $afk.macroComboCycleDelaySeconds) {
                $macroComboCycleDelaySeconds = [int]$afk.macroComboCycleDelaySeconds
            }

            if ((Test-AfkConfigProperty -Object $afk -Name 'macroCombo') -and $null -ne $afk.macroCombo) {
                $macroCombo = $afk.macroCombo
                $macroComboCycleDelaySeconds = Get-AfkConfigIntValue -Object $macroCombo -Name 'cycleDelaySeconds' -DefaultValue $macroComboCycleDelaySeconds
                if ((Test-AfkConfigProperty -Object $macroCombo -Name 'steps') -and $null -ne $macroCombo.steps) {
                    $macroComboSteps = @(ConvertTo-AfkMacroComboSteps -Steps $macroCombo.steps)
                }
            }
        }
    }

    $nonNegativeChecks = @(
        @{ Name = 'afk.startupDelaySeconds'; Value = $startupDelaySeconds },
        @{ Name = 'afk.keyTapHoldMilliseconds'; Value = $keyTapHoldMilliseconds },
        @{ Name = 'afk.sequence.enterDelaySeconds'; Value = $sequenceEnterDelaySeconds },
        @{ Name = 'afk.sequence.xDelayMilliseconds'; Value = $sequenceXDelayMilliseconds },
        @{ Name = 'afk.sequence.loopDelaySeconds'; Value = $sequenceLoopDelaySeconds },
        @{ Name = 'afk.macroCombo.cycleDelaySeconds'; Value = $macroComboCycleDelaySeconds }
    )
    foreach ($check in $nonNegativeChecks) {
        if ($check.Value -lt 0) {
            throw "Config value '$($check.Name)' cannot be negative."
        }
    }

    if ($enterEveryDelaySeconds -lt 1) {
        throw "Config value 'afk.enterEvery10s.delaySeconds' must be at least 1."
    }

    if ($macroComboCycleDelaySeconds -lt 0) {
        throw "Config value 'afk.macroCombo.cycleDelaySeconds' cannot be negative."
    }
    if (@('SendKeys', 'SendInputScanCode', 'SendInputVirtualKey') -notcontains $inputMethod) {
        throw "Config value 'afk.inputMethod' must be SendKeys, SendInputScanCode, or SendInputVirtualKey."
    }

    [pscustomobject]@{
        ConfigPath                   = $configPath
        StartupDelaySeconds          = $startupDelaySeconds
        KeyTapHoldMilliseconds       = $keyTapHoldMilliseconds
        InputMethod                  = $inputMethod
        SequenceEnterDelaySeconds    = $sequenceEnterDelaySeconds
        SequenceXDelayMilliseconds   = $sequenceXDelayMilliseconds
        SequenceLoopDelaySeconds     = $sequenceLoopDelaySeconds
        EnterEveryDelaySeconds       = $enterEveryDelaySeconds
        MacroComboCycleDelaySeconds  = $macroComboCycleDelaySeconds
        MacroComboSteps              = @($macroComboSteps)
    }
}

function Resolve-AfkRuntimeOptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config,
        [int]$StartupDelaySeconds = -1,
        [int]$EnterDelaySeconds = -1,
        [int]$XDelayMilliseconds = -1,
        [int]$LoopDelaySeconds = -1,
        [int]$EnterOnlyDelaySeconds = -1,
        [int]$KeyTapHoldMilliseconds = -1,
        [int]$MacroComboCycleDelaySeconds = -1,
        [ValidateSet('', 'SendKeys', 'SendInputScanCode', 'SendInputVirtualKey')][string]$InputMethod = ''
    )

    $resolvedStartupDelaySeconds = if ($StartupDelaySeconds -ge 0) { $StartupDelaySeconds } else { $Config.StartupDelaySeconds }
    $resolvedEnterDelaySeconds = if ($EnterDelaySeconds -ge 0) { $EnterDelaySeconds } else { $Config.SequenceEnterDelaySeconds }
    $resolvedXDelayMilliseconds = if ($XDelayMilliseconds -ge 0) { $XDelayMilliseconds } else { $Config.SequenceXDelayMilliseconds }
    $resolvedLoopDelaySeconds = if ($LoopDelaySeconds -ge 0) { $LoopDelaySeconds } else { $Config.SequenceLoopDelaySeconds }
    $resolvedEnterOnlyDelaySeconds = if ($EnterOnlyDelaySeconds -ge 0) { $EnterOnlyDelaySeconds } else { $Config.EnterEveryDelaySeconds }
    $resolvedKeyTapHoldMilliseconds = if ($KeyTapHoldMilliseconds -ge 0) { $KeyTapHoldMilliseconds } else { $Config.KeyTapHoldMilliseconds }
    $resolvedMacroComboCycleDelaySeconds = if ($MacroComboCycleDelaySeconds -ge 0) { $MacroComboCycleDelaySeconds } else { $Config.MacroComboCycleDelaySeconds }
    $resolvedInputMethod = if (-not [string]::IsNullOrWhiteSpace($InputMethod)) { $InputMethod } else { $Config.InputMethod }

    $nonNegativeChecks = @(
        @{ Name = 'StartupDelaySeconds'; Value = $resolvedStartupDelaySeconds },
        @{ Name = 'EnterDelaySeconds'; Value = $resolvedEnterDelaySeconds },
        @{ Name = 'XDelayMilliseconds'; Value = $resolvedXDelayMilliseconds },
        @{ Name = 'LoopDelaySeconds'; Value = $resolvedLoopDelaySeconds },
        @{ Name = 'KeyTapHoldMilliseconds'; Value = $resolvedKeyTapHoldMilliseconds },
        @{ Name = 'MacroComboCycleDelaySeconds'; Value = $resolvedMacroComboCycleDelaySeconds }
    )
    foreach ($check in $nonNegativeChecks) {
        if ($check.Value -lt 0) {
            throw "AFK option '$($check.Name)' cannot be negative."
        }
    }

    if ($resolvedEnterOnlyDelaySeconds -lt 1) {
        throw "AFK option 'EnterOnlyDelaySeconds' must be at least 1."
    }

    [pscustomobject]@{
        StartupDelaySeconds          = $resolvedStartupDelaySeconds
        EnterDelaySeconds           = $resolvedEnterDelaySeconds
        XDelayMilliseconds          = $resolvedXDelayMilliseconds
        LoopDelaySeconds            = $resolvedLoopDelaySeconds
        EnterOnlyDelaySeconds       = $resolvedEnterOnlyDelaySeconds
        KeyTapHoldMilliseconds      = $resolvedKeyTapHoldMilliseconds
        InputMethod                 = $resolvedInputMethod
        MacroComboCycleDelaySeconds = $resolvedMacroComboCycleDelaySeconds
        MacroComboSteps             = @($Config.MacroComboSteps)
    }
}

function Write-AfkLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO',
        [Parameter(Mandatory = $true)][string]$Message
    )

    Initialize-AfkWorkspace -Paths $Paths
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $Paths.LogPath -Value "[$timestamp] [$Level] $Message" -Encoding UTF8
}

function Initialize-AfkNative {
    if ('GameAfkNative' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class GameAfkNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT
    {
        public uint type;
        public InputUnion u;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct InputUnion
    {
        [FieldOffset(0)]
        public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    public const uint INPUT_KEYBOARD = 1;
    public const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
    public const uint KEYEVENTF_KEYUP = 0x0002;
    public const uint KEYEVENTF_SCANCODE = 0x0008;

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    public static extern uint MapVirtualKey(uint uCode, uint uMapType);

    public static uint SendScanCode(ushort scanCode, bool keyUp)
    {
        return SendScanCode(scanCode, keyUp, false);
    }

    public static uint SendScanCode(ushort scanCode, bool keyUp, bool extendedKey)
    {
        INPUT[] inputs = new INPUT[1];
        inputs[0].type = INPUT_KEYBOARD;
        inputs[0].u.ki.wVk = 0;
        inputs[0].u.ki.wScan = scanCode;
        inputs[0].u.ki.dwFlags = KEYEVENTF_SCANCODE | (keyUp ? KEYEVENTF_KEYUP : 0) | (extendedKey ? KEYEVENTF_EXTENDEDKEY : 0);
        inputs[0].u.ki.time = 0;
        inputs[0].u.ki.dwExtraInfo = UIntPtr.Zero;
        return SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT)));
    }

    public static uint SendVirtualKey(ushort virtualKey, bool keyUp, bool extendedKey)
    {
        INPUT[] inputs = new INPUT[1];
        inputs[0].type = INPUT_KEYBOARD;
        inputs[0].u.ki.wVk = virtualKey;
        inputs[0].u.ki.wScan = 0;
        inputs[0].u.ki.dwFlags = (keyUp ? KEYEVENTF_KEYUP : 0) | (extendedKey ? KEYEVENTF_EXTENDEDKEY : 0);
        inputs[0].u.ki.time = 0;
        inputs[0].u.ki.dwExtraInfo = UIntPtr.Zero;
        return SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT)));
    }
}
'@
}

function ConvertTo-AfkSendKeysToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Enter', 'Esc', 'A', 'D', 'S', 'W', 'X', 'Space', 'Backspace', 'Left', 'Right', 'Up', 'Down')]
        [string]$Key
    )

    switch ($Key) {
        'Enter' { return '{ENTER}' }
        'Esc' { return '{ESC}' }
        'Backspace' { return '{BACKSPACE}' }
        'Space' { return ' ' }
        'Left' { return '{LEFT}' }
        'Right' { return '{RIGHT}' }
        'Up' { return '{UP}' }
        'Down' { return '{DOWN}' }
        default { return $Key.ToLowerInvariant() }
    }
}

function Send-AfkWDown {
    [CmdletBinding()]
    param(
        [switch]$DryRun
    )

    if ($DryRun) {
        return
    }

    Initialize-AfkNative
    $vkW = [byte]0x57
    $scan = [UInt16]([GameAfkNative]::MapVirtualKey($vkW, 0))
    [void][GameAfkNative]::SendScanCode($scan, $false)
}

function Send-AfkWUp {
    [CmdletBinding()]
    param(
        [switch]$DryRun
    )

    if ($DryRun) {
        return
    }

    Initialize-AfkNative
    $vkW = [byte]0x57
    $scan = [UInt16]([GameAfkNative]::MapVirtualKey($vkW, 0))
    [void][GameAfkNative]::SendScanCode($scan, $true)
}

function Send-AfkVirtualKeyTap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$VirtualKey,
        [int]$HoldMilliseconds = 50,
        [switch]$ExtendedKey,
        [ValidateSet('SendInputScanCode', 'SendInputVirtualKey')][string]$InputMethod = 'SendInputScanCode',
        [switch]$DryRun
    )

    if ($DryRun) {
        return [pscustomobject]@{
            Method      = $InputMethod
            VirtualKey  = $VirtualKey
            ScanCode    = $null
            ExtendedKey = [bool]$ExtendedKey
            DownResult  = 0
            UpResult    = 0
            DryRun      = $true
        }
    }

    if ($HoldMilliseconds -lt 0) {
        $HoldMilliseconds = 0
    }

    Initialize-AfkNative
    $scan = [UInt16]([GameAfkNative]::MapVirtualKey([uint32]$VirtualKey, 0))
    if ($InputMethod -eq 'SendInputScanCode' -and $scan -eq 0) {
        throw "Could not map virtual key: $VirtualKey"
    }

    if ($InputMethod -eq 'SendInputVirtualKey') {
        $downResult = [GameAfkNative]::SendVirtualKey([UInt16]$VirtualKey, $false, [bool]$ExtendedKey)
    }
    else {
        $downResult = [GameAfkNative]::SendScanCode($scan, $false, [bool]$ExtendedKey)
    }
    if ($HoldMilliseconds -gt 0) {
        Start-Sleep -Milliseconds $HoldMilliseconds
    }
    if ($InputMethod -eq 'SendInputVirtualKey') {
        $upResult = [GameAfkNative]::SendVirtualKey([UInt16]$VirtualKey, $true, [bool]$ExtendedKey)
    }
    else {
        $upResult = [GameAfkNative]::SendScanCode($scan, $true, [bool]$ExtendedKey)
    }

    [pscustomobject]@{
        Method      = $InputMethod
        VirtualKey  = $VirtualKey
        ScanCode    = $scan
        ExtendedKey = [bool]$ExtendedKey
        DownResult  = $downResult
        UpResult    = $upResult
        DryRun      = $false
    }
}

function Send-AfkNamedKeyTap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Enter', 'Esc', 'A', 'D', 'S', 'W', 'X', 'Space', 'Backspace', 'Left', 'Right', 'Up', 'Down')]
        [string]$Key,
        [int]$HoldMilliseconds = 50,
        [ValidateSet('SendInputScanCode', 'SendInputVirtualKey', 'SendKeys')][string]$InputMethod = 'SendInputScanCode',
        [switch]$DryRun
    )

    $virtualKey = switch ($Key) {
        'Enter' { 0x0D }
        'Esc' { 0x1B }
        'A' { 0x41 }
        'D' { 0x44 }
        'S' { 0x53 }
        'W' { 0x57 }
        'X' { 0x58 }
        'Space' { 0x20 }
        'Backspace' { 0x08 }
        'Left' { 0x25 }
        'Up' { 0x26 }
        'Right' { 0x27 }
        'Down' { 0x28 }
    }
    $isExtendedKey = $Key -in @('Left', 'Right', 'Up', 'Down')

    if ($InputMethod -eq 'SendKeys') {
        $token = ConvertTo-AfkSendKeysToken -Key $Key
        if (-not $DryRun) {
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.SendKeys]::SendWait($token)
            if ($HoldMilliseconds -gt 0) {
                Start-Sleep -Milliseconds $HoldMilliseconds
            }
        }

        return [pscustomobject]@{
            Method      = 'SendKeys'
            VirtualKey  = $virtualKey
            ScanCode    = $null
            ExtendedKey = $isExtendedKey
            DownResult  = $null
            UpResult    = $null
            DryRun      = [bool]$DryRun
            Token       = $token
        }
    }

    Send-AfkVirtualKeyTap -VirtualKey $virtualKey -HoldMilliseconds $HoldMilliseconds -ExtendedKey:$isExtendedKey -InputMethod $InputMethod -DryRun:$DryRun
}

function Send-AfkDigitKeyTap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[0-9]$')]
        [string]$Digit,
        [int]$HoldMilliseconds = 50,
        [ValidateSet('SendInputScanCode', 'SendInputVirtualKey', 'SendKeys')][string]$InputMethod = 'SendInputScanCode',
        [switch]$DryRun
    )

    $virtualKey = [int][char]$Digit
    if ($InputMethod -eq 'SendKeys') {
        if (-not $DryRun) {
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.SendKeys]::SendWait($Digit)
            if ($HoldMilliseconds -gt 0) {
                Start-Sleep -Milliseconds $HoldMilliseconds
            }
        }

        return [pscustomobject]@{
            Method      = 'SendKeys'
            VirtualKey  = $virtualKey
            ScanCode    = $null
            ExtendedKey = $false
            DownResult  = $null
            UpResult    = $null
            DryRun      = [bool]$DryRun
            Token       = $Digit
        }
    }

    Send-AfkVirtualKeyTap -VirtualKey $virtualKey -HoldMilliseconds $HoldMilliseconds -InputMethod $InputMethod -DryRun:$DryRun
}

function Send-AfkKeys {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Keys,
        [switch]$DryRun
    )

    if ($DryRun) {
        return
    }

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.SendKeys]::SendWait($Keys)
}

function Set-AfkPid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths
    )

    Initialize-AfkWorkspace -Paths $Paths
    Set-Content -LiteralPath $Paths.PidPath -Value ([string]$PID) -Encoding ASCII
}

function Remove-AfkPid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths
    )

    if (Test-Path -LiteralPath $Paths.PidPath -PathType Leaf) {
        Remove-Item -LiteralPath $Paths.PidPath -Force
    }
}

function Get-AfkState {
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
            Message     = 'AFK is not running.'
        }
    }

    $pidText = (Get-Content -LiteralPath $Paths.PidPath -ErrorAction SilentlyContinue | Select-Object -First 1)
    $afkPid = 0
    if (-not [int]::TryParse(([string]$pidText).Trim(), [ref]$afkPid)) {
        return [pscustomobject]@{
            Status      = 'InvalidPid'
            Pid         = $null
            Process     = $null
            CommandLine = $null
            Message     = "PID file is invalid: $($Paths.PidPath)"
        }
    }

    $process = Get-Process -Id $afkPid -ErrorAction SilentlyContinue
    if (-not $process) {
        return [pscustomobject]@{
            Status      = 'Stale'
            Pid         = $afkPid
            Process     = $null
            CommandLine = $null
            Message     = "PID file is stale. Process $afkPid is not running."
        }
    }

    $commandLine = $null
    try {
        $cim = Get-CimInstance Win32_Process -Filter "ProcessId = $afkPid" -ErrorAction Stop
        $commandLine = $cim.CommandLine
    }
    catch {
        try {
            $wmi = Get-WmiObject Win32_Process -Filter "ProcessId = $afkPid" -ErrorAction Stop
            $commandLine = $wmi.CommandLine
        }
        catch {
            $commandLine = $null
        }
    }

    $normalizedCommand = if ($commandLine) { $commandLine.ToLowerInvariant() } else { '' }
    $isAfk = $normalizedCommand.Contains('runafk.ps1')

    if ($isAfk) {
        return [pscustomobject]@{
            Status      = 'Running'
            Pid         = $afkPid
            Process     = $process
            CommandLine = $commandLine
            Message     = "AFK is running. PID=$afkPid"
        }
    }

    if ([string]::IsNullOrWhiteSpace($commandLine) -and $process.ProcessName -like 'powershell*') {
        return [pscustomobject]@{
            Status      = 'RunningUnverified'
            Pid         = $afkPid
            Process     = $process
            CommandLine = $commandLine
            Message     = "AFK appears to be running, but process command line could not be verified. PID=$afkPid"
        }
    }

    [pscustomobject]@{
        Status      = 'PidConflict'
        Pid         = $afkPid
        Process     = $process
        CommandLine = $commandLine
        Message     = "PID file points to a process that does not look like AFK. PID=$afkPid"
    }
}

function Remove-StaleAfkPid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)]$State
    )

    if ($State.Status -in @('Stale', 'InvalidPid', 'PidConflict')) {
        Remove-AfkPid -Paths $Paths
    }
}

function Release-AfkKeys {
    [CmdletBinding()]
    param(
        [switch]$DryRun
    )

    Send-AfkWUp -DryRun:$DryRun
}
