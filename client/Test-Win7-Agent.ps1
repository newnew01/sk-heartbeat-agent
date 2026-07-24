$ErrorActionPreference = 'Stop'

$legacyDirectory = Join-Path $PSScriptRoot 'legacy-win7'
$runtimeScripts = @(
    'LegacyCommon.ps1',
    'Send-Heartbeat-Win7.ps1',
    'Configure-Agent-Win7.ps1',
    'Get-AgentStatus-Win7.ps1',
    'Enable-Tls12-Win7.ps1',
    'Install-Agent-Win7.ps1',
    'Uninstall-Agent-Win7.ps1'
)

foreach ($fileName in $runtimeScripts) {
    $path = Join-Path $legacyDirectory $fileName
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile(
        $path,
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null
    if ($errors.Count -gt 0) {
        throw "$fileName has PowerShell syntax errors: $($errors[0].Message)"
    }

    $source = [IO.File]::ReadAllText($path)
    $unsupportedPatterns = @(
        '\$PSScriptRoot',
        '\[ordered\]',
        'ConvertTo-Json',
        'ConvertFrom-Json',
        'Invoke-RestMethod',
        'Invoke-WebRequest',
        '::new\(',
        '\.Dispose\(',
        'ForEach-Object\s+-Parallel',
        '\?\?'
    )
    foreach ($pattern in $unsupportedPatterns) {
        if ($source -match $pattern) {
            throw "$fileName contains a PowerShell 3+ construct: $pattern"
        }
    }
}
Write-Host 'PASS PowerShell 2 compatibility scan'

$installSource = [IO.File]::ReadAllText(
    (Join-Path $legacyDirectory 'Install-Agent-Win7.ps1')
)
$configureSource = [IO.File]::ReadAllText(
    (Join-Path $legacyDirectory 'Configure-Agent-Win7.ps1')
)
if (
    $installSource -notmatch '\[String\]\$DeviceKey' -or
    $configureSource -notmatch '\[String\]\$DeviceKey'
) {
    throw 'Inline Device Key parameter is missing from install/configure scripts.'
}
Write-Host 'PASS optional inline Device Key support'

if (
    $installSource -notmatch 'RunHeartbeat\.cmd' -or
    $installSource -notmatch '/TR \$taskRunnerPath' -or
    $installSource -match '/TR \$taskAction'
) {
    throw 'Scheduled Task must use the argument-free compatibility runner.'
}
Write-Host 'PASS Windows 7 schtasks compatibility runner'

$workerSource = [IO.File]::ReadAllText(
    (Join-Path $legacyDirectory 'Send-Heartbeat-Win7.ps1')
)
if (
    $workerSource -notmatch 'WinHttp\.WinHttpRequest\.5\.1' -or
    $workerSource -match 'ServicePointManager|HttpWebRequest'
) {
    throw 'Heartbeat worker must use WinHTTP without the legacy .NET TLS stack.'
}
if ($installSource -notmatch 'Test-LegacyHttpsEndpoint') {
    throw 'Installer must perform the TLS 1.2 preflight.'
}
Write-Host 'PASS WinHTTP transport and TLS preflight'

$tlsHelperSource = [IO.File]::ReadAllText(
    (Join-Path $legacyDirectory 'Enable-Tls12-Win7.ps1')
)
if (
    $tlsHelperSource -match '\.FileVersion\s*\)' -or
    $tlsHelperSource -notmatch 'FileMajorPart' -or
    $tlsHelperSource -notmatch 'FilePrivatePart'
) {
    throw 'TLS helper must parse numeric file version parts on Windows 7.'
}
Write-Host 'PASS Windows 7 WinHTTP version parsing'

$commonSource = [IO.File]::ReadAllText(
    (Join-Path $legacyDirectory 'LegacyCommon.ps1')
)
if (
    $tlsHelperSource -match '&\s+reg\.exe\s+export' -or
    $tlsHelperSource -match '&\s+reg\.exe\s+add' -or
    $tlsHelperSource -notmatch 'Export-LegacyRegistryKeyIfPresent' -or
    $tlsHelperSource -notmatch 'Set-LegacyRegistryDword' -or
    $commonSource -notmatch 'Test-Path\s+-LiteralPath'
) {
    throw 'TLS helper must safely handle registry keys that do not exist.'
}
Write-Host 'PASS guarded TLS registry operations'

$testDirectory = Join-Path $env:TEMP (
    'branch-heartbeat-win7-test-' + [Guid]::NewGuid().ToString('N')
)
$previousDirectory = $env:BRANCH_HEARTBEAT_LEGACY_DATA_DIR
try {
    $env:BRANCH_HEARTBEAT_LEGACY_DATA_DIR = $testDirectory
    [IO.Directory]::CreateDirectory($testDirectory) | Out-Null
    . (Join-Path $legacyDirectory 'LegacyCommon.ps1')

    $registryTestName = (
        'HKCU\Software\BranchHeartbeatAgentTests\' +
        [Guid]::NewGuid().ToString('N')
    )
    $registryProviderPath = (
        ConvertTo-LegacyRegistryProviderPath $registryTestName
    )
    $registryBackupPath = Join-Path $testDirectory 'registry-test.reg'
    try {
        if (
            Export-LegacyRegistryKeyIfPresent `
                $registryTestName `
                $registryBackupPath
        ) {
            throw 'A nonexistent registry key was reported as present.'
        }
        Set-LegacyRegistryDword $registryTestName 'TestValue' 2048
        $registryValue = Get-LegacyRegistryDword `
            $registryTestName `
            'TestValue'
        if ([Int32]$registryValue -ne 2048) {
            throw 'Registry DWORD write failed.'
        }
        if (
            -not (
                Export-LegacyRegistryKeyIfPresent `
                    $registryTestName `
                    $registryBackupPath
            )
        ) {
            throw 'An existing registry key was reported as absent.'
        }
        if (-not [IO.File]::Exists($registryBackupPath)) {
            throw 'Registry backup file was not created.'
        }
        Write-Host 'PASS missing/existing registry key integration test'
    }
    finally {
        if (Test-Path -LiteralPath $registryProviderPath) {
            Remove-Item -LiteralPath $registryProviderPath -Recurse -Force
        }
    }

    $missingTaskName = (
        'BranchHeartbeatLegacy-Test-' + [Guid]::NewGuid().ToString('N')
    )
    if (Test-LegacyScheduledTask $missingTaskName) {
        throw 'A nonexistent Scheduled Task was reported as present.'
    }
    Write-Host 'PASS missing Scheduled Task integration test'

    $testKey = 'legacy-secret-that-must-not-appear-on-disk'
    Set-LegacyConfiguration `
        'https://heartbeat.example.test/api/v1/heartbeat' `
        'legacy-device-01' `
        $testKey
    $configuration = Get-LegacyConfiguration
    $decrypted = Unprotect-LegacyDeviceKey `
        $configuration['ProtectedDeviceKey']

    if ($configuration['DeviceId'] -ne 'legacy-device-01') {
        throw 'Device ID configuration round-trip failed.'
    }
    if ($decrypted -ne $testKey) {
        throw 'DPAPI Device Key round-trip failed.'
    }
    $onDisk = [IO.File]::ReadAllText((Get-LegacyConfigPath))
    if ($onDisk.Contains($testKey)) {
        throw 'Plaintext Device Key was written to disk.'
    }

    Write-LegacyStatus `
        'healthy' `
        '2026-07-24T10:00:00.0000000Z' `
        '203.0.113.7' `
        '2026-07-24T10:10:00+00:00' `
        $null
    $status = [IO.File]::ReadAllText((Get-LegacyStatusPath))
    if ($status -notmatch '"state": "healthy"') {
        throw 'Status write failed.'
    }
    Write-Host 'PASS DPAPI configuration and status round-trip'
}
finally {
    $env:BRANCH_HEARTBEAT_LEGACY_DATA_DIR = $previousDirectory
    if ([IO.Directory]::Exists($testDirectory)) {
        Remove-Item -LiteralPath $testDirectory -Recurse -Force
    }
}

Write-Host 'All Windows 7 Legacy Agent tests passed.'
