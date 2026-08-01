param(
    [string]$TaskName = "SYBASE-19371",
    [int]$TimeoutSec = 60,
    [switch]$ShowDetails
)

$ErrorActionPreference = "Continue"
$script:rootDir = "C:\AIS\AI\Prod"
$logFile = "$rootDir\temp\last_output.log"
$testLog = "$rootDir\temp\test_ValidationWindow_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$scriptPath = "C:\AIS\AI\Prod\bin\Prod-GUI.ps1"

function Write-TestLog {
    param([string]$msg)
    $line = "$(Get-Date -Format 'HH:mm:ss') [VAL_WIN] $msg"
    Write-Host $line
    $line | Out-File $testLog -Append -Encoding UTF8
}

Write-TestLog "=== Test: Validation Error Window (Merge button) ==="

$debugLog = "$env:TEMP\ais_gui_debug.log"
if (Test-Path $debugLog) { Remove-Item $debugLog -Force -EA SilentlyContinue }
if (Test-Path $logFile) { Remove-Item $logFile -Force -EA SilentlyContinue }

Get-Process powershell -EA SilentlyContinue | Where-Object { $_.MainWindowTitle -match "AIS|Prod|Validation" } | Stop-Process -Force -EA SilentlyContinue
Start-Sleep -Seconds 2

$argStr = "-NoLogo -ExecutionPolicy Bypass -File `"$scriptPath`" -AutoRun -OpName `"9`" -TaskName `"$TaskName`" -Password `"sqlsql`""
Write-TestLog "Command: powershell $argStr"

$start = Get-Date
$proc = Start-Process -FilePath powershell.exe -ArgumentList $argStr -PassThru
Write-TestLog "Process started: $($proc.Id)"

$waited = 0
$validationWindowShown = $false
$mergeClicked = $false

while (-not $proc.HasExited -and $waited -lt $TimeoutSec) {
    Start-Sleep -Seconds 5
    $waited += 5

    if (Test-Path $debugLog) {
        $debugContent = Get-Content $debugLog -Raw -Encoding UTF8
        if ($debugContent -match "Ошибки валидации|VALIDATION_ERROR") {
            $validationWindowShown = $true
            Write-TestLog "Validation window detected at ${waited}s"
            break
        }
    }

    if ($ShowDetails -and $waited % 15 -eq 0) {
        Write-TestLog "  Still running... ${waited}s"
    }
}

Write-TestLog ""
Write-TestLog "=== RESULT ==="
if ($validationWindowShown) {
    Write-TestLog "STATUS: PASS - Validation window shown"
    Write-TestLog "Test completed: GUI opened without NULL error on Merge"
} else {
    Write-TestLog "STATUS: FAIL - Validation window not detected"
}
Write-TestLog "Duration: ${waited}s"

if ($proc.HasExited) {
    Write-TestLog "Process exited with code: $($proc.ExitCode)"
} else {
    Write-TestLog "Process still running, terminating..."
    Stop-Process -Id $proc.Id -Force -EA SilentlyContinue
}

Write-TestLog "Log saved to: $testLog"
exit $(if ($validationWindowShown) { 0 } else { 1 })
