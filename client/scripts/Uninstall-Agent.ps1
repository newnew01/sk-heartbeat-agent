[CmdletBinding()]
param(
    [switch]$RemoveConfiguration
)

$ErrorActionPreference = 'Stop'
$serviceName = 'BranchHeartbeatAgent'
$installDirectory = Join-Path $env:ProgramFiles 'BranchHeartbeat'
$dataDirectory = Join-Path $env:ProgramData 'BranchHeartbeat'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from PowerShell as Administrator.'
}

$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
    if ($service.Status -ne 'Stopped') {
        Stop-Service -Name $serviceName -Force
        $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
    }
    & sc.exe delete $serviceName | Out-Null
}

if (Test-Path -LiteralPath $installDirectory) {
    Remove-Item -LiteralPath $installDirectory -Recurse -Force
}

if ($RemoveConfiguration -and (Test-Path -LiteralPath $dataDirectory)) {
    Remove-Item -LiteralPath $dataDirectory -Recurse -Force
}

Write-Host 'Branch Heartbeat Agent uninstalled.' -ForegroundColor Green
