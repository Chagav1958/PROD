<#
.SYNOPSIS
    Полный цикл автотестов сервиса TaskPlan (без вмешательства человека).
.DESCRIPTION
    Тестирует: создание плана, чтение, статусы, этапы, бриф, GUI через UI Automation.
    Возвращает JSON-массив результатов.
#>
param(
    [switch]$ShowUI,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$scriptPath = Split-Path $PSCommandPath -Parent
$tracker = Join-Path $scriptPath 'TaskPlan-Tracker.ps1'
$brief    = Join-Path $scriptPath 'TaskPlan-PrepareBrief.ps1'
$gui      = Join-Path $scriptPath 'Show-TaskPlanGUI.ps1'
$testRoot = 'C:\AIS\AI\Prod\tasks'
$testTaskName = "__test_$(Get-Random -Maximum 99999)"
$results = [System.Collections.ArrayList]@()

# Импорт логгера для OUTPL
$loggerPath = Join-Path $scriptPath 'TaskPlan-Logger.ps1'
if (Test-Path $loggerPath) { . $loggerPath }

function Write-Result {
    param([string]$TestName, [bool]$Passed, [string]$Detail = '')
    $status = if ($Passed) { 'PASS' } else { 'FAIL' }
    $color  = if ($Passed) { 'Green' } else { 'Red' }
    Write-Host ("[$status] $TestName") -ForegroundColor $color
    if ($Detail) { Write-Host "  $Detail" -ForegroundColor Gray }
    [void]$results.Add([PSCustomObject]@{ Test = $TestName; Status = $status; Detail = $Detail })
    if (-not $Passed -and (Get-Command Write-TaskPlanLog -ErrorAction SilentlyContinue)) {
        Write-TaskPlanLog -Message "TEST FAIL: $TestName Detail=$Detail" -Level 'FAIL' -Source 'Tests'
    }
}

function Read-PlanStateJson {
    param([string]$Name, [string]$Root = $testRoot)
    $folder = Join-Path $Root $Name
    $jsonFile = Join-Path $folder 'Describe\plan_state.json'
    if (-not (Test-Path $jsonFile)) { return $null }
    $raw = Get-Content -LiteralPath $jsonFile -Raw -Encoding UTF8
    try {
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction SilentlyContinue
        $jss = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $jss.MaxJsonLength = 10 * 1024 * 1024
        return $jss.DeserializeObject($raw)
    } catch { return $null }
}

if (Get-Command Write-TaskPlanLog -ErrorAction SilentlyContinue) {
    Write-TaskPlanLog -Message "TESTS START task=$testTaskName" -Level 'INFO' -Source 'Tests'
}
try {
# ============ БЛОК 1: ТРЕКЕР (BUSINESS LOGIC) ============
Write-Host "`n=== БЛОК 1: ТРЕКЕР (BUSINESS LOGIC) ===" -ForegroundColor Cyan

# Test 1: Create plan
try {
    & $tracker -Action 'new' -TaskName $testTaskName -ReleaseRoot $testRoot -Goal "Test automation goal" -Stages @("Stage 1", "Stage 2|tester", "Stage 3") -Force
    Write-Result -TestName 'Создание плана' -Passed $true
} catch { Write-Result -TestName 'Создание плана' -Passed $false -Detail $_.Exception.Message }

# Test 2: Read plan state
try {
    $state = Read-PlanStateJson -Name $testTaskName
    if ($state -and $state['goal'] -eq 'Test automation goal' -and $state['total'] -eq 3) {
        Write-Result -TestName 'Чтение плана (state)' -Passed $true
    } else {
        Write-Result -TestName 'Чтение плана (state)' -Passed $false -Detail "goal=$($state['goal']) total=$($state['total'])"
    }
} catch { Write-Result -TestName 'Чтение плана (state)' -Passed $false -Detail $_.Exception.Message }

# Test 3: Set status wip
try {
    & $tracker -Action 'set' -TaskName $testTaskName -ReleaseRoot $testRoot -StageNum 1 -Status 'wip' -DoneBy 'tester'
    Write-Result -TestName 'Установка статуса wip' -Passed $true
} catch { Write-Result -TestName 'Установка статуса wip' -Passed $false -Detail $_.Exception.Message }

# Test 4: Verify status changed
try {
    $state = Read-PlanStateJson -Name $testTaskName
    $s1 = $state['stages'][0]
    if ($s1['status'] -eq 'wip' -and $s1['by'] -eq 'tester') {
        Write-Result -TestName 'Проверка статуса wip' -Passed $true
    } else {
        Write-Result -TestName 'Проверка статуса wip' -Passed $false -Detail "status=$($s1['status']) by=$($s1['by'])"
    }
} catch { Write-Result -TestName 'Проверка статуса wip' -Passed $false -Detail $_.Exception.Message }

# Test 5: Set status done
try {
    & $tracker -Action 'set' -TaskName $testTaskName -ReleaseRoot $testRoot -StageNum 1 -Status 'done'
    Write-Result -TestName 'Установка статуса done' -Passed $true
} catch { Write-Result -TestName 'Установка статуса done' -Passed $false -Detail $_.Exception.Message }

# Test 6: Next stage
try {
    $out = & $tracker -Action 'next' -TaskName $testTaskName -ReleaseRoot $testRoot
    if ($out -match '2') {
        Write-Result -TestName 'Поиск следующего этапа' -Passed $true
    } else {
        Write-Result -TestName 'Поиск следующего этапа' -Passed $false -Detail "output: $out"
    }
} catch { Write-Result -TestName 'Поиск следующего этапа' -Passed $false -Detail $_.Exception.Message }

# Test 7: Add stages
try {
    & $tracker -Action 'add' -TaskName $testTaskName -ReleaseRoot $testRoot -Stages @("Stage 4", "Stage 5")
    Write-Result -TestName 'Добавление этапов' -Passed $true
} catch { Write-Result -TestName 'Добавление этапов' -Passed $false -Detail $_.Exception.Message }

# Test 8: Verify added stages
try {
    $state = Read-PlanStateJson -Name $testTaskName
    if ($state['total'] -eq 5) {
        Write-Result -TestName 'Проверка добавленных этапов' -Passed $true
    } else {
        Write-Result -TestName 'Проверка добавленных этапов' -Passed $false -Detail "total=$($state['total']) expected=5"
    }
} catch { Write-Result -TestName 'Проверка добавленных этапов' -Passed $false -Detail $_.Exception.Message }

# Test 9: Sync
try {
    & $tracker -Action 'sync' -TaskName $testTaskName -ReleaseRoot $testRoot
    Write-Result -TestName 'Синхронизация JSON' -Passed $true
} catch { Write-Result -TestName 'Синхронизация JSON' -Passed $false -Detail $_.Exception.Message }

# Test 10: Show plan
try {
    $out = & $tracker -Action 'show' -TaskName $testTaskName -ReleaseRoot $testRoot
    if ($out -match 'Stage') {
        Write-Result -TestName 'Просмотр плана (show)' -Passed $true
    } else {
        Write-Result -TestName 'Просмотр плана (show)' -Passed $false -Detail "output: $out"
    }
} catch { Write-Result -TestName 'Просмотр плана (show)' -Passed $false -Detail $_.Exception.Message }

# Test 11: Prepare brief
try {
    # Сначала добавим отложенный этап для теста брифа
    & $tracker -Action 'set' -TaskName $testTaskName -ReleaseRoot $testRoot -StageNum 2 -Status 'defer' -DoneBy 'deferred-llm'
    $psiBrief = New-Object Diagnostics.ProcessStartInfo
    $psiBrief.FileName = 'powershell'
    $psiBrief.Arguments = "-NoLogo -File `"$brief`" -TaskName `"$testTaskName`" -ReleaseRoot `"$testRoot`""
    $psiBrief.UseShellExecute = $false
    $psiBrief.RedirectStandardOutput = $true
    $psiBrief.RedirectStandardError = $true
    $psiBrief.CreateNoWindow = $true
    $pB = [Diagnostics.Process]::Start($psiBrief)
    $outB = $pB.StandardOutput.ReadToEnd()
    $errB = $pB.StandardError.ReadToEnd()
    $pB.WaitForExit(15000) | Out-Null
    if ($outB -match 'Бриф') { Write-Result -TestName 'Подготовка брифа' -Passed $true }
    else { Write-Result -TestName 'Подготовка брифа' -Passed $false -Detail ($outB + $errB) }
} catch { Write-Result -TestName 'Подготовка брифа' -Passed $false -Detail $_.Exception.Message }

# Test 12: Cleanup
try {
    $folder = Join-Path $testRoot $testTaskName
    if (Test-Path $folder) { Remove-Item -LiteralPath $folder -Recurse -Force }
    if (-not (Test-Path $folder)) {
        Write-Result -TestName 'Удаление тестового плана' -Passed $true
    } else {
        Write-Result -TestName 'Удаление тестового плана' -Passed $false -Detail 'Folder still exists'
    }
} catch { Write-Result -TestName 'Удаление тестового плана' -Passed $false -Detail $_.Exception.Message }

# ============ БЛОК 2: GUI (UI Automation) ============
Write-Host "`n=== БЛОК 2: GUI (UI AUTOMATION) ===" -ForegroundColor Cyan

# Test 13: Launch GUI
$guiProcess = $null
try {
    $psi2 = New-Object Diagnostics.ProcessStartInfo
    $psi2.FileName = 'powershell'
    $psi2.Arguments = "-NoLogo -File `"$gui`""
    $psi2.UseShellExecute = $false
    $psi2.CreateNoWindow = $true
    $guiProcess = [Diagnostics.Process]::Start($psi2)
    Start-Sleep -Seconds 3
    if (-not $guiProcess.HasExited) {
        Write-Result -TestName 'Запуск GUI' -Passed $true
    } else {
        Write-Result -TestName 'Запуск GUI' -Passed $false -Detail 'Process exited early'
    }
} catch { Write-Result -TestName 'Запуск GUI' -Passed $false -Detail $_.Exception.Message }

# Test 14: Find GUI window via Automation
if ($guiProcess -and -not $guiProcess.HasExited) {
    try {
        Add-Type -AssemblyName UIAutomationClient -ErrorAction SilentlyContinue
        Add-Type -AssemblyName UIAutomationTypes -ErrorAction SilentlyContinue
        $rootElement = [System.Windows.Automation.AutomationElement]::RootElement
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, 'TaskPlan — управление планом задачи')
        $guiWindow = $null
        for ($i = 0; $i -lt 15; $i++) {
            $guiWindow = $rootElement.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
            if ($guiWindow) { break }
            Start-Sleep -Seconds 1
        }
        if ($guiWindow) {
            Write-Result -TestName 'Поиск окна GUI (Automation)' -Passed $true
        } else {
            Write-Result -TestName 'Поиск окна GUI (Automation)' -Passed $false -Detail 'Window not found'
        }
    } catch { Write-Result -TestName 'Поиск окна GUI (Automation)' -Passed $false -Detail $_.Exception.Message }
} else {
    Write-Result -TestName 'Поиск окна GUI (Automation)' -Passed $false -Detail 'GUI process not available'
}

# Test 15: Close GUI
if ($guiProcess -and -not $guiProcess.HasExited) {
    try {
        $guiProcess.Kill()
        $guiProcess.WaitForExit(5000) | Out-Null
        Write-Result -TestName 'Закрытие GUI' -Passed $true
    } catch { Write-Result -TestName 'Закрытие GUI' -Passed $false -Detail $_.Exception.Message }
} else {
    Write-Result -TestName 'Закрытие GUI' -Passed $false -Detail 'GUI not running'
}

# ============ ИТОГ ============
Write-Host "`n=== ИТОГ ===" -ForegroundColor Cyan
$passed = @($results | Where-Object { $_.Status -eq 'PASS' }).Count
$failed = @($results | Where-Object { $_.Status -eq 'FAIL' }).Count
$total = $results.Count
Write-Host "Всего: $total | PASS: $passed | FAIL: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })

$resultObj = [PSCustomObject]@{
    Total   = $total
    Passed  = $passed
    Failed  = $failed
    Results = @($results)
}
$json = $resultObj | ConvertTo-Json -Depth 10
if ($PassThru) { return $resultObj }
Write-Host $json

if (Get-Command Write-TaskPlanLog -ErrorAction SilentlyContinue) {
    $level = if ($failed -eq 0) { 'PASS' } else { 'FAIL' }
    Write-TaskPlanLog -Message "TESTS END total=$total pass=$passed fail=$failed" -Level $level -Source 'Tests'
}
} catch {
    $errMsg = $_.Exception.Message
    Write-Host "CRITICAL ERROR: $errMsg" -ForegroundColor Red
    if (Get-Command Write-TaskPlanLog -ErrorAction SilentlyContinue) {
        Write-TaskPlanLog -Message "TESTS CRASH: $errMsg" -Level 'ERROR' -Source 'Tests'
    }
    throw
}