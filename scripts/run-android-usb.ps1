[CmdletBinding()]
param(
    [string]$DeviceId,
    [switch]$Attach
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$adbCommand = Get-Command adb -CommandType Application -ErrorAction SilentlyContinue
$adbCandidates = @(
    if ($adbCommand) { $adbCommand.Source }
    if ($env:ANDROID_HOME) { Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe' }
    if ($env:ANDROID_SDK_ROOT) { Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe' }
    if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe' }
)
$adbPath = $adbCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $adbPath) {
    throw 'Android platform-tools were not found. Set ANDROID_HOME to your Android SDK directory.'
}

Push-Location $projectRoot
try {
    $connectedDevices = @(& $adbPath devices)
    if ($LASTEXITCODE -ne 0) { throw 'Could not list Android devices.' }
    $readyDevices = @($connectedDevices | Where-Object { $_ -match '^\S+\s+device\s*$' } | ForEach-Object { ($_ -split '\s+')[0] })
    if (-not $DeviceId) {
        if ($readyDevices.Count -ne 1) {
            throw 'Connect one Android phone with USB debugging enabled and accept its authorization prompt, or specify -DeviceId.'
        }
        $DeviceId = $readyDevices[0]
    }
    if ($DeviceId -notin $readyDevices) { throw 'The selected Android device is not connected or USB debugging is not authorized.' }

    # Buildx 0.37+ refuses this build without the entitlement opt-out yet Compose may still exit 0.
    if (-not $env:BUILDX_BAKE_ENTITLEMENTS_FS) { $env:BUILDX_BAKE_ENTITLEMENTS_FS = '0' }
    & docker compose up -d --build --wait --wait-timeout 180
    if ($LASTEXITCODE -ne 0) { throw 'The backend did not start. Open Docker Desktop and check docker compose logs.' }
    try {
        $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8000/api/health/' -TimeoutSec 10
    } catch {
        throw 'The API is not answering at http://127.0.0.1:8000/api/health/. Check docker compose ps and docker compose logs api.'
    }
    if ($health.status -ne 'ok') { throw 'The API health check did not report ok.' }

    & $adbPath -s $DeviceId reverse tcp:8000 tcp:8000
    if ($LASTEXITCODE -ne 0) { throw 'Could not forward the API port over USB.' }
    Write-Host 'Backend ready. Keep the phone connected by USB while using this local build.'
    Set-Location (Join-Path $projectRoot 'mobile')
    & flutter build apk --debug --dart-define=API_URL=http://127.0.0.1:8000/api/v1/
    if ($LASTEXITCODE -ne 0) { throw 'Flutter could not build the debug app.' }
    $apkPath = Join-Path $projectRoot 'mobile\build\app\outputs\flutter-apk\app-debug.apk'
    # Never uninstall automatically: a signing conflict must not erase app data.
    & $adbPath -s $DeviceId install -r $apkPath
    if ($LASTEXITCODE -ne 0) { throw 'Could not update BasketWise. Existing app data was preserved; resolve the installation error before retrying.' }
    & $adbPath -s $DeviceId shell am force-stop in.basketwise.mobile
    if ($LASTEXITCODE -ne 0) { throw 'Could not stop the previous BasketWise process.' }
    $launchOutput = @(& $adbPath -s $DeviceId shell am start -n in.basketwise.mobile/.MainActivity 2>&1)
    if ($LASTEXITCODE -ne 0 -or ($launchOutput -match '(?i)Error:|Error type|Exception').Count) {
        throw "Could not launch BasketWise: $($launchOutput -join [Environment]::NewLine)"
    }
    Write-Host 'BasketWise is open on your phone. Use -Attach to connect Flutter debugging and hot reload.'
    if ($Attach) {
        & flutter attach -d $DeviceId
        if ($LASTEXITCODE -ne 0) { throw 'Flutter could not attach to the running app.' }
    }
} finally {
    Pop-Location
}
