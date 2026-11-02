$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $projectRoot '.env'
if (!(Test-Path -LiteralPath $envPath)) {
    throw 'Create the local .env before building the private Android app.'
}
$githubClientIdLine = Get-Content -LiteralPath $envPath | Where-Object {
    $_ -match '^\s*GITHUB_CLIENT_ID\s*='
} | Select-Object -First 1
$githubClientId = if ($githubClientIdLine) {
    ($githubClientIdLine -replace '^\s*GITHUB_CLIENT_ID\s*=\s*', '').Trim().Trim('"').Trim("'")
} else {
    ''
}

Push-Location $projectRoot
try {
    $flutterArgs = @('build', 'apk', '--release')
    if ($githubClientId) {
        $flutterArgs += "--dart-define=GITHUB_CLIENT_ID=$githubClientId"
    }
    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed.' }
} finally {
    Pop-Location
}
