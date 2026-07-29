# Registers a Scheduled Task that runs Invoke-ExternalWatchdog.ps1 every
# 5 minutes as SYSTEM. This is intentionally independent of the agent
# process (separate Task Scheduler engine, separate thread/logging stack)
# so it can recover the service even if the agent's in-process watchdog
# is itself stuck.
[CmdletBinding()]
param(
    [int]$IntervalMinutes = 5
)

$ErrorActionPreference = 'Stop'
$taskName = 'BranchHeartbeatExternalWatchdog'
$installDirectory = Join-Path $env:ProgramFiles 'BranchHeartbeat'
$scriptPath = Join-Path $installDirectory 'Invoke-ExternalWatchdog.ps1'
$sourceScript = Join-Path $PSScriptRoot 'Invoke-ExternalWatchdog.ps1'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from PowerShell as Administrator.'
}

if (-not (Test-Path -LiteralPath $installDirectory)) {
    throw "Agent is not installed at $installDirectory. Run Install-Agent.ps1 first."
}

Copy-Item -LiteralPath $sourceScript -Destination $scriptPath -Force

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
    -RepetitionDuration ([TimeSpan]::MaxValue)
$principalTask = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2)

Register-ScheduledTask -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principalTask `
    -Settings $settings `
    -Force | Out-Null

Write-Host "Registered scheduled task '$taskName' (every $IntervalMinutes minutes)." -ForegroundColor Green
Write-Host "Log: $env:ProgramData\BranchHeartbeat\external-watchdog.log"
