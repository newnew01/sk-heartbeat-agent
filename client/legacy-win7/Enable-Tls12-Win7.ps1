Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDirectory 'LegacyCommon.ps1')

if (-not (Test-LegacyAdministrator)) {
    throw 'Run this script from PowerShell as Administrator.'
}

$operatingSystem = Get-WmiObject Win32_OperatingSystem
if (
    $operatingSystem.Version -notmatch '^6\.1\.' -or
    [Int32]$operatingSystem.ServicePackMajorVersion -lt 1
) {
    throw 'This script requires Windows 7 SP1 or Windows Server 2008 R2 SP1.'
}

$winHttpPath = Join-Path $env:SystemRoot 'System32\winhttp.dll'
$winHttpVersion = [Version](
    [Diagnostics.FileVersionInfo]::GetVersionInfo($winHttpPath).FileVersion
)
$minimumVersion = [Version]'6.1.7601.23375'
if ($winHttpVersion -lt $minimumVersion) {
    throw (
        'WinHTTP is too old (' + $winHttpVersion.ToString() + '). Install ' +
        'Windows update KB3140245 or a superseding update, then run this ' +
        'script again.'
    )
}

$dataDirectory = Get-LegacyDataDirectory
if (-not [IO.Directory]::Exists($dataDirectory)) {
    [IO.Directory]::CreateDirectory($dataDirectory) | Out-Null
}
$backupDirectory = Join-Path $dataDirectory (
    'tls-registry-backup-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss')
)
[IO.Directory]::CreateDirectory($backupDirectory) | Out-Null

$registryExports = @(
    @(
        'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp',
        'winhttp-native.reg'
    ),
    @(
        'HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp',
        'winhttp-wow6432.reg'
    ),
    @(
        'HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client',
        'schannel-tls12-client.reg'
    )
)
foreach ($registryExport in $registryExports) {
    & reg.exe export $registryExport[0] `
        (Join-Path $backupDirectory $registryExport[1]) /y 2>$null | Out-Null
}

$winHttpKeys = @(
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp'
)
$is64Bit = (
    -not [String]::IsNullOrEmpty($env:PROCESSOR_ARCHITEW6432) -or
    $env:PROCESSOR_ARCHITECTURE -eq 'AMD64'
)
if ($is64Bit) {
    $winHttpKeys += (
        'HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\' +
        'Internet Settings\WinHttp'
    )
}
foreach ($winHttpKey in $winHttpKeys) {
    & reg.exe add $winHttpKey /v DefaultSecureProtocols /t REG_DWORD `
        /d 2048 /f | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw ('Unable to update ' + $winHttpKey)
    }
}

$schannelKey = (
    'HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\' +
    'Protocols\TLS 1.2\Client'
)
& reg.exe add $schannelKey /v DisabledByDefault /t REG_DWORD /d 0 /f |
    Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to enable the TLS 1.2 Schannel client.'
}
& reg.exe add $schannelKey /v Enabled /t REG_DWORD /d 1 /f | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to enable the TLS 1.2 Schannel client.'
}

Write-Host ''
Write-Host 'TLS 1.2 settings were applied.' -ForegroundColor Green
Write-Host ('Registry backup: ' + $backupDirectory)
Write-Host 'Restart Windows before installing or testing the agent.'
