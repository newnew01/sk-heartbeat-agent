param(
    [Switch]$RemoveConfiguration
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDirectory 'LegacyCommon.ps1')

if (-not (Test-LegacyAdministrator)) {
    throw 'Run this script from PowerShell as Administrator.'
}

if (Test-LegacyScheduledTask 'BranchHeartbeatLegacy') {
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & schtasks.exe /End /TN 'BranchHeartbeatLegacy' 2>&1 | Out-Null
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    & schtasks.exe /Delete /TN 'BranchHeartbeatLegacy' /F | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to delete the BranchHeartbeatLegacy scheduled task.'
    }
}

$taskRunnerPath = Join-Path (Get-LegacyDataDirectory) 'RunHeartbeat.cmd'
if ([IO.File]::Exists($taskRunnerPath)) {
    Remove-Item -LiteralPath $taskRunnerPath -Force
}

$installDirectory = Join-Path $env:ProgramFiles 'BranchHeartbeatLegacy'
if ([IO.Directory]::Exists($installDirectory)) {
    Remove-Item -LiteralPath $installDirectory -Recurse -Force
}

if ($RemoveConfiguration) {
    $dataDirectory = Get-LegacyDataDirectory
    if ([IO.Directory]::Exists($dataDirectory)) {
        Remove-Item -LiteralPath $dataDirectory -Recurse -Force
    }
}

Write-Host 'Branch Heartbeat Legacy Agent removed.' -ForegroundColor Green
