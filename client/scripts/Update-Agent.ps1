[CmdletBinding()]
param(
    [string]$Version,
    [string]$ZipUrl,
    [string]$ZipPath,
    [string]$Sha256
)

$ErrorActionPreference = 'Stop'
$serviceName = 'BranchHeartbeatAgent'
$installDirectory = Join-Path $env:ProgramFiles 'BranchHeartbeat'
$installedExecutable = Join-Path $installDirectory 'BranchHeartbeat.Agent.exe'
$repo = 'newnew01/sk-heartbeat-agent'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from PowerShell as Administrator.'
}

if (-not (Test-Path -LiteralPath $installedExecutable)) {
    throw "Agent is not installed at $installedExecutable. Run Install-Agent.ps1 first."
}

if ([string]::IsNullOrEmpty($ZipUrl) -and [string]::IsNullOrEmpty($ZipPath)) {
    if ([string]::IsNullOrEmpty($Version)) {
        throw 'Specify -Version (e.g. 1.0.3), or -ZipUrl, or -ZipPath.'
    }
    $ZipUrl = "https://github.com/$repo/releases/download/v$Version/BranchHeartbeat-Agent-$Version-win-x64.zip"
}

$workDirectory = Join-Path $env:TEMP "branch-heartbeat-update-$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null

try {
    if ([string]::IsNullOrEmpty($ZipPath)) {
        $ZipPath = Join-Path $workDirectory 'agent.zip'
        Write-Host "Downloading $ZipUrl ..."
        Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath
    }

    if (-not [string]::IsNullOrEmpty($Sha256)) {
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ZipPath).Hash
        if ($actualHash -ne $Sha256.ToUpperInvariant()) {
            throw "SHA-256 mismatch. Expected $Sha256, got $actualHash."
        }
        Write-Host 'Checksum verified.'
    }

    $extractDirectory = Join-Path $workDirectory 'extracted'
    Expand-Archive -Path $ZipPath -DestinationPath $extractDirectory -Force

    $newExecutable = Join-Path $extractDirectory 'BranchHeartbeat.Agent.exe'
    if (-not (Test-Path -LiteralPath $newExecutable)) {
        throw "BranchHeartbeat.Agent.exe not found in the downloaded package."
    }

    $existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $existingService) {
        throw "Service $serviceName is not installed. Run Install-Agent.ps1 first."
    }

    $backupExecutable = "$installedExecutable.bak"
    Copy-Item -LiteralPath $installedExecutable -Destination $backupExecutable -Force

    Write-Host "Stopping $serviceName ..."
    if ($existingService.Status -ne 'Stopped') {
        Stop-Service -Name $serviceName -Force
        $existingService.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
    }

    Copy-Item -LiteralPath $newExecutable -Destination $installedExecutable -Force

    Write-Host "Starting $serviceName ..."
    Start-Service -Name $serviceName

    $version = (Get-Item -LiteralPath $installedExecutable).VersionInfo.ProductVersion
    Write-Host ''
    Write-Host "Branch Heartbeat Agent updated to $version." -ForegroundColor Green
    Write-Host "Previous binary kept at $backupExecutable in case a rollback is needed."
    Write-Host "Status: & `"$installedExecutable`" status"
}
finally {
    Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
