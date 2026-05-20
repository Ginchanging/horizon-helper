[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version
)

$ErrorActionPreference = 'Stop'
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
$distRoot = Join-Path $scriptRoot 'dist'
$stagingRoot = Join-Path $distRoot '_package'
$packageName = "gamesave-guardian-v$Version.zip"
$packagePath = Join-Path $distRoot $packageName

function Remove-DirectoryInside {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$AllowedRoot
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $resolvedRoot = [System.IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\')
    if (-not $resolvedPath.StartsWith($resolvedRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove path outside allowed root: $resolvedPath"
    }

    if (Test-Path -LiteralPath $resolvedPath) {
        Remove-Item -LiteralPath $resolvedPath -Recurse -Force
    }
}

if (-not (Test-Path -LiteralPath $distRoot -PathType Container)) {
    New-Item -Path $distRoot -ItemType Directory -Force | Out-Null
}

Remove-DirectoryInside -Path $stagingRoot -AllowedRoot $distRoot
New-Item -Path $stagingRoot -ItemType Directory -Force | Out-Null
New-Item -Path (Join-Path $stagingRoot 'scripts') -ItemType Directory -Force | Out-Null

$rootFiles = @(
    'GameSaveGuardian.cmd',
    'GameSaveGuardian.ps1',
    'BackupNow.cmd',
    'BackupNow.ps1',
    'StartBackup.cmd',
    'StartBackup.ps1',
    'StopBackup.cmd',
    'StopBackup.ps1',
    'StatusBackup.cmd',
    'StatusBackup.ps1',
    'StartFocusLock.cmd',
    'StartFocusLock.ps1',
    'StopFocusLock.cmd',
    'StopFocusLock.ps1',
    'StatusFocusLock.cmd',
    'StatusFocusLock.ps1',
    'config.json',
    'README.md',
    'README.zh-CN.md'
)

$scriptFiles = @(
    'BackupLib.ps1',
    'FocusLib.ps1',
    'KeepWindowFocused.ps1',
    'WatchBackup.ps1'
)

foreach ($file in $rootFiles) {
    $source = Join-Path $scriptRoot $file
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required release file is missing: $file"
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $stagingRoot $file) -Force
}

foreach ($file in $scriptFiles) {
    $source = Join-Path (Join-Path $scriptRoot 'scripts') $file
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required release script is missing: scripts\$file"
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path (Join-Path $stagingRoot 'scripts') $file) -Force
}

if (Test-Path -LiteralPath $packagePath -PathType Leaf) {
    Remove-Item -LiteralPath $packagePath -Force
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $stagingRoot,
    $packagePath,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
)

Remove-DirectoryInside -Path $stagingRoot -AllowedRoot $distRoot

Write-Host "Created release package: $packagePath"
