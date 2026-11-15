$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $repo
try {
  & (Join-Path $PSScriptRoot 'start-status-probe.ps1') -Tunnel
  & node (Join-Path $PSScriptRoot 'connect-bolna-status.mjs')
  if ($LASTEXITCODE -ne 0) { throw 'Bolna connection failed.' }
  $webcallReady = $false
  try { $webcallReady = (Invoke-WebRequest -Uri 'http://127.0.0.1:19001/' -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200 } catch { }
  if (!$webcallReady) {
    Start-Process -FilePath (Get-Command node).Source -ArgumentList @(Join-Path $PSScriptRoot 'bolna-webcall.mjs') -WorkingDirectory $repo -WindowStyle Hidden -RedirectStandardOutput 'build/status-probe/webcall.stdout.log' -RedirectStandardError 'build/status-probe/webcall.stderr.log' | Out-Null
  }
  Write-Output 'Open http://127.0.0.1:19001 and click Call Buildify.'
} finally { Pop-Location }
