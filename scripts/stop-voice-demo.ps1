$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
& (Join-Path $PSScriptRoot 'stop-status-probe.ps1')
$record = Join-Path $repo 'build/status-probe/webcall-server.json'
if (Test-Path -LiteralPath $record) {
  $webcall = Get-Content -LiteralPath $record -Raw | ConvertFrom-Json
  $processId = [int]$webcall.pid
  $process = Get-CimInstance Win32_Process -Filter "ProcessId=$processId" -ErrorAction SilentlyContinue
  $expectedScript = Join-Path $PSScriptRoot 'bolna-webcall.mjs'
  if ($process -and $process.CommandLine.IndexOf($expectedScript, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
    Stop-Process -Id $processId
    Write-Output 'Stopped the local browser-call helper.'
  }
}
