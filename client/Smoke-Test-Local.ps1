[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$AgentExecutable,

    [Parameter(Mandatory = $true)]
    [string]$DeviceId,

    [Parameter(Mandatory = $true)]
    [string]$DeviceKeyFile,

    [Parameter(Mandatory = $true)]
    [string]$DataDirectory,

    [int]$DeadlineSeconds = 30
)

$ErrorActionPreference = 'Stop'
$AgentExecutable = (Resolve-Path -LiteralPath $AgentExecutable).Path
$DeviceKeyFile = (Resolve-Path -LiteralPath $DeviceKeyFile).Path
if (Test-Path -LiteralPath $DataDirectory) {
    throw "Smoke-test directory already exists: $DataDirectory"
}

New-Item -ItemType Directory -Path $DataDirectory | Out-Null
$deviceKey = (Get-Content -Raw -LiteralPath $DeviceKeyFile).Trim()
$env:BRANCH_HEARTBEAT_DATA_DIR = $DataDirectory
$deviceKey | & $AgentExecutable configure --device-id $DeviceId --key-stdin
if ($LASTEXITCODE -ne 0) {
    throw "Agent configuration failed with exit code $LASTEXITCODE."
}

$job = Start-Job -ScriptBlock {
    param($Executable, $AgentDataDirectory)
    $env:BRANCH_HEARTBEAT_DATA_DIR = $AgentDataDirectory
    & $Executable run
} -ArgumentList $AgentExecutable, $DataDirectory

try {
    $statusPath = Join-Path $DataDirectory 'status.json'
    $deadline = (Get-Date).AddSeconds($DeadlineSeconds)
    do {
        Start-Sleep -Milliseconds 500
        if (Test-Path -LiteralPath $statusPath) {
            $status = Get-Content -Raw -LiteralPath $statusPath | ConvertFrom-Json
            if ($status.state -eq 'healthy') {
                $status | ConvertTo-Json
                exit 0
            }
            if ($status.state -eq 'error') {
                throw "Agent error: $($status.lastError)"
            }
        }
    } while ((Get-Date) -lt $deadline)
    throw "Agent did not become healthy within $DeadlineSeconds seconds."
}
finally {
    Stop-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    $deviceKey = $null
}
