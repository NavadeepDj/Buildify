param([string]$Destination = (Join-Path $PSScriptRoot '../build/windows-runtime'))
$ErrorActionPreference = 'Stop'
$Destination = [IO.Path]::GetFullPath($Destination)
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
$downloads = Join-Path $Destination 'downloads'
$native = Join-Path $Destination 'native/windows'
New-Item -ItemType Directory -Force -Path $downloads,$native | Out-Null
function Get-VerifiedFile([string]$Url, [string]$Name, [string]$Sha256) {
  $target = Join-Path $downloads $Name
  if (!(Test-Path -LiteralPath $target) -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $Sha256) {
    Invoke-WebRequest -Uri $Url -OutFile $target -UseBasicParsing
  }
  if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $Sha256) { throw "Checksum mismatch: $Name" }
  return $target
}
$llama = Get-VerifiedFile 'https://github.com/ggml-org/llama.cpp/releases/download/b12184/llama-b12184-bin-win-cpu-x64.zip' 'llama-b12184-win-cpu-x64.zip' '6164e72376100557ff4664a665bc35593fcc76ac4043d87dcdfdba155f94eae0'
$cloudflared = Get-VerifiedFile 'https://github.com/cloudflare/cloudflared/releases/download/2026.10.7/cloudflared-windows-amd64.exe' 'cloudflared-2026.10.7.exe' '2493dbc168923bb3e59e5e7716f71deced92992eea9acd6e9d74f84ac7751343'
Expand-Archive -LiteralPath $llama -DestinationPath (Join-Path $Destination 'llama') -Force
Get-ChildItem (Join-Path $Destination 'llama') -Recurse -File | Where-Object { $_.Name -eq 'llama-server.exe' -or $_.Extension -eq '.dll' -or $_.Name -match '^LICENSE|^NOTICE|^COPYING' } | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination $native -Force
}
Copy-Item -LiteralPath $cloudflared -Destination (Join-Path $native 'cloudflared.exe') -Force
Invoke-WebRequest 'https://raw.githubusercontent.com/ggml-org/llama.cpp/b12184/LICENSE' -OutFile (Join-Path $native 'LICENSE-llama.cpp.txt') -UseBasicParsing
Invoke-WebRequest 'https://raw.githubusercontent.com/cloudflare/cloudflared/2026.10.7/LICENSE' -OutFile (Join-Path $native 'LICENSE-cloudflared.txt') -UseBasicParsing
@{
  architecture = 'windows-x64-cpu'
  llama_cpp = 'b12184'
  llama_archive_sha256 = '6164e72376100557ff4664a665bc35593fcc76ac4043d87dcdfdba155f94eae0'
  cloudflared = '2026.10.7'
  cloudflared_sha256 = '2493dbc168923bb3e59e5e7716f71deced92992eea9acd6e9d74f84ac7751343'
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $native 'runtime-versions.json') -Encoding UTF8
Write-Output "Verified Windows runtimes prepared in $native"
