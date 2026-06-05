# Deploy Firestore security rules for Safe Hair chat (project: safe-hair-274).
# Run from repo:  powershell -File mobile_app\scripts\deploy_firestore_rules.ps1

$ErrorActionPreference = 'Stop'
$mobileApp = Split-Path $PSScriptRoot -Parent
Set-Location $mobileApp

$npmCandidates = @(
  'C:\Program Files\nodejs\npm.cmd',
  "$env:ProgramFiles\nodejs\npm.cmd",
  "$env:APPDATA\npm\npm.cmd"
)

$npm = $npmCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $npm) {
  Write-Host ''
  Write-Host 'Node.js/npm was not found on this PC.' -ForegroundColor Yellow
  Write-Host 'Deploy rules manually:' -ForegroundColor Cyan
  Write-Host '  1. Open https://console.firebase.google.com/project/safe-hair-274/firestore/rules'
  Write-Host '  2. Copy all text from:  firebase\firestore.rules  (repo root, next to mobile_app)'
  Write-Host '  3. Paste into the editor and click Publish'
  Write-Host ''
  exit 1
}

Write-Host "Using npm: $npm"
& $npm exec --yes firebase-tools -- deploy --only firestore:rules
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host 'Firestore rules deployed successfully.' -ForegroundColor Green
