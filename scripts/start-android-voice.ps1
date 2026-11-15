param(
  [string]$PairingFile,
  [switch]$FromClipboard,
  [ValidateSet('phone', 'laptop')][string]$RunOn = 'phone',
  [string]$TargetSession,
  [int]$Port,
  [switch]$ShowPlan
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$routingScript = Join-Path $PSScriptRoot 'voice-session.mjs'
$routingArgs = @("--root=$repo", "--run-on=$RunOn")
if ($PSBoundParameters.ContainsKey('RunOn')) { $routingArgs += '--run-on-explicit' }
if ($TargetSession) { $routingArgs += "--target-session=$TargetSession" }
if ($PSBoundParameters.ContainsKey('Port')) { $routingArgs += "--port=$Port" }
$planJson = & node $routingScript 'android-plan' @routingArgs
if ($LASTEXITCODE -ne 0) { throw 'Choose a valid phone or laptop voice mode before pairing.' }
$plan = $planJson | ConvertFrom-Json
if ($ShowPlan) { Write-Output $planJson; return }
$demoDir = $plan.demoDir
$sessionPath = $plan.sessionPath
$Port = [int]$plan.port
. (Join-Path $PSScriptRoot 'voice-processes.ps1')
$recordPath = Join-Path $demoDir 'processes.json'
if (@(Get-BuildifyVoiceProcesses -RecordPath $recordPath -Repo $repo -ScriptsRoot $PSScriptRoot).Count -gt 0) {
  throw "The $($plan.runOn) voice helper is already running. Stop that mode before reconfiguring it, including when choosing a new port."
}
$existingListener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($existingListener) { throw "Port $Port is already in use. Stop the previous $($plan.runOn) voice setup or choose -Port." }
$cloudflared = Join-Path $repo 'build/windows-runtime/native/windows/cloudflared.exe'
if (!(Test-Path -LiteralPath $cloudflared)) { throw 'The local cloudflared executable is missing.' }
if ($plan.runOn -eq 'phone') {
  if ($FromClipboard -and $PairingFile) { throw 'Choose a pairing file or clipboard input.' }
  $pairingText = if ($FromClipboard) { Get-Clipboard -Raw } elseif ($PairingFile) { Get-Content -LiteralPath $PairingFile -Raw } else {
    throw 'Enable Call Buildify in the APK, copy pairing details, then use -FromClipboard or -PairingFile <private-file>.'
  }
  $null = $pairingText | & node $routingScript 'configure-android' @routingArgs
} else {
  $null = & node $routingScript 'configure-android' @routingArgs
}
if ($LASTEXITCODE -ne 0) { throw 'Android voice session could not be configured. No agent was updated.' }
Push-Location $repo
$tunnel = $null
$helper = $null
$ready = $false
try {
  & node (Join-Path $PSScriptRoot 'connect-bolna-status.mjs') "--session=$sessionPath"
  if ($LASTEXITCODE -ne 0) { throw "Bolna pairing failed for $($plan.runOn) mode. Keep the selected Buildify host connected and retry." }
  $tunnelLog = Join-Path $demoDir 'webcall-tunnel.log'
  $tunnel = Start-Process -FilePath $cloudflared -ArgumentList @('tunnel', '--url', "http://127.0.0.1:$Port", '--no-autoupdate') -WindowStyle Hidden -RedirectStandardError $tunnelLog -RedirectStandardOutput (Join-Path $demoDir 'webcall-tunnel.stdout.log') -PassThru
  $deadline = [DateTime]::UtcNow.AddSeconds(45)
  $publicOrigin = $null
  while ([DateTime]::UtcNow -lt $deadline) {
    $tunnel.Refresh()
    if ($tunnel.HasExited) { break }
    $logText = Get-Content -LiteralPath $tunnelLog -Raw -ErrorAction SilentlyContinue
    if ($logText -match 'https://[a-z0-9-]+\.trycloudflare\.com') { $publicOrigin = $Matches[0]; break }
    Start-Sleep -Milliseconds 400
  }
  if (!$publicOrigin) { Stop-Process -Id $tunnel.Id -ErrorAction SilentlyContinue; throw 'Could not create the phone call link. Check the tunnel log.' }
  $stateFile = Join-Path $demoDir 'webcall-server.json'
  if (Test-Path -LiteralPath $stateFile) { Remove-Item -LiteralPath $stateFile }
  $webcallScript = Join-Path $PSScriptRoot 'bolna-webcall.mjs'
  $helper = Start-Process -FilePath (Get-Command node).Source -ArgumentList @("`"$webcallScript`"", "`"--session=$sessionPath`"", "--port=$Port", "--public-origin=$publicOrigin", "`"--state-file=$stateFile`"") -WorkingDirectory $repo -WindowStyle Hidden -RedirectStandardOutput (Join-Path $demoDir 'webcall.stdout.log') -RedirectStandardError (Join-Path $demoDir 'webcall.stderr.log') -PassThru
  @{ tunnel_pid = $tunnel.Id; helper_pid = $helper.Id; port = $Port; tunnel_started_at = $tunnel.StartTime.ToUniversalTime().ToString('o'); helper_started_at = $helper.StartTime.ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $recordPath -Encoding UTF8
  $deadline = [DateTime]::UtcNow.AddSeconds(15)
  while (!(Test-Path -LiteralPath $stateFile) -and [DateTime]::UtcNow -lt $deadline) {
    $helper.Refresh()
    if ($helper.HasExited) { break }
    Start-Sleep -Milliseconds 200
  }
  $helper.Refresh()
  if (!(Test-Path -LiteralPath $stateFile) -or $helper.HasExited) {
    Stop-Process -Id $tunnel.Id,$helper.Id -ErrorAction SilentlyContinue
    throw "Call helper did not start. Inspect $demoDir/webcall.stderr.log."
  }
  $ready = $true
  Write-Output "Voice ready in $($plan.runOn) mode. Your private phone call link is in $stateFile (phone_url)."
  if ($plan.runOn -eq 'phone') {
    Write-Output 'Paste phone_url into Call Buildify in the APK, then tap Call with Bolna. Keep this computer online.'
    Write-Output 'Disconnect voice separately in the APK to revoke Android pairing.'
  } else {
    Write-Output 'Open phone_url in Chrome on your phone. Keep Buildify and this laptop online. Android pairing is not required.'
  }
  Write-Output "Stop this helper with ./scripts/stop-android-voice.ps1 -RunOn $($plan.runOn)."
} finally {
  if (!$ready) {
    foreach ($child in @($helper, $tunnel)) {
      if ($null -eq $child) { continue }
      try { $child.Refresh(); if (!$child.HasExited) { Stop-Process -Id $child.Id -ErrorAction SilentlyContinue } } catch { }
    }
    if (Test-Path -LiteralPath $recordPath) { Remove-Item -LiteralPath $recordPath }
  }
  Pop-Location
}
