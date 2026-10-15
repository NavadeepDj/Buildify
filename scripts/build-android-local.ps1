$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $projectRoot '.env'
if (!(Test-Path -LiteralPath $envPath)) {
    throw 'Create the local .env before building the private Android app.'
}
Push-Location $projectRoot
try {
    & flutter build apk --release "--dart-define-from-file=$envPath"
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed.' }
} finally {
    Pop-Location
}
