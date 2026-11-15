$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$buildRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build'))
$fixture = Join-Path $buildRoot "voice-launcher-tests-$([Guid]::NewGuid().ToString('N'))"
if (![IO.Path]::GetFullPath($fixture).StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Test fixture is outside build.' }
$fixtureScripts = Join-Path $fixture 'scripts'
$fixtureSessionDirectory = Join-Path $fixture 'build/status-probe'
[IO.Directory]::CreateDirectory($fixtureScripts) | Out-Null
[IO.Directory]::CreateDirectory($fixtureSessionDirectory) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $fixture 'build/windows-runtime/native/windows')) | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'start-status-probe.ps1') -Destination $fixtureScripts
Set-Content -LiteralPath (Join-Path $fixture 'build/windows-runtime/native/windows/cloudflared.exe') -Value 'Synthetic test fixture; never executed.'
$sessionPath = Join-Path $fixtureSessionDirectory 'session.json'
@{ token = 'synthetic-launcher-test-token-1234567890'; public_url = 'https://old-connection.trycloudflare.com/v1/status'; agent_id = 'synthetic-existing-agent'; app_pid = 1234 } | ConvertTo-Json | Set-Content -LiteralPath $sessionPath
$global:voiceLauncherTestPublicHealthy = $true
$global:voiceLauncherTestTunnelLaunches = 0
function Invoke-RestMethod {
  param($Uri, $Headers, $TimeoutSec)
  if ($Uri -like 'http://127.0.0.1:*' -or $global:voiceLauncherTestPublicHealthy) { return @{ ok = $true; source = 'buildify_live_app'; model_state = 'stopped' } }
  throw 'Synthetic stale public tunnel.'
}
function Start-Process {
  param($FilePath, $ArgumentList, $WindowStyle, $RedirectStandardError, $RedirectStandardOutput, [switch]$PassThru)
  if ($FilePath -notlike '*cloudflared.exe') { throw 'Unexpected process launch in test.' }
  $global:voiceLauncherTestTunnelLaunches++
  Set-Content -LiteralPath $RedirectStandardError -Value 'Synthetic assigned URL https://recovered-connection.trycloudflare.com'
  return [PSCustomObject]@{ Id = 8765; HasExited = $false }
}
try {
  & (Join-Path $fixtureScripts 'start-status-probe.ps1') -Tunnel | Out-Null
  if ($global:voiceLauncherTestTunnelLaunches -ne 0) { throw 'Healthy public tunnel was unnecessarily replaced.' }
  $global:voiceLauncherTestPublicHealthy = $false
  & (Join-Path $fixtureScripts 'start-status-probe.ps1') -Tunnel | Out-Null
  $recovered = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
  if ($global:voiceLauncherTestTunnelLaunches -ne 1 -or $recovered.public_url -ne 'https://recovered-connection.trycloudflare.com/v1/status') { throw 'Stale tunnel was not recovered.' }
  if ($recovered.app_pid -ne 1234 -or $recovered.agent_id -ne 'synthetic-existing-agent' -or $recovered.token -ne 'synthetic-launcher-test-token-1234567890') { throw 'Recovering the tunnel changed the active app pairing.' }
  Write-Output '2 launcher checks passed: healthy reuse and stale tunnel recovery preserve the app and pairing.'
} finally {
  if ([IO.Path]::GetFullPath($fixture).StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $fixture -Recurse -Force
  }
}
