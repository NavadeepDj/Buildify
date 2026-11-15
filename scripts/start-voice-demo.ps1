$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $repo
try {
  & (Join-Path $PSScriptRoot 'start-status-probe.ps1') -Tunnel
  & node (Join-Path $PSScriptRoot 'connect-bolna-status.mjs')
  if ($LASTEXITCODE -ne 0) { throw 'Bolna connection failed.' }
  foreach ($mobileSessionRelative in @('build/android-voice/session.json', 'build/mobile-laptop-voice/session.json')) {
  $mobileSessionPath = Join-Path $repo $mobileSessionRelative
  if (Test-Path -LiteralPath $mobileSessionPath) {
    $mobileSession = Get-Content -LiteralPath $mobileSessionPath -Raw | ConvertFrom-Json
    $desktopSessionPath = Join-Path $repo 'build/status-probe/session.json'
    if ($mobileSession.target_session -and
        [IO.Path]::GetFullPath($mobileSession.target_session) -eq [IO.Path]::GetFullPath($desktopSessionPath)) {
      & node (Join-Path $PSScriptRoot 'connect-bolna-status.mjs') "--session=$mobileSessionPath" "--target-session=$desktopSessionPath"
      if ($LASTEXITCODE -ne 0) { throw 'Mobile agent could not reconnect to the laptop.' }
    }
  }
  }
  $webcallReady = $false
  try { $webcallReady = (Invoke-WebRequest -Uri 'http://127.0.0.1:19001/' -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200 } catch { }
  if (!$webcallReady) {
    Start-Process -FilePath (Get-Command node).Source -ArgumentList @(Join-Path $PSScriptRoot 'bolna-webcall.mjs') -WorkingDirectory $repo -WindowStyle Hidden -RedirectStandardOutput 'build/status-probe/webcall.stdout.log' -RedirectStandardError 'build/status-probe/webcall.stderr.log' | Out-Null
  }
  Write-Output 'Open the private url in build/status-probe/webcall-server.json and click Call Buildify.'
} finally { Pop-Location }
