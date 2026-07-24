$executable = Join-Path $env:ProgramFiles 'BranchHeartbeat\BranchHeartbeat.Agent.exe'
if (-not (Test-Path -LiteralPath $executable)) {
    throw 'Branch Heartbeat Agent is not installed.'
}

& $executable status
exit $LASTEXITCODE
