[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]{1,128}$')]
    [string]$DeviceId,

    [ValidatePattern('^https://')]
    [string]$ApiUrl = 'https://heartbeat.184184184.xyz/api/v1/heartbeat',

    [ValidateRange(15, 300)]
    [int]$IntervalSeconds = 60,

    [ValidateRange(5, 300)]
    [int]$RetrySeconds = 15,

    [string]$DeviceKey
)

$ErrorActionPreference = 'Stop'
$serviceName = 'BranchHeartbeatAgent'
$installDirectory = Join-Path $env:ProgramFiles 'BranchHeartbeat'
$dataDirectory = Join-Path $env:ProgramData 'BranchHeartbeat'
$sourceExecutable = Join-Path $PSScriptRoot 'BranchHeartbeat.Agent.exe'
$installedExecutable = Join-Path $installDirectory 'BranchHeartbeat.Agent.exe'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this installer from PowerShell as Administrator.'
}

if (-not (Test-Path -LiteralPath $sourceExecutable)) {
    throw "Missing $sourceExecutable"
}

$secureDeviceKey = $null
$bstr = [IntPtr]::Zero
$plainDeviceKey = $null
try {
    if ([string]::IsNullOrEmpty($DeviceKey)) {
        $secureDeviceKey = Read-Host 'Paste Device Key' -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
            $secureDeviceKey
        )
        $plainDeviceKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
            $bstr
        )
    }
    else {
        Write-Warning (
            'Device Key supplied on the command line may remain in shell ' +
            'history and may be visible to other administrators.'
        )
        $plainDeviceKey = $DeviceKey
    }

    $existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($existingService -and $existingService.Status -ne 'Stopped') {
        Stop-Service -Name $serviceName -Force
        $existingService.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
    }

    New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
    Copy-Item -LiteralPath $sourceExecutable -Destination $installedExecutable -Force

    $plainDeviceKey | & $installedExecutable configure `
        --device-id $DeviceId `
        --api-url $ApiUrl `
        --interval-seconds $IntervalSeconds `
        --retry-seconds $RetrySeconds `
        --timeout-seconds 15 `
        --key-stdin
    if ($LASTEXITCODE -ne 0) {
        throw "Agent configuration failed with exit code $LASTEXITCODE."
    }

    & icacls.exe $dataDirectory /inheritance:r | Out-Null
    & icacls.exe $dataDirectory /grant:r `
        '*S-1-5-18:(OI)(CI)F' `
        '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to secure the configuration directory.'
    }

    if (-not $existingService) {
        New-Service `
            -Name $serviceName `
            -BinaryPathName "`"$installedExecutable`" run" `
            -DisplayName 'Branch Heartbeat Agent' `
            -Description 'Renews the branch public IP lease for MSSQL access.' `
            -StartupType Automatic
    }

    & sc.exe failure $serviceName reset= 86400 actions= restart/15000/restart/30000/restart/60000 | Out-Null
    & sc.exe failureflag $serviceName 1 | Out-Null
    Start-Service -Name $serviceName

    Write-Host ''
    Write-Host 'Branch Heartbeat Agent installed and started.' -ForegroundColor Green
    Write-Host "Device ID: $DeviceId"
    Write-Host "Status: & `"$installedExecutable`" status"
}
finally {
    if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    $plainDeviceKey = $null
    $DeviceKey = $null
    if ($null -ne $secureDeviceKey) {
        $secureDeviceKey.Dispose()
    }
}
