param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]{1,128}$')]
    [String]$DeviceId,

    [ValidatePattern('^https://')]
    [String]$ApiUrl = 'https://heartbeat.184184184.xyz/api/v1/heartbeat'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$sourceDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $sourceDirectory 'LegacyCommon.ps1')

if (-not (Test-LegacyAdministrator)) {
    throw 'Run this installer from PowerShell as Administrator.'
}

$operatingSystem = Get-WmiObject Win32_OperatingSystem
if (
    $operatingSystem.Version -notmatch '^6\.1\.' -or
    [Int32]$operatingSystem.ServicePackMajorVersion -lt 1
) {
    throw 'This package requires Windows 7 SP1 or Windows Server 2008 R2 SP1.'
}

$requiredFiles = @(
    'LegacyCommon.ps1',
    'Send-Heartbeat-Win7.ps1',
    'Configure-Agent-Win7.ps1',
    'Get-AgentStatus-Win7.ps1',
    'Uninstall-Agent-Win7.ps1'
)
foreach ($fileName in $requiredFiles) {
    $sourcePath = Join-Path $sourceDirectory $fileName
    if (-not [IO.File]::Exists($sourcePath)) {
        throw ('Missing ' + $sourcePath)
    }
}

$installDirectory = Join-Path $env:ProgramFiles 'BranchHeartbeatLegacy'
if (-not [IO.Directory]::Exists($installDirectory)) {
    [IO.Directory]::CreateDirectory($installDirectory) | Out-Null
}
foreach ($fileName in $requiredFiles) {
    Copy-Item -LiteralPath (Join-Path $sourceDirectory $fileName) `
        -Destination (Join-Path $installDirectory $fileName) -Force
}

& (Join-Path $installDirectory 'Configure-Agent-Win7.ps1') `
    -DeviceId $DeviceId -ApiUrl $ApiUrl -NoRestart

$powershellPath = Join-Path $env:SystemRoot `
    'System32\WindowsPowerShell\v1.0\powershell.exe'
$workerPath = Join-Path $installDirectory 'Send-Heartbeat-Win7.ps1'
$taskAction = '"' + $powershellPath +
    '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
    $workerPath + '"'

& schtasks.exe /Create /TN 'BranchHeartbeatLegacy' /TR $taskAction `
    /SC MINUTE /MO 1 /RU SYSTEM /F | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to create the BranchHeartbeatLegacy scheduled task.'
}

& schtasks.exe /Run /TN 'BranchHeartbeatLegacy' | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Legacy Agent was installed, but its first run could not be started.'
}

Write-Host ''
Write-Host 'Branch Heartbeat Legacy Agent installed.' -ForegroundColor Green
Write-Host ('Device ID: ' + $DeviceId)
Write-Host 'Schedule: every 1 minute as SYSTEM'
Write-Host (
    'Status: powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' +
    (Join-Path $installDirectory 'Get-AgentStatus-Win7.ps1') + '"'
)
