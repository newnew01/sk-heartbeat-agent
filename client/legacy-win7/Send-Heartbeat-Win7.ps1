Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDirectory 'LegacyCommon.ps1')

$response = $null
$reader = $null
$deviceKey = $null
$lastSuccessAt = Get-LegacyStatusValue 'lastSuccessAt'
$observedIp = Get-LegacyStatusValue 'observedIp'
$allowedUntil = Get-LegacyStatusValue 'allowedUntil'

try {
    $configuration = Get-LegacyConfiguration
    $deviceKey = Unprotect-LegacyDeviceKey $configuration['ProtectedDeviceKey']

    # TLS 1.2 numeric value keeps this script compatible with PowerShell 2.
    [Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject(
        [Net.SecurityProtocolType],
        3072
    )

    $request = [Net.HttpWebRequest]::Create($configuration['ApiUrl'])
    $request.Method = 'POST'
    $request.Timeout = 15000
    $request.ReadWriteTimeout = 15000
    $request.KeepAlive = $false
    $request.ContentLength = 0
    $request.UserAgent = 'BranchHeartbeat-Legacy-Win7/1.0'
    $request.Headers.Add('Authorization', 'Bearer ' + $deviceKey)
    $request.Headers.Add('X-Device-ID', $configuration['DeviceId'])

    $response = $request.GetResponse()
    if ([Int32]$response.StatusCode -ne 200) {
        throw ('Heartbeat API returned HTTP ' + [Int32]$response.StatusCode + '.')
    }
    $reader = New-Object IO.StreamReader -ArgumentList $response.GetResponseStream()
    $body = $reader.ReadToEnd()

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
    if ($_.Exception -is [Net.WebException] -and $null -ne $_.Exception.Response) {
        try {
            $message = 'Heartbeat API returned HTTP ' +
                [Int32]$_.Exception.Response.StatusCode + '.'
        }
        catch {
            $message = $_.Exception.Message
        }
    }
    Write-LegacyStatus 'error' $lastSuccessAt $observedIp $allowedUntil $message
    exit 1
}
finally {
    if ($null -ne $reader) {
        $reader.Close()
    }
    if ($null -ne $response) {
        $response.Close()
    }
    $deviceKey = $null
}
