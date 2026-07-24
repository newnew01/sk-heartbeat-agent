param(
    [String]$Version = '1.0.0'
)

$ErrorActionPreference = 'Stop'
$clientDirectory = $PSScriptRoot
$legacyDirectory = Join-Path $clientDirectory 'legacy-win7'
$artifactsDirectory = Join-Path $clientDirectory 'artifacts'
$packageName = 'BranchHeartbeat-Agent-Win7-' + $Version
$stageDirectory = Join-Path $artifactsDirectory $packageName
$archivePath = Join-Path $artifactsDirectory ($packageName + '.zip')

& (Join-Path $clientDirectory 'Test-Win7-Agent.ps1')

if ([IO.Directory]::Exists($stageDirectory)) {
    Remove-Item -LiteralPath $stageDirectory -Recurse -Force
}
if ([IO.File]::Exists($archivePath)) {
    Remove-Item -LiteralPath $archivePath -Force
}
[IO.Directory]::CreateDirectory($stageDirectory) | Out-Null

$packageFiles = @(
    'LegacyCommon.ps1',
    'Send-Heartbeat-Win7.ps1',
    'Configure-Agent-Win7.ps1',
    'Get-AgentStatus-Win7.ps1',
    'Enable-Tls12-Win7.ps1',
    'Install-Agent-Win7.ps1',
    'Uninstall-Agent-Win7.ps1',
    'README.md'
)
foreach ($fileName in $packageFiles) {
    Copy-Item -LiteralPath (Join-Path $legacyDirectory $fileName) `
        -Destination (Join-Path $stageDirectory $fileName)
}

Compress-Archive -Path (Join-Path $stageDirectory '*') `
    -DestinationPath $archivePath -CompressionLevel Optimal

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath
Write-Host ('Created ' + $archivePath)
Write-Host ('SHA-256 ' + $hash.Hash)
