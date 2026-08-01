<#
.SYNOPSIS
    Импорт ранее подготовленных TASK-задач в TASKPL (TaskPlan).
.DESCRIPTION
    Подхватывает папку задачи, созданную по правилу TASK
    (имеет даты-папки Git_YYYY_MM_DD / Test_YYYY_MM_DD / Ready_YYYY_MM_DD
    и папку Describe с анализом/рекомендациями).
    Преобразует содержимое в ПЛАН_РЕАЛИЗАЦИИ.txt + plan_state.json
    (формат TaskPlan-Tracker), отмечая:
      - обработанные объекты (есть в Ready_ или Test_) как этапы [x];
      - необработанные объекты (только в Git_) как этапы [ ] (todo);
      - рекомендации из Describe как исполняемые этапы [ ] (todo) / [!] (дорогая LLM).
.PARAMETER TaskName
    Имя задачи (папка, можно с суффиксом _NNNN)
.PARAMETER ReleaseRoot
    Корень папок задач (авто: SYBASE/SUPRT -> C:\AIS\1 Release)
.PARAMETER Force
    Перезаписать существующий ПЛАН_РЕАЛИЗАЦИИ.txt
#>
param(
    [string]$TaskName = '',
    [string]$ReleaseRoot = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# ── Корень ──
if (-not $ReleaseRoot) {
    if ($TaskName -match '^(SYBASE|SUPRT)-') { $ReleaseRoot = 'C:\AIS\1 Release' }
    else { $ReleaseRoot = 'C:\AIS\AI\Prod\tasks' }
}

# ── Поиск папки (как в Tracker) ──
function Resolve-TaskFolder {
    param([string]$Name)
    if (-not $Name) { throw "Укажите -TaskName" }
    $exact = Join-Path $ReleaseRoot $Name
    if (Test-Path -LiteralPath $exact) { return $exact }
    $found = Get-ChildItem $ReleaseRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$Name*" } | Select-Object -First 1
    if ($found) { return $found.FullName }
    throw "Папка задачи не найдена: $Name"
}

# ── Сбор объектов из даты-папки (рекурсивно, только файлы) ──
function Get-ObjectsFromDateFolders {
    param([string]$TaskFolder)
    $result = @{ Git = @{}; Test = @{}; Ready = @{} }
    $patterns = @('Git_*', 'Test_*', 'Ready_*')
    foreach ($pat in $patterns) {
        $dateDirs = Get-ChildItem -LiteralPath $TaskFolder -Directory -Filter $pat -ErrorAction SilentlyContinue
        $key = if ($pat -like 'Git_*') { 'Git' } elseif ($pat -like 'Test_*') { 'Test' } else { 'Ready' }
        foreach ($dd in $dateDirs) {
            Get-ChildItem -LiteralPath $dd.FullName -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                $nm = $_.Name
                if (-not $result[$key].ContainsKey($nm)) { $result[$key][$nm] = $_.FullName }
            }
        }
    }
    return $result
}

# ── Извлечение списка ИЗМЕНЁННЫХ объектов из текстового отчёта ──
function Get-ModifiedObjectsFromReport {
    param([string]$DescribeDir)
    $modified = @()
    $reportFiles = Get-ChildItem -LiteralPath $DescribeDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(REPORT|отч[её]т|ОТЧЁТ)' -and $_.Extension -eq '.txt' }
    foreach ($rf in $reportFiles) {
        try { $raw = Get-Content -LiteralPath $rf.FullName -Encoding UTF8 -ErrorAction SilentlyContinue }
        catch { continue }
        $inSection = $false
        foreach ($ln in $raw) {
            $lnStr = $ln.Trim()
            if ($lnStr -match 'ИЗМЕН[ЁЕ]ННЫЕ\s+ОБЪЕКТЫ') { $inSection = $true; continue }
            if ($inSection -and $lnStr -match '^={3,}') { $inSection = $false; continue }
            if ($inSection -and $lnStr.Length -gt 3) {
                if ($lnStr -match '^(\S+\.(sru|srw|srd|sql))') { $modified += $matches[1] }
            }
        }
    }
    return $modified
}

# ── Извлечение ожидающих объектов из report_data.json ──
function Get-PendingObjectsFromReportJson {
    param([string]$TaskFolder)
    $pending = @()
    $jsonFile = Join-Path $TaskFolder 'report_data.json'
    if (-not (Test-Path -LiteralPath $jsonFile)) { return $pending }
    try {
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction SilentlyContinue
        $jss = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $jss.MaxJsonLength = 10 * 1024 * 1024
        $raw = Get-Content -LiteralPath $jsonFile -Raw -Encoding UTF8
        $data = $jss.DeserializeObject($raw)
        if ($data.ContainsKey('pb_ide_objects')) {
            foreach ($obj in $data['pb_ide_objects']) {
                if ($obj.ContainsKey('status') -and $obj['status'] -eq 'ожидает') {
                    $pending += @{
                        object = $obj['object']
                        library = if ($obj.ContainsKey('library')) { $obj['library'] } else { '' }
                        changes = if ($obj.ContainsKey('required_changes')) { $obj['required_changes'] } else { '' }
                    }
                }
            }
        }
    } catch {}
    return $pending
}

# ── Извлечение уже изменённых объектов из report_data.json ──
function Get-ChangedObjectsFromReportJson {
    param([string]$TaskFolder)
    $changed = @()
    $jsonFile = Join-Path $TaskFolder 'report_data.json'
    if (-not (Test-Path -LiteralPath $jsonFile)) { return $changed }
    try {
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction SilentlyContinue
        $jss = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $jss.MaxJsonLength = 10 * 1024 * 1024
        $raw = Get-Content -LiteralPath $jsonFile -Raw -Encoding UTF8
        $data = $jss.DeserializeObject($raw)
        if ($data.ContainsKey('changed_objects')) {
            foreach ($obj in $data['changed_objects']) {
                if ($obj.ContainsKey('object')) {
                    $changed += @{ object = $obj['object']; description = $obj['description'] }
                }
            }
        }
    } catch {}
    return $changed
}

# ── Сравнение размеров Git vs Test/Ready для определения изменённых ──
function Get-ModifiedBySize {
    param($Objs)
    $modified = @()
    foreach ($k in $Objs.Git.Keys) {
        $gitSize = (Get-Item -LiteralPath $Objs.Git[$k] -ErrorAction SilentlyContinue).Length
        if ($Objs.Test.ContainsKey($k)) {
            $testSize = (Get-Item -LiteralPath $Objs.Test[$k] -ErrorAction SilentlyContinue).Length
            if ($null -ne $gitSize -and $null -ne $testSize -and $gitSize -ne $testSize) { $modified += $k; continue }
        }
        if ($Objs.Ready.ContainsKey($k)) {
            $readySize = (Get-Item -LiteralPath $Objs.Ready[$k] -ErrorAction SilentlyContinue).Length
            if ($null -ne $gitSize -and $null -ne $readySize -and $gitSize -ne $readySize) { $modified += $k }
        }
    }
    return $modified
}

# ── Чтение рекомендаций из Describe ──
function Get-Recommendations {
    param([string]$DescribeDir)
    $recs = @()
    if (-not (Test-Path $DescribeDir)) { return $recs }
    # Файлы с анализом/отчётом/планом/рекомендациями (только текст, не html/pdf)
    $files = Get-ChildItem -LiteralPath $DescribeDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(анализ|отч[ёе]т|ПЛАН|PLAN|REPORT|изменения|оценка|RECOMMEND|ВЫВОД)' -and $_.Extension -notin @('.html','.pdf') }
    foreach ($f in $files) {
        $recs += @{ file = $f.Name; path = $f.FullName }
    }
    return $recs
}

# ── Извлечение заголовков/рекомендаций из текста (эвристика) ──
function Extract-RecLines {
    param([string]$Path)
    $lines = @()
    if (-not (Test-Path $Path)) { return $lines }
    try {
        $raw = Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { return $lines }
    $inRec = $false
    $afterHeader = 0
    foreach ($ln in $raw) {
        $lnStr = $ln.Trim()
        if ($lnStr.Length -eq 0) { if ($inRec) { $afterHeader++ }; continue }
        # Заголовки разделов рекомендаций / выводов / след. шага
        if ($lnStr -match '^(===\s*)?(РЕКОМЕНДАЦИЯ|Рекомендация|СЛЕДУЮЩИЙ ШАГ|Следующий шаг|ОЧЕРЕДЬ ДОРОГИХ|ВЫВОД|Вывод|ГОТОВО К VSS)') {
            $inRec = $true; $afterHeader = 0; continue
        }
        if ($lnStr -match '^={3,}\s*$') { $inRec = $false; continue }
        # Захват: строки внутри секции (до 8 строк после заголовка) ИЛИ строки с ключевыми префиксами
        $isKeyLine = $lnStr -match '^(Рекомендация|Следующий шаг|Вывод|РЕКОМЕНДАЦИЯ|СЛЕДУЮЩИЙ ШАГ|ВЫВОД)\s*[:—-]'
        if (($inRec -and $afterHeader -lt 8) -or $isKeyLine) {
            $clean = $lnStr -replace '<[^>]+>', '' -replace '\s+', ' '
            if ($clean.Length -gt 3 -and $clean -match '\S' -and $clean -notmatch '^(</?pre|</?body|</?html)') {
                $lines += $clean
                $afterHeader++
            }
        }
    }
    # Ограничим объём
    if ($lines.Count -gt 20) { $lines = $lines[0..19] }
    return $lines
}

# ── Запись ПЛАН_РЕАЛИЗАЦИИ.txt ──
function Write-PlanTxt {
    param([string]$Path, [string]$Goal, $Stages)
    $sb = New-Object Text.StringBuilder
    $null = $sb.AppendLine("=== ПЛАН РЕАЛИЗАЦИИ ===")
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("ЦЕЛЬ: $Goal")
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("ЭТАПЫ:")
    foreach ($s in $Stages) {
        $mark = switch ($s.status) { 'todo' {'[ ]'} 'wip' {'[~]'} 'done' {'[x]'} 'defer' {'[!]'} default {'[ ]'} }
        $byStr = if ($s.by) { " ($($s.by))" } else { '' }
        $null = $sb.AppendLine("$mark $($s.num). $($s.text)$byStr")
    }
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("---")
    Set-Content -LiteralPath $Path -Value $sb.ToString() -Encoding UTF8
}

# ── Запись plan_state.json (зеркало) ──
function Write-StateJson {
    param([string]$Path, [string]$Goal, $Stages)
    $done = @($Stages | Where-Object { $_.status -eq 'done' }).Count
    $wip = @($Stages | Where-Object { $_.status -eq 'wip' }).Count
    $defer = @($Stages | Where-Object { $_.status -eq 'defer' }).Count
    $total = $Stages.Count
    $pct = if ($total -gt 0) { [math]::Round(($done + $wip * 0.5) / $total * 100) } else { 0 }
    $stageList = @()
    foreach ($s in $Stages) {
        $stageList += @{ num = $s.num; text = $s.text; status = $s.status; by = if ($s.by) { $s.by } else { '' } }
    }
    $obj = @{
        task_name = $TaskName
        goal = $Goal
        stages = $stageList
        total = $total; done = $done; wip = $wip; defer = $defer
        pct = $pct
        imported_from = 'TASK'
        timestamp = (Get-Date -Format 'dd.MM.yyyy HH:mm:ss')
    }
    Set-Content -LiteralPath $Path -Value ($obj | ConvertTo-Json -Depth 5) -Encoding UTF8
}

# ===== ОСНОВНАЯ ЛОГИКА =====

if (-not $TaskName) { throw "Укажите -TaskName" }
$taskFolder = Resolve-TaskFolder -Name $TaskName
Write-Output "Папка задачи: $taskFolder" -ForegroundColor Cyan

$descDir = Join-Path $taskFolder 'Describe'
if (-not (Test-Path $descDir)) { New-Item -ItemType Directory -Path $descDir -Force | Out-Null }
$planFile = Join-Path $descDir 'ПЛАН_РЕАЛИЗАЦИИ.txt'
$stateFile = Join-Path $descDir 'plan_state.json'

if ((Test-Path $planFile) -and (-not $Force)) {
    throw "План уже существует: $planFile. Используйте -Force для перезаписи."
}

# 1. Сбор объектов
$objs = Get-ObjectsFromDateFolders -TaskFolder $taskFolder
$gitKeys = @($objs.Git.Keys)
$testKeys = @($objs.Test.Keys)
$readyKeys = @($objs.Ready.Keys)

$allKeys = @()
foreach ($k in $gitKeys + $testKeys + $readyKeys) { if ($allKeys -notcontains $k) { $allKeys += $k } }

# 2. Определение РЕАЛЬНО изменённых объектов
# 2a. Парсинг отчёта (REPORT_*.txt)
$modifiedFromReport = Get-ModifiedObjectsFromReport -DescribeDir $descDir
# 2b. Сравнение размеров Git vs Test/Ready
$modifiedBySize = Get-ModifiedBySize -Objs $objs
# 2c. Объединяем оба списка (уникальные)
$modifiedSet = @{}
foreach ($m in $modifiedFromReport + $modifiedBySize) { $modifiedSet[$m] = $true }

# 2d. Парсинг report_data.json для ожидающих и уже изменённых объектов
$jsonPending = Get-PendingObjectsFromReportJson -TaskFolder $taskFolder
$jsonChanged = Get-ChangedObjectsFromReportJson -TaskFolder $taskFolder
# Добавляем уже изменённые из JSON в модифицированные
foreach ($c in $jsonChanged) { $modifiedSet[$c.object] = $true }

# 3. Классификация
$processed = @()   # реально изменённые (done)
$unchanged = @()   # есть в Ready/Test, но НЕ изменены (dependency)
$unprocessed = @() # только в Git
$pendingFromJson = @() # объекты со статусом "ожидает" из report_data.json
foreach ($k in $allKeys) {
    $inReady = $readyKeys -contains $k
    $inTest = $testKeys -contains $k
    $isModified = $modifiedSet.ContainsKey($k)
    if ($isModified) { $processed += $k }
    elseif ($inReady -or $inTest) { $unchanged += $k }
    elseif ($gitKeys -contains $k) { $unprocessed += $k }
}
# Также добавляем все ожидающие из JSON (даже если их нет в папках)
foreach ($p in $jsonPending) {
    if ($allKeys -notcontains $p.object) { $pendingFromJson += $p }
}
# Удаляем ожидающие объекты из unchanged/processed если они есть в jsonPending
$pendingNames = @($jsonPending | ForEach-Object { $_.object })
$unchanged = @($unchanged | Where-Object { $pendingNames -notcontains $_ })
$processed = @($processed | Where-Object { $pendingNames -notcontains $_ })

Write-Output "Объектов всего: $($allKeys.Count) | изменено: $($processed.Count) | ожидает: $(($jsonPending.Count + $pendingFromJson.Count)) | зависимостей: $($unchanged.Count) | необработано: $($unprocessed.Count)" -ForegroundColor White

# 4. Формирование этапов
$stages = @()
$num = 1

# 4a. Изменённые объекты -> [x]
foreach ($k in $processed) {
    $where = if ($readyKeys -contains $k) { 'Ready' } else { 'Test' }
    $stages += @{ num = $num; text = "Объект изменён: $k ($where)"; status = 'done'; by = 'TASK' }
    $num++
}

# 4b. Неизменённые зависимости (в Ready/Test, но не менялись) -> [ ] (todo)
foreach ($k in $unchanged) {
    $stages += @{ num = $num; text = "Зависимость (без изменений): $k"; status = 'todo'; by = '' }
    $num++
}

# 4c. Необработанные объекты -> [ ] (todo)
foreach ($k in $unprocessed) {
    $stages += @{ num = $num; text = "Объект не обработан: $k (Git) — требует доработки"; status = 'todo'; by = '' }
    $num++
}

# 4d. Ожидающие объекты из report_data.json -> [ ] (todo)
foreach ($p in $jsonPending + $pendingFromJson) {
    $changeText = $p.changes
    if ($changeText.Length -gt 100) { $changeText = $changeText.Substring(0, 97) + '...' }
    $libText = if ($p.library) { " ($($p.library))" } else { '' }
    $stageText = "Объект ожидает доработки: $($p.object)$libText — $changeText"
    $stages += @{ num = $num; text = $stageText; status = 'todo'; by = '' }
    $num++
}

# 5. Рекомендации из Describe -> исполняемые этапы
$recs = Get-Recommendations -DescribeDir $descDir
$recLines = @()
foreach ($r in $recs) {
    $recLines += Extract-RecLines -Path $r.path
}
# Уникальные рекомендации
$seen = @{}
$uniqRec = @()
foreach ($rl in $recLines) {
    $key = $rl.Substring(0, [math]::Min(40, $rl.Length))
    if (-not $seen.ContainsKey($key)) { $seen[$key] = $true; $uniqRec += $rl }
}
foreach ($rl in $uniqRec) {
    # Маркируем как дорогую подзадачу, если упоминается сложность/Opus/дорог
    $isDefer = $rl -match '(Opus|дорог|сложн|рефактор|глубок)'
    $stages += @{
        num = $num
        text = "Рекомендация: $rl"
        status = if ($isDefer) { 'defer' } else { 'todo' }
        by = ''
    }
    $num++
}

# 8. Цель задачи
$goal = "Импортировано из TASK: $TaskName. Объектов: $($allKeys.Count) (изменено $($processed.Count), ожидает $($jsonPending.Count + $pendingFromJson.Count), зависимостей $($unchanged.Count), необработано $($unprocessed.Count)). Рекомендаций: $($uniqRec.Count)."

# 6. Запись
Write-PlanTxt -Path $planFile -Goal $goal -Stages $stages
Write-StateJson -Path $stateFile -Goal $goal -Stages $stages

Write-Output "План импортирован: $planFile" -ForegroundColor Green
Write-Output "Этапов: $($stages.Count) (done: $($processed.Count), todo: $(@($stages | Where-Object {$_.status -eq 'todo'}).Count), defer: $(@($stages | Where-Object {$_.status -eq 'defer'}).Count))" -ForegroundColor Yellow

# 8. Краткий отчёт объектов
Write-Output ""
Write-Output "--- ИЗМЕНЁННЫЕ (done) ---" -ForegroundColor Gray
foreach ($k in $processed) { Write-Output "  [x] $k" -ForegroundColor Green }
Write-Output "--- ОЖИДАЮТ ДОРАБОТКИ ---" -ForegroundColor Gray
foreach ($p in $jsonPending + $pendingFromJson) { Write-Output "  [ ] $($p.object) ($($p.library))" -ForegroundColor Yellow }
Write-Output "--- ЗАВИСИМОСТИ (без изменений) ---" -ForegroundColor Gray
foreach ($k in $unchanged) { Write-Output "  [ ] $k" -ForegroundColor DarkGray }
Write-Output "--- НЕОБРАБОТАННЫЕ (только Git) ---" -ForegroundColor Gray
foreach ($k in $unprocessed) { Write-Output "  [ ] $k" -ForegroundColor Yellow }
