param([ValidateSet('phone', 'laptop')][string]$RunOn = 'phone')
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$record = Join-Path $repo $(if ($RunOn -eq 'phone') { 'build/android-voice/processes.json' } else { 'build/mobile-laptop-voice/processes.json' })
if (!(Test-Path -LiteralPath $record)) { return }
. (Join-Path $PSScriptRoot 'voice-processes.ps1')
foreach ($process in @(Get-BuildifyVoiceProcesses -RecordPath $record -Repo $repo -ScriptsRoot $PSScriptRoot)) {
  Stop-Process -Id ([int]$process.ProcessId)
}
Remove-Item -LiteralPath $record
Write-Output "Stopped the $RunOn voice call helper."
if ($RunOn -eq 'phone') { Write-Output 'Disconnect voice in the APK to revoke device pairing.' }
