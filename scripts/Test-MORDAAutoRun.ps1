﻿param(
    [string]$OpName = "Сравнение PB: Current и Main",
    [string]$TaskName = "SYBASE-19371",
    [string]$OutputFile = "C:\AIS\AI\Prod\compare_pb_report.txt",
    [int]$TimeoutSec = 300
)

$logFile = "C:\AIS\AI\Prod\temp\last_output.log"
$testLog = "C:\AIS\AI\Prod\temp\autorun_test.log"

$start = Get-Date
"$start Starting AutoRun test" | Out-File $testLog

$errLog = "$env:TEMP\ais_gui_debug.log"
if (Test-Path $errLog) { Remove-Item $errLog -Force -EA SilentlyContinue }

Get-Process powershell -EA SilentlyContinue | Where-Object { $_.MainWindowTitle -match "AIS|Prod" } | Stop-Process -Force
Start-Sleep -Seconds 2

$proc = Start-Process -FilePath powershell.exe -ArgumentList "-NoLogo -ExecutionPolicy Bypass -File `"C:\AIS\AI\Prod\bin\Prod-GUI.ps1`" -AutoRun -OpName `"$OpName`" -TaskName $TaskName -OutputFile `"$OutputFile`"" -PassThru
"Started process $($proc.Id)" | Out-File $testLog -Append

$waited = 0
while (-not $proc.HasExited -and $waited -lt $TimeoutSec) {
    Start-Sleep -Seconds 5
    $waited += 5
    "$((Get-Date)) waited ${waited}s, still running" | Out-File $testLog -Append
}

if ($proc.HasExited) {
    "Process exited with code $($proc.ExitCode)" | Out-File $testLog -Append
} else {
    "Timeout reached ($TimeoutSec sec), terminating" | Out-File $testLog -Append
    Stop-Process -Id $proc.Id -Force -EA SilentlyContinue
}

Start-Sleep -Seconds 3

$end = Get-Date
"$end Test completed" | Out-File $testLog -Append

if (Test-Path $logFile) {
    $log = Get-Content $logFile -Raw
    "=== LAST OUTPUT LOG ===" | Out-File $testLog -Append
    Get-Content $logFile | Select-Object -Last 50 | Out-File $testLog -Append
    
    if ($log -match "VALIDATION_ERROR") {
        "RESULT: VALIDATION_ERROR found" | Out-File $testLog -Append
    } else {
        "RESULT: VALIDATION_ERROR NOT found" | Out-File $testLog -Append
    }
    
    if ($log -match "AutoRun.*Run clicked") {
        "RESULT: AutoRun executed successfully" | Out-File $testLog -Append
    } else {
        "RESULT: AutoRun may not have executed" | Out-File $testLog -Append
    }
    
    if ($log -match "Fatal:|Exception:") {
        "RESULT: ERRORS found in log" | Out-File $testLog -Append
    }
}

$testLog
