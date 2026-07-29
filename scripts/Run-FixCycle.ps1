param(
    [int]$MaxIter = 100,
    [string]$VssPass = "12345"
)

$ErrorActionPreference = "Continue"
$projRoot = "C:\AIS\AI\Prod"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Run-FixCycle: Testing background + encoding" -ForegroundColor Cyan
Write-Host "  Max iterations: ${MaxIter}" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$tests = @(
    @{ Name = "Test-MetroTheme"; Script = "scripts\Test-MetroTheme.ps1"; Args = @() },
    @{ Name = "Test-VssEncoding (Quick)"; Script = "scripts\Test-VssEncoding.ps1"; Args = @("-Quick", "-VssPass", $VssPass) },
    @{ Name = "Test-VssEncoding (Extract)"; Script = "scripts\Test-VssEncoding.ps1"; Args = @("-MaxObjects", "3", "-VssPass", $VssPass) }
)

for ($iter = 1; $iter -le $MaxIter; $iter++) {
    Write-Host "--- Iteration ${iter} / ${MaxIter} ---" -ForegroundColor Magenta
    $allPassed = $true
    foreach ($test in $tests) {
        $scriptPath = Join-Path $projRoot $test.Script
        Write-Host "  Running $($test.Name)..." -NoNewline
        $testArgs = $test.Args
        if ($testArgs) { $output = & powershell -NoProfile -File $scriptPath @testArgs 2>&1 }
        else { $output = & powershell -NoProfile -File $scriptPath 2>&1 }
        $exitCode = $LASTEXITCODE
        $outStr = $output | Out-String
        if ($exitCode -eq 0) {
            Write-Host " PASS" -ForegroundColor Green
        } else {
            $lines = $outStr -split "`r`n|`n"
            Write-Host " FAIL (exit: $exitCode)" -ForegroundColor Red
            $lines | Where-Object { $_.Trim() -ne '' } | Select-Object -First 5 | ForEach-Object { Write-Host "    $_" }
            $allPassed = $false
        }
    }
    if ($allPassed) {
        Write-Host ""
        Write-Host "=== CYCLE COMPLETE: All tests passed at iteration $iter ===" -ForegroundColor Green
        exit 0
    }
    Write-Host ""
}

Write-Host ""
Write-Host "=== CYCLE FAILED: Max iterations ($MaxIter) reached ===" -ForegroundColor Red
exit 2


