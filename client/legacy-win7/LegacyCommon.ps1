Set-StrictMode -Version 2.0

function Get-LegacyDataDirectory {
    if (-not [String]::IsNullOrEmpty($env:BRANCH_HEARTBEAT_LEGACY_DATA_DIR)) {
        return $env:BRANCH_HEARTBEAT_LEGACY_DATA_DIR
    }
    return (Join-Path $env:ProgramData 'BranchHeartbeatLegacy')
}

function Get-LegacyConfigPath {
    return (Join-Path (Get-LegacyDataDirectory) 'agent.conf')
}

function Get-LegacyStatusPath {
    return (Join-Path (Get-LegacyDataDirectory) 'status.json')
}

function Test-LegacyAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Get-LegacyEntropy {
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return $sha256.ComputeHash(
            [Text.Encoding]::UTF8.GetBytes('BranchHeartbeat.Legacy.Win7.v1')
        )
    }
    finally {
        # SHA256Managed on the .NET version bundled with Windows 7 exposes
        # Clear(), but PowerShell 2 cannot call Dispose() on that type.
        $sha256.Clear()
    }
}

function Protect-LegacyDeviceKey {
    param([Parameter(Mandatory = $true)][String]$DeviceKey)

    [Reflection.Assembly]::LoadWithPartialName('System.Security') | Out-Null
    $plainBytes = [Text.Encoding]::UTF8.GetBytes($DeviceKey)
    try {
        $encrypted = [Security.Cryptography.ProtectedData]::Protect(
            $plainBytes,
            (Get-LegacyEntropy),
            [Security.Cryptography.DataProtectionScope]::LocalMachine
        )
        return [Convert]::ToBase64String($encrypted)
    }
    finally {
        [Array]::Clear($plainBytes, 0, $plainBytes.Length)
    }
}

function Unprotect-LegacyDeviceKey {
    param([Parameter(Mandatory = $true)][String]$ProtectedDeviceKey)

    [Reflection.Assembly]::LoadWithPartialName('System.Security') | Out-Null
    $encrypted = [Convert]::FromBase64String($ProtectedDeviceKey)
    $plainBytes = $null
    try {
        $plainBytes = [Security.Cryptography.ProtectedData]::Unprotect(
            $encrypted,
            (Get-LegacyEntropy),
            [Security.Cryptography.DataProtectionScope]::LocalMachine
        )
        return [Text.Encoding]::UTF8.GetString($plainBytes)
    }
    finally {
        if ($null -ne $plainBytes) {
            [Array]::Clear($plainBytes, 0, $plainBytes.Length)
        }
        [Array]::Clear($encrypted, 0, $encrypted.Length)
    }
}

function ConvertTo-LegacyBase64 {
    param([Parameter(Mandatory = $true)][String]$Value)
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

function ConvertFrom-LegacyBase64 {
    param([Parameter(Mandatory = $true)][String]$Value)
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
}

function Set-LegacyConfiguration {
    param(
        [Parameter(Mandatory = $true)][String]$ApiUrl,
        [Parameter(Mandatory = $true)][String]$DeviceId,
        [Parameter(Mandatory = $true)][String]$DeviceKey
    )

    if ($ApiUrl -notmatch '^https://') {
        throw 'API URL must use HTTPS.'
    }
    if ($DeviceId -notmatch '^[A-Za-z0-9._-]{1,128}$') {
        throw 'Device ID contains unsupported characters.'
    }
    if ([String]::IsNullOrEmpty($DeviceKey)) {
        throw 'Device Key is required.'
    }

    $dataDirectory = Get-LegacyDataDirectory
    if (-not [IO.Directory]::Exists($dataDirectory)) {
        [IO.Directory]::CreateDirectory($dataDirectory) | Out-Null
    }

    $lines = @(
        'FormatVersion=1',
        ('ApiUrl=' + (ConvertTo-LegacyBase64 $ApiUrl)),
        ('DeviceId=' + (ConvertTo-LegacyBase64 $DeviceId)),
        ('ProtectedDeviceKey=' + (Protect-LegacyDeviceKey $DeviceKey))
    )
    $configPath = Get-LegacyConfigPath
    $temporaryPath = $configPath + '.tmp'
    [IO.File]::WriteAllLines($temporaryPath, $lines)
    Move-Item -LiteralPath $temporaryPath -Destination $configPath -Force
}

function Get-LegacyConfiguration {
    $configPath = Get-LegacyConfigPath
    if (-not [IO.File]::Exists($configPath)) {
        throw ('Agent is not configured. Missing ' + $configPath)
    }

    $values = @{}
    foreach ($line in [IO.File]::ReadAllLines($configPath)) {
        $separator = $line.IndexOf('=')
        if ($separator -gt 0) {
            $name = $line.Substring(0, $separator)
            $value = $line.Substring($separator + 1)
            $values[$name] = $value
        }
    }
    if (
        -not $values.ContainsKey('ApiUrl') -or
        -not $values.ContainsKey('DeviceId') -or
        -not $values.ContainsKey('ProtectedDeviceKey')
    ) {
        throw 'Agent configuration is invalid.'
    }

    return @{
        ApiUrl = ConvertFrom-LegacyBase64 $values['ApiUrl']
        DeviceId = ConvertFrom-LegacyBase64 $values['DeviceId']
        ProtectedDeviceKey = $values['ProtectedDeviceKey']
    }
}

function ConvertTo-LegacyJsonString {
    param($Value)
    if ($null -eq $Value) {
        return 'null'
    }
    $escaped = [String]$Value
    $escaped = $escaped.Replace('\', '\\')
    $escaped = $escaped.Replace('"', '\"')
    $escaped = $escaped.Replace("`r", '\r')
    $escaped = $escaped.Replace("`n", '\n')
    $escaped = $escaped.Replace("`t", '\t')
    return '"' + $escaped + '"'
}

function Write-LegacyStatus {
    param(
        [Parameter(Mandatory = $true)][String]$State,
        $LastSuccessAt,
        $ObservedIp,
        $AllowedUntil,
        $LastError
    )

    $statusPath = Get-LegacyStatusPath
    $statusDirectory = Split-Path -Parent $statusPath
    if (-not [IO.Directory]::Exists($statusDirectory)) {
        [IO.Directory]::CreateDirectory($statusDirectory) | Out-Null
    }
    $updatedAt = [DateTime]::UtcNow.ToString('o')
    $content = @(
        '{',
        ('  "state": ' + (ConvertTo-LegacyJsonString $State) + ','),
        ('  "updatedAt": ' + (ConvertTo-LegacyJsonString $updatedAt) + ','),
        ('  "lastSuccessAt": ' + (ConvertTo-LegacyJsonString $LastSuccessAt) + ','),
        ('  "observedIp": ' + (ConvertTo-LegacyJsonString $ObservedIp) + ','),
        ('  "allowedUntil": ' + (ConvertTo-LegacyJsonString $AllowedUntil) + ','),
        ('  "lastError": ' + (ConvertTo-LegacyJsonString $LastError)),
        '}'
    )
    $temporaryPath = $statusPath + '.tmp'
    [IO.File]::WriteAllLines($temporaryPath, $content)
    Move-Item -LiteralPath $temporaryPath -Destination $statusPath -Force
}

function Get-LegacyStatusValue {
    param(
        [Parameter(Mandatory = $true)][String]$Name
    )
    $statusPath = Get-LegacyStatusPath
    if (-not [IO.File]::Exists($statusPath)) {
        return $null
    }
    $content = [IO.File]::ReadAllText($statusPath)
    $pattern = '"' + [Regex]::Escape($Name) + '"\s*:\s*(null|"([^"]*)")'
    $match = [Regex]::Match($content, $pattern)
    if (-not $match.Success -or $match.Groups[1].Value -eq 'null') {
        return $null
    }
    return $match.Groups[2].Value
}
