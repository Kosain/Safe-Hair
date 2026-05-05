# Safe Hair - Wireless Android Connect (run in PowerShell)
# Phone: Settings > Developer options > Wireless debugging ON

$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    $adb = "adb"
}

Write-Host "`n=== Wireless Android Connect ===" -ForegroundColor Green
Write-Host "On your phone: Open Wireless debugging, tap 'Pair device with pairing code'`n"

$pair = Read-Host "Enter pair address (e.g. 192.168.1.10:37123)"
if ($pair) {
    & $adb pair $pair
    Write-Host "`nNow on phone: Check 'Device IP address' (e.g. 192.168.1.10:5555)`n"
}

$connect = Read-Host "Enter connect address (e.g. 192.168.1.10:5555)"
if ($connect) {
    & $adb connect $connect
    & $adb devices
    Write-Host "`nDone! Run: flutter run" -ForegroundColor Green
}
