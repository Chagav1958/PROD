<#
.SYNOPSIS
    Compare PowerBuilder export sets: PB_Current vs PB_Main.
    Lists objects that differ, are missing in Main, or missing in Current.
.DESCRIPTION
    Scans all .sr* files in PB_Current and PB_Main, compares by MD5 hash.
    Outputs results to console and saves to a report file.
    If TaskName is specified, only objects from Ready_* folders of that task are compared.
.PARAMETER ConfigPath
    Path to config.json (default: C:\AIS\AI\Prod\config\config.json)
.PARAMETER OutputFile
    Path for the comparison report (default: C:\AIS\AI\Prod\compare_pb_report.txt)
.PARAMETER TaskName
    Jira task name. If specified, only objects from Ready_* folders of this task are compared.
.EXAMPLE
    .\Compare-PB.ps1
.EXAMPLE
    .\Compare-PB.ps1 -OutputFile C:\Temp\pb_diff.txt
.EXAMPLE
    .\Compare-PB.ps1 -TaskName "SYBASE-19248"
#>

param(
    [string]$ConfigPath = "C:\AIS\AI\Prod\config\config.json",
    [string]$OutputFile = "C:\AIS\AI\Prod\compare_pb_report.txt",
    [string]$TaskName = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ConfigPath)) { throw "Конфиг не найден: $ConfigPath" }
$cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

$pbCR = $cfg.paths.pb_current_export
$pbMR = $cfg.paths.pb_main_export

if (-not (Test-Path $pbCR) -or -not (Test-Path $pbMR)) {
    throw "Пути экспорта PB не найдены. Проверьте config.json"
}

Write-Host "=== Сравнение PowerBuilder: Current и Main ===" -ForegroundColor Cyan
Write-Host "Текущая (Current): $pbCR" -ForegroundColor Gray
Write-Host "Эталонная (Main):    $pbMR" -ForegroundColor Gray
if ($TaskName) { Write-Host "Задача: $TaskName (только объекты из Ready_* папок)" -ForegroundColor Yellow }
Write-Host ""

# If TaskName specified, collect objects from Ready_* folders
$taskObjectNames = $null
if ($TaskName) {
    $releaseRoot = $cfg.paths.release_root
    $matchDir = Get-ChildItem $releaseRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$TaskName*" } | Sort-Object Name -Descending | Select-Object -First 1
    if ($matchDir) {
        $taskPath = $matchDir.FullName
    } else {
        $taskPath = Join-Path $releaseRoot $TaskName
    }
    if (-not (Test-Path $taskPath)) {
        Write-Host "ОШИБКА: Папка задачи не найдена: $taskPath" -ForegroundColor Red
        return
    }
    $readyDirs = Get-ChildItem $taskPath -Directory | Where-Object { $_.Name -like 'Ready_*' -and $_.Name -ne 'Ready_' }
    if (-not $readyDirs) {
        $matchDir = Get-ChildItem $releaseRoot -Directory -ErrorAction SilentlyContinue `
            | Where-Object { $_.Name -like "$TaskName*_*" -and $_.Name -ne $TaskName } | Select-Object -First 1
        if ($matchDir) { $taskPath = $matchDir.FullName }
        $readyDirs = Get-ChildItem $taskPath -Directory | Where-Object { $_.Name -like 'Ready_*' -and $_.Name -ne 'Ready_' }
    }
    if (-not $readyDirs) {
        $gitDirs = Get-ChildItem $taskPath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'Git_*' -and $_.Name -ne 'Git_' }
        if ($gitDirs) {
            Write-Host "Папки Ready_* не найдены, используем Git_*" -ForegroundColor Yellow
            $readyDirs = $gitDirs
        }
    }
    if (-not $readyDirs) {
        Write-Host "ОШИБКА: Папки Ready_* или Git_* не найдены в $taskPath" -ForegroundColor Red
        return
    }
    # Сортировка папок Ready_* по дате (убывание) по имени папки
    $readyDirs = $readyDirs | Sort-Object Name -Descending
    Write-Host "Папки Ready (от newest к oldest): $($readyDirs.Count)" -ForegroundColor Gray
    $readyDirs | ForEach-Object { Write-Host "  $($_.Name)" -ForegroundColor Gray }
    
    # Для каждого объекта берём самую свежую версию из папок Ready_*
    # $taskObjectLatest[baseName] = @{ FilePath = "..."; ReadyDir = "..." }
    $taskObjectLatest = @{}
    foreach ($rd in $readyDirs) {
        Get-ChildItem $rd.FullName -Recurse -File -Filter '*.sr*' | ForEach-Object {
            $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            if (-not $taskObjectLatest.ContainsKey($base)) {
                $taskObjectLatest[$base] = @{
                    FilePath  = $_.FullName
                    FileName  = $_.Name
                    ReadyDir  = $rd.Name
                }
            }
        }
    }
    Write-Host "Уникальных объектов в задаче: $($taskObjectLatest.Count)" -ForegroundColor Yellow
    
    # Валидация: сравниваем Latest Ready с Current
    Write-Host ""
    Write-Host "=== Валидация: Latest Ready vs Current ===" -ForegroundColor Cyan
    $validationErrors = @()
    foreach ($baseName in $taskObjectLatest.Keys) {
        $readyFile = $taskObjectLatest[$baseName].FilePath
        $fileName  = $taskObjectLatest[$baseName].FileName
        $readyDir  = $taskObjectLatest[$baseName].ReadyDir
        
        # Ищем файл в Current
        $currentFile = Get-ChildItem $pbCR -Recurse -File -Filter $fileName -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $currentFile) {
            $validationErrors += "$baseName|Файл отсутствует в Current|$readyFile|(не найден)"
            continue
        }
        
        # Сравниваем MD5
        $readyHash = (Get-FileHash $readyFile -Algorithm MD5).Hash
        $currentHash = (Get-FileHash $currentFile.FullName -Algorithm MD5).Hash
        if ($readyHash -ne $currentHash) {
            $validationErrors += "$baseName|Хеш не совпадает|$readyFile|$($currentFile.FullName)"
        }
    }
    
    if ($validationErrors.Count -gt 0) {
        Write-Host "НАЙДЕНЫ ОШИБКИ ВАЛИДАЦИИ: $($validationErrors.Count)" -ForegroundColor Red
        foreach ($ve in $validationErrors) {
            Write-Host "  $ve" -ForegroundColor Red
            "###VALIDATION_ERROR###$ve"
        }
        # Формируем список имён для продолжения (только валидные объекты)
    }
    
    # Продолжаем только с валидными объектами
    $taskObjectNames = @{}
    foreach ($baseName in $taskObjectLatest.Keys) {
        $veMatch = $validationErrors | Where-Object { $_ -match "^$([regex]::Escape($baseName))\|" }
        if (-not $veMatch) {
            $taskObjectNames[$baseName] = $taskObjectLatest[$baseName].FileName
        }
    }
    
    if ($taskObjectNames.Count -eq 0 -and $validationErrors.Count -gt 0) {
        Write-Host "ОШИБКА: все объекты задачи имеют ошибки валидации" -ForegroundColor Red
        return
    }
    Write-Host "Объектов для сравнения (после валидации): $($taskObjectNames.Count)" -ForegroundColor Yellow
    Write-Host ""
}

# Collect files
$currentFiles = Get-ChildItem $pbCR -Recurse -File | Where-Object { $_.Extension -match '\.sr' }
$mainFiles    = Get-ChildItem $pbMR -Recurse -File | Where-Object { $_.Extension -match '\.sr' }

# Filter by TaskName if specified
if ($taskObjectNames) {
    $currentFiles = $currentFiles | Where-Object { $taskObjectNames.ContainsKey([System.IO.Path]::GetFileNameWithoutExtension($_.Name)) }
    $mainFiles    = $mainFiles    | Where-Object { $taskObjectNames.ContainsKey([System.IO.Path]::GetFileNameWithoutExtension($_.Name)) }
    Write-Host "После фильтрации по задаче:" -ForegroundColor Cyan
    Write-Host "  PB_Current: $($currentFiles.Count) файлов" -ForegroundColor Yellow
    Write-Host "  PB_Main:    $($mainFiles.Count) файлов" -ForegroundColor Yellow
} else {
    Write-Host "PB_Current: $($currentFiles.Count) файлов" -ForegroundColor Yellow
    Write-Host "PB_Main:    $($mainFiles.Count) файлов" -ForegroundColor Yellow
}

# Build Main lookup
$mainLookup = @{}
foreach ($f in $mainFiles) {
    $rel = $f.FullName.Substring($pbMR.Length + 1)
    $mainLookup[$rel] = $f
}

$results = @()
$diffByLib = @{}

# Compare Current -> Main
$totalCompare = $currentFiles.Count + $mainFiles.Count
Write-Host "###PHASE###CompareCurrent|$($currentFiles.Count)###"
foreach ($cf in $currentFiles) {
    $rel = $cf.FullName.Substring($pbCR.Length + 1)
    $lib = $rel.Split('\')[0]
    $name = $rel.Split('\')[-1]

    if (-not $mainLookup.ContainsKey($rel)) {
        $results += [PSCustomObject]@{
            Library    = $lib
            ObjectName = $name
            Status     = "NOT_IN_MAIN"
            CurrentMD5 = (Get-FileHash $cf.FullName -Algorithm MD5).Hash
            MainMD5    = "-"
        }
        if (-not $diffByLib[$lib]) { $diffByLib[$lib] = @{DIFF=0; NOT_IN_MAIN=0; NOT_IN_CURRENT=0} }
        $diffByLib[$lib].NOT_IN_MAIN++
        Write-Host "###STEP###"
        continue
    }

    $mf = $mainLookup[$rel]
    $ch = (Get-FileHash $cf.FullName -Algorithm MD5).Hash
    $mh = (Get-FileHash $mf.FullName -Algorithm MD5).Hash

    if ($ch -ne $mh) {
        $results += [PSCustomObject]@{
            Library    = $lib
            ObjectName = $name
            Status     = "DIFF"
            CurrentMD5 = $ch
            MainMD5    = $mh
        }
        if (-not $diffByLib[$lib]) { $diffByLib[$lib] = @{DIFF=0; NOT_IN_MAIN=0; NOT_IN_CURRENT=0} }
        $diffByLib[$lib].DIFF++
    }
    Write-Host "###STEP###"
}

Write-Host "###PHASE###CompareMain|$($mainFiles.Count)###"
# Compare Main -> Current (NOT_IN_CURRENT)
foreach ($mf in $mainFiles) {
    $rel = $mf.FullName.Substring($pbMR.Length + 1)
    $lib = $rel.Split('\')[0]
    $name = $rel.Split('\')[-1]
    $cfPath = Join-Path $pbCR $rel

    if (-not (Test-Path $cfPath)) {
        $results += [PSCustomObject]@{
            Library    = $lib
            ObjectName = $name
            Status     = "NOT_IN_CURRENT"
            CurrentMD5 = "-"
            MainMD5    = (Get-FileHash $mf.FullName -Algorithm MD5).Hash
        }
        if (-not $diffByLib[$lib]) { $diffByLib[$lib] = @{DIFF=0; NOT_IN_MAIN=0; NOT_IN_CURRENT=0} }
        $diffByLib[$lib].NOT_IN_CURRENT++
    }
    Write-Host "###STEP###"
}

# Output complete comparison table markers
$allRelPaths = @{}
foreach ($cf in $currentFiles) {
    $rel = $cf.FullName.Substring($pbCR.Length + 1)
    $allRelPaths[$rel] = $cf
}
foreach ($mf in $mainFiles) {
    $rel = $mf.FullName.Substring($pbMR.Length + 1)
    if (-not $allRelPaths.ContainsKey($rel)) { $allRelPaths[$rel] = $mf }
}
$matchedStatus = @{}
foreach ($r in $results) {
    $key = $r.Library + "\" + $r.ObjectName
    $matchedStatus[$key] = $r.Status
}
foreach ($rel in ($allRelPaths.Keys | Sort-Object)) {
    $key = $rel
    if ($matchedStatus.ContainsKey($key)) {
        $st = $matchedStatus[$key]
    } else {
        $st = "SAME"
    }
    "###PB_COMPARE_TABLE###$($key)|$st"
}

# Sort results: status, then library, then name
$results = $results | Sort-Object Status, Library, ObjectName

# -- Display summary table --
Write-Host ""
Write-Host ("{0,-25} {1,6} {2,13} {3,16} {4,7}" -f "Библиотека", "ДИФФ", "НЕТ_MAIN", "НЕТ_CRNT", "ВСЕГО") -ForegroundColor Yellow
Write-Host ("="*70)
$totalD = 0; $totalNim = 0; $totalNic = 0
$diffByLib.Keys | Sort-Object | ForEach-Object {
    $d = $diffByLib[$_]
    $t = $d.DIFF + $d.NOT_IN_MAIN + $d.NOT_IN_CURRENT
    Write-Host ("{0,-25} {1,6} {2,13} {3,16} {4,7}" -f $_, $d.DIFF, $d.NOT_IN_MAIN, $d.NOT_IN_CURRENT, $t)
    $totalD += $d.DIFF; $totalNim += $d.NOT_IN_MAIN; $totalNic += $d.NOT_IN_CURRENT
}
Write-Host ("="*70)
$grandTotal = $totalD + $totalNim + $totalNic
Write-Host ("{0,-25} {1,6} {2,13} {3,16} {4,7}" -f "ВСЕГО", $totalD, $totalNim, $totalNic, $grandTotal) -ForegroundColor Cyan

# -- Display detailed list --
Write-Host ""
Write-Host "=== Детальный список различий ===" -ForegroundColor Cyan
Write-Host ""
$currentStatus = ""
foreach ($r in $results) {
    if ($r.Status -ne $currentStatus) {
        $currentStatus = $r.Status
        $color = @{"DIFF"="Red"; "NOT_IN_MAIN"="Yellow"; "NOT_IN_CURRENT"="Magenta"}[$r.Status]
        $statusRu = @{"DIFF"="РАЗЛИЧАЮТСЯ"; "NOT_IN_MAIN"="НЕТ В MAIN"; "NOT_IN_CURRENT"="НЕТ В CURRENT"}[$r.Status]
        Write-Host "--- $statusRu ---" -ForegroundColor $color
    }
    Write-Host ("  {0,-30}  {1}" -f ($r.Library+"\"+$r.ObjectName), $r.Status)
    # Генерация маркера для диалога сравнения TortoiseMerge
    $objFull = $r.Library+"\"+$r.ObjectName
    $basePath = if ($r.Status -eq "NOT_IN_CURRENT") { "" } else { Join-Path $pbCR ($r.Library+"\"+$r.ObjectName) }
    $readyPath = if ($r.Status -eq "NOT_IN_MAIN") { "" } else { Join-Path $pbMR ($r.Library+"\"+$r.ObjectName) }
    $compareType = if ($r.Status -eq "NOT_IN_MAIN") { "Current" } else { "Main" }
    "###DIFF_OBJECT###$objFull|$($r.Status)|$basePath|$readyPath|$compareType"
}

# -- Save report --
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("==============================================")
[void]$sb.AppendLine("  COMPARE POWERBUILDER: Current vs Main")
[void]$sb.AppendLine("  Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
if ($TaskName) { [void]$sb.AppendLine("  Task: $TaskName") }
[void]$sb.AppendLine("  Current: $pbCR")
[void]$sb.AppendLine("  Main:    $pbMR")
[void]$sb.AppendLine("==============================================")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Files: Current=$($currentFiles.Count)  Main=$($mainFiles.Count)  Diff=$grandTotal")
[void]$sb.AppendLine("")

# Summary table
[void]$sb.AppendLine(("{0,-25} {1,6} {2,13} {3,16} {4,7}" -f "Library", "DIFF", "NOT_IN_MAIN", "NOT_IN_CURRENT", "TOTAL"))
[void]$sb.AppendLine(("-"*70))
$diffByLib.Keys | Sort-Object | ForEach-Object {
    $d = $diffByLib[$_]
    $t = $d.DIFF + $d.NOT_IN_MAIN + $d.NOT_IN_CURRENT
    [void]$sb.AppendLine(("{0,-25} {1,6} {2,13} {3,16} {4,7}" -f $_, $d.DIFF, $d.NOT_IN_MAIN, $d.NOT_IN_CURRENT, $t))
}
[void]$sb.AppendLine(("-"*70))
[void]$sb.AppendLine(("{0,-25} {1,6} {2,13} {3,16} {4,7}" -f "TOTAL", $totalD, $totalNim, $totalNic, $grandTotal))
[void]$sb.AppendLine("")

# Detailed list
[void]$sb.AppendLine("=== Detailed list ===")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Library                           Object             Status")
[void]$sb.AppendLine("----------------------------------------------------------------")
foreach ($r in $results) {
    [void]$sb.AppendLine(("{0,-33} {1}" -f ($r.Library+"\"), $r.ObjectName, $r.Status))
}

[System.IO.File]::WriteAllText($OutputFile, $sb.ToString(), [System.Text.Encoding]::Default)
Write-Host ""
Write-Host "Отчёт сохранён: $OutputFile" -ForegroundColor Green

