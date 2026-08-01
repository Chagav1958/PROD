<#
.SYNOPSIS
    Сравнение SQL-объектов задачи между БД Current (dev_golden) и Main (galaxy).
.DESCRIPTION
    Режим задачи (TaskName задан):
      1. Собирает ТОЛЬКО ИМЕНА объектов из папок Git_/Ready_/Test_ задачи.
      2. ПЕРЕД сравнением выгружает (обновляет) эти объекты из БД Current и Main
         через SQL_exp_single.bat (логин/пароль как в ОП7).
      3. Сравнивает выгруженные файлы Current vs Main по MD5.
      4. Объекты из Ready_* попадают в отчёт всегда; из Git_*/Test_* — только при различии.
      5. Генерирует маркеры ###SQL_TASK_OBJECT### для диалога выбора действий.
    Режим без задачи (TaskName пуст):
      Сравнивает все объекты Current vs Main и генерирует маркеры ###DIFF_OBJECT###
      (старое поведение, диалог TortoiseMerge).
.PARAMETER TaskName
    Имя задачи Jira (папка в release_root).
.PARAMETER Password
    Пароль Sybase для логина vchaga.
.PARAMETER ConfigPath
    Путь к config.json.
#>
param(
    [string]$TaskName = "",
    [string]$Password = "",
    [string]$ConfigPath = "C:\AIS\AI\Prod\config\config.json"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ConfigPath)) { throw "Конфиг не найден: $ConfigPath" }
$cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

$bdCurrent = $cfg.paths.bd_current_export
$bdMain    = $cfg.paths.bd_main_export
$releaseRoot = $cfg.paths.release_root
$bat = "C:\AIS\AI\Prod\bin\SQL_exp_single.bat"
$db  = "golden"
$srvCurrent = "dev_golden"
$srvMain    = "galaxy"

if (-not $bdCurrent -or -not (Test-Path $bdCurrent)) { throw "SQL Current export не найден: $bdCurrent" }
if (-not $bdMain -or -not (Test-Path $bdMain)) { throw "SQL Main export не найден: $bdMain" }

Write-Host "=== Compare SQL: Current vs Main ===" -ForegroundColor Cyan
Write-Host "Current (SQL Current export): $bdCurrent"
Write-Host "Main    (SQL Main export):    $bdMain"

# ---------------------------------------------------------------------------
# Режим БЕЗ задачи — сравнение всех объектов (старое поведение)
# ---------------------------------------------------------------------------
if (-not $TaskName) {
    Write-Host "Задача не указана — сравнение всех объектов." -ForegroundColor Yellow
    $subdirs = @("Procedure","Functions","Triggers","Tables","Views","Indexes","PK","FK","Grants")
    $currentFiles = @{}; $mainFiles = @{}
    foreach ($sd in $subdirs) {
        $curSub = Join-Path $bdCurrent $sd
        $mainSub = Join-Path $bdMain $sd
        if (Test-Path $curSub) { Get-ChildItem $curSub -File -Filter '*.sql' | ForEach-Object { $currentFiles[$_.Name] = $_.FullName } }
        if (Test-Path $mainSub) { Get-ChildItem $mainSub -File -Filter '*.sql' | ForEach-Object { $mainFiles[$_.Name] = $_.FullName } }
    }
    Write-Host "Файлов в Current: $($currentFiles.Count)"
    Write-Host "Файлов в Main:    $($mainFiles.Count)"
    $allNames = @($currentFiles.Keys) + @($mainFiles.Keys) | Select-Object -Unique | Sort-Object
    $diffResults = @()
    foreach ($name in $allNames) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($name)
        $curPath = if ($currentFiles.ContainsKey($name)) { $currentFiles[$name] } else { $null }
        $mainPath = if ($mainFiles.ContainsKey($name)) { $mainFiles[$name] } else { $null }
        if (-not $curPath -and $mainPath) {
            Write-Host "  $baseName : НЕТ В CURRENT" -ForegroundColor Magenta
            $diffResults += [PSCustomObject]@{ ObjectName=$baseName; Status="NOT_IN_CURRENT"; CurrentPath=""; MainPath=$mainPath }
        } elseif ($curPath -and -not $mainPath) {
            Write-Host "  $baseName : НЕТ В MAIN" -ForegroundColor Yellow
            $diffResults += [PSCustomObject]@{ ObjectName=$baseName; Status="NOT_IN_MAIN"; CurrentPath=$curPath; MainPath="" }
        } else {
            $ch = (Get-FileHash $curPath -Algorithm MD5).Hash
            $mh = (Get-FileHash $mainPath -Algorithm MD5).Hash
            if ($ch -ne $mh) {
                Write-Host "  $baseName : РАЗЛИЧАЮТСЯ" -ForegroundColor Red
                $diffResults += [PSCustomObject]@{ ObjectName=$baseName; Status="DIFF"; CurrentPath=$curPath; MainPath=$mainPath }
            } else {
                Write-Host "  $baseName : СОВПАДАЕТ" -ForegroundColor Green
            }
        }
        Write-Host "###STEP###"
    }
    Write-Host ""
    Write-Host "=== ИТОГО ===" -ForegroundColor Cyan
    Write-Host "Всего: $($allNames.Count)"
    Write-Host "Различаются: $(@($diffResults | Where-Object { $_.Status -eq 'DIFF' }).Count)" -ForegroundColor Red
    Write-Host "Нет в Current: $(@($diffResults | Where-Object { $_.Status -eq 'NOT_IN_CURRENT' }).Count)" -ForegroundColor Magenta
    Write-Host "Нет в Main:    $(@($diffResults | Where-Object { $_.Status -eq 'NOT_IN_MAIN' }).Count)" -ForegroundColor Yellow
    if ($diffResults.Count -gt 0) {
        foreach ($r in $diffResults) {
            $basePath = if ($r.CurrentPath) { $r.CurrentPath } else { "" }
            $readyPath = if ($r.MainPath) { $r.MainPath } else { "" }
            $compareType = if ($r.Status -eq "NOT_IN_MAIN") { "Current" } else { "Main" }
            "###DIFF_OBJECT###$($r.ObjectName)|$($r.Status)|$basePath|$readyPath|$compareType"
        }
    }
    return
}

# ---------------------------------------------------------------------------
# Режим ЗАДАЧИ
# ---------------------------------------------------------------------------
Write-Host "Задача: $TaskName" -ForegroundColor Yellow
$matchDir = Get-ChildItem $releaseRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$TaskName*" } | Sort-Object Name -Descending | Select-Object -First 1
if ($matchDir) {
    $taskPath = $matchDir.FullName
} else {
    $taskPath = Join-Path $releaseRoot $TaskName
}
if (-not (Test-Path $taskPath)) { throw "Папка задачи не найдена: $TaskName" }
Write-Host "Папка задачи: $taskPath"

function Get-ObjectType {
    param([string]$Name, [string]$SubPath)
    if ($SubPath -match 'Procedure') { return 'Procedure' }
    if ($SubPath -match 'Functions') { return 'Function' }
    if ($SubPath -match 'Triggers')  { return 'Trigger' }
    if ($SubPath -match 'Tables')    { return 'Table' }
    if ($SubPath -match 'Views')     { return 'View' }
    if ($SubPath -match 'Indexes')   { return 'Index' }
    if ($SubPath -match 'PK')        { return 'PK' }
    if ($SubPath -match 'FK')        { return 'FK' }
    if ($SubPath -match 'Grants')    { return 'Grant' }
    if ($Name -like 'usp_*' -or $Name -like 'p_*' -or $Name -like 'pr_*') { return 'Procedure' }
    if ($Name -like 'fn*') { return 'Function' }
    if ($Name -like 'td_*' -or $Name -like 'ti_*' -or $Name -like 'tu_*' -or $Name -like 'tr_*' -or $Name -like 'tg_*') { return 'Trigger' }
    return 'Procedure'
}

# Сбор ТОЛЬКО ИМЁН объектов из Git_/Ready_/Test_
$taskObjects = @{}
foreach ($prefix in @('Git_*','Ready_*','Test_*')) {
    Get-ChildItem $taskPath -Directory -Filter $prefix -ErrorAction SilentlyContinue | ForEach-Object {
        $folderDir = $_.FullName
        $folderName = $_.Name
        Get-ChildItem $folderDir -Recurse -File -Filter '*.sql' -ErrorAction SilentlyContinue | ForEach-Object {
            $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            $rel = $_.DirectoryName.Substring($folderDir.Length).TrimStart('\')
            $type = Get-ObjectType -Name $base -SubPath $rel
            if (-not $taskObjects.ContainsKey($base)) {
                $taskObjects[$base] = @{ Type=$type; Folder=$folderName; FilePath=$_.FullName }
            }
        }
    }
}

if ($taskObjects.Count -eq 0) {
    Write-Host "В папках Git_/Ready_/Test_ задачи не найдено SQL-объектов." -ForegroundColor Yellow
    return
}

Write-Host "Собрано имён объектов из папок задачи: $($taskObjects.Count)" -ForegroundColor Yellow
$taskObjects.Keys | Sort-Object | ForEach-Object { Write-Host "  $_ ($($taskObjects[$_].Type), $($taskObjects[$_].Folder))" -ForegroundColor Gray }

# ПЕРЕД сравнением — обновляем (выгружаем) объекты из БД Current и Main
if (-not $Password) { Write-Host "[ПРЕДУПРЕЖДЕНИЕ] Пароль не передан — выгрузка из БД может не пройти." -ForegroundColor Yellow }
$idx = 0
foreach ($key in ($taskObjects.Keys | Sort-Object)) {
    $idx++
    $obj = $taskObjects[$key]
    $objType = $obj.Type
    $objName = $key
    Write-Host "###PHASE###Export|$($taskObjects.Count)|$idx###"
    Write-Host "  [$idx/$($taskObjects.Count)] Выгрузка: $objName ($objType)"
    $quotedArgs = @($objType, $objName, $srvCurrent, $db, $Password) | ForEach-Object { "`"$_`"" }
    & cmd /c "`"$bat`" $($quotedArgs -join ' ') 2>&1" | Out-Null
    $quotedArgs = @($objType, $objName, $srvMain, $db, $Password) | ForEach-Object { "`"$_`"" }
    & cmd /c "`"$bat`" $($quotedArgs -join ' ') 2>&1" | Out-Null
    Write-Host "###STEP###"
}

# Сравнение выгруженных объектов Current vs Main
$typeFolderMap = @{ Procedure='Procedure'; Function='Functions'; Trigger='Triggers'; Table='Tables'; View='Views'; Index='Indexes'; PK='PK'; FK='FK'; Grant='Grants' }
$results = @()
foreach ($key in ($taskObjects.Keys | Sort-Object)) {
    $obj = $taskObjects[$key]
    $objType = $obj.Type
    $objName = $key
    $folder = $obj.Folder
    $filePath = $obj.FilePath
    $tf = $typeFolderMap[$objType]
    $curPath = Join-Path $bdCurrent ($tf + "\$objName.sql")
    $mainPath = Join-Path $bdMain ($tf + "\$objName.sql")
    $curExists = Test-Path $curPath
    $mainExists = Test-Path $mainPath
    $status = ''
    if (-not $curExists -and -not $mainExists) {
        $status = 'NOT_EXPORTED'
        Write-Host "  $objName : НЕ ВЫГРУЖЕН" -ForegroundColor Red
    } elseif (-not $curExists) {
        $status = 'NOT_IN_CURRENT'
        Write-Host "  $objName : НЕТ В CURRENT" -ForegroundColor Magenta
    } elseif (-not $mainExists) {
        $status = 'NOT_IN_MAIN'
        Write-Host "  $objName : НЕТ В MAIN" -ForegroundColor Yellow
    } else {
        $ch = (Get-FileHash $curPath -Algorithm MD5).Hash
        $mh = (Get-FileHash $mainPath -Algorithm MD5).Hash
        if ($ch -ne $mh) { $status = 'DIFF'; Write-Host "  $objName : РАЗЛИЧАЮТСЯ" -ForegroundColor Red }
        else { $status = 'SAME'; Write-Host "  $objName : СОВПАДАЕТ" -ForegroundColor Green }
    }
    $results += [PSCustomObject]@{ ObjectName=$objName; Type=$objType; Folder=$folder; Status=$status; FilePath=$filePath }
}

# Фильтрация: Ready_* — всегда; Git_*/Test_* — только при различии
$toShow = @($results | Where-Object {
    if ($_.Folder -like 'Ready_*') { return $true }
    if ($_.Status -eq 'DIFF') { return $true }
    return $false
})

Write-Host ""
Write-Host "=== ИТОГО ===" -ForegroundColor Cyan
Write-Host "Всего объектов: $($results.Count)"
Write-Host "К показу: $($toShow.Count)"
Write-Host "  DIFF:           $(@($results | Where-Object { $_.Status -eq 'DIFF' }).Count)" -ForegroundColor Red
Write-Host "  NOT_IN_MAIN:    $(@($results | Where-Object { $_.Status -eq 'NOT_IN_MAIN' }).Count)" -ForegroundColor Yellow
Write-Host "  NOT_IN_CURRENT: $(@($results | Where-Object { $_.Status -eq 'NOT_IN_CURRENT' }).Count)" -ForegroundColor Magenta
Write-Host "  NOT_EXPORTED:   $(@($results | Where-Object { $_.Status -eq 'NOT_EXPORTED' }).Count)" -ForegroundColor Red

if ($toShow.Count -gt 0) {
    foreach ($r in $toShow) {
        "###SQL_TASK_OBJECT###$($r.ObjectName)|$($r.Type)|$($r.Folder)|$($r.Status)|$($r.FilePath)"
    }
    if ($toShow.Count -gt 10) { "###CONFIRM_DIFF###$($toShow.Count)" }
}

