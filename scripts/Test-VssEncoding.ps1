param(
    [string]$VssDb = "\\ren-msksf01\VSS2005\srcsafe.ini",
    [string]$VssUser = "vchaga",
    [string]$VssPass = "",
    [int]$MaxObjects = 5,
    [switch]$Quick
)

$ErrorActionPreference = "Continue"
$thisDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projRoot = Split-Path -Parent $thisDir
. (Join-Path $projRoot "scripts\VSS-History.ps1")
$passed = 0; $failed = 0; $issues = @()

# ======== Test A: Get-VssVersionFile encoding detection ========
Write-Host "=== Test A: Get-VssVersionFile encoding detection ===" -ForegroundColor Cyan
# Check that function detects UTF-16LE without BOM, UTF-8 BOM, and CP1251
$funcText = (Get-Content (Join-Path $projRoot "scripts\VSS-History.ps1") -Raw -Encoding UTF8)
$hasUtf16NoBom = $funcText -match "isUtf16LeNoBom"
$hasCp1251 = $funcText -match "GetEncoding\(1251\)"
$hasUtf8Bom = $funcText -match "hasUtf8Bom"
$hasUtf16Bom = $funcText -match "hasUtf16Bom"

if ($hasUtf16NoBom) { Write-Host "  UTF-16LE no-BOM detection: OK" -ForegroundColor Green; $passed++ }
else { Write-Host "  UTF-16LE no-BOM detection: MISSING" -ForegroundColor Red; $issues += "VSS-History.ps1 lacks UTF-16LE no-BOM detection"; $failed++ }

if ($hasCp1251) { Write-Host "  CP1251 fallback: OK" -ForegroundColor Green; $passed++ }
else { Write-Host "  CP1251 fallback: MISSING" -ForegroundColor Red; $issues += "VSS-History.ps1 lacks CP1251 fallback"; $failed++ }

if ($hasUtf8Bom -and $hasUtf16Bom) { Write-Host "  BOM detection: OK" -ForegroundColor Green; $passed++ }
else { Write-Host "  BOM detection: MISSING" -ForegroundColor Red; $issues += "VSS-History.ps1 lacks BOM detection"; $failed++ }

# ======== Test B: VSS extraction Cyrillic check (only if not -Quick) ========
if (-not $Quick) {
    Write-Host "=== Test B: VSS extraction Cyrillic check ===" -ForegroundColor Cyan
    $pbCurrent = "C:\AIS\AI\Prod\PB_Current"
    $allFiles = Get-ChildItem "$pbCurrent\golden_commission" -File -Filter "w_*.sr?" -ErrorAction SilentlyContinue | Select-Object -First $MaxObjects
    if ($allFiles.Count -eq 0) {
        Write-Host "  SKIP: no golden_commission/w_* found" -ForegroundColor Yellow
        $passed++
    } else {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "vss_enc_$(Get-Random -Maximum 99999)"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        try {
            foreach ($f in $allFiles) {
                $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
                $ext = $f.Extension
                $vssPath = "$/SRC125/gold/golden_commission/$($base)$($ext)"
                Write-Host "  golden_commission/$base$ext..." -NoNewline
                try {
                    $history = Get-VssHistory -VssPath $vssPath -VssDb $VssDb -VssUser $VssUser -VssPass $VssPass -MaxVersions 1
                    if ($history.Count -eq 0) { Write-Host " NO HIST" -ForegroundColor Yellow; continue }
                    $file = Get-VssVersionFile -VssPath $vssPath -Version $history[0].Version -VssDb $VssDb -VssUser $VssUser -VssPass $VssPass -OutputDir $tempDir
                    if (-not $file -or -not (Test-Path $file)) { Write-Host " NOT EXT" -ForegroundColor Yellow; $failed++; continue }
                    $bytes = [System.IO.File]::ReadAllBytes($file)
                    $hasBom = $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE
                    if (-not $hasBom) {
                        Write-Host " NO BOM" -ForegroundColor Red
                            $issues += "${base}${ext}: no UTF-16LE BOM after conversion"
                        $failed++
                    } else {
                        Write-Host " v$($history[0].Version) UTF16-BOM OK" -ForegroundColor Green
                        $passed++
                    }
                } catch { Write-Host " ERR: $($_.Exception.Message)" -ForegroundColor Red; $failed++ }
            }
        } finally { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
} else {
    Write-Host "=== Test B: SKIP (Quick mode) ===" -ForegroundColor Yellow; $passed++
}

# ======== Test C: Get-FileLinesWithEncoding in Add-ReleaseComment ========
Write-Host "=== Test C: Add-ReleaseComment.ps1 encoding fix ===" -ForegroundColor Cyan
$arcPath = Join-Path $projRoot "scripts\Add-ReleaseComment.ps1"
if (Test-Path $arcPath) {
    $arcText = Get-Content $arcPath -Raw -Encoding UTF8
    $hasEncFunc = $arcText -match "function Get-FileLinesWithEncoding"
    $badUtf8Calls = [regex]::Matches($arcText, "Get-Content\s.*-Encoding.*UTF8").Count
    $badUtf8Calls -= 1  # exclude config read (line 44)
    if ($hasEncFunc) { Write-Host "  Get-FileLinesWithEncoding: OK" -ForegroundColor Green; $passed++ }
    else { Write-Host "  Get-FileLinesWithEncoding: MISSING" -ForegroundColor Red; $issues += "Missing Get-FileLinesWithEncoding"; $failed++ }
    if ($badUtf8Calls -eq 0) { Write-Host "  No Get-Content -Encoding UTF8: OK" -ForegroundColor Green; $passed++ }
    else { Write-Host "  Has ${badUtf8Calls} Get-Content -Encoding UTF8: FAIL" -ForegroundColor Red; $issues += "Add-ReleaseComment.ps1 has ${badUtf8Calls} Get-Content -Encoding UTF8"; $failed++ }
} else {
    Write-Host "  SKIP: Add-ReleaseComment.ps1 not found" -ForegroundColor Yellow; $passed++
}

Write-Host ""
Write-Host "=== RESULT: ${passed} passed, ${failed} failed ===" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
foreach ($issue in $issues) { Write-Host "  ISSUE: ${issue}" -ForegroundColor Yellow }
if ($failed -gt 0) { exit 1 } else { exit 0 }



