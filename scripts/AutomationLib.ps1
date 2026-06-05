Set-StrictMode -Version 2.0

function Get-AutomationAppRoot {
    [CmdletBinding()]
    param(
        [string]$AppRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($AppRoot)) {
        return [System.IO.Path]::GetFullPath($AppRoot)
    }

    return [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
}

function Get-AutomationPaths {
    [CmdletBinding()]
    param(
        [string]$AppRoot
    )

    $root = Get-AutomationAppRoot -AppRoot $AppRoot
    $runtimeRoot = Join-Path $root 'runtime'
    $logsRoot = Join-Path $root 'logs'

    [pscustomobject]@{
        AppRoot     = $root
        RuntimeRoot = $runtimeRoot
        LogsRoot    = $logsRoot
        LogPath     = Join-Path $logsRoot 'automation.log'
        PidPath     = Join-Path $runtimeRoot 'automation.pid'
    }
}

function Initialize-AutomationWorkspace {
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

function Write-AutomationLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO',
        [Parameter(Mandatory = $true)][string]$Message
    )

    Initialize-AutomationWorkspace -Paths $Paths
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $Paths.LogPath -Value "[$timestamp] [$Level] $Message" -Encoding UTF8
}

function Test-AutomationConfigProperty {
    param(
        $Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    return ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name)
}

function Get-AutomationConfigIntValue {
    param(
        $Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$DefaultValue
    )

    if ((Test-AutomationConfigProperty -Object $Object -Name $Name) -and $null -ne $Object.$Name) {
        return [int]$Object.$Name
    }

    return $DefaultValue
}

function Get-AutomationConfigBoolValue {
    param(
        $Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$DefaultValue
    )

    if ((Test-AutomationConfigProperty -Object $Object -Name $Name) -and $null -ne $Object.$Name) {
        return [bool]$Object.$Name
    }

    return $DefaultValue
}

function Get-AutomationConfigStringValue {
    param(
        $Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$DefaultValue
    )

    if ((Test-AutomationConfigProperty -Object $Object -Name $Name) -and $null -ne $Object.$Name) {
        return [string]$Object.$Name
    }

    return $DefaultValue
}

function Get-DefaultAutoBuyCarSteps {
    @(
        [pscustomobject]@{ Key = 'Space'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'Down'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 0 }
    )
}

function Get-DefaultDeleteCarSteps {
    @(
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 },
        [pscustomobject]@{ Key = 'Enter'; WaitMilliseconds = 1000 },
        [pscustomobject]@{ Key = 'S'; WaitMilliseconds = 500 }
    )
}

function ConvertTo-AutomationSteps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Steps,
        [Parameter(Mandatory = $true)][string]$ConfigName
    )

    $converted = @()
    foreach ($step in @($Steps)) {
        if (-not (Test-AutomationConfigProperty -Object $step -Name 'key')) {
            throw "Config value '$ConfigName[].key' is required."
        }
        if (-not (Test-AutomationConfigProperty -Object $step -Name 'waitMilliseconds')) {
            throw "Config value '$ConfigName[].waitMilliseconds' is required."
        }

        $key = Normalize-AfkKeyName -Key ([string]$step.key)
        $waitMilliseconds = [int]$step.waitMilliseconds
        if ($waitMilliseconds -lt 0) {
            throw "Config value '$ConfigName[].waitMilliseconds' cannot be negative."
        }

        $converted += [pscustomobject]@{
            Key              = $key
            WaitMilliseconds = $waitMilliseconds
        }
    }

    if ($converted.Count -lt 1) {
        throw "Config value '$ConfigName' must contain at least one step."
    }

    return $converted
}

function Get-AutomationConfig {
    [CmdletBinding()]
    param(
        [string]$AppRoot
    )

    $root = Get-AutomationAppRoot -AppRoot $AppRoot
    $configPath = Join-Path $root 'config.json'

    $startupDelaySeconds = 5
    $keyTapHoldMilliseconds = 50
    $inputMethod = 'SendKeys'
    $autoBuyLoopCount = 1
    $autoBuyBetweenLoopsMilliseconds = 1000
    $autoBuySteps = @(Get-DefaultAutoBuyCarSteps)
    $deleteCarLoopCount = 1
    $deleteCarBetweenLoopsMilliseconds = 1000
    $deleteCarSteps = @(Get-DefaultDeleteCarSteps)
    $findLoopCount = 1
    $findBetweenLoopsMilliseconds = 3000
    $findMaxSearchAttempts = 50
    $findSearchKey = 'Left'
    $findSearchSettleMilliseconds = 500
    $findAfterSelectDelayMilliseconds = 2000
    $defaultSubaruText = [string]([char]0x65AF) + [string]([char]0x5DF4) + [string]([char]0x9C81)
    $defaultNewBadgeText = [string]([char]0x5168) + [string]([char]0x65B0)
    $findTargetKeywords = @('1998', $defaultSubaruText)
    $findNewBadgeText = $defaultNewBadgeText
    $findRequireTargetConfirmation = $true
    $findVerticalScanSteps = 2

    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $rawConfig = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
        $json = $rawConfig | ConvertFrom-Json
        if ((Test-AutomationConfigProperty -Object $json -Name 'automation') -and $null -ne $json.automation) {
            $automation = $json.automation
            $startupDelaySeconds = Get-AutomationConfigIntValue -Object $automation -Name 'startupDelaySeconds' -DefaultValue $startupDelaySeconds
            $keyTapHoldMilliseconds = Get-AutomationConfigIntValue -Object $automation -Name 'keyTapHoldMilliseconds' -DefaultValue $keyTapHoldMilliseconds
            $inputMethod = Get-AutomationConfigStringValue -Object $automation -Name 'inputMethod' -DefaultValue $inputMethod

            if ((Test-AutomationConfigProperty -Object $automation -Name 'autoBuyCar') -and $null -ne $automation.autoBuyCar) {
                $autoBuy = $automation.autoBuyCar
                $autoBuyLoopCount = Get-AutomationConfigIntValue -Object $autoBuy -Name 'loopCount' -DefaultValue $autoBuyLoopCount
                $autoBuyBetweenLoopsMilliseconds = Get-AutomationConfigIntValue -Object $autoBuy -Name 'betweenLoopsMilliseconds' -DefaultValue $autoBuyBetweenLoopsMilliseconds
                if ((Test-AutomationConfigProperty -Object $autoBuy -Name 'steps') -and $null -ne $autoBuy.steps) {
                    $autoBuySteps = @(ConvertTo-AutomationSteps -Steps $autoBuy.steps -ConfigName 'automation.autoBuyCar.steps')
                }
            }

            if ((Test-AutomationConfigProperty -Object $automation -Name 'deleteCar') -and $null -ne $automation.deleteCar) {
                $deleteCar = $automation.deleteCar
                $deleteCarLoopCount = Get-AutomationConfigIntValue -Object $deleteCar -Name 'loopCount' -DefaultValue $deleteCarLoopCount
                $deleteCarBetweenLoopsMilliseconds = Get-AutomationConfigIntValue -Object $deleteCar -Name 'betweenLoopsMilliseconds' -DefaultValue $deleteCarBetweenLoopsMilliseconds
                if ((Test-AutomationConfigProperty -Object $deleteCar -Name 'steps') -and $null -ne $deleteCar.steps) {
                    $deleteCarSteps = @(ConvertTo-AutomationSteps -Steps $deleteCar.steps -ConfigName 'automation.deleteCar.steps')
                }
            }

            if ((Test-AutomationConfigProperty -Object $automation -Name 'findNewSubaru') -and $null -ne $automation.findNewSubaru) {
                $find = $automation.findNewSubaru
                $findLoopCount = Get-AutomationConfigIntValue -Object $find -Name 'loopCount' -DefaultValue $findLoopCount
                $findBetweenLoopsMilliseconds = Get-AutomationConfigIntValue -Object $find -Name 'betweenLoopsMilliseconds' -DefaultValue $findBetweenLoopsMilliseconds
                $findMaxSearchAttempts = Get-AutomationConfigIntValue -Object $find -Name 'maxSearchAttempts' -DefaultValue $findMaxSearchAttempts
                $findSearchKey = Normalize-AfkKeyName -Key (Get-AutomationConfigStringValue -Object $find -Name 'searchKey' -DefaultValue $findSearchKey)
                $findSearchSettleMilliseconds = Get-AutomationConfigIntValue -Object $find -Name 'searchSettleMilliseconds' -DefaultValue $findSearchSettleMilliseconds
                $findAfterSelectDelayMilliseconds = Get-AutomationConfigIntValue -Object $find -Name 'afterSelectDelayMilliseconds' -DefaultValue $findAfterSelectDelayMilliseconds
                $findNewBadgeText = Get-AutomationConfigStringValue -Object $find -Name 'newBadgeText' -DefaultValue $findNewBadgeText
                $findRequireTargetConfirmation = Get-AutomationConfigBoolValue -Object $find -Name 'requireTargetConfirmation' -DefaultValue $findRequireTargetConfirmation
                $findVerticalScanSteps = Get-AutomationConfigIntValue -Object $find -Name 'verticalScanSteps' -DefaultValue $findVerticalScanSteps
                if ((Test-AutomationConfigProperty -Object $find -Name 'targetKeywords') -and $null -ne $find.targetKeywords) {
                    $findTargetKeywords = @($find.targetKeywords | ForEach-Object { [string]$_ })
                }
            }
        }
    }

    $nonNegativeChecks = @(
        @{ Name = 'automation.startupDelaySeconds'; Value = $startupDelaySeconds },
        @{ Name = 'automation.keyTapHoldMilliseconds'; Value = $keyTapHoldMilliseconds },
        @{ Name = 'automation.autoBuyCar.betweenLoopsMilliseconds'; Value = $autoBuyBetweenLoopsMilliseconds },
        @{ Name = 'automation.deleteCar.betweenLoopsMilliseconds'; Value = $deleteCarBetweenLoopsMilliseconds },
        @{ Name = 'automation.findNewSubaru.betweenLoopsMilliseconds'; Value = $findBetweenLoopsMilliseconds },
        @{ Name = 'automation.findNewSubaru.searchSettleMilliseconds'; Value = $findSearchSettleMilliseconds },
        @{ Name = 'automation.findNewSubaru.afterSelectDelayMilliseconds'; Value = $findAfterSelectDelayMilliseconds },
        @{ Name = 'automation.findNewSubaru.verticalScanSteps'; Value = $findVerticalScanSteps }
    )
    foreach ($check in $nonNegativeChecks) {
        if ($check.Value -lt 0) {
            throw "Config value '$($check.Name)' cannot be negative."
        }
    }

    if ($autoBuyLoopCount -lt 1) { throw "Config value 'automation.autoBuyCar.loopCount' must be at least 1." }
    if ($deleteCarLoopCount -lt 1) { throw "Config value 'automation.deleteCar.loopCount' must be at least 1." }
    if ($findLoopCount -lt 1) { throw "Config value 'automation.findNewSubaru.loopCount' must be at least 1." }
    if ($findMaxSearchAttempts -lt 1) { throw "Config value 'automation.findNewSubaru.maxSearchAttempts' must be at least 1." }
    if ($findTargetKeywords.Count -lt 1) { throw "Config value 'automation.findNewSubaru.targetKeywords' must contain at least one item." }
    if (@('SendKeys', 'SendInputScanCode', 'SendInputVirtualKey') -notcontains $inputMethod) {
        throw "Config value 'automation.inputMethod' must be SendKeys, SendInputScanCode, or SendInputVirtualKey."
    }

    [pscustomobject]@{
        ConfigPath                       = $configPath
        StartupDelaySeconds              = $startupDelaySeconds
        KeyTapHoldMilliseconds           = $keyTapHoldMilliseconds
        InputMethod                      = $inputMethod
        AutoBuyCarLoopCount              = $autoBuyLoopCount
        AutoBuyCarSteps                  = @($autoBuySteps)
        AutoBuyCarBetweenLoopsMilliseconds = $autoBuyBetweenLoopsMilliseconds
        DeleteCarLoopCount               = $deleteCarLoopCount
        DeleteCarSteps                   = @($deleteCarSteps)
        DeleteCarBetweenLoopsMilliseconds = $deleteCarBetweenLoopsMilliseconds
        FindNewSubaruLoopCount           = $findLoopCount
        FindNewSubaruBetweenLoopsMilliseconds = $findBetweenLoopsMilliseconds
        FindNewSubaruMaxSearchAttempts   = $findMaxSearchAttempts
        FindNewSubaruSearchKey           = $findSearchKey
        FindNewSubaruSearchSettleMilliseconds = $findSearchSettleMilliseconds
        FindNewSubaruAfterSelectDelayMilliseconds = $findAfterSelectDelayMilliseconds
        FindNewSubaruTargetKeywords      = @($findTargetKeywords)
        FindNewSubaruNewBadgeText        = $findNewBadgeText
        FindNewSubaruRequireTargetConfirmation = $findRequireTargetConfirmation
        FindNewSubaruVerticalScanSteps   = $findVerticalScanSteps
    }
}

function Resolve-AutomationRuntimeOptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config,
        [ValidateSet('AutoBuyCar', 'DeleteCar', 'FindNewSubaru')][string]$Mode = 'AutoBuyCar',
        [int]$LoopCount = -1,
        [int]$StartupDelaySeconds = -1
    )

    $resolvedLoopCount = if ($LoopCount -ge 1) {
        $LoopCount
    }
    elseif ($Mode -eq 'FindNewSubaru') {
        $Config.FindNewSubaruLoopCount
    }
    elseif ($Mode -eq 'DeleteCar') {
        $Config.DeleteCarLoopCount
    }
    else {
        $Config.AutoBuyCarLoopCount
    }

    $resolvedStartupDelaySeconds = if ($StartupDelaySeconds -ge 0) { $StartupDelaySeconds } else { $Config.StartupDelaySeconds }

    if ($resolvedLoopCount -lt 1) { throw "Automation loop count must be at least 1." }
    if ($resolvedStartupDelaySeconds -lt 0) { throw "Automation startup delay cannot be negative." }

    [pscustomobject]@{
        Mode                         = $Mode
        LoopCount                    = $resolvedLoopCount
        StartupDelaySeconds          = $resolvedStartupDelaySeconds
        KeyTapHoldMilliseconds       = $Config.KeyTapHoldMilliseconds
        InputMethod                  = $Config.InputMethod
        AutoBuyCarSteps              = @($Config.AutoBuyCarSteps)
        AutoBuyCarBetweenLoopsMilliseconds = $Config.AutoBuyCarBetweenLoopsMilliseconds
        DeleteCarSteps              = @($Config.DeleteCarSteps)
        DeleteCarBetweenLoopsMilliseconds = $Config.DeleteCarBetweenLoopsMilliseconds
        FindNewSubaruBetweenLoopsMilliseconds = $Config.FindNewSubaruBetweenLoopsMilliseconds
        FindNewSubaruMaxSearchAttempts = $Config.FindNewSubaruMaxSearchAttempts
        FindNewSubaruSearchKey       = $Config.FindNewSubaruSearchKey
        FindNewSubaruSearchSettleMilliseconds = $Config.FindNewSubaruSearchSettleMilliseconds
        FindNewSubaruAfterSelectDelayMilliseconds = $Config.FindNewSubaruAfterSelectDelayMilliseconds
        FindNewSubaruTargetKeywords  = @($Config.FindNewSubaruTargetKeywords)
        FindNewSubaruNewBadgeText    = $Config.FindNewSubaruNewBadgeText
        FindNewSubaruRequireTargetConfirmation = $Config.FindNewSubaruRequireTargetConfirmation
        FindNewSubaruVerticalScanSteps = $Config.FindNewSubaruVerticalScanSteps
    }
}

function Set-AutomationPid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths
    )

    Initialize-AutomationWorkspace -Paths $Paths
    Set-Content -LiteralPath $Paths.PidPath -Value ([string]$PID) -Encoding ASCII
}

function Remove-AutomationPid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths
    )

    if (Test-Path -LiteralPath $Paths.PidPath -PathType Leaf) {
        Remove-Item -LiteralPath $Paths.PidPath -Force
    }
}

function Get-AutomationState {
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
            Message     = 'Automation is not running.'
        }
    }

    $pidText = (Get-Content -LiteralPath $Paths.PidPath -ErrorAction SilentlyContinue | Select-Object -First 1)
    $automationPid = 0
    if (-not [int]::TryParse(([string]$pidText).Trim(), [ref]$automationPid)) {
        return [pscustomobject]@{
            Status      = 'InvalidPid'
            Pid         = $null
            Process     = $null
            CommandLine = $null
            Message     = "PID file is invalid: $($Paths.PidPath)"
        }
    }

    $process = Get-Process -Id $automationPid -ErrorAction SilentlyContinue
    if (-not $process) {
        return [pscustomobject]@{
            Status      = 'Stale'
            Pid         = $automationPid
            Process     = $null
            CommandLine = $null
            Message     = "PID file is stale. Process $automationPid is not running."
        }
    }

    $commandLine = $null
    try {
        $cim = Get-CimInstance Win32_Process -Filter "ProcessId = $automationPid" -ErrorAction Stop
        $commandLine = $cim.CommandLine
    }
    catch {
        try {
            $wmi = Get-WmiObject Win32_Process -Filter "ProcessId = $automationPid" -ErrorAction Stop
            $commandLine = $wmi.CommandLine
        }
        catch {
            $commandLine = $null
        }
    }

    $normalizedCommand = if ($commandLine) { $commandLine.ToLowerInvariant() } else { '' }
    $isAutomation = $normalizedCommand.Contains('runautomation.ps1')

    if ($isAutomation) {
        return [pscustomobject]@{
            Status      = 'Running'
            Pid         = $automationPid
            Process     = $process
            CommandLine = $commandLine
            Message     = "Automation is running. PID=$automationPid"
        }
    }

    if ([string]::IsNullOrWhiteSpace($commandLine) -and $process.ProcessName -like 'powershell*') {
        return [pscustomobject]@{
            Status      = 'RunningUnverified'
            Pid         = $automationPid
            Process     = $process
            CommandLine = $commandLine
            Message     = "Automation appears to be running, but process command line could not be verified. PID=$automationPid"
        }
    }

    [pscustomobject]@{
        Status      = 'PidConflict'
        Pid         = $automationPid
        Process     = $process
        CommandLine = $commandLine
        Message     = "PID file points to a process that does not look like Automation. PID=$automationPid"
    }
}

function Remove-StaleAutomationPid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)]$State
    )

    if ($State.Status -in @('Stale', 'InvalidPid', 'PidConflict')) {
        Remove-AutomationPid -Paths $Paths
    }
}

function Initialize-AutomationNative {
    if ('AutomationNative' -as [type]) {
        return
    }

    Add-Type -ReferencedAssemblies @('System.Drawing') -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class AutomationRectInfo
{
    public bool Found;
    public int X;
    public int Y;
    public int Width;
    public int Height;
    public int PixelCount;
}

public class AutomationNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}

public class AutomationImageTools
{
    private static bool IsHighlight(byte r, byte g, byte b)
    {
        return g >= 170 && r >= 110 && r <= 235 && b <= 90 && (g - b) >= 120;
    }

    private static bool IsYellow(byte r, byte g, byte b)
    {
        return r >= 220 && g >= 210 && b <= 95 && Math.Abs(r - g) <= 70;
    }

    private static Bitmap Ensure32bpp(Bitmap input, out bool ownsBitmap)
    {
        if (input.PixelFormat == PixelFormat.Format32bppArgb) {
            ownsBitmap = false;
            return input;
        }

        Bitmap converted = new Bitmap(input.Width, input.Height, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(converted)) {
            g.DrawImage(input, 0, 0, input.Width, input.Height);
        }
        ownsBitmap = true;
        return converted;
    }

    public static AutomationRectInfo FindHighlightRect(Bitmap input)
    {
        AutomationRectInfo result = new AutomationRectInfo();
        bool ownsBitmap;
        Bitmap bitmap = Ensure32bpp(input, out ownsBitmap);
        try {
            int width = bitmap.Width;
            int height = bitmap.Height;
            Rectangle rect = new Rectangle(0, 0, width, height);
            BitmapData data = bitmap.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try {
                int stride = data.Stride;
                int bytes = Math.Abs(stride) * height;
                byte[] pixels = new byte[bytes];
                Marshal.Copy(data.Scan0, pixels, 0, bytes);

                bool[] mask = new bool[width * height];
                bool[] visited = new bool[width * height];
                for (int y = 0; y < height; y++) {
                    int row = stride > 0 ? y * stride : (height - 1 - y) * (-stride);
                    for (int x = 0; x < width; x++) {
                        int offset = row + x * 4;
                        byte b = pixels[offset];
                        byte g = pixels[offset + 1];
                        byte r = pixels[offset + 2];
                        mask[y * width + x] = IsHighlight(r, g, b);
                    }
                }

                int[] queue = new int[width * height];
                int bestCount = 0;
                int bestMinX = 0, bestMinY = 0, bestMaxX = 0, bestMaxY = 0;

                for (int i = 0; i < mask.Length; i++) {
                    if (!mask[i] || visited[i]) {
                        continue;
                    }

                    int head = 0;
                    int tail = 0;
                    queue[tail++] = i;
                    visited[i] = true;

                    int count = 0;
                    int minX = width, minY = height, maxX = 0, maxY = 0;

                    while (head < tail) {
                        int current = queue[head++];
                        int cy = current / width;
                        int cx = current - cy * width;
                        count++;
                        if (cx < minX) minX = cx;
                        if (cy < minY) minY = cy;
                        if (cx > maxX) maxX = cx;
                        if (cy > maxY) maxY = cy;

                        if (cx > 0) {
                            int next = current - 1;
                            if (mask[next] && !visited[next]) { visited[next] = true; queue[tail++] = next; }
                        }
                        if (cx + 1 < width) {
                            int next = current + 1;
                            if (mask[next] && !visited[next]) { visited[next] = true; queue[tail++] = next; }
                        }
                        if (cy > 0) {
                            int next = current - width;
                            if (mask[next] && !visited[next]) { visited[next] = true; queue[tail++] = next; }
                        }
                        if (cy + 1 < height) {
                            int next = current + width;
                            if (mask[next] && !visited[next]) { visited[next] = true; queue[tail++] = next; }
                        }
                    }

                    int componentWidth = maxX - minX + 1;
                    int componentHeight = maxY - minY + 1;
                    if (count > bestCount && componentWidth >= 80 && componentHeight >= 80) {
                        bestCount = count;
                        bestMinX = minX;
                        bestMinY = minY;
                        bestMaxX = maxX;
                        bestMaxY = maxY;
                    }
                }

                if (bestCount > 0) {
                    result.Found = true;
                    result.X = bestMinX;
                    result.Y = bestMinY;
                    result.Width = bestMaxX - bestMinX + 1;
                    result.Height = bestMaxY - bestMinY + 1;
                    result.PixelCount = bestCount;
                }
                return result;
            }
            finally {
                bitmap.UnlockBits(data);
            }
        }
        finally {
            if (ownsBitmap) {
                bitmap.Dispose();
            }
        }
    }

    public static int CountYellowPixels(Bitmap input, int x, int y, int width, int height)
    {
        bool ownsBitmap;
        Bitmap bitmap = Ensure32bpp(input, out ownsBitmap);
        try {
            int left = Math.Max(0, x);
            int top = Math.Max(0, y);
            int right = Math.Min(bitmap.Width, x + width);
            int bottom = Math.Min(bitmap.Height, y + height);
            if (right <= left || bottom <= top) {
                return 0;
            }

            Rectangle rect = new Rectangle(left, top, right - left, bottom - top);
            BitmapData data = bitmap.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try {
                int stride = data.Stride;
                int bytes = Math.Abs(stride) * rect.Height;
                byte[] pixels = new byte[bytes];
                Marshal.Copy(data.Scan0, pixels, 0, bytes);

                int count = 0;
                for (int yy = 0; yy < rect.Height; yy++) {
                    int row = stride > 0 ? yy * stride : (rect.Height - 1 - yy) * (-stride);
                    for (int xx = 0; xx < rect.Width; xx++) {
                        int offset = row + xx * 4;
                        byte b = pixels[offset];
                        byte g = pixels[offset + 1];
                        byte r = pixels[offset + 2];
                        if (IsYellow(r, g, b)) {
                            count++;
                        }
                    }
                }
                return count;
            }
            finally {
                bitmap.UnlockBits(data);
            }
        }
        finally {
            if (ownsBitmap) {
                bitmap.Dispose();
            }
        }
    }
}
'@
    [AutomationNative]::SetProcessDPIAware() | Out-Null
}

function Get-AutomationForegroundWindowHandle {
    Initialize-AutomationNative
    return [AutomationNative]::GetForegroundWindow().ToInt64()
}

function Get-AutomationWindowRect {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Int64]$WindowHandle
    )

    Initialize-AutomationNative
    $handle = [IntPtr]$WindowHandle
    if (-not [AutomationNative]::IsWindow($handle)) {
        throw "Window handle is not valid: $WindowHandle"
    }

    $rect = New-Object AutomationNative+RECT
    if (-not [AutomationNative]::GetWindowRect($handle, [ref]$rect)) {
        throw "Failed to read window rectangle: $WindowHandle"
    }

    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -le 0 -or $height -le 0) {
        throw "Window rectangle is empty: $WindowHandle"
    }

    [pscustomobject]@{
        Left   = $rect.Left
        Top    = $rect.Top
        Right  = $rect.Right
        Bottom = $rect.Bottom
        Width  = $width
        Height = $height
    }
}

function New-AutomationWindowBitmap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Int64]$WindowHandle
    )

    Add-Type -AssemblyName System.Drawing
    $rect = Get-AutomationWindowRect -WindowHandle $WindowHandle
    $bitmap = New-Object System.Drawing.Bitmap($rect.Width, $rect.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size($rect.Width, $rect.Height)))
        return $bitmap
    }
    catch {
        $bitmap.Dispose()
        throw
    }
    finally {
        $graphics.Dispose()
    }
}

function Get-AutomationBitmapFromPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ImagePath
    )

    Add-Type -AssemblyName System.Drawing
    $source = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $ImagePath).ProviderPath)
    try {
        return (New-Object System.Drawing.Bitmap($source))
    }
    finally {
        $source.Dispose()
    }
}

function Save-AutomationBitmapCrop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Bitmap,
        [Parameter(Mandatory = $true)]$Rect,
        [Parameter(Mandatory = $true)][string]$Path
    )

    Add-Type -AssemblyName System.Drawing
    $x = [Math]::Max(0, [int]$Rect.X)
    $y = [Math]::Max(0, [int]$Rect.Y)
    $right = [Math]::Min($Bitmap.Width, $x + [int]$Rect.Width)
    $bottom = [Math]::Min($Bitmap.Height, $y + [int]$Rect.Height)
    if ($right -le $x -or $bottom -le $y) {
        throw 'Crop rectangle is empty.'
    }

    $rectangle = New-Object System.Drawing.Rectangle($x, $y, ($right - $x), ($bottom - $y))
    $crop = $Bitmap.Clone($rectangle, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $crop.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $crop.Dispose()
    }
}

function Find-AutomationHighlightedCard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Bitmap
    )

    Initialize-AutomationNative
    [AutomationImageTools]::FindHighlightRect($Bitmap)
}

function Test-AutomationNewBadge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Bitmap,
        [Parameter(Mandatory = $true)]$HighlightRect
    )

    Initialize-AutomationNative
    $regionX = [int]($HighlightRect.X + ($HighlightRect.Width * 0.62))
    $regionY = [int]($HighlightRect.Y + ($HighlightRect.Height * 0.45))
    $regionWidth = [int]($HighlightRect.Width * 0.38)
    $regionHeight = [int]($HighlightRect.Height * 0.45)
    $yellowPixels = [AutomationImageTools]::CountYellowPixels($Bitmap, $regionX, $regionY, $regionWidth, $regionHeight)

    [pscustomobject]@{
        Found        = ($yellowPixels -ge 30)
        YellowPixels = $yellowPixels
        RegionX      = $regionX
        RegionY      = $regionY
        RegionWidth  = $regionWidth
        RegionHeight = $regionHeight
    }
}

function Invoke-AutomationWinRtAsync {
    param(
        [Parameter(Mandatory = $true)]$AsyncOperation,
        [Parameter(Mandatory = $true)][type]$ResultType
    )

    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $method = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq 'AsTask' -and
            $_.IsGenericMethodDefinition -and
            $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        } |
        Select-Object -First 1

    if (-not $method) {
        throw 'Could not find WindowsRuntime AsTask helper.'
    }

    $task = $method.MakeGenericMethod($ResultType).Invoke($null, @($AsyncOperation))
    [void]$task.Wait()
    return $task.Result
}

function Invoke-AutomationOcrImagePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ImagePath
    )

    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $null = [Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
        $null = [Windows.Storage.FileAccessMode,Windows.Storage,ContentType=WindowsRuntime]
        $null = [Windows.Storage.Streams.IRandomAccessStream,Windows.Storage.Streams,ContentType=WindowsRuntime]
        $null = [Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
        $null = [Windows.Graphics.Imaging.SoftwareBitmap,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
        $null = [Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime]
        $null = [Windows.Media.Ocr.OcrResult,Windows.Foundation,ContentType=WindowsRuntime]
        $null = [Windows.Globalization.Language,Windows.Foundation,ContentType=WindowsRuntime]

        $engine = $null
        try {
            $language = [Windows.Globalization.Language]::new('zh-Hans')
            $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($language)
        }
        catch {
            $engine = $null
        }
        if (-not $engine) {
            $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
        }
        if (-not $engine) {
            throw 'Windows OCR engine is not available.'
        }

        $resolvedPath = (Resolve-Path -LiteralPath $ImagePath).ProviderPath
        $file = Invoke-AutomationWinRtAsync -AsyncOperation ([Windows.Storage.StorageFile]::GetFileFromPathAsync($resolvedPath)) -ResultType ([Windows.Storage.StorageFile])
        $stream = Invoke-AutomationWinRtAsync -AsyncOperation ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) -ResultType ([Windows.Storage.Streams.IRandomAccessStream])
        try {
            $decoder = Invoke-AutomationWinRtAsync -AsyncOperation ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) -ResultType ([Windows.Graphics.Imaging.BitmapDecoder])
            $softwareBitmap = Invoke-AutomationWinRtAsync -AsyncOperation ($decoder.GetSoftwareBitmapAsync()) -ResultType ([Windows.Graphics.Imaging.SoftwareBitmap])
            $ocrResult = Invoke-AutomationWinRtAsync -AsyncOperation ($engine.RecognizeAsync($softwareBitmap)) -ResultType ([Windows.Media.Ocr.OcrResult])
            return [pscustomobject]@{
                Success = $true
                Text    = [string]$ocrResult.Text
                Error   = $null
            }
        }
        finally {
            if ($stream -and ($stream.PSObject.Methods.Name -contains 'Dispose')) {
                $stream.Dispose()
            }
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Text    = ''
            Error   = $_.Exception.Message
        }
    }
}

function Test-AutomationKeywordMatch {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string[]]$Keywords
    )

    return (Test-AutomationTargetTextMatch -Text $Text -Keywords $Keywords).Match
}

function Test-AutomationTargetTextMatch {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string[]]$Keywords
    )

    $normalizedText = ($Text -replace '\s', '').ToLowerInvariant()
    $missingKeywords = @()
    foreach ($keyword in $Keywords) {
        $normalizedKeyword = (([string]$keyword) -replace '\s', '').ToLowerInvariant()
        if (-not $normalizedText.Contains($normalizedKeyword)) {
            $missingKeywords += [string]$keyword
        }
    }

    if ($missingKeywords.Count -eq 0) {
        return [pscustomobject]@{
            Match    = $true
            Mode     = 'Exact'
            Reason   = 'All target keywords matched.'
            Text     = $Text
            Missing  = @()
        }
    }

    $hasYear = $normalizedText.Contains('1998')
    $hasSubaruFuzzy = ($normalizedText.Contains(([string][char]0x65AF).ToLowerInvariant()) -and $normalizedText.Contains(([string][char]0x5DF4).ToLowerInvariant()))
    if ($hasYear -and $hasSubaruFuzzy) {
        return [pscustomobject]@{
            Match    = $true
            Mode     = 'FuzzySubaru'
            Reason   = 'OCR text contains 1998 and fuzzy Subaru markers.'
            Text     = $Text
            Missing  = @($missingKeywords)
        }
    }

    return [pscustomobject]@{
        Match    = $false
        Mode     = 'None'
        Reason   = "Missing target keywords: $($missingKeywords -join ', ')"
        Text     = $Text
        Missing  = @($missingKeywords)
    }
}

function Test-AutomationSelectedCar {
    [CmdletBinding()]
    param(
        [Int64]$WindowHandle = 0,
        [string]$ImagePath,
        [Parameter(Mandatory = $true)][string[]]$TargetKeywords,
        [string]$NewBadgeText = '',
        [bool]$RequireTargetConfirmation = $true,
        [Parameter(Mandatory = $true)][string]$TempRoot
    )

    $bitmap = $null
    $cropPath = $null
    try {
        if (-not [string]::IsNullOrWhiteSpace($ImagePath)) {
            $bitmap = Get-AutomationBitmapFromPath -ImagePath $ImagePath
        }
        else {
            if ($WindowHandle -eq 0) {
                throw 'Window handle is required when RecognitionImagePath is not provided.'
            }
            $bitmap = New-AutomationWindowBitmap -WindowHandle $WindowHandle
        }

        $highlight = Find-AutomationHighlightedCard -Bitmap $bitmap
        if (-not $highlight.Found) {
            return [pscustomobject]@{
                Match                = $false
                Stop                 = $false
                Reason               = 'Highlighted card was not found.'
                HasNewBadge          = $false
                IsTargetWithoutBadge = $false
                OcrSuccess           = $false
                OcrText              = ''
                MatchMode            = 'NoHighlight'
                Rect                 = $highlight
            }
        }

        $badge = Test-AutomationNewBadge -Bitmap $bitmap -HighlightRect $highlight
        if (-not $badge.Found) {
            $isTargetWithoutBadge = $false
            $noBadgeOcrSuccess = $false
            $noBadgeOcrText = ''
            if ($RequireTargetConfirmation) {
                if (-not (Test-Path -LiteralPath $TempRoot -PathType Container)) {
                    New-Item -Path $TempRoot -ItemType Directory -Force | Out-Null
                }
                $cropPath = Join-Path $TempRoot ("selected-card-{0}.png" -f ([guid]::NewGuid().ToString('N')))
                Save-AutomationBitmapCrop -Bitmap $bitmap -Rect $highlight -Path $cropPath
                $noBadgeOcr = Invoke-AutomationOcrImagePath -ImagePath $cropPath
                $noBadgeOcrSuccess = [bool]$noBadgeOcr.Success
                $noBadgeOcrText = [string]$noBadgeOcr.Text
                if ($noBadgeOcrSuccess) {
                    $noBadgeTextMatch = Test-AutomationTargetTextMatch -Text $noBadgeOcrText -Keywords $TargetKeywords
                    $isTargetWithoutBadge = $noBadgeTextMatch.Match
                    if ($isTargetWithoutBadge -and -not [string]::IsNullOrWhiteSpace($NewBadgeText) -and $noBadgeOcrText -match [regex]::Escape($NewBadgeText)) {
                        return [pscustomobject]@{
                            Match                = $true
                            Stop                 = $false
                            Reason               = "Target new car matched via OCR badge text fallback (color detection missed). BadgeText='$NewBadgeText' OCR='$noBadgeOcrText'"
                            HasNewBadge          = $true
                            IsTargetWithoutBadge = $false
                            OcrSuccess           = $true
                            OcrText              = $noBadgeOcrText
                            MatchMode            = 'OcrBadge'
                            Rect                 = $highlight
                        }
                    }
                }
            }
            return [pscustomobject]@{
                Match                = $false
                Stop                 = $false
                Reason               = "Highlighted card is not marked new. YellowPixels=$($badge.YellowPixels) BadgeRegion=[$($badge.RegionX),$($badge.RegionY),$($badge.RegionWidth),$($badge.RegionHeight)] CardRect=[$($highlight.X),$($highlight.Y),$($highlight.Width),$($highlight.Height)] IsTargetWithoutBadge=$isTargetWithoutBadge OcrText='$noBadgeOcrText'"
                HasNewBadge          = $false
                IsTargetWithoutBadge = $isTargetWithoutBadge
                OcrSuccess           = $noBadgeOcrSuccess
                OcrText              = $noBadgeOcrText
                MatchMode            = 'NoNewBadge'
                Rect                 = $highlight
            }
        }

        $ocrText = ''
        $ocrSuccess = $false
        $ocrError = $null
        if ($RequireTargetConfirmation) {
            if (-not (Test-Path -LiteralPath $TempRoot -PathType Container)) {
                New-Item -Path $TempRoot -ItemType Directory -Force | Out-Null
            }
            $cropPath = Join-Path $TempRoot ("selected-card-{0}.png" -f ([guid]::NewGuid().ToString('N')))
            Save-AutomationBitmapCrop -Bitmap $bitmap -Rect $highlight -Path $cropPath
            $ocr = Invoke-AutomationOcrImagePath -ImagePath $cropPath
            $ocrSuccess = [bool]$ocr.Success
            $ocrText = [string]$ocr.Text
            $ocrError = $ocr.Error

            if (-not $ocrSuccess) {
                return [pscustomobject]@{
                    Match                = $false
                    Stop                 = $false
                    Reason               = "New badge was detected, but OCR failed. Continuing search. Error=$ocrError"
                    HasNewBadge          = $true
                    IsTargetWithoutBadge = $false
                    OcrSuccess           = $false
                    OcrText              = ''
                    MatchMode            = 'OcrFailed'
                    Rect                 = $highlight
                }
            }

            $matchResult = Test-AutomationTargetTextMatch -Text $ocrText -Keywords $TargetKeywords
            if (-not $matchResult.Match) {
                return [pscustomobject]@{
                    Match                = $false
                    Stop                 = $false
                    Reason               = "New badge was detected, but OCR text did not match target. Continuing search. MatchMode=$($matchResult.Mode) OCR='$ocrText'"
                    HasNewBadge          = $true
                    IsTargetWithoutBadge = $false
                    OcrSuccess           = $true
                    OcrText              = $ocrText
                    MatchMode            = $matchResult.Mode
                    Rect                 = $highlight
                }
            }
        }

        return [pscustomobject]@{
            Match                = $true
            Stop                 = $false
            Reason               = if ($RequireTargetConfirmation) { "Target new car matched. MatchMode=$($matchResult.Mode)" } else { 'Target new car matched without OCR confirmation.' }
            HasNewBadge          = $true
            IsTargetWithoutBadge = $false
            OcrSuccess           = $ocrSuccess
            OcrText              = $ocrText
            MatchMode            = if ($RequireTargetConfirmation) { $matchResult.Mode } else { 'Skipped' }
            Rect                 = $highlight
        }
    }
    finally {
        if ($bitmap) {
            $bitmap.Dispose()
        }
        if ($cropPath -and (Test-Path -LiteralPath $cropPath -PathType Leaf)) {
            Remove-Item -LiteralPath $cropPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-AutomationKeySteps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)]$Steps,
        [Parameter(Mandatory = $true)][string]$Mode,
        [int]$LoopIndex = 1,
        [int]$KeyTapHoldMilliseconds = 50,
        [ValidateSet('SendKeys', 'SendInputScanCode', 'SendInputVirtualKey')][string]$InputMethod = 'SendKeys',
        [switch]$DryRun
    )

    $stepIndex = 0
    foreach ($step in @($Steps)) {
        $stepIndex++
        $sendResult = Send-AfkNamedKeyTap -Key $step.Key -HoldMilliseconds $KeyTapHoldMilliseconds -InputMethod $InputMethod -DryRun:$DryRun
        Write-AutomationLog -Paths $Paths -Level 'INFO' -Message "Sent key. Mode=$Mode Loop=$LoopIndex Step=$stepIndex Key=$($step.Key) WaitMs=$($step.WaitMilliseconds) InputMethod=$($sendResult.Method) Extended=$($sendResult.ExtendedKey) DownResult=$($sendResult.DownResult) UpResult=$($sendResult.UpResult) DryRun=$DryRun"
        if ($step.WaitMilliseconds -gt 0) {
            Start-Sleep -Milliseconds $step.WaitMilliseconds
        }
    }
}
