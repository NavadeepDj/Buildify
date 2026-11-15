$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$buildRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build'))
$fixture = [IO.Path]::GetFullPath((Join-Path $buildRoot "voice-process-tests-$([Guid]::NewGuid().ToString('N'))"))
if (!$fixture.StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test fixture.' }
$fixtureScripts = Join-Path $fixture 'scripts'
$phoneDirectory = Join-Path $fixture 'build/android-voice'
$laptopDirectory = Join-Path $fixture 'build/mobile-laptop-voice'
foreach ($path in @($fixtureScripts, $phoneDirectory, $laptopDirectory, (Join-Path $fixture 'build/windows-runtime/native/windows'))) { [IO.Directory]::CreateDirectory($path) | Out-Null }
foreach ($name in @('voice-processes.ps1', 'stop-android-voice.ps1', 'start-android-voice.ps1', 'restart-voice-webcall.ps1', 'voice-session.mjs')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $fixtureScripts }
Set-Content -LiteralPath (Join-Path $fixture 'build/windows-runtime/native/windows/cloudflared.exe') -Value 'Synthetic; never executed.'
$helperScript = Join-Path $fixtureScripts 'bolna-webcall.mjs'
Set-Content -LiteralPath $helperScript -Value '// Synthetic; never executed.'
$phoneSession = Join-Path $phoneDirectory 'session.json'
$laptopSession = Join-Path $laptopDirectory 'session.json'
$record = Join-Path $phoneDirectory 'processes.json'
$recordLaptop = Join-Path $laptopDirectory 'processes.json'
$started = [DateTime]'2026-11-15T10:00:00Z'
$nodeExecutable = (Get-Command node).Source
$global:voiceProcessRows = @{}
$global:voiceProcessStarts = @{}
$global:voiceProcessStopped = @()
$global:voiceProcessConnectorCalls = 0
$global:voiceProcessLaunches = 0
$global:voiceProcessRejectReuse = $false
$global:voiceProcessInspectionFails = $false

function Get-CimInstance {
  param($ClassName, $Filter, $ErrorAction)
  if ($global:voiceProcessInspectionFails) { throw 'Synthetic inspection permission failure.' }
  $testProcessId = [int]($Filter -replace '^ProcessId=', '')
  return $global:voiceProcessRows[$testProcessId]
}
function Get-Process { param($Id, $ErrorAction) return [PSCustomObject]@{ StartTime = $global:voiceProcessStarts[[int]$Id] } }
function Stop-Process { param($Id, $ErrorAction) $global:voiceProcessStopped += @($Id) }
function Get-NetTCPConnection { param($LocalPort, $State, $ErrorAction) return @() }
function node {
  [CmdletBinding(PositionalBinding = $false)]
  param([Parameter(ValueFromRemainingArguments = $true, Position = 0)][object[]]$NodeArguments, [Parameter(ValueFromPipeline = $true)][string]$PipelineText)
  $name = Split-Path -Leaf $NodeArguments[0]
  if ($name -eq 'connect-bolna-status.mjs') { $global:voiceProcessConnectorCalls++; $global:LASTEXITCODE = 0; return }
  if ($name -eq 'bolna-webcall.mjs') { $global:LASTEXITCODE = $(if ($global:voiceProcessRejectReuse -and '--check-reuse-state' -in $NodeArguments) { 1 } else { 0 }); return }
  $result = if ($PipelineText) { $PipelineText | & $nodeExecutable @NodeArguments } else { & $nodeExecutable @NodeArguments }
  $global:LASTEXITCODE = $LASTEXITCODE
  return $result
}
function Start-Process {
  param($FilePath, $ArgumentList, $WindowStyle, $RedirectStandardError, $RedirectStandardOutput, $WorkingDirectory, [switch]$PassThru)
  $global:voiceProcessLaunches++
  if ($FilePath -notlike '*cloudflared.exe') { throw 'Synthetic helper spawn failure.' }
  Set-Content -LiteralPath $RedirectStandardError -Value 'https://synthetic-tunnel.trycloudflare.com'
  $child = [PSCustomObject]@{ Id = 7001; HasExited = $false; StartTime = $started }
  $child | Add-Member -MemberType ScriptMethod -Name Refresh -Value { }
  return $child
}
function Assert-VoiceTest($Condition, $Message) { if (!$Condition) { throw $Message } }
function Reset-VoiceTest { $global:voiceProcessStopped = @(); $global:voiceProcessConnectorCalls = 0; $global:voiceProcessLaunches = 0 }

try {
  . (Join-Path $fixtureScripts 'voice-processes.ps1')
  $global:voiceProcessRows[101] = [PSCustomObject]@{ ProcessId = 101; Name = 'node.exe'; CommandLine = "node `"$helperScript`" `"--session=$phoneSession`" --port=19002" }
  $global:voiceProcessRows[202] = [PSCustomObject]@{ ProcessId = 202; Name = 'cloudflared.exe'; CommandLine = "`"$(Join-Path $fixture 'build/windows-runtime/native/windows/cloudflared.exe')`" tunnel --url http://127.0.0.1:19002" }
  $global:voiceProcessStarts[101] = $started
  $global:voiceProcessStarts[202] = $started
  $state = @{ helper_pid = 101; tunnel_pid = 202; port = 19002; helper_started_at = $started.ToUniversalTime().ToString('o'); tunnel_started_at = $started.ToUniversalTime().ToString('o') }
  $state | ConvertTo-Json | Set-Content -LiteralPath $record
  $active = @(Get-BuildifyVoiceProcesses -RecordPath $record -Repo $fixture -ScriptsRoot $fixtureScripts)
  Assert-VoiceTest ($active.Count -eq 2) 'Owned helper and tunnel were not recognized.'

  $global:voiceProcessStarts[101] = $started.AddMinutes(1)
  Assert-VoiceTest (@(Get-BuildifyVoiceProcesses -RecordPath $record -Repo $fixture -ScriptsRoot $fixtureScripts).Count -eq 1) 'A recycled PID matched the recorded process creation time.'
  $global:voiceProcessStarts[101] = $started

  @{ helper_pid = 101; tunnel_pid = 202; port = 19003 } | ConvertTo-Json | Set-Content -LiteralPath $recordLaptop
  & (Join-Path $fixtureScripts 'stop-android-voice.ps1') -RunOn laptop | Out-Null
  Assert-VoiceTest ($global:voiceProcessStopped.Count -eq 0) 'Stopping laptop mode killed phone-mode processes from stale PIDs.'
  Assert-VoiceTest (Test-Path -LiteralPath $record) 'Stopping laptop mode removed phone process metadata.'

  $blocked = $false
  try { & (Join-Path $fixtureScripts 'start-android-voice.ps1') -RunOn phone -Port 19005 | Out-Null } catch { $blocked = $_.Exception.Message -like '*already running*' }
  Assert-VoiceTest $blocked 'A new port bypassed the same-mode active helper check.'
  Assert-VoiceTest ($global:voiceProcessConnectorCalls -eq 0 -and $global:voiceProcessLaunches -eq 0) 'Blocked reconfiguration updated an agent or launched processes.'

  $global:voiceProcessInspectionFails = $true
  $blocked = $false
  try { & (Join-Path $fixtureScripts 'stop-android-voice.ps1') -RunOn phone | Out-Null } catch { $blocked = $_.Exception.Message -like '*metadata was preserved*' }
  Assert-VoiceTest ($blocked -and (Test-Path -LiteralPath $record) -and $global:voiceProcessStopped.Count -eq 0) 'Failed inspection lost metadata or stopped a process.'
  $global:voiceProcessInspectionFails = $false

  & (Join-Path $fixtureScripts 'stop-android-voice.ps1') -RunOn phone | Out-Null
  Assert-VoiceTest ($global:voiceProcessStopped.Count -eq 2 -and 101 -in $global:voiceProcessStopped -and 202 -in $global:voiceProcessStopped) 'Stopping the selected mode failed to stop its owned processes.'
  Assert-VoiceTest (!(Test-Path -LiteralPath $record)) 'Stopped process metadata was retained.'

  Reset-VoiceTest
  $global:voiceProcessRows = @{}
  $pairing = Join-Path $fixture 'pairing.json'
  @{ platform = 'android'; public_url = 'https://synthetic-phone.trycloudflare.com/v1/status'; token = 'synthetic-test-pairing-token-1234567890' } | ConvertTo-Json | Set-Content -LiteralPath $pairing
  $failed = $false
  $failureMessage = ''
  try { & (Join-Path $fixtureScripts 'start-android-voice.ps1') -RunOn phone -PairingFile $pairing | Out-Null } catch { $failureMessage = $_.Exception.Message; $failed = $failureMessage -eq 'Synthetic helper spawn failure.' }
  Assert-VoiceTest $failed "The synthetic helper spawn failure was not reached: $failureMessage"
  Assert-VoiceTest (7001 -in $global:voiceProcessStopped) 'A helper spawn failure orphaned the newly created tunnel.'
  Assert-VoiceTest (!(Test-Path -LiteralPath $record)) 'A failed startup retained process metadata.'

  Reset-VoiceTest
  $stateFile = Join-Path $phoneDirectory 'webcall-server.json'
  @{ session_file = $phoneSession; url = 'http://127.0.0.1:19002/#invite=synthetic'; pid = 101 } | ConvertTo-Json | Set-Content -LiteralPath $stateFile
  $global:voiceProcessRejectReuse = $true
  $blocked = $false
  try { & (Join-Path $fixtureScripts 'restart-voice-webcall.ps1') -Target android | Out-Null } catch { $blocked = $_.Exception.Message -like '*was not stopped*' }
  Assert-VoiceTest $blocked 'An invalid invitation was not rejected by restart preflight.'
  Assert-VoiceTest ($global:voiceProcessStopped.Count -eq 0 -and $global:voiceProcessLaunches -eq 0) 'Restart stopped or replaced a helper before invitation validation.'

  $freshReachedLaunch = $false
  try { & (Join-Path $fixtureScripts 'restart-voice-webcall.ps1') -Target android -NewInvitation | Out-Null } catch { $freshReachedLaunch = $_.Exception.Message -eq 'Synthetic helper spawn failure.' }
  Assert-VoiceTest $freshReachedLaunch 'Explicit fresh-invitation recovery incorrectly required old invitation reuse.'
  Reset-VoiceTest
  @{ session_file = $laptopSession; url = 'http://127.0.0.1:19002/#invite=synthetic'; pid = 101 } | ConvertTo-Json | Set-Content -LiteralPath $stateFile
  $blocked = $false
  try { & (Join-Path $fixtureScripts 'restart-voice-webcall.ps1') -Target android -NewInvitation | Out-Null } catch { $blocked = $_.Exception.Message -like '*selected target session*' }
  Assert-VoiceTest $blocked 'Fresh recovery accepted a different mode source session.'
  Assert-VoiceTest ($global:voiceProcessStopped.Count -eq 0 -and $global:voiceProcessLaunches -eq 0) 'Wrong-mode restart affected running processes.'
  Write-Output '10 lifecycle checks passed: process identity, recycled PIDs, mode isolation, reconfiguration blocking, inspection failure, selected stop, failed-start cleanup, restart preflight, fresh invitation, and source binding.'
} finally {
  if ([IO.Path]::GetFullPath($fixture).StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
