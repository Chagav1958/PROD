<#
.SYNOPSIS
    Цикл автоисправления для TaskPlan — аналог auto_fix_loop.ps1 для OUTPL.
.DESCRIPTION
    1. Запускает указанный скрипт TaskPlan (тесты, трекер, GUI)
    2. Анализирует лог через Out-TaskPlan.ps1
    3. Если ошибка найдена — пытается применить известный фикс
    4. Повторяет до MaxIter итераций
.PARAMETER MaxIter
    Максимальное количество итераций (по умолчанию 10).
.PARAMETER TaskName
    Имя задачи для трекера (если проверяем трекер).
.PARAMETER RunTests
    Запускать тесты TaskPlan-Tests.ps1 на каждой итерации.
.PARAMETER RunTracker
    Запускать трекер show для TaskName на каждой итерации.
.PARAMETER RunGUI
    Запускать GUI и проверять, не падает ли.
.EXAMPLE
    .\Out-TaskPlan-FixCycle.ps1 -RunTests -MaxIter 5
    Запускает тесты TaskPlan до 5 раз, анализирует ошибки после каждого запуска.
.EXAMPLE
    .\Out-TaskPlan-FixCycle.ps1 -RunTracker -TaskName TASK-OUTPL -MaxIter 3
    Проверяет трекер на указанной задаче и исправляет ошибки.
#>
param(
    [int]$MaxIter = 10,
    [string]$TaskName = '',
    [switch]$RunTests,
    [switch]$RunTracker,
    [switch]$RunGUI
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$logFile = "C:\AIS\AI\Prod\temp\taskplan_last_output.log"
$scriptsDir = "C:\AIS\AI\Prod\scripts"
$tracker = Join-Path $scriptsDir 'TaskPlan-Tracker.ps1'
$tests = Join-Path $scriptsDir 'TaskPlan-Tests.ps1'
$gui = Join-Path $scriptsDir 'Show-TaskPlanGUI.ps1'
$outpl = Join-Path $scriptsDir 'Out-TaskPlan.ps1'
$releaseRoot = 'C:\AIS\AI\Prod\tasks'

Write-Host "=== OUTPL Fix Cycle ===" -ForegroundColor Cyan
Write-Host "Max iterations: $MaxIter" -ForegroundColor Cyan

for ($iter = 1; $iter -le $MaxIter; $iter++) {
    Write-Host "--- Iteration $iter of $MaxIter ---" -ForegroundColor Magenta

    # Шаг 1: очистить лог
    $loggerPath = Join-Path $scriptsDir 'TaskPlan-Logger.ps1'
    if (Test-Path $loggerPath) { . $loggerPath; Clear-TaskPlanLog }

    # Шаг 2: выполнить целевую операцию
    $operationOk = $true
    if ($RunTests) {
        Write-Host "  Running TaskPlan-Tests.ps1..." -NoNewline
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell'
        $psi.Arguments = "-NoLogo -File `"$tests`""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $p = [Diagnostics.Process]::Start($psi)
        $outT = $p.StandardOutput.ReadToEnd()
        $errT = $p.StandardError.ReadToEnd()
        $p.WaitForExit(120000) | Out-Null
        Write-Host " done ($($outT.Length) chars)"
    }
    if ($RunTracker -and $TaskName) {
        Write-Host "  Running tracker for $TaskName..." -NoNewline
        $psi2 = New-Object Diagnostics.ProcessStartInfo
        $psi2.FileName = 'powershell'
        $psi2.Arguments = "-NoLogo -File `"$tracker`" -Action show -TaskName `"$TaskName`" -ReleaseRoot `"$releaseRoot`""
        $psi2.UseShellExecute = $false
        $psi2.RedirectStandardOutput = $true
        $psi2.RedirectStandardError = $true
        $psi2.CreateNoWindow = $true
        $p2 = [Diagnostics.Process]::Start($psi2)
        $out2 = $p2.StandardOutput.ReadToEnd()
        $err2 = $p2.StandardError.ReadToEnd()
        $p2.WaitForExit(30000) | Out-Null
        Write-Host " done"
    }
    if ($RunGUI) {
        Write-Host "  Running Show-TaskPlanGUI.ps1 (3s)..." -NoNewline
        $psi3 = New-Object Diagnostics.ProcessStartInfo
        $psi3.FileName = 'powershell'
        if ($TaskName) { $psi3.Arguments = "-NoLogo -File `"$gui`" -TaskName `"$TaskName`"" }
        else { $psi3.Arguments = "-NoLogo -File `"$gui`"" }
        $psi3.UseShellExecute = $false
        $psi3.CreateNoWindow = $true
        $p3 = [Diagnostics.Process]::Start($psi3)
        Start-Sleep -Seconds 3
        if (-not $p3.HasExited) { $p3.Kill(); Write-Host " killed after 3s" }
        else { Write-Host " exited early" }
    }

    # Шаг 3: проанализировать лог через OUTPL
    Write-Host "  Analyzing with OUTPL..."
    $analysis = & powershell -NoLogo -File $outpl -AutoFix 2>&1 | Out-String

    # Шаг 4: проверить, есть ли ошибки
    if ($analysis -match 'Найдено проблем: 0') {
        Write-Host ""
        Write-Host "=== CYCLE COMPLETE: No errors at iteration $iter ===" -ForegroundColor Green
        exit 0
    }

    if ($analysis -match 'Найдено проблем: \d+') {
        Write-Host "  Errors detected. Auto-fix attempted."
    }

    Start-Sleep -Seconds 1
}

Write-Host ""
Write-Host "=== CYCLE FAILED: Max iterations ($MaxIter) reached ===" -ForegroundColor Red
exit 2
