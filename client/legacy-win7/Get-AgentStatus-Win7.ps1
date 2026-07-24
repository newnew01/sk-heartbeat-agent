Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDirectory 'LegacyCommon.ps1')

$statusPath = Get-LegacyStatusPath
if (-not [IO.File]::Exists($statusPath)) {
    Write-Output '{"state":"not-started"}'
    exit 2
}

$content = [IO.File]::ReadAllText($statusPath)
Write-Output $content
if ($content -match '"state"\s*:\s*"healthy"') {
    exit 0
}
exit 1
