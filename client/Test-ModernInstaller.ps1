$ErrorActionPreference = 'Stop'

$scriptsDirectory = Join-Path $PSScriptRoot 'scripts'
$scriptNames = @(
    'Install-Agent.ps1',
    'Configure-Agent.ps1',
    'Get-AgentStatus.ps1',
    'Uninstall-Agent.ps1'
)

foreach ($scriptName in $scriptNames) {
    $path = Join-Path $scriptsDirectory $scriptName
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile(
        $path,
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null
    if ($errors.Count -gt 0) {
        throw "$scriptName has PowerShell syntax errors: $($errors[0].Message)"
    }
}
Write-Host 'PASS modern installer script syntax'

$installSource = [IO.File]::ReadAllText(
    (Join-Path $scriptsDirectory 'Install-Agent.ps1')
)
$configureSource = [IO.File]::ReadAllText(
    (Join-Path $scriptsDirectory 'Configure-Agent.ps1')
)
foreach ($source in @($installSource, $configureSource)) {
    if ($source -notmatch '\[string\]\$DeviceKey') {
        throw 'Optional inline Device Key parameter is missing.'
    }
    if ($source -notmatch 'Read-Host.*-AsSecureString') {
        throw 'Secure interactive Device Key prompt is missing.'
    }
    if ($source -notmatch '--key-stdin') {
        throw 'Device Key is not being passed to the Agent through standard input.'
    }
}
Write-Host 'PASS optional inline Device Key and secure prompt support'
