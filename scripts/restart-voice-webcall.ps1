param(
  [ValidateSet('windows', 'android', 'mobile-laptop')][string]$Target = 'windows',
  [string]$PreviousHelperScript,
  [switch]$NewInvitation
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$directory = Join-Path $repo $(if ($Target -eq 'android') { 'build/android-voice' } elseif ($Target -eq 'mobile-laptop') { 'build/mobile-laptop-voice' } else { 'build/status-probe' })
$stateFile = Join-Path $directory 'webcall-server.json'
if (!(Test-Path -LiteralPath $stateFile)) { throw 'Start the voice demo once before restarting its call helper.' }
$state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
$sessionPath = [IO.Path]::GetFullPath($state.session_file)
$expectedSession = Join-Path $directory 'session.json'
if ($sessionPath -ne $expectedSession) { throw 'The call helper does not belong to the selected target session. It was not stopped.' }
$localUrl = [Uri]$state.url
if ($localUrl.Scheme -ne 'http' -or $localUrl.Host -ne '127.0.0.1' -or $localUrl.Port -lt 1024) { throw 'Invalid local call helper URL.' }
$scriptPath = Join-Path $PSScriptRoot 'bolna-webcall.mjs'
$arguments = @("`"$scriptPath`"", "`"--session=$sessionPath`"", "`"--state-file=$stateFile`"", "--port=$($localUrl.Port)")
$preflightArguments = @($scriptPath, "--session=$sessionPath", "--state-file=$stateFile", "--port=$($localUrl.Port)")
if ($NewInvitation) {
  $preflightArguments += '--check-start'
} else {
  $arguments += '--reuse-state'
  $preflightArguments += @('--reuse-state', '--check-reuse-state')
}
if ($state.phone_url) {
  $publicUrl = [Uri]$state.phone_url
  if ($publicUrl.Scheme -ne 'https' -or $publicUrl.Host -notmatch '^[a-z0-9-]+\.trycloudflare\.com$' -or $publicUrl.UserInfo) { throw 'Invalid public call origin. The helper was not stopped.' }
  $originArgument = "--public-origin=$($publicUrl.GetLeftPart([UriPartial]::Authority))"
  $arguments += $originArgument
  $preflightArguments += $originArgument
}
$null = & node @preflightArguments
if ($LASTEXITCODE -ne 0) { throw 'The saved invitation or selected target is invalid. The helper was not stopped. Reconfigure that mode or use -NewInvitation for a fresh call link.' }
$expectedPreviousScript = $scriptPath
if ($PreviousHelperScript) {
  $expectedPreviousScript = [IO.Path]::GetFullPath($PreviousHelperScript)
  if (!$expectedPreviousScript.StartsWith($repo + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
      [IO.Path]::GetExtension($expectedPreviousScript) -ne '.mjs' -or !(Test-Path -LiteralPath $expectedPreviousScript)) {
    throw 'The previous helper must be an existing JavaScript module inside this workspace.'
  }
}
$processId = [int]$state.pid
$process = Get-CimInstance Win32_Process -Filter "ProcessId=$processId" -ErrorAction SilentlyContinue
if ($process -and ($process.Name -ne 'node.exe' -or !$process.CommandLine -or $process.CommandLine.Replace('/', '\').IndexOf($expectedPreviousScript.Replace('/', '\'), [StringComparison]::OrdinalIgnoreCase) -lt 0)) {
  throw 'The recorded process is no longer the Buildify call helper. It was not stopped.'
}
if ($process -and ($Target -ne 'windows' -or $process.CommandLine -match '--session=')) {
  $sessionArgument = [regex]::Escape("--session=$sessionPath".Replace('/', '\'))
  if ($process.CommandLine.Replace('/', '\') -notmatch ('(?i)(?:^|[\s"''])' + $sessionArgument + '(?=$|[\s"''])')) {
    throw 'The recorded helper belongs to a different target session. It was not stopped.'
  }
}
if ($process -and !(Get-NetTCPConnection -LocalPort $localUrl.Port -State Listen -ErrorAction SilentlyContinue | Where-Object OwningProcess -EQ $processId)) {
  throw 'The recorded helper does not own its call port. It was not stopped.'
}
if ($process) { Stop-Process -Id $processId -ErrorAction Stop }
$helper = Start-Process -FilePath (Get-Command node).Source -ArgumentList $arguments -WorkingDirectory $repo -WindowStyle Hidden -RedirectStandardOutput (Join-Path $directory 'webcall.stdout.log') -RedirectStandardError (Join-Path $directory 'webcall.stderr.log') -PassThru
$deadline = [DateTime]::UtcNow.AddSeconds(15)
$ready = $false
while ([DateTime]::UtcNow -lt $deadline) {
  $helper.Refresh()
  if ($helper.HasExited) { break }
  try {
    $health = Invoke-RestMethod -Uri "http://127.0.0.1:$($localUrl.Port)/health" -TimeoutSec 1
    $updated = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    if ($health.helper_version -ge 2 -and $updated.pid -eq $helper.Id) { $ready = $true; break }
  } catch { }
  Start-Sleep -Milliseconds 200
}
if (!$ready) { Stop-Process -Id $helper.Id -ErrorAction SilentlyContinue; throw 'Call helper did not restart. Inspect its webcall.stderr.log.' }
$processRecord = Join-Path $directory 'processes.json'
if (Test-Path -LiteralPath $processRecord) {
  $processes = Get-Content -LiteralPath $processRecord -Raw | ConvertFrom-Json
  $processes.helper_pid = $helper.Id
  $processes | Add-Member -NotePropertyName helper_started_at -NotePropertyValue $helper.StartTime.ToUniversalTime().ToString('o') -Force
  $processes | ConvertTo-Json | Set-Content -LiteralPath $processRecord -Encoding UTF8
}
if ($NewInvitation) {
  Write-Output "Restarted the $Target call helper with a fresh invitation. Open phone_url (or url for desktop) from $stateFile; previous private links are revoked."
} else {
  Write-Output "Restarted the $Target call helper. Existing private invitation links are preserved. Refresh the call page."
}
