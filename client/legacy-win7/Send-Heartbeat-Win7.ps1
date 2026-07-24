Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDirectory 'LegacyCommon.ps1')

$client = $null
$deviceKey = $null
$lastSuccessAt = Get-LegacyStatusValue 'lastSuccessAt'
$observedIp = Get-LegacyStatusValue 'observedIp'
$allowedUntil = Get-LegacyStatusValue 'allowedUntil'

try {
    $configuration = Get-LegacyConfiguration
    $deviceKey = Unprotect-LegacyDeviceKey $configuration['ProtectedDeviceKey']

    $client = New-Object -ComObject WinHttp.WinHttpRequest.5.1
    $client.SetTimeouts(5000, 5000, 5000, 15000)
    $client.Open('POST', $configuration['ApiUrl'], $false)
    $client.SetRequestHeader('Authorization', 'Bearer ' + $deviceKey)
    $client.SetRequestHeader('X-Device-ID', $configuration['DeviceId'])
    $client.SetRequestHeader('User-Agent', 'BranchHeartbeat-Legacy-Win7/1.0')
    $client.Send()
    if ([Int32]$client.Status -ne 200) {
        throw ('Heartbeat API returned HTTP ' + [Int32]$client.Status + '.')
    }
    $body = [String]$client.ResponseText

    $ipMatch = [Regex]::Match($body, '"observedIp"\s*:\s*"([^"]+)"')
    $expiryMatch = [Regex]::Match($body, '"allowedUntil"\s*:\s*"([^"]+)"')
    if (-not $ipMatch.Success -or -not $expiryMatch.Success) {
        throw 'Heartbeat API response is invalid.'
    }

    $lastSuccessAt = [DateTime]::UtcNow.ToString('o')
    $observedIp = $ipMatch.Groups[1].Value
    $allowedUntil = $expiryMatch.Groups[1].Value
    Write-LegacyStatus 'healthy' $lastSuccessAt $observedIp $allowedUntil $null
    exit 0
}
catch {
    $message = $_.Exception.Message
    Write-LegacyStatus 'error' $lastSuccessAt $observedIp $allowedUntil $message
    exit 1
}
finally {
    $client = $null
    $deviceKey = $null
}
