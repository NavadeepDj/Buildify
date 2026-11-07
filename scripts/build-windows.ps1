param(
  [string]$Flutter = 'flutter',
  [string]$PublicConfig = '',
  [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $repo
try {
  # This script accepts public app settings only. Never pass a backend .env.
  $buildArgs = @('build','windows','--release')
  if ($PublicConfig) {
    $settings = Get-Content -LiteralPath $PublicConfig -Raw | ConvertFrom-Json
    $allowed = @('BUILDIFY_ENV','SUPABASE_URL','SUPABASE_PUBLISHABLE_KEY','MANAGEMENT_API_URL')
    foreach ($property in $settings.PSObject.Properties) {
      if ($allowed -notcontains $property.Name) { throw "Unexpected app config field: $($property.Name)" }
    }
    $buildArgs += "--dart-define-from-file=$PublicConfig"
  }
  if (!$SkipBuild) {
    & $Flutter @buildArgs
    if ($LASTEXITCODE -ne 0) { throw 'Windows release build failed' }
  }
  & (Join-Path $PSScriptRoot 'prepare-windows-runtime.ps1')
  $bundle = Join-Path $repo 'build/windows/x64/runner/Release'
  if (!(Test-Path (Join-Path $bundle 'buildify_flutter.exe'))) { throw 'Windows release executable is missing' }
  # sqflite_common_ffi can find this in pub cache during development, hiding a
  # missing release dependency. Resolve its locked package and bundle the DLL.
  $packageConfigPath = Join-Path $repo '.dart_tool/package_config.json'
  $packages = Get-Content -LiteralPath $packageConfigPath -Raw | ConvertFrom-Json
  $sqlitePackage = $packages.packages | Where-Object { $_.name -eq 'sqflite_common_ffi' } | Select-Object -First 1
  if (!$sqlitePackage) { throw 'Run flutter pub get before packaging SQLite' }
  $sqliteRoot = [Uri]::new([Uri]$packageConfigPath, [string]$sqlitePackage.rootUri).LocalPath
  $sqliteDll = Join-Path $sqliteRoot 'lib/src/windows/sqlite3.dll'
  if (!(Test-Path -LiteralPath $sqliteDll)) { throw 'The locked SQLite runtime DLL is missing' }
  Copy-Item -LiteralPath $sqliteDll -Destination $bundle -Force
  Copy-Item -LiteralPath (Join-Path $sqliteRoot 'LICENSE') -Destination (Join-Path $bundle 'LICENSE-sqflite-common-ffi.txt') -Force
  $native = Join-Path $repo 'build/windows-runtime/native'
  Copy-Item -LiteralPath $native -Destination $bundle -Recurse -Force
  Copy-Item -LiteralPath (Join-Path $repo 'LICENSE') -Destination (Join-Path $bundle 'LICENSE-HostAny.txt') -Force
  Copy-Item -LiteralPath (Join-Path $repo 'docs/windows-quick-start.txt') -Destination (Join-Path $bundle 'START-HERE.txt') -Force
  # Include the actual executable in addition to its adjacent data/DLLs. A lone
  # .exe is not a portable Flutter Windows application.
  $archive = Join-Path $repo 'build/HostAny-windows-x64.zip'
  Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $archive -Force
  Get-FileHash -LiteralPath $archive -Algorithm SHA256
  Write-Output "Run: $(Join-Path $bundle 'buildify_flutter.exe')"
  Write-Output "Portable bundle: $archive"
} finally { Pop-Location }
