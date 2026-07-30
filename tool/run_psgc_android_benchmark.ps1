param(
    [string]$DeviceId = '',
    [ValidateRange(1, 65535)]
    [int]$Port = 8765,
    [switch]$Profile
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$adb = Join-Path $env:LOCALAPPDATA 'Android\sdk\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb)) {
    throw "adb was not found at $adb"
}

if ([string]::IsNullOrWhiteSpace($DeviceId)) {
    $connected = @(
        & $adb devices |
            Select-Object -Skip 1 |
            ForEach-Object {
                if ($_ -match '^(\S+)\s+device$') {
                    $Matches[1]
                }
            }
    )
    if ($connected.Count -ne 1) {
        throw 'Pass -DeviceId when exactly one authorized device is not connected.'
    }
    $DeviceId = $connected[0]
}

$serverScript = Join-Path $PSScriptRoot 'serve_psgc_benchmark.mjs'
$server = Start-Process `
    -FilePath 'node' `
    -ArgumentList @($serverScript, $Port, $adb, $DeviceId) `
    -PassThru `
    -WindowStyle Hidden

try {
    $ready = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try {
            $response = Invoke-WebRequest `
                -Uri "http://127.0.0.1:$Port/regions.json" `
                -UseBasicParsing `
                -TimeoutSec 1
            if ($response.StatusCode -eq 200) {
                $ready = $true
                break
            }
        } catch {
            Start-Sleep -Milliseconds 100
        }
    }
    if (-not $ready) {
        throw 'The local PSGC benchmark server did not become ready.'
    }

    & $adb -s $DeviceId reverse "tcp:$Port" "tcp:$Port"
    if ($LASTEXITCODE -ne 0) {
        throw 'adb reverse failed.'
    }

    Push-Location $repositoryRoot
    try {
        if ($Profile) {
            & flutter drive `
                --driver=test_driver\integration_test.dart `
                --target=integration_test\psgc_native_benchmark_test.dart `
                -d $DeviceId `
                --profile `
                "--dart-define=PSGC_BENCHMARK_BASE_URL=http://127.0.0.1:$Port"
        } else {
            & flutter test `
                integration_test\psgc_native_benchmark_test.dart `
                -d $DeviceId `
                "--dart-define=PSGC_BENCHMARK_BASE_URL=http://127.0.0.1:$Port" `
                --reporter expanded
        }
        if ($LASTEXITCODE -ne 0) {
            throw 'The PSGC Android benchmark failed.'
        }
    } finally {
        Pop-Location
    }
} finally {
    & $adb -s $DeviceId reverse --remove "tcp:$Port" 2>$null
    if (-not $server.HasExited) {
        Stop-Process -Id $server.Id -Force
    }
}
