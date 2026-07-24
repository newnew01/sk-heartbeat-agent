param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]{1,128}$')]
    [String]$DeviceId,

    [ValidatePattern('^https://')]
    [String]$ApiUrl = 'https://heartbeat.184184184.xyz/api/v1/heartbeat',

    [Switch]$NoRestart
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDirectory 'LegacyCommon.ps1')

if (-not (Test-LegacyAdministrator)) {
    throw 'Run this script from PowerShell as Administrator.'
}

$secureKey = Read-Host 'Paste Device Key' -AsSecureString
$bstr = [IntPtr]::Zero
$plainKey = $null
try {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    Set-LegacyConfiguration $ApiUrl $DeviceId $plainKey

    $dataDirectory = Get-LegacyDataDirectory
    & icacls.exe $dataDirectory /inheritance:r | Out-Null
    & icacls.exe $dataDirectory /grant:r `
        '*S-1-5-18:(OI)(CI)F' `
        '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to secure the configuration directory.'
    }
}
finally {
    if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    $plainKey = $null
    if ($null -ne $secureKey) {
        $secureKey.Dispose()
    }
}

if (-not $NoRestart) {
    & schtasks.exe /Query /TN 'BranchHeartbeatLegacy' 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        & schtasks.exe /Run /TN 'BranchHeartbeatLegacy' | Out-Null
    }
}

Write-Host 'Legacy Agent configuration saved securely.' -ForegroundColor Green
