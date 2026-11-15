# Match both the selected mode's command arguments and process creation time.
# A stale PID alone must never stop another mode or an unrelated process.
function Get-BuildifyVoiceProcesses {
  param([string]$RecordPath, [string]$Repo, [string]$ScriptsRoot)
  if (!(Test-Path -LiteralPath $RecordPath)) { return }
  $state = Get-Content -LiteralPath $RecordPath -Raw | ConvertFrom-Json
  $sessionPath = Join-Path (Split-Path -Parent $RecordPath) 'session.json'
  foreach ($entry in @(
    @{ id = $state.helper_pid; script = (Join-Path $ScriptsRoot 'bolna-webcall.mjs'); argument = "--session=$sessionPath"; started = $state.helper_started_at },
    @{ id = $state.tunnel_pid; script = (Join-Path $Repo 'build/windows-runtime/native/windows/cloudflared.exe'); argument = "http://127.0.0.1:$($state.port)"; started = $state.tunnel_started_at }
  )) {
    $processId = [int]$entry.id
    if ($processId -le 0) { continue }
    try { $process = Get-CimInstance Win32_Process -Filter "ProcessId=$processId" -ErrorAction Stop } catch {
      throw 'The recorded voice process could not be inspected. Its process metadata was preserved.'
    }
    if (!$process -or !$process.CommandLine) { continue }
    $command = $process.CommandLine.Replace('/', '\')
    $identityMatches = $true
    foreach ($value in @($entry.script, $entry.argument)) {
      $pattern = '(?i)(?:^|[\s"''])' + [regex]::Escape($value.Replace('/', '\')) + '(?=$|[\s"''])'
      if ($command -notmatch $pattern) { $identityMatches = $false; break }
    }
    if (!$identityMatches) { continue }
    if ($entry.started) {
      try {
        $liveProcess = Get-Process -Id $processId -ErrorAction Stop
        $expectedStart = [DateTime]::Parse($entry.started).ToUniversalTime()
        if ($liveProcess.StartTime.ToUniversalTime().Ticks -ne $expectedStart.Ticks) { continue }
      } catch { throw 'The recorded voice process identity could not be verified. Its process metadata was preserved.' }
    }
    $process
  }
}
