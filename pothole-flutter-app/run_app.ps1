# Runs the app on a connected Android phone.
#
#   .\run_app.ps1          USB: forwards the phone's port 8000 to this PC, then runs the app.
#   .\run_app.ps1 -Wifi    Wi-Fi: builds the app to use this PC's network address instead,
#                          so it keeps working after the cable is unplugged.
param([switch]$Wifi)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $adb) { $adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe" }
if (-not (Test-Path $adb)) { throw "adb not found. Install Android platform-tools or add them to PATH." }

$devices = & $adb devices | Select-Object -Skip 1 | Where-Object { $_.Trim() }
if (-not $devices) { throw "No phone found. Connect it by USB and turn on USB debugging." }
if ($devices -match "unauthorized") { throw "Phone is not authorized. Unlock it and tap Allow on the USB debugging prompt." }

try {
  Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 "http://127.0.0.1:8000/health" | Out-Null
} catch {
  Write-Warning "The backend is not answering on port 8000. Start it first: ..\pothole-detection-app\scripts\run_backend.ps1"
}

if ($Wifi) {
  # The adapter that carries the internet connection, not a virtual or link-local one.
  $config = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq "Up" } | Select-Object -First 1
  $ip = $config.IPv4Address.IPAddress | Select-Object -First 1
  if (-not $ip) { throw "Could not find this PC's network address. Is Wi-Fi connected?" }

  # Both devices must be on the same network, or the phone can never reach the PC.
  $phoneIp = ((& $adb shell "ip -4 addr show wlan0") -join " ") -replace '.*inet (\d+\.\d+\.\d+\.\d+).*', '$1'
  if ($phoneIp -match '^\d+\.\d+\.\d+\.\d+$') {
    $pcNet = ($ip -split '\.')[0..2] -join '.'
    $phoneNet = ($phoneIp -split '\.')[0..2] -join '.'
    if ($pcNet -ne $phoneNet) {
      throw ("The phone ($phoneIp) and this PC ($ip) are on different networks, so the phone cannot " +
        "reach the backend. Connect both to the same Wi-Fi, or run .\run_app.ps1 without -Wifi to use USB.")
    }
  } else {
    Write-Warning "Could not read the phone's Wi-Fi address. Make sure it is on the same Wi-Fi as this PC ($ip)."
  }

  Write-Host "Using backend at http://${ip}:8000"
  flutter run "--dart-define=API_BASE_URL=http://${ip}:8000"
} else {
  & $adb reverse tcp:8000 tcp:8000 | Out-Null
  Write-Host "Forwarding phone port 8000 to this PC over USB (lost if the cable is unplugged)"
  flutter run
}
