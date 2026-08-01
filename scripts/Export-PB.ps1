<#
.SYNOPSIS
    Выгрузка объектов PowerBuilder из PBL-файлов.
.DESCRIPTION
    Выгружает объекты из библиотек PowerBuilder (PBL) с помощью pbldump.
    Поддерживает выгрузку из Current или Main.
    Если указана задача (TaskName) — выгружаются только объекты из Ready_* папок этой задачи.
    Если задача не указана — выгружаются все объекты из библиотек, указанных в PBT-файле.
.PARAMETER Source
    Источник выгрузки: "Current" или "Main".
.PARAMETER TaskName
    Имя задачи Jira. Если указано — выгружаются только объекты из Ready_* папок.
.PARAMETER OutputDir
    Папка для выгрузки. Если не указана — используется PB_Current или PB_Main из config.json.
.PARAMETER ConfigPath
    Путь к config.json.
.EXAMPLE
    .\Export-PB.ps1 -Source Current
    .\Export-PB.ps1 -Source Main -TaskName "SYBASE-19248"
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Current","Main")]
    [string]$Source,
    [string]$TaskName = "",
    [string]$OutputDir = "",
    [string]$ConfigPath = "C:\AIS\AI\Prod\config\config.json"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ConfigPath)) { throw "Конфиг не найден: $ConfigPath" }
$cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

# Определение путей
$PbldumpExe = $cfg.paths.pbl_dump
if (-not $PbldumpExe -or -not (Test-Path $PbldumpExe)) { throw "pbldump не найден: $PbldumpExe" }

if ($Source -eq "Current") {
    $MisRoot = $cfg.paths.pb_current_source
    $defaultOut = $cfg.paths.pb_current_export
} else {
    $MisRoot = $cfg.paths.pb_main_source
    $defaultOut = $cfg.paths.pb_main_export
}

$OutRoot = if ($OutputDir) { $OutputDir } else { $defaultOut }
if (-not (Test-Path $MisRoot)) { throw "Папка-источник не найдена: $MisRoot" }

# PBT-файл — имя из config или по умолчанию "gold"
$pbtName = if ($cfg.paths.pbt_name) { $cfg.paths.pbt_name } else { "gold" }
$pbtFile = Join-Path $MisRoot "${pbtName}.pbt"
if (-not (Test-Path $pbtFile)) { throw "PBT-файл не найден: $pbtFile" }

Write-Host "=== Выгрузка PowerBuilder: $Source ===" -ForegroundColor Cyan
Write-Host "Источник:    $MisRoot" -ForegroundColor Gray
Write-Host "Назначение:  $OutRoot" -ForegroundColor Gray
Write-Host "PBT-файл:    $pbtFile" -ForegroundColor Gray
if ($TaskName) { Write-Host "Задача:      $TaskName (только объекты из Ready_* папок)" -ForegroundColor Yellow }
Write-Host ""

# Парсинг PBT-файла — получение списка PBL-библиотек
$raw = Get-Content -LiteralPath $pbtFile -Raw
if ($raw -notmatch 'LibList\s+"([^"]+)"') { throw "Строка LibList не найдена в: $pbtFile" }
$libEntries = $matches[1] -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
Write-Host "Библиотек в PBT: $($libEntries.Count)" -ForegroundColor Gray

# Если указана задача — собираем имена объектов из Ready_* папок
$taskObjectNames = $null
if ($TaskName) {
    $releaseRoot = $cfg.paths.release_root
    $matchDir = Get-ChildItem $releaseRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$TaskName*" } | Sort-Object Name -Descending | Select-Object -First 1
    if ($matchDir) {
        $taskPath = $matchDir.FullName
    } else {
        $taskPath = Join-Path $releaseRoot $TaskName
    }
    if (-not (Test-Path $taskPath)) { throw "Папка задачи не найдена: $taskPath" }
    
    $readyDirs = Get-ChildItem $taskPath -Directory | Where-Object { $_.Name -like 'Ready_*' -and $_.Name -ne 'Ready_' }
    if (-not $readyDirs) { throw "Папки Ready_* не найдены в $taskPath" }
    Write-Host "Папки Ready: $($readyDirs.Count)" -ForegroundColor Gray
    # Сортировка от newest к oldest — берём latest версию каждого объекта
    $readyDirs = $readyDirs | Sort-Object Name -Descending
    $taskObjectLatest = @{}
    foreach ($rd in $readyDirs) {
        Get-ChildItem $rd.FullName -Recurse -File -Filter '*.sr*' | ForEach-Object {
            $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            if (-not $taskObjectLatest.ContainsKey($base)) {
                $taskObjectLatest[$base] = $_.Name
            }
        }
    }
    Write-Host "Объектов в задаче: $($taskObjectLatest.Count)" -ForegroundColor Yellow
    Write-Host ""
    # Преобразуем в простой hashtable для совместимости с остальным кодом
    $taskObjectNames = @{}
    foreach ($k in $taskObjectLatest.Keys) { $taskObjectNames[$k] = $taskObjectLatest[$k] }
}
# Подсчёт библиотек для прогресс-бара
$validLibs = $libEntries | Where-Object {
    $e = $_ -replace '\\+', '\'
    $ext = [System.IO.Path]::GetExtension($e).ToLowerInvariant()
    $ext -eq '.pbl'
} | Measure-Object | Select-Object -ExpandProperty Count
Write-Host "###PHASE###PB-библиотеки|$validLibs###"
# Обработка каждой библиотеки
$okCount = 0; $errCount = 0; $skipCount = 0; $exportedCount = 0
$usedDirNames = @{}

foreach ($entry in $libEntries) {
    $entry = $entry -replace '\\+', '\'
    $ext = [System.IO.Path]::GetExtension($entry).ToLowerInvariant()
    
    # Пропуск PBD и неизвестных расширений
    if ($ext -eq '.pbd') { Write-Host "  SKIP PBD: $entry" -ForegroundColor DarkGray; $skipCount++; continue }
    if ($ext -ne '.pbl') { Write-Host "  SKIP: $entry (не PBL)" -ForegroundColor DarkGray; $skipCount++; continue }
    
    $fullPath = Join-Path $MisRoot $entry
    if (-not (Test-Path $fullPath)) { Write-Host "  MISSING: $fullPath" -ForegroundColor Red; $errCount++; continue }
    
    # Маркер смены метки для верхнего ПБ
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($entry)
    Write-Host "###PB###${baseName}"
    # Проверка дубликатов
    if (-not $usedDirNames.ContainsKey($baseName)) { $usedDirNames[$baseName] = 0 }
    $usedDirNames[$baseName]++
    $dirName = if ($usedDirNames[$baseName] -eq 1) { $baseName } else { "${baseName}_$($usedDirNames[$baseName])" }
    
    $targetDir = Join-Path $OutRoot $dirName
    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
    
    Write-Host "  $dirName" -NoNewline
    
    # Если указана задача — экспортируем только нужные объекты
    if ($taskObjectNames) {
        # Сначала полный экспорт, потом фильтрация
        Push-Location $targetDir
        try {
            & $PbldumpExe -esu $fullPath '*.*' 2>&1 | Out-Null
            $okCount++
        } catch {
            Write-Host " ОШИБКА" -ForegroundColor Red
            $errCount++
            Pop-Location
            continue
        }
        Pop-Location
        
        # Фильтрация — удаление объектов не из задачи
        $exported = Get-ChildItem $targetDir -File -Filter '*.sr*' -ErrorAction SilentlyContinue
        $removed = 0
        foreach ($f in $exported) {
            $objBase = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if (-not $taskObjectNames.ContainsKey($objBase)) {
                Remove-Item $f.FullName -Force
                $removed++
            }
        }
        $remaining = ($exported | Measure-Object).Count - $removed
        Write-Host " OK ($remaining/$($exported.Count) объектов)" -ForegroundColor Green
        $exportedCount += $remaining
    } else {
        Push-Location $targetDir
        try {
            & $PbldumpExe -esu $fullPath '*.*' 2>&1 | Out-Null
            $okCount++
            $count = (Get-ChildItem $targetDir -File -Filter '*.sr*' | Measure-Object).Count
            Write-Host " OK ($count объектов)" -ForegroundColor Green
            $exportedCount += $count
        } catch {
            Write-Host " ОШИБКА" -ForegroundColor Red
            $errCount++
        }
        Pop-Location
    }
    Write-Host "###STEP###"
}

# Конвертация выгруженных объектов в UTF-8 with BOM, CRLF (не UTF-16)
$convPs = Join-Path $PSScriptRoot "Convert-ExportEncoding.ps1"
if (Test-Path $convPs) {
    Write-Host ""
    & powershell -NoLogo -ExecutionPolicy RemoteSigned -File $convPs -Path $OutRoot -Extensions '*.sr*'
}

Write-Host ""
Write-Host "=== Готово ===" -ForegroundColor Cyan
Write-Host "Выгружено библиотек: $okCount" -ForegroundColor Green
Write-Host "Всего объектов: $exportedCount" -ForegroundColor Green
if ($errCount -gt 0) { Write-Host "Ошибок: $errCount" -ForegroundColor Red }
if ($skipCount -gt 0) { Write-Host "Пропущено: $skipCount" -ForegroundColor Gray }
Write-Host "Назначение: $OutRoot" -ForegroundColor Gray

