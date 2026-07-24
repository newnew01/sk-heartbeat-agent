$ErrorActionPreference = 'Stop'

$legacyDirectory = Join-Path $PSScriptRoot 'legacy-win7'
$runtimeScripts = @(
    'LegacyCommon.ps1',
    'Send-Heartbeat-Win7.ps1',
    'Configure-Agent-Win7.ps1',
    'Get-AgentStatus-Win7.ps1',
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

$testDirectory = Join-Path $env:TEMP (
    'branch-heartbeat-win7-test-' + [Guid]::NewGuid().ToString('N')
)
$previousDirectory = $env:BRANCH_HEARTBEAT_LEGACY_DATA_DIR
try {
    $env:BRANCH_HEARTBEAT_LEGACY_DATA_DIR = $testDirectory
    . (Join-Path $legacyDirectory 'LegacyCommon.ps1')

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
