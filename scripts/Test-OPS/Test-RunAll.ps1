param(
    [string]$TaskName = "SYBASE-19371",
    [int]$TimeoutSec = 300,
    [switch]$ContinueOnFail,
    [switch]$ShowDetails
)

$ErrorActionPreference = "Continue"
$script:rootDir = "C:\AIS\AI\Prod"
$testLog = "$rootDir\temp\test_runall_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$resultsJson = "$rootDir\temp\test_runall_results.json"

function Write-TestLog {
    param([string]$msg, [string]$color = $null)
    $line = "$(Get-Date -Format 'HH:mm:ss') $msg"
    if ($color) { Write-Host $line -ForegroundColor $color } else { Write-Host $line }
    $line | Out-File $testLog -Append -Encoding UTF8
}

# Список тестов
$tests = @(
    @{ Name = "OP04-Collect-PROD"; Script = "$rootDir\scripts\Test-OPS\Test-OP04.ps1"; OpName = "Collect PROD Objects" },
    @{ Name = "OP10-Create-RFC"; Script = "$rootDir\scripts\Test-OPS\Test-OP10.ps1"; OpName = "Create RFC in Jira" },
    @{ Name = "OP11-Jira-Comment"; Script = "$rootDir\scripts\Test-OPS\Test-OP11.ps1"; OpName = "Jira Release Comment" },
    @{ Name = "OP13-VSS-Status"; Script = "$rootDir\scripts\Test-OPS\Test-OP13.ps1"; OpName = "VSS: Check Status" },
    @{ Name = "OP18-VSS-History"; Script = "$rootDir\scripts\Test-OPS\Test-OP18.ps1"; OpName = "VSS: Object History" }
)

Write-TestLog "=== Test Run All Operations ===" "Cyan"
Write-TestLog "TaskName: $TaskName"
Write-TestLog "Timeout: ${TimeoutSec}s per test"
Write-TestLog "ContinueOnFail: $ContinueOnFail"
Write-TestLog ""

$results = @()
$passed = 0
$failed = 0

foreach ($test in $tests) {
    Write-TestLog "========================================"
    Write-TestLog "Running: $($test.Name)" "Yellow"
    Write-TestLog "========================================"

    if (-not (Test-Path $test.Script)) {
        Write-TestLog "ERROR: Script not found: $($test.Script)" "Red"
        $results += @{
            Name = $test.Name
            OpName = $test.OpName
            Status = "SKIP"
            Error = "Script not found"
            Duration = 0
        }
        $failed++
        continue
    }

    $testLogTest = "$rootDir\temp\test_$($test.Name)_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    $argStr = "-NoLogo -ExecutionPolicy Bypass -File `"$($test.Script)`" -TaskName `"$TaskName`" -TimeoutSec $TimeoutSec"
    if ($ShowDetails) { $argStr += " -ShowDetails" }

    $start = Get-Date
    $proc = Start-Process -FilePath powershell.exe -ArgumentList $argStr -PassThru -Wait -NoNewWindow
    $duration = ((Get-Date) - $start).TotalSeconds

    $exitCode = $proc.ExitCode
    $status = if ($exitCode -eq 0) { "PASS" } else { "FAIL" }

    if ($status -eq "PASS") {
        $passed++
        Write-TestLog "RESULT: $($test.Name) - PASS" "Green"
    } else {
        $failed++
        Write-TestLog "RESULT: $($test.Name) - FAIL (exit code: $exitCode)" "Red"
        if (-not $ContinueOnFail) {
            Write-TestLog "Stopping due to ContinueOnFail=false" "Red"
            break
        }
    }

    $results += @{
        Name = $test.Name
        OpName = $test.OpName
        Status = $status
        ExitCode = $exitCode
        Duration = [Math]::Round($duration, 1)
    }

    Write-TestLog ""
}

# Итоги
Write-TestLog "========================================" "Cyan"
Write-TestLog "=== SUMMARY ===" "Cyan"
Write-TestLog "========================================"
Write-TestLog "Total: $($tests.Count)"
Write-TestLog "Passed: $passed" "Green"
Write-TestLog "Failed: $failed" $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-TestLog ""
Write-TestLog "Log: $testLog"

# Детали по провалившимся
$failedTests = $results | Where-Object { $_.Status -eq "FAIL" }
if ($failedTests) {
    Write-TestLog ""
    Write-TestLog "=== FAILED TESTS ===" "Red"
    foreach ($ft in $failedTests) {
        Write-TestLog "  $($ft.Name) ($($ft.OpName)) - exit code: $($ft.ExitCode)"
    }
}

# Сохранение результатов
$results | ConvertTo-Json -Depth 3 | Out-File -FilePath $resultsJson -Encoding UTF8
Write-TestLog ""
Write-TestLog "Results JSON: $resultsJson"

exit $(if ($failed -gt 0) { 1 } else { 0 })
