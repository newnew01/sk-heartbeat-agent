[CmdletBinding()]
param(
    [string]$Version = '1.0.0'
)

$ErrorActionPreference = 'Stop'
$clientRoot = $PSScriptRoot
$project = Join-Path $clientRoot 'BranchHeartbeat.Agent\BranchHeartbeat.Agent.csproj'
$testProject = Join-Path $clientRoot 'BranchHeartbeat.Agent.Tests\BranchHeartbeat.Agent.Tests.csproj'
$publishDirectory = Join-Path $clientRoot 'artifacts\publish'
$packageDirectory = Join-Path $clientRoot 'artifacts\package'
$zipPath = Join-Path $clientRoot "artifacts\BranchHeartbeat-Agent-$Version-win-x64.zip"

dotnet run --project $testProject -c Release
if ($LASTEXITCODE -ne 0) {
    throw 'Agent tests failed.'
}
& (Join-Path $clientRoot 'Test-ModernInstaller.ps1')

if (Test-Path -LiteralPath $publishDirectory) {
    Remove-Item -LiteralPath $publishDirectory -Recurse -Force
}
if (Test-Path -LiteralPath $packageDirectory) {
    Remove-Item -LiteralPath $packageDirectory -Recurse -Force
}

dotnet publish $project `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -p:Version=$Version `
    -p:PublishSingleFile=true `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -o $publishDirectory
if ($LASTEXITCODE -ne 0) {
    throw 'Agent publish failed.'
}

New-Item -ItemType Directory -Path $packageDirectory -Force | Out-Null
Copy-Item `
    -LiteralPath (Join-Path $publishDirectory 'BranchHeartbeat.Agent.exe') `
    -Destination $packageDirectory
Copy-Item -Path (Join-Path $clientRoot 'scripts\*.ps1') -Destination $packageDirectory
Copy-Item -LiteralPath (Join-Path $clientRoot 'PACKAGE-README.md') `
    -Destination (Join-Path $packageDirectory 'README.md')

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $packageDirectory '*') -DestinationPath $zipPath
Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath
