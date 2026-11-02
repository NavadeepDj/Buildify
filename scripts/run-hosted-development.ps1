param(
    [string]$Device = '',
    [switch]$BuildApk
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    $configPath = Join-Path $projectRoot 'config/supabase.development.json'
    if (!(Test-Path -LiteralPath $configPath)) {
        throw 'Copy config/supabase.development.example.json to config/supabase.development.json and fill in the public project configuration.'
    }
    & dart tool/validate_hosted_config.dart $configPath development
    if ($LASTEXITCODE -ne 0) { throw 'Hosted development configuration is invalid.' }
    $flutterArgs = if ($BuildApk) { @('build', 'apk', '--debug') } else { @('run') }
    if ($Device -and !$BuildApk) { $flutterArgs += @('-d', $Device) }
    $flutterArgs += "--dart-define-from-file=$configPath"
    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) { throw 'Hosted development launch/build failed.' }
} finally {
    Pop-Location
}
