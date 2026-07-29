param(
    [string]$TaskName = "SYBASE-19371",
    [int]$TimeoutSec = 300,
    [switch]$SkipDialogs,
    [switch]$ShowDetails
)

$script:rootDir = "C:\AIS\AI\Prod"
$logFile = "$rootDir\temp\last_output.log"
$testLog = "$rootDir\temp\test_all_ops_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$debugLog = "$env:TEMP\ais_gui_debug.log"

function Write-TestLog {
    param([string]$msg)
    $line = "$(Get-Date -Format 'HH:mm:ss') $msg"
    Write-Host $line
    $line | Out-File $testLog -Append -Encoding UTF8
}

function Test-Operation {
    param([string]$OpName, [hashtable]$Params = @{})

    Write-TestLog "=== Testing: $OpName ==="

    # Очистка предыдущих логов
    if (Test-Path $debugLog) { Remove-Item $debugLog -Force -EA SilentlyContinue }
    if (Test-Path $logFile) { Remove-Item $logFile -Force -EA SilentlyContinue }

    # Остановка предыдущих процессов
    Get-Process powershell -EA SilentlyContinue | Where-Object { $_.MainWindowTitle -match "AIS|Prod" } | Stop-Process -Force -EA SilentlyContinue
    Start-Sleep -Seconds 2

    # Формирование параметров
    $argStr = "-NoLogo -ExecutionPolicy Bypass -File `"$rootDir\bin\Prod-GUI.ps1`" -AutoRun -OpName `"$OpName`""
    if ($TaskName) { $argStr += " -TaskName `"$TaskName`"" }
    foreach ($k in $Params.Keys) {
        $argStr += " -$k `"$($Params[$k])`""
    }

    Write-TestLog "  Params: $argStr"

    $start = Get-Date
    $proc = Start-Process -FilePath powershell.exe -ArgumentList $argStr -PassThru
    Write-TestLog "  Process started: $($proc.Id)"

    $waited = 0
    $success = $false
    while (-not $proc.HasExited -and $waited -lt $TimeoutSec) {
        Start-Sleep -Seconds 5
        $waited += 5
        if ($ShowDetails -and $waited % 30 -eq 0) {
            Write-TestLog "  Still running... ${waited}s"
        }
    }

    $result = @{
        OpName = $OpName
        Success = $false
        ExitCode = $null
        Duration = $waited
        Error = $null
        LogPreview = $null
    }

    if ($proc.HasExited) {
        $result.ExitCode = $proc.ExitCode
        Write-TestLog "  Exited with code: $($proc.ExitCode)"
    } else {
        Write-TestLog "  TIMEOUT after ${TimeoutSec}s"
        Stop-Process -Id $proc.Id -Force -EA SilentlyContinue
        $result.Error = "Timeout"
    }

    # Анализ лога
    if (Test-Path $logFile) {
        $log = Get-Content $logFile -Raw -Encoding UTF8
        $result.LogPreview = $log.Substring(0, [Math]::Min(500, $log.Length))

        if ($log -match "ERROR:|Exception:|###ERROR###") {
            $result.Error = "Errors in log"
            Write-TestLog "  RESULT: FAIL (errors found)"
        } elseif ($log -match "AutoRun.*Run clicked") {
            $result.Success = $true
            Write-TestLog "  RESULT: PASS (AutoRun executed)"
        } elseif ($proc.HasExited -and $proc.ExitCode -eq 0) {
            $result.Success = $true
            Write-TestLog "  RESULT: PASS (exit code 0)"
        } else {
            Write-TestLog "  RESULT: UNKNOWN (check log manually)"
        }

        if ($ShowDetails) {
            Write-TestLog "  Log preview:"
            ($log -split "`n" | Select-Object -First 10) | ForEach-Object { Write-TestLog "    $_" }
        }
    } else {
        Write-TestLog "  RESULT: FAIL (no log file)"
        $result.Error = "No log file"
    }

    Write-TestLog ""
    return [PSCustomObject]$result
}

# Получение списка операций
Write-TestLog "=== Getting operations list ==="
$guiContent = Get-Content "$rootDir\bin\Prod-GUI.ps1" -Raw -Encoding UTF8
$opsText = $guiContent.Substring($guiContent.IndexOf('$operations = @('))
$opsText = $opsText.Substring(0, $opsText.IndexOf('"Operations defined:'))
$rx = [regex]::new('(?m)^(?:[ \t]*@\{|,[ \t]*@\{)')
$allBlocks = $rx.Split($opsText)

$operations = @()
foreach ($block in $allBlocks) {
    if ($block -match 'Name\s*=\s*"([^"]+)' -and $block -match 'RusName\s*=') {
        $operations += $matches[1]
    }
}
Write-TestLog "Found $($operations.Count) operations"
Write-TestLog ""

# Тестирование каждой операции
$results = @()
$passCount = 0
$failCount = 0

foreach ($opName in $operations) {
    # Skip операции с диалогами если указано
    if ($SkipDialogs -and ($opName -match "History|Compare|Diff|Select")) {
        Write-TestLog "SKIP (dialog): $opName"
        Write-TestLog ""
        continue
    }

    $r = Test-Operation -OpName $opName
    $results += $r
    if ($r.Success) { $passCount++ } else { $failCount++ }
}

# Итоги
Write-TestLog "=== SUMMARY ==="
Write-TestLog "Total: $($operations.Count), Passed: $passCount, Failed: $failCount"
Write-TestLog ""

# Детали по провалившимся
$failed = $results | Where-Object { -not $_.Success }
if ($failed) {
    Write-TestLog "=== FAILED OPERATIONS ==="
    foreach ($f in $failed) {
        Write-TestLog "  $($f.OpName): $($f.Error) (exited:$($f.ExitCode), took:$($f.Duration)s)"
    }
}

Write-TestLog ""
Write-TestLog "Log saved to: $testLog"

# Сохранение результатов в JSON
$resultsJson = $results | Select-Object OpName, Success, ExitCode, Duration, Error | ConvertTo-Json -Depth 3
$resultsJson | Out-File -FilePath "$rootDir\temp\test_all_ops_results.json" -Encoding UTF8
Write-TestLog "Results JSON: $rootDir\temp\test_all_ops_results.json"
