[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]{1,128}$')]
    [string]$DeviceId,

    [ValidatePattern('^https://')]
    [string]$ApiUrl = 'https://heartbeat.184184184.xyz/api/v1/heartbeat'
)

$ErrorActionPreference = 'Stop'
$serviceName = 'BranchHeartbeatAgent'
$executable = Join-Path $env:ProgramFiles 'BranchHeartbeat\BranchHeartbeat.Agent.exe'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from PowerShell as Administrator.'
}

if (-not (Test-Path -LiteralPath $executable)) {
    throw 'Branch Heartbeat Agent is not installed.'
}

$deviceKey = Read-Host 'Paste new Device Key' -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($deviceKey)
try {
    $plainDeviceKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    Stop-Service -Name $serviceName -Force
    $plainDeviceKey | & $executable configure `
        --device-id $DeviceId `
        --api-url $ApiUrl `
        --interval-seconds 60 `
        --retry-seconds 15 `
        --timeout-seconds 15 `
        --key-stdin
    if ($LASTEXITCODE -ne 0) {
        throw "Agent configuration failed with exit code $LASTEXITCODE."
    }
    Start-Service -Name $serviceName
    Write-Host 'Configuration updated and service restarted.' -ForegroundColor Green
}
finally {
    if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    $plainDeviceKey = $null
    $deviceKey.Dispose()
}
