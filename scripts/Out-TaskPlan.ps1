<#
.SYNOPSIS
    OUTPL — анализ лога taskplan_last_output.log, диагностика и автоисправление ошибок TaskPlan.
.DESCRIPTION
    Читает temp\taskplan_last_output.log и temp\taskplan_gui_log.log, распознаёт 9 типов ошибок,
    выдаёт [ERROR]+[FIX] по каждому типу. С -AutoFix убивает зависшие GUI-процессы.
    Сохраняет отчёт в temp\taskplan_outpl_report.txt.
.PARAMETER AutoFix
    Автоматически исправлять найденные ошибки (убивать зависшие процессы GUI).
#>
param([switch]$AutoFix)

$ErrorActionPreference = 'Stop'
$scriptPath = Split-Path $PSCommandPath -Parent
$prodRoot = 'C:\AIS\AI\Prod'
$logFile = Join-Path $prodRoot 'temp\taskplan_last_output.log'
$guiLogFile = Join-Path $prodRoot 'temp\taskplan_gui_log.log'
$reportFile = Join-Path $prodRoot 'temp\taskplan_outpl_report.txt'
$trackerPath = Join-Path $scriptPath 'TaskPlan-Tracker.ps1'
$guiPath = Join-Path $scriptPath 'Show-TaskPlanGUI.ps1'

$loggerPath = Join-Path $scriptPath 'TaskPlan-Logger.ps1'
if (Test-Path $loggerPath) { . $loggerPath }

$report = New-Object Collections.Generic.List[string]

function Write-Report {
    param([string]$Line)
    $report.Add($Line)
    Write-Host $Line
}

function Read-LogFile {
    if (-not (Test-Path $logFile)) { return @() }
    return Get-Content -LiteralPath $logFile -Encoding UTF8 -ErrorAction SilentlyContinue
}

# ── Определение ошибок ──
$errors = @()

# Тип 1: TASK_PATH_ERROR — ошибка пути задачи
$logLines = Read-LogFile
$hasTaskPathError = ($logLines | Where-Object { $_ -match 'TASK_PATH_ERROR|Папка задачи не найдена' }).Count -gt 0
$errors += @{
    Type = 'TASK_PATH_ERROR'
    Description = 'Ошибка пути задачи — папка задачи не найдена или не создана'
    Found = $hasTaskPathError
    Fix = if ($hasTaskPathError) {
        'Создайте папку задачи через "TaskPlan-Tracker.ps1 -Action new -TaskName <имя> -Goal <цель> -Stages @(...)"'
    } else { '' }
}

# Тип 2: TRACKER_MISSING_PLAN — план не найден
$hasMissingPlan = ($logLines | Where-Object { $_ -match 'TRACKER_MISSING_PLAN|План не найден' }).Count -gt 0
$errors += @{
    Type = 'TRACKER_MISSING_PLAN'
    Description = 'План задачи (ПЛАН_РЕАЛИЗАЦИИ.txt) не найден'
    Found = $hasMissingPlan
    Fix = if ($hasMissingPlan) {
        'Создайте план через трекер с -Action new или создайте Describe\ПЛАН_РЕАЛИЗАЦИИ.txt вручную'
    } else { '' }
}

# Тип 3: TRACKER_JSON_ERROR — ошибка JSON
$hasJsonError = ($logLines | Where-Object { $_ -match 'TRACKER_JSON_ERROR|plan_state.json|JavaScriptSerializer' }).Count -gt 0
$errors += @{
    Type = 'TRACKER_JSON_ERROR'
    Description = 'Ошибка чтения plan_state.json (повреждённый JSON или проблема с парсером)'
    Found = $hasJsonError
    Fix = if ($hasJsonError) {
        'Запустите синхронизацию: TaskPlan-Tracker.ps1 -Action sync -TaskName <имя>'
    } else { '' }
}

# Тип 4: GUI_LAUNCH_FAIL — GUI не запускается
$hasGuiLaunchFail = ($logLines | Where-Object { $_ -match 'GUI_LAUNCH_FAIL|GUI.*exit|Show-TaskPlanGUI' -and $_ -match 'ERROR|FAIL' }).Count -gt 0
$errors += @{
    Type = 'GUI_LAUNCH_FAIL'
    Description = 'GUI (Show-TaskPlanGUI.ps1) не запускается или выходит с ошибкой'
    Found = $hasGuiLaunchFail
    Fix = if ($hasGuiLaunchFail) {
        'Проверьте наличие BOM (UTF-8 with BOM) в Show-TaskPlanGUI.ps1. Проверьте синтаксис: powershell -NoLogo -File scripts\Show-TaskPlanGUI.ps1 (смотреть ошибки)'
    } else { '' }
}

# Тип 5: GUI_AUTOMATION_FAIL — Automation не находит окно
$hasAutoFail = ($logLines | Where-Object { $_ -match 'GUI_AUTOMATION_FAIL|Window not found|UIAutomation' -and $_ -match 'ERROR|FAIL' }).Count -gt 0
$errors += @{
    Type = 'GUI_AUTOMATION_FAIL'
    Description = 'UI Automation не находит окно TaskPlan (проверьте заголовок окна)'
    Found = $hasAutoFail
    Fix = if ($hasAutoFail) {
        'Убедитесь, что Title окна содержит "TaskPlan — управление планом задачи". Проверьте, что окно не скрыто (CreateNoWindow)'
    } else { '' }
}

# Тип 6: PS51_SYNTAX_ERROR — синтаксическая ошибка PS 5.1
$hasPS51Error = ($logLines | Where-Object { $_ -match 'PS51_SYNTAX_ERROR|ParserError|UnexpectedToken|Непредвиденная лексема' }).Count -gt 0
$errors += @{
    Type = 'PS51_SYNTAX_ERROR'
    Description = 'Синтаксическая ошибка PowerShell 5.1 — ??, ??=, ?. или Test-Path -and'
    Found = $hasPS51Error
    Fix = if ($hasPS51Error) {
        'Замените ?? на if/else, ??= на if/else, ?. на if/else. Test-Path $x -and $y → (Test-Path $x) -and ($y). Проверьте BOM (UTF-8 with BOM)'
    } else { '' }
}

# Тип 7: TEST_FAILURE — тест не прошёл
$hasTestFail = ($logLines | Where-Object { $_ -match 'TEST_FAILURE|TEST FAIL|TESTS END.*fail=[1-9]' }).Count -gt 0
$errors += @{
    Type = 'TEST_FAILURE'
    Description = 'Один или несколько тестов TaskPlan-Tests.ps1 не прошли'
    Found = $hasTestFail
    Fix = if ($hasTestFail) {
        'Запустите тесты вручную: powershell -NoLogo -File scripts\TaskPlan-Tests.ps1 -ShowUI. Анализируйте вывод каждого FAIL'
    } else { '' }
}

# Тип 8: LOGGER_MISSING — логгер не подключён
$hasLoggerMissing = ($logLines | Where-Object { $_ -match 'LOGGER_MISSING|Write-TaskPlanLog' }).Count -gt 0
if ($hasLoggerMissing) {
    $errors += @{
        Type = 'LOGGER_MISSING'
        Description = 'Логгер TaskPlan-Logger.ps1 не подключён (функция Write-TaskPlanLog не найдена)'
        Found = $true
        Fix = 'Убедитесь, что скрипты выполняют dot-source TaskPlan-Logger.ps1: . "C:\AIS\AI\Prod\scripts\TaskPlan-Logger.ps1"'
    }
}

# Тип 9: GUI_OPERATION_ERROR — ошибки из GUI-лога (mgmtLog)
$guiLogLines = @()
if (Test-Path $guiLogFile) {
    $guiLogLines = Get-Content -LiteralPath $guiLogFile -Encoding UTF8 -ErrorAction SilentlyContinue
}
$guiErrors = $guiLogLines | Where-Object { $_ -match 'ОШИБКА|ERROR|FAIL' }
$hasGuiOpError = $guiErrors.Count -gt 0
$errors += @{
    Type = 'GUI_OPERATION_ERROR'
    Description = "Ошибки в логе операций GUI ($guiLogFile)"
    Found = $hasGuiOpError
    Fix = if ($hasGuiOpError) {
        $first = $guiErrors | Select-Object -First 1
        "Первая ошибка: $first. Проверьте полный лог: $guiLogFile"
    } else { '' }
}

# ── Вывод диагностики ──
Write-Report "=== OUTPL — диагностика TaskPlan ==="
Write-Report "Дата: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')"
Write-Report "Лог-файл: $logFile"
Write-Report "GUI-лог: $guiLogFile"
Write-Report ""

$foundAny = $false
foreach ($e in $errors) {
    if ($e.Found) {
        $foundAny = $true
        Write-Report ""
        Write-Report "[ERROR] $($e.Type): $($e.Description)"
        if ($e.Fix) {
            Write-Report "[FIX]   $($e.Fix)"
        }
    } else {
        Write-Report "[OK]    $($e.Type) — не обнаружено"
    }
}

if (-not $foundAny) {
    Write-Report ""
    Write-Report "Ошибки не обнаружены."
}

# ── AutoFix ──
if ($AutoFix) {
    Write-Report ""
    Write-Report "=== AUTOFIX ==="
    # Убить зависшие GUI-процессы
    $guiProcs = Get-Process -Name powershell -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -match 'Show-TaskPlanGUI'
    }
    if ($guiProcs) {
        foreach ($p in $guiProcs) {
            try {
                $p.Kill()
                Write-Report "  [KILL] Убит процесс GUI PID=$($p.Id)"
            } catch {
                Write-Report "  [FAIL] Не удалось убить PID=$($p.Id): $_"
            }
        }
    } else {
        Write-Report "  [OK] Зависших GUI-процессов не найдено"
    }

    # Проверка BOM в скриптах
    $scriptsToCheck = @($trackerPath, $guiPath, (Join-Path $scriptPath 'TaskPlan-Tests.ps1'))
    foreach ($s in $scriptsToCheck) {
        if (Test-Path $s) {
            $bytes = [System.IO.File]::ReadAllBytes($s)
            if (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) {
                $content = Get-Content -LiteralPath $s -Raw -Encoding UTF8
                $utf8Bom = New-Object System.Text.UTF8Encoding $true
                [System.IO.File]::WriteAllText($s, $content, $utf8Bom)
                Write-Report "  [FIX] Добавлен BOM в $(Split-Path $s -Leaf)"
            }
        }
    }
}

# ── Сохранение отчёта ──
$reportDir = Split-Path $reportFile -Parent
if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
$utf8Bom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($reportFile, ($report -join "`r`n"), $utf8Bom)
Write-Report ""
Write-Report "Отчёт сохранён: $reportFile"
