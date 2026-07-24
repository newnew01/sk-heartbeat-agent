param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]{1,128}$')]
    [String]$DeviceId,

    [ValidatePattern('^https://')]
    [String]$ApiUrl = 'https://heartbeat.184184184.xyz/api/v1/heartbeat',

    [String]$DeviceKey,

    [Switch]$NoRestart
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDirectory 'LegacyCommon.ps1')

if (-not (Test-LegacyAdministrator)) {
    throw 'Run this script from PowerShell as Administrator.'
}

$secureKey = $null
$bstr = [IntPtr]::Zero
$plainKey = $null
try {
    if ([String]::IsNullOrEmpty($DeviceKey)) {
        $secureKey = Read-Host 'Paste Device Key' -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
        $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    else {
        Write-Warning (
            'Device Key supplied on the command line may remain in shell history ' +
            'and may be visible to other administrators.'
        )
        $plainKey = $DeviceKey
    }
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
    $DeviceKey = $null
    if ($null -ne $secureKey) {
        $secureKey.Clear()
    }
}

if (-not $NoRestart) {
    & schtasks.exe /Query /TN 'BranchHeartbeatLegacy' 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        & schtasks.exe /Run /TN 'BranchHeartbeatLegacy' | Out-Null
    }
}

Write-Host 'Legacy Agent configuration saved securely.' -ForegroundColor Green
