param([switch]$Tunnel)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$demoDir = Join-Path $repo 'build/status-probe'
[IO.Directory]::CreateDirectory($demoDir) | Out-Null
$sessionPath = Join-Path $demoDir 'session.json'
$previousSession = $null
$session = @{}
$status = $null
if (Test-Path -LiteralPath $sessionPath) {
  $previousSession = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
  try {
    $existing = Invoke-RestMethod -Uri 'http://127.0.0.1:18791/v1/status' -Headers @{ Authorization = "Bearer $($previousSession.token)" } -TimeoutSec 2
    if ($existing.ok) {
      foreach ($property in $previousSession.PSObject.Properties) { $session[$property.Name] = $property.Value }
      $status = $existing
      Write-Output 'Reusing the running Buildify app; checking its tool connection.'
    }
  } catch { }
}
if (!$status) {
  $exe = Join-Path $repo 'build/windows/x64/runner/Debug/buildify_flutter.exe'
  if (!(Test-Path -LiteralPath $exe)) { throw 'Build the Windows debug app first.' }
  $bytes = New-Object byte[] 32
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
  $token = [Convert]::ToBase64String($bytes)
  $info = New-Object Diagnostics.ProcessStartInfo
  $info.FileName = $exe
  $info.WorkingDirectory = Split-Path -Parent $exe
  $info.UseShellExecute = $false
  $info.EnvironmentVariables['BUILDIFY_STATUS_TOKEN'] = $token
  $info.EnvironmentVariables['BUILDIFY_LLAMA_SERVER'] = Join-Path $repo 'build/windows-runtime/native/windows/llama-server.exe'
  $info.EnvironmentVariables['BUILDIFY_CLOUDFLARED'] = Join-Path $repo 'build/windows-runtime/native/windows/cloudflared.exe'
  $info.EnvironmentVariables['BUILDIFY_ENDPOINT_EMAIL_ENV_FILE'] = Join-Path $repo '.env'
  $app = [Diagnostics.Process]::Start($info)
  $session = @{ app_pid = $app.Id; token = $token; local_url = 'http://127.0.0.1:18791/v1/status' }
  if ($previousSession.agent_id) { $session.agent_id = $previousSession.agent_id }
  $session | ConvertTo-Json | Set-Content -LiteralPath $sessionPath -Encoding UTF8
  $deadline = [DateTime]::UtcNow.AddSeconds(30)
  while ([DateTime]::UtcNow -lt $deadline) {
    try {
      $status = Invoke-RestMethod -Uri $session.local_url -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 3
      break
    } catch { Start-Sleep -Milliseconds 300 }
  }
  if (!$status) { throw 'The live app did not expose its opt-in status endpoint within 30 seconds.' }
}
$status | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $demoDir 'local-result.json') -Encoding UTF8
Write-Output ($status | ConvertTo-Json -Compress)
if ($Tunnel) {
  $publicReady = $false
  if ($session.public_url -match '^https://[a-z0-9-]+\.trycloudflare\.com/v1/status$') {
    try {
      $publicStatus = Invoke-RestMethod -Uri $session.public_url -Headers @{ Authorization = "Bearer $($session.token)" } -TimeoutSec 5
      $publicReady = $publicStatus.ok -eq $true -and $publicStatus.source -eq 'buildify_live_app'
    } catch { }
  }
  if (!$publicReady) {
    $cloudflared = Join-Path $repo 'build/windows-runtime/native/windows/cloudflared.exe'
    if (!(Test-Path -LiteralPath $cloudflared)) { throw 'Bundled cloudflared executable is missing.' }
    if ($session.tunnel_pid) {
      $ownedTunnel = Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$session.tunnel_pid)" -ErrorAction SilentlyContinue
      if ($ownedTunnel -and $ownedTunnel.ExecutablePath -eq $cloudflared -and
          $ownedTunnel.CommandLine -match 'http://127\.0\.0\.1:18791(?:\s|$)') {
        Stop-Process -Id ([int]$session.tunnel_pid) -ErrorAction SilentlyContinue
      }
    }
    $session.Remove('public_url')
    $tunnelLog = Join-Path $demoDir "tunnel-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff')).log"
    $tunnelProcess = Start-Process -FilePath $cloudflared -ArgumentList @('tunnel','--url','http://127.0.0.1:18791','--no-autoupdate') -WindowStyle Hidden -RedirectStandardError $tunnelLog -RedirectStandardOutput "$tunnelLog.stdout.log" -PassThru
    $session.tunnel_pid = $tunnelProcess.Id
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    while ([DateTime]::UtcNow -lt $deadline) {
      $text = Get-Content -LiteralPath $tunnelLog -Raw -ErrorAction SilentlyContinue
      if ($text -match 'https://[a-z0-9-]+\.trycloudflare\.com') {
        $session.public_url = "$($Matches[0])/v1/status"
        break
      }
      if ($tunnelProcess.HasExited) { break }
      Start-Sleep -Milliseconds 500
    }
    $session | ConvertTo-Json | Set-Content -LiteralPath $sessionPath -Encoding UTF8
    if (!$session.public_url) { throw "Tunnel did not produce a URL; inspect $tunnelLog." }
  } else { Write-Output 'The existing public tool connection is healthy.' }
  Write-Output "Public tool URL: $($session.public_url)"
}
Write-Output 'Temporary credentials are stored only in ignored build/status-probe/session.json. Do not share that file.'
