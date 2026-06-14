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

# --- Virtual gamepad (ViGEm) -------------------------------------------------------------------------
# A virtual Xbox 360 controller, used to HOLD the throttle (right trigger) so a driving game (Forza)
# drives forward continuously -- something synthetic keyboard input cannot reliably do, because Forza
# ignores SendInput-injected keys while driving. Backed by the managed Nefarius.ViGEm.Client.dll
# (native lib embedded) + the ViGEmBus driver. Loaded lazily on first Connect so the GUI / other
# subsystems that dot-source this file pay nothing unless a gamepad is actually used.
#
# IMPORTANT: connect ONCE per run and keep it plugged in until the run ends. Plugging/unplugging the
# controller per drive makes the game flash a "controller disconnected" popup every loop; a single
# long-lived connection keeps the game seeing a controller the whole time. The pad is auto-unplugged
# when this process exits (so a force-Stop still cleans up at the OS level).

# Connection state for the lazily-loaded virtual gamepad. Initialized once when this lib is
# dot-sourced (the worker / GUI each dot-source it exactly once), so StrictMode reads are safe.
$script:AfkGamepadClient = $null
$script:AfkGamepadPad = $null

function Get-AfkGamepadDllPath {
    [CmdletBinding()]
    param(
        [string]$AppRoot
    )

    $root = Get-AfkAppRoot -AppRoot $AppRoot
    $candidates = @(
        (Join-Path $root 'Nefarius.ViGEm.Client.dll'),
        (Join-Path $root 'lib\Nefarius.ViGEm.Client.dll')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    return $null
}

function Test-AfkGamepadConnected {
    [CmdletBinding()]
    param()

    return ($null -ne $script:AfkGamepadPad)
}

function Connect-AfkGamepad {
    [CmdletBinding()]
    param(
        [string]$AppRoot,
        [string]$DllPath,
        [switch]$DryRun
    )

    if ($DryRun) {
        return $false
    }
    if ($null -ne $script:AfkGamepadPad) {
        return $true
    }

    if ([string]::IsNullOrWhiteSpace($DllPath)) {
        $DllPath = Get-AfkGamepadDllPath -AppRoot $AppRoot
    }
    if ([string]::IsNullOrWhiteSpace($DllPath) -or -not (Test-Path -LiteralPath $DllPath -PathType Leaf)) {
        throw "ViGEm client DLL (Nefarius.ViGEm.Client.dll) not found. Place it at the app root (next to GameSaveGuardian.ps1) or set ultimate.gamepadThrottle.dllPath."
    }
    $DllPath = (Resolve-Path -LiteralPath $DllPath).Path
    try { Unblock-File -LiteralPath $DllPath -ErrorAction SilentlyContinue } catch { }
    [void][Reflection.Assembly]::LoadFrom($DllPath)

    $client = $null
    try {
        $client = New-Object Nefarius.ViGEm.Client.ViGEmClient
    }
    catch {
        $inner = $_.Exception
        if ($inner.InnerException) { $inner = $inner.InnerException }
        if ($inner.GetType().Name -eq 'VigemBusNotFoundException') {
            throw 'ViGEmBus driver is not installed. Install it from https://github.com/nefarius/ViGEmBus/releases then retry.'
        }
        throw
    }

    $pad = $client.CreateXbox360Controller()
    $pad.Connect()
    $script:AfkGamepadClient = $client
    $script:AfkGamepadPad = $pad
    return $true
}

function Set-AfkGamepadRightTrigger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateRange(0, 255)][int]$Value
    )

    if ($null -eq $script:AfkGamepadPad) {
        throw 'Gamepad is not connected. Call Connect-AfkGamepad first.'
    }
    $script:AfkGamepadPad.SetSliderValue([Nefarius.ViGEm.Client.Targets.Xbox360.Xbox360Slider]::RightTrigger, [byte]$Value)
    $script:AfkGamepadPad.SubmitReport()
}

function Disconnect-AfkGamepad {
    [CmdletBinding()]
    param()

    if ($null -ne $script:AfkGamepadPad) {
        try {
            $script:AfkGamepadPad.SetSliderValue([Nefarius.ViGEm.Client.Targets.Xbox360.Xbox360Slider]::RightTrigger, [byte]0)
            $script:AfkGamepadPad.SetAxisValue([Nefarius.ViGEm.Client.Targets.Xbox360.Xbox360Axis]::LeftThumbY, [short]0)
            $script:AfkGamepadPad.SubmitReport()
            $script:AfkGamepadPad.Disconnect()
        }
        catch { }
        $script:AfkGamepadPad = $null
    }
    if ($null -ne $script:AfkGamepadClient) {
        try { $script:AfkGamepadClient.Dispose() } catch { }
        $script:AfkGamepadClient = $null
    }
}

function Release-AfkKeys {
    [CmdletBinding()]
    param(
        [switch]$DryRun
    )

    Send-AfkWUp -DryRun:$DryRun
}
