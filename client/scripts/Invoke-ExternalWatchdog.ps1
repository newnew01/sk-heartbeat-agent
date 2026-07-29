# Runs as a scheduled task, completely outside the agent's own process,
# threads, and logging stack. Its only job is to notice a stale
# status.json or a stopped service and restart the service - a backstop
# for the case where the agent's own in-process HeartbeatWatchdog is
# itself stuck (e.g. hung inside the same logging call it's trying to
# recover from).
$ErrorActionPreference = 'Stop'

$serviceName = 'BranchHeartbeatAgent'
$dataDirectory = Join-Path $env:ProgramData 'BranchHeartbeat'
$statusFile = Join-Path $dataDirectory 'status.json'
$logFile = Join-Path $dataDirectory 'external-watchdog.log'
$staleThreshold = [TimeSpan]::FromMinutes(8)

function Write-WatchdogLog {
    param([string]$Message)
    $line = "{0:yyyy-MM-dd HH:mm:ss}Z  $Message" -f (Get-Date).ToUniversalTime()
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    if ((Test-Path -LiteralPath $logFile) -and
        (Get-Item -LiteralPath $logFile).Length -gt 1MB) {
        $tail = Get-Content -LiteralPath $logFile -Tail 500
        Set-Content -LiteralPath $logFile -Value $tail -Encoding UTF8
    }
}

$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-WatchdogLog "Service $serviceName is not installed. Nothing to do."
    return
}

if ($service.Status -ne 'Running') {
    Write-WatchdogLog "Service $serviceName is $($service.Status), not Running. Starting it."
    Start-Service -Name $serviceName
    return
}

if (-not (Test-Path -LiteralPath $statusFile)) {
    Write-WatchdogLog "Service is Running but $statusFile does not exist yet. Skipping (may still be starting up)."
    return
}

try {
    $status = Get-Content -LiteralPath $statusFile -Raw | ConvertFrom-Json
}
catch {
    Write-WatchdogLog "Unable to parse $statusFile ($($_.Exception.Message)). Restarting service."
    Restart-Service -Name $serviceName -Force
    return
}

$updatedAt = [DateTimeOffset]::Parse($status.updatedAt)
$staleness = [DateTimeOffset]::UtcNow - $updatedAt

if ($staleness -gt $staleThreshold) {
    Write-WatchdogLog (
        "status.json has not updated for {0:0}s (threshold {1:0}s); " +
        "the agent appears hung. Restarting $serviceName." -f
        $staleness.TotalSeconds, $staleThreshold.TotalSeconds
    )
    Restart-Service -Name $serviceName -Force
}
