$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sessionPath = Join-Path $repo 'build/status-probe/session.json'
if (!(Test-Path -LiteralPath $sessionPath)) { return }
$session = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
$expected = @{
  app_pid = Join-Path $repo 'build/windows/x64/runner/Debug/buildify_flutter.exe'
  tunnel_pid = Join-Path $repo 'build/windows-runtime/native/windows/cloudflared.exe'
}
foreach ($property in @('tunnel_pid', 'app_pid')) {
  $processId = $session.$property
  if (!$processId) { continue }
  $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
  if (!$process) { continue }
  if ([IO.Path]::GetFullPath($process.Path) -ne [IO.Path]::GetFullPath($expected[$property])) {
    throw "Refusing to stop a different process for $property."
  }
  Stop-Process -Id $processId
}
Write-Output 'Stopped the prototype app and tunnel. The saved status token no longer grants access.'
