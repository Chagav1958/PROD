<#
.SYNOPSIS
    Quick test for GUI parameter panel changes.
    Runs parser and encoding checks only (fast subset of Run-Tests.ps1).
.DESCRIPTION
    Use this after making changes to Prod-GUI.ps1 or Settings-Module.ps1
    to verify that all files still parse and have correct encoding.
#>

Write-Host "=== Quick GUI test (parser + encoding) ===" -ForegroundColor Cyan
$masterTest = "C:\AIS\AI\Prod\scripts\Run-Tests.ps1"
if (Test-Path $masterTest) {
    & powershell -NoProfile -File $masterTest -Quick
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n=== PASSED ===" -ForegroundColor Green
    } else {
        Write-Host "`n=== FAILED ===" -ForegroundColor Red
    }
    exit $LASTEXITCODE
} else {
    Write-Host "ERROR: Run-Tests.ps1 not found" -ForegroundColor Red
    exit 1
}
