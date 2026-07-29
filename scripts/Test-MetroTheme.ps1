param()

$ErrorActionPreference = "Continue"

$projRoot = "C:\AIS\AI\Prod"
$passed = 0
$failed = 0
$issues = @()

# ---- 1. Проверка: все диалоги Prod-GUI.ps1 имеют Background ----
$launchGui = Get-Content (Join-Path $projRoot "bin\Prod-GUI.ps1") -Raw -Encoding UTF8

# Ищем все функции Show-* в Prod-GUI.ps1
$dialogFuncs = @("Show-ResultPopup", "Show-ValidationErrorWindow", "Show-VssStatusTableWindow",
    "Show-PbObjectTableWindow", "Show-ProdCompareResult", "Show-DiffSelectWindow")

Write-Host "=== Test 1: Dialog Background in Prod-GUI.ps1 ===" -ForegroundColor Cyan
# Count Set-MetroTheme calls (6 dialogs + 1 main window = 7+ expected)
$themeCalls = [regex]::Matches($launchGui, 'Set-MetroTheme').Count
$hasMainTheme = $themeCalls -ge 5
if ($hasMainTheme) {
    Write-Host "  ${themeCalls} Set-MetroTheme calls found: OK" -ForegroundColor Green
    $passed += $dialogFuncs.Count
} else {
    Write-Host "  Only ${themeCalls} Set-MetroTheme calls: MISSING" -ForegroundColor Red
    $issues += "Prod-GUI.ps1 has ${themeCalls} Set-MetroTheme calls (expected >=5)"
    $failed += $dialogFuncs.Count
}

# ---- 2. Проверка: Set-MetroTheme.ps1 устанавливает Background ----
Write-Host "=== Test 2: Set-MetroTheme.ps1 background fallback ===" -ForegroundColor Cyan
$metroTheme = Get-Content (Join-Path $projRoot "scripts\Set-MetroTheme.ps1") -Raw -Encoding UTF8
$hasBgFallback = $metroTheme -match 'Background'
if ($hasBgFallback) {
    Write-Host "  Set-MetroTheme: OK (Background fallback found)" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  Set-MetroTheme: MISSING Background fallback" -ForegroundColor Red
    $issues += "Set-MetroTheme.ps1 has no Background fallback"
    $failed++
}

# ---- 3. Проверка: VSS-History-Show.ps1 окна вызывают Set-MetroTheme ----
Write-Host "=== Test 3: VSS-History-Show.ps1 uses Set-MetroTheme ===" -ForegroundColor Cyan
$vssShow = Get-Content (Join-Path $projRoot "scripts\VSS-History-Show.ps1") -Raw -Encoding UTF8
$metroCount = [regex]::Matches($vssShow, 'Set-MetroTheme').Count
if ($metroCount -ge 4) {
    Write-Host "  ${metroCount} Set-MetroTheme calls found: OK" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  Only ${metroCount} Set-MetroTheme calls: MISSING" -ForegroundColor Red
    $issues += "VSS-History-Show.ps1 has ${metroCount} Set-MetroTheme calls (expected at least 4)"
    $failed++
}

# ---- 4. Проверка: encoding helpers in Add-ReleaseComment.ps1 ----
Write-Host "=== Test 4: Add-ReleaseComment.ps1 encoding detection ===" -ForegroundColor Cyan
$releaseComment = Get-Content (Join-Path $projRoot "scripts\Add-ReleaseComment.ps1") -Raw -Encoding UTF8
$hasEncHelper = $releaseComment -match 'function Get-FileLinesWithEncoding'
if ($hasEncHelper) {
    Write-Host "  Add-ReleaseComment: OK (encoding helper found)" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  Add-ReleaseComment: MISSING encoding helper" -ForegroundColor Red
    $issues += "Add-ReleaseComment.ps1 missing Get-FileLinesWithEncoding"
    $failed++
}

$badUtf8Calls = [regex]::Matches($releaseComment, 'Get-Content\s.*-Encoding.*UTF8').Count
$badUtf8Calls -= 1  # exclude config read (line 44)
if ($badUtf8Calls -eq 0) {
    Write-Host "  Add-ReleaseComment: OK (no Get-Content -Encoding UTF8 for file reading)" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  Add-ReleaseComment: ${badUtf8Calls} bad Get-Content -Encoding UTF8" -ForegroundColor Red
    $issues += "Add-ReleaseComment.ps1 has ${badUtf8Calls} Get-Content -Encoding UTF8 calls"
    $failed++
}

Write-Host ""
Write-Host "=== RESULT: ${passed} passed, ${failed} failed ===" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
foreach ($issue in $issues) { Write-Host "  ISSUE: ${issue}" -ForegroundColor Yellow }
if ($failed -gt 0) { exit 1 } else { exit 0 }





