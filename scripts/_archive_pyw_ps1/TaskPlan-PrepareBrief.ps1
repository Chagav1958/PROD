<#
.SYNOPSIS
    Формирует бриф для дорогой LLM из отложенного [!] этапа общего плана.
.DESCRIPTION
    Выбирает этап(ы) со статусом defer ([!]), собирает контекст (знания MCP,
    карту зависимостей, фрагменты кода) и пишет Describe\<имя>_SUB_<n>_бриф.txt.
    Цель: дорогая LLM тратит минимум токенов (стратегия п.6).
.PARAMETER TaskName
    Имя задачи (папка в C:\AIS\1 Release)
.PARAMETER StageNum
    Номер [!]-этапа. Если не указан - берётся первый defer.
.PARAMETER SubName
    Имя подзадачи (по умолчанию <TaskName>_SUB_<n>)
.PARAMETER Context
    Дополнительный контекст/инструкция для дорогой LLM (строка)
.PARAMETER Objects
    Объекты PB/SQL для выгрузки фрагментов в бриф (массив)
#>
param(
    [string]$TaskName,
    [int]$StageNum = 0,
    [string]$SubName = '',
    [string]$Context = '',
    [string[]]$Objects = @(),
    [string]$ReleaseRoot = ''
)

$ErrorActionPreference = 'Stop'
if (-not $ReleaseRoot) {
    if ($TaskName -match '^(SYBASE|SUPRT)-') { $ReleaseRoot = 'C:\AIS\1 Release' }
    else { $ReleaseRoot = 'C:\AIS\AI\Prod\tasks' }
}

function Resolve-TaskPath {
    param([string]$Name)
    if (-not $Name) { throw "Укажите -TaskName" }
    $exact = Join-Path $ReleaseRoot $Name
    if (Test-Path -LiteralPath $exact) { return $exact }
    $found = Get-ChildItem $ReleaseRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$Name*" } | Select-Object -First 1
    if ($found) { return $found.FullName }
    throw "Папка задачи не найдена: $Name"
}

function Parse-StageLine {
    param([string]$line)
    $m = [regex]::Match($line, '^\[([ x~!])\]\s*(\d+)\.\s*(.*)$')
    if (-not $m.Success) { return $null }
    $mark = $m.Groups[1].Value
    $status = switch ($mark) { '~' {'wip'} 'x' {'done'} '!' {'defer'} default {'todo'} }
    $num = [int]$m.Groups[2].Value
    $rest = $m.Groups[3].Value
    $by = ''
    if ($rest -match '\s*\(([^)]*)\)$') {
        $by = $rest.Substring($rest.LastIndexOf('(') + 1).TrimEnd(')')
        $rest = $rest.Substring(0, $rest.LastIndexOf('(')).Trim()
    }
    return [PSCustomObject]@{ num = $num; status = $status; text = $rest; by = $by }
}

# --- разбор плана ---
$taskPath = Resolve-TaskPath -Name $TaskName
$descDir = Join-Path $taskPath "Describe"
$planFile = Join-Path $descDir "ПЛАН_РЕАЛИЗАЦИИ.txt"
if (-not (Test-Path -LiteralPath $planFile)) { throw "План не найден: $planFile" }

$stages = @()
$inStages = $false
$rawAll = Get-Content -LiteralPath $planFile -Encoding UTF8 -Raw
$rawAll = $rawAll.TrimStart([char]0xFEFF)
$lines = $rawAll -split [Environment]::NewLine -split "`n"
foreach ($raw in $lines) {
    $line = $raw.TrimEnd()
    if ($line -match 'ЭТАП') { $inStages = $true; continue }
    if ($inStages -and $line -match '^---') { $inStages = $false }
    if ($inStages) {
        $p = Parse-StageLine -line $line
        if ($p) { $stages += $p }
    }
}

$target = $null
if ($StageNum -gt 0) {
    $target = $stages | Where-Object { $_.num -eq $StageNum -and $_.status -eq 'defer' } | Select-Object -First 1
} else {
    $target = $stages | Where-Object { $_.status -eq 'defer' } | Select-Object -First 1
}
if (-not $target) { throw "Нет отложенных [!] этапов" }

$subN = 1
Get-ChildItem $descDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '_SUB_' } | ForEach-Object { $subN++ }
if (-not $SubName) { $SubName = "$TaskName`_SUB_$subN" }

# --- сбор контекста ---
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("ПОДЗАДАЧА ДЛЯ ДОРОГОЙ LLM: $SubName")
[void]$sb.AppendLine("Родительская задача: $TaskName")
[void]$sb.AppendLine("Этап плана: [$($target.num)] $($target.text)")
[void]$sb.AppendLine("Почему нужна мощная LLM: $($target.by)")
[void]$sb.AppendLine("Дата подготовки: $(Get-Date -Format 'dd.MM.yyyy HH:mm')")
[void]$sb.AppendLine()
[void]$sb.AppendLine("=== ЗАПРОС К ДОРОГОЙ LLM ===")
[void]$sb.AppendLine("Реши задачу, описанную в этапе выше. Используй приложенный контекст.")
[void]$sb.AppendLine("Ожидаемый результат: готовый код/правка + критерий приёмки.")
[void]$sb.AppendLine()
[void]$sb.AppendLine("=== ДОПОЛНИТЕЛЬНЫЙ КОНТЕКСТ ОТ ДЕШЁВОЙ LLM ===")
if ($Context) { [void]$sb.AppendLine($Context) } else { [void]$sb.AppendLine("(не задан)") }
[void]$sb.AppendLine()
[void]$sb.AppendLine("=== ЗАМЕЧАНИЕ ===")
[void]$sb.AppendLine("1. Перед запуском дорогой LLM выполнено всё возможное дешёвой LLM.")
[void]$sb.AppendLine("2. Дорогая LLM берёт ТОЛЬКО этот этап, не весь план.")
[void]$sb.AppendLine("3. Модель выбрать через DLLM (рекомендуется Opus для сложной логики).")
[void]$sb.AppendLine("4. Бюджет: держать баланс выше порога Insufficient balance.")

$briefFile = Join-Path $descDir "$SubName`_бриф.txt"
Set-Content -LiteralPath $briefFile -Value $sb.ToString() -Encoding UTF8
Write-Output "Бриф создан: $briefFile" -ForegroundColor Green
Write-Output "Этап: [$($target.num)] $($target.text)" -ForegroundColor Cyan
Write-Output "Подзадача: $SubName" -ForegroundColor White
