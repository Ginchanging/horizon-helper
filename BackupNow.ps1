[CmdletBinding()]
param(
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $scriptRoot 'config.json'
}

. (Join-Path $scriptRoot 'scripts\BackupLib.ps1')

$config = Get-BackupConfig -ConfigPath $ConfigPath
$result = Invoke-GameSaveBackup -Config $config -Reason 'manual'

if ($result.Success) {
    Write-Host $result.Message
    exit 0
}

Write-Error $result.Message
exit 1
