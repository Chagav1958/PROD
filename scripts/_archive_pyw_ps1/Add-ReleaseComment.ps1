<#
.SYNOPSIS
    Добавляет комментарий в задачу Jira с таблицей объектов PB и SQL к выпуску в ПРОД.
.DESCRIPTION
    Сканирует папки Ready_* указанной задачи, собирает объекты PowerBuilder (.sr*)
    и SQL (.sql), и создаёт комментарий в Jira с таблицей этих объектов в формате Jira-вики.
    Таблица содержит 4 колонки: Проект/Сервер, Библиотека/БД, Наименование объекта, Информация.
.PARAMETER TaskName
    Идентификатор задачи Jira (например SYBASE-19337)
.PARAMETER ProjectName
    Имя проекта PowerBuilder (по умолчанию "AIS")
.PARAMETER JiraUser
    E-mail для Jira (опционально, из config.json по умолчанию)
.PARAMETER JiraPassword
    Пароль/токен Jira (опционально, будет запрошен)
.PARAMETER ConfigPath
    Путь к config.json
.PARAMETER Force
    Без подтверждения
.EXAMPLE
    .\Add-ReleaseComment.ps1 -TaskName SYBASE-19337 -JiraPassword "token"
.EXAMPLE
    .\Add-ReleaseComment.ps1 -TaskName SYBASE-19337
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$TaskName,
    [string]$ProjectName = "AIS",
    [string]$JiraUser,
    [string]$JiraPassword,
    [string]$DbPassword,
    [string]$VssDb,
    [string]$VssUser,
    [string]$VssPass,
    [string]$ConfigPath = "C:\AIS\AI\Prod\config\config.json",
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ConfigPath)) { throw "Конфиг не найден: $ConfigPath" }
$cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

$vssHistoryScript = Join-Path $cfg.paths.scripts_dir "VSS-History.ps1"
if (Test-Path $vssHistoryScript) { . $vssHistoryScript }

$jiraBase   = $cfg.jira.base_url
$jiraUser   = if ($JiraUser) { $JiraUser } else { $cfg.jira.jira_email }
$releaseRoot = $cfg.paths.release_root

if ([string]::IsNullOrWhiteSpace($JiraPassword)) {
    if ($DryRun) {
        $JiraPassword = "dryrun"
    } else {
        $securePass = Read-Host "Пароль/токен Jira" -AsSecureString
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
        $JiraPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    }
}

# PAT (Personal Access Token) — Bearer, иначе Basic Auth
if ($JiraPassword -match '^[a-zA-Z0-9+/=]{20,}$') {
    $authHeader = "Bearer $JiraPassword"
} else {
    $authBytes = [System.Text.Encoding]::ASCII.GetBytes("$($jiraUser):$($JiraPassword)")
    $authHeader = "Basic " + [Convert]::ToBase64String($authBytes)
}
$headers = @{ Authorization = $authHeader }

function Invoke-Jira {
    param([string]$Method, [string]$Endpoint, $Body)
    $uri = "$jiraBase/rest/api/2/$Endpoint"
    $params = @{Uri=$uri; Method=$Method; Headers=$headers; ContentType="application/json;charset=utf-8"}
    if ($Body) {
        $jsonBody = ($Body | ConvertTo-Json -Depth 10)
        $params.Body = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
    }
    try { return Invoke-RestMethod @params -ErrorAction Stop } catch { throw "Ошибка Jira API ($Method $Endpoint): " + $_.Exception.Message }
}

Write-Host "=== Комментарий в Jira: таблица объектов ===" -ForegroundColor Cyan
Write-Host "Задача: $TaskName"
Write-Host "Пользователь: $jiraUser"
Write-Host ""

$found = Get-ChildItem $releaseRoot -Directory | Where-Object { $_.Name -like "$TaskName*" } | Sort-Object Name -Descending | Select-Object -First 1
if ($found) {
    $taskPath = $found.FullName
    Write-Host "Найдено: $taskPath" -ForegroundColor Green
} else {
    $taskPath = Join-Path $releaseRoot $TaskName
    if (-not (Test-Path $taskPath)) { throw "Папка задачи не найдена: $taskPath" }
}

$readyDirs = Get-ChildItem $taskPath -Directory | Where-Object { $_.Name -like "Ready_*" -and $_.Name -ne "Ready_" } | Sort-Object Name -Descending
if ($readyDirs.Count -eq 0) { throw "Папки Ready не найдены в $taskPath" }
Write-Host "Найдено папок Ready: $($readyDirs.Count)" -ForegroundColor Cyan

$pbObjects = @{}
$sqlObjects = @{}
foreach ($rd in $readyDirs) {
    $files = Get-ChildItem $rd.FullName -Recurse -File
    foreach ($f in $files) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        if ($f.Extension -match '^\.sr') {
            if (-not $pbObjects.ContainsKey($baseName)) {
                $parentDir = $f.Directory.Name
                $lib = if ($parentDir -eq 'PB' -or $parentDir -eq 'SQL') { "" } else { $parentDir }
                $pbObjects[$baseName] = @{ Name = $baseName; File = $f.Name; Path = $f.FullName; Library = $lib }
            }
        } elseif ($f.Extension -eq '.sql') {
            if (-not $sqlObjects.ContainsKey($baseName)) {
                $sqlObjects[$baseName] = @{ Name = $baseName; File = $f.Name; Path = $f.FullName }
            }
        }
    }
}

if ($pbObjects.Count -eq 0 -and $sqlObjects.Count -eq 0) {
    throw "Не найдено ни одного объекта PB или SQL в папках Ready задачи '$TaskName'"
}

Write-Host "Найдено объектов: PB=$($pbObjects.Count), SQL=$($sqlObjects.Count)" -ForegroundColor Green

# Определение библиотеки PB по имени объекта
function Get-PbLibraryName {
    param([string]$ObjectName)
    $searchDirs = @($cfg.paths.pb_current_export, $cfg.paths.pb_main_export)
    foreach ($dir in $searchDirs) {
        if (Test-Path $dir) {
            $found = Get-ChildItem $dir -Recurse -File -Filter "$ObjectName.sr*" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { return $found.Directory.Name }
        }
    }
    return "???"
}

# Поиск исходного объекта (OLDPB/OLDSQL) в папках Git_*
function Get-GitObjectPath {
    param([string]$ObjectName, [string]$Pattern)
    $gitDirs = Get-ChildItem $taskPath -Directory | Where-Object { $_.Name -like 'Git_*' -and $_.Name -ne 'Git_' } | Sort-Object Name -Descending
    foreach ($gd in $gitDirs) {
        $f = Get-ChildItem $gd.FullName -Recurse -File -Filter $Pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($f) { return $f.FullName }
    }
    return $null
}

# Вспомогательная функция: читает файл с автоопределением кодировки
function Get-FileLinesWithEncoding {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $encoding = if ($bytes.Length -gt 1 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        [Text.Encoding]::Unicode  # UTF-16LE с BOM
    } elseif ($bytes.Length -gt 2 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        [Text.Encoding]::UTF8     # UTF-8 с BOM
    } elseif ($bytes.Length -gt 3 -and $bytes -match '^(45|47|48|49|4C|50)') {
        # Первые байты похожи на ASCII -- SYBASE/CREATE и т.д.
        # Проверяем UTF-8 признаки: байты 0x80-0xBF после 0xC0-0xDF или 0xE0-0xEF
        $isUtf8 = $true
        for ($i = 0; $i -lt $bytes.Length -and $i -lt 200; $i++) {
            $b = $bytes[$i]
            if ($b -ge 0x80 -and $b -le 0xBF) {
                # Продолжающий байт UTF-8 - OK
            } elseif ($b -ge 0xC0 -and $b -le 0xDF) {
                # Начало 2-байтового символа
                if ($i + 1 -lt $bytes.Length -and $bytes[$i+1] -ge 0x80 -and $bytes[$i+1] -le 0xBF) { $i++ } else { $isUtf8 = $false; break }
            } elseif ($b -ge 0xE0 -and $b -le 0xEF) {
                # Начало 3-байтового символа (кириллица)
                if ($i + 2 -lt $bytes.Length -and $bytes[$i+1] -ge 0x80 -and $bytes[$i+1] -le 0xBF -and $bytes[$i+2] -ge 0x80 -and $bytes[$i+2] -le 0xBF) { $i += 2 } else { $isUtf8 = $false; break }
            } elseif ($b -ge 0xF0 -and $b -le 0xF7) {
                # 4-байтовый символ
                if ($i + 3 -lt $bytes.Length -and $bytes[$i+1] -ge 0x80 -and $bytes[$i+1] -le 0xBF -and $bytes[$i+2] -ge 0x80 -and $bytes[$i+2] -le 0xBF -and $bytes[$i+3] -ge 0x80 -and $bytes[$i+3] -le 0xBF) { $i += 3 } else { $isUtf8 = $false; break }
            } elseif ($b -ge 0x80) {
                $isUtf8 = $false; break
            }
        }
        if ($isUtf8) { [Text.Encoding]::UTF8 } else { [Text.Encoding]::GetEncoding(1251) }
    } else {
        [Text.Encoding]::GetEncoding(1251)  # CP1251 (ANSI русская Windows)
    }
    return [System.IO.File]::ReadAllLines($Path, $encoding)
}

# Анализ изменений PB: сравнение .sr* файлов, поиск изменённых функций/элементов
function Get-PbDiffInfo {
    param([string]$NewPath, [string]$OldPath, [string]$ObjectName)
    if (-not $OldPath) { return "" }
    if (-not (Test-Path $OldPath)) { return "" }

    $newLines = Get-FileLinesWithEncoding $NewPath
    $oldLines = Get-FileLinesWithEncoding $OldPath

    # Разбиваем на блоки функций/событий
    function Split-PbBlocks {
        param([string[]]$Lines)
        $blocks = @()
        $i = 0
        while ($i -lt $Lines.Count) {
            $line = $Lines[$i]
            $name = $null; $start = $i

            # Пропускаем секции объявлений
            if ($line -match '^\s*(forward\s+prototypes|type\s+variables|forward)\s*$') {
                $section = $matches[1]
                $endKwd = if ($section -match 'forward' -and $section -eq 'forward') { 'end forward' } elseif ($section -eq 'type variables') { 'end variables' } else { 'end prototypes' }
                $i++
                while ($i -lt $Lines.Count -and $Lines[$i] -notmatch "^\s*$endKwd") { $i++ }
                $i++
                continue
            }

            if ($line -match '^\s*(?:public|private|protected)?\s*(?:function\s+\w+\s+|subroutine\s+|event\s+(?:type\s+\w+\s+)?)(\w+)') {
                $name = $matches[1]
                $full = $matches[0]
                if ($full -match '\bfunction\b') { $type = "function" } elseif ($full -match '\bsubroutine\b') { $type = "subroutine" } else { $type = "event" }
                $endKwd = "end $type"
                $i++
                while ($i -lt $Lines.Count -and $Lines[$i] -notmatch "^\s*$endKwd") { $i++ }
                $block = @{ Name = $name; Type = $type; Start = $start; End = $i; Text = $Lines[$start..$i] }
                $blocks += $block
            } elseif ($line -match '^\s*on\s+(\w+)\.(\w+)') {
                $name = "$($matches[1]).$($matches[2])"
                $i++
                while ($i -lt $Lines.Count -and $Lines[$i] -notmatch '^\s*end\s+on') { $i++ }
                $block = @{ Name = $name; Type = "event"; Start = $start; End = $i; Text = $Lines[$start..$i] }
                $blocks += $block
            }
            $i++
    }
        return $blocks
    }

    $newBlocks = Split-PbBlocks -Lines $newLines
    $oldBlocks = Split-PbBlocks -Lines $oldLines

    $oldMap = @{}
    foreach ($b in $oldBlocks) { $oldMap[$b.Name] = $b }

    $changed = @()
    $added = @()
    $removed = @()

    foreach ($nb in $newBlocks) {
        $ob = $oldMap[$nb.Name]
        if (-not $ob) {
            if ($added -notcontains $nb.Name) { $added += $nb.Name }
        } else {
            $nText = ($nb.Text | ForEach-Object { $_ -replace '\s+', ' ' }) -join "`n"
            $oText = ($ob.Text | ForEach-Object { $_ -replace '\s+', ' ' }) -join "`n"
            if ($nText -ne $oText -and $changed -notcontains $nb.Name) { $changed += $nb.Name }
        }
    }

    foreach ($ob in $oldBlocks) {
        if (-not ($newBlocks | Where-Object { $_.Name -eq $ob.Name }) -and $removed -notcontains $ob.Name) {
            $removed += $ob.Name
        }
    }

    $parts = @()
    if ($changed.Count -gt 0) { $parts += "изменены: " + ($changed -join ", ") }
    if ($added.Count -gt 0) { $parts += "добавлены: " + ($added -join ", ") }
    if ($removed.Count -gt 0) { $parts += "удалены: " + ($removed -join ", ") }

    if ($parts.Count -eq 0) { return "" }
    $result = ($parts -join "; ")
    if ($result.Length -gt 300) { $result = $result.Substring(0, 297) + "..." }
    return $result
}

# Анализ изменений SQL: сравнение .sql файлов, поиск русских комментариев
function Get-SqlDiffInfo {
    param([string]$NewPath, [string]$OldPath, [string]$ObjectName)
    if (-not $OldPath) { return "" }
    if (-not (Test-Path $OldPath)) { return "" }

    $newLines = Get-FileLinesWithEncoding $NewPath
    $oldLines = Get-FileLinesWithEncoding $OldPath

    $ns = $newLines | ForEach-Object { $_ -replace '\s+', ' ' }
    $os = $oldLines | ForEach-Object { $_ -replace '\s+', ' ' }

    $russianComments = @()
    $max = [Math]::Max($ns.Count, $os.Count)
    for ($i = 0; $i -lt $max; $i++) {
        $o = if ($i -lt $os.Count) { $os[$i] } else { "" }
        $n = if ($i -lt $ns.Count) { $ns[$i] } else { "" }
        if ($o -ne $n) {
            $nOrig = if ($i -lt $newLines.Count) { $newLines[$i] } else { "" }
            if ($nOrig -match '^\s*--\s*([А-Яа-я].*)' -or $nOrig -match '/\*.*([А-Яа-я].*)\*/') {
                $russianComments += $matches[1]
            }
        }
    }

    if ($russianComments.Count -eq 0) { return "" }

    # Определяем тип объекта
    $type = "SQL"
    foreach ($l in $newLines) {
        if ($l -match 'CREATE\s+(PROCEDURE|FUNCTION|TRIGGER)\s') {
            $type = $matches[1]
            $type = switch ($type) {
                'PROCEDURE' { "Процедура" }
                'FUNCTION'  { "Функция" }
                'TRIGGER'   { "Триггер" }
                default { $type }
            }
            break
        }
    }

    # Выбираем осмысленные комментарии
    $validComments = $russianComments | Where-Object { $_.Trim().Length -gt 3 -and $_.Trim() -notmatch '^\d+$' }
    if ($validComments.Count -eq 0) { return "" }

    $result = "$type. " + ($validComments -join "; ")
    if ($result.Length -gt 300) { $result = $result.Substring(0, 297) + "..." }
    return $result
}

# ========== Валидация объектов перед сравнением ==========

function Get-FileMd5 {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    return (Get-FileHash $Path -Algorithm MD5).Hash
}

function Add-ValidationResult {
    param($Results, [string]$ObjName, [string]$Type, [string]$ExpectedSource, [string]$ExpectedDir, [string]$ActualPath, [string]$FilePattern)
    if (-not $ActualPath -or -not (Test-Path $ActualPath)) {
        $Results += [PSCustomObject]@{ Object = $ObjName; Тип = $Type; Ожидаемый = $ExpectedSource; Фактический = "Файл не найден"; Статус = "Ошибка" }
        return $Results
    }
    $actualHash = Get-FileMd5 -Path $ActualPath
    $expectedFile = Get-ChildItem $ExpectedDir -Recurse -File -Filter $FilePattern -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $expectedFile) {
        $Results += [PSCustomObject]@{ Object = $ObjName; Тип = $Type; Ожидаемый = $ExpectedSource; Фактический = "Не найден в $ExpectedSource"; Статус = "Ошибка" }
        return $Results
    }
    $expectedHash = Get-FileMd5 -Path $expectedFile.FullName
    $status = if ($actualHash -eq $expectedHash) { "Совпадает" } else { "Не совпадает" }
    $Results += [PSCustomObject]@{ Object = $ObjName; Тип = $Type; Ожидаемый = $ExpectedSource; Фактический = $expectedFile.FullName; Статус = $status }
    return $Results
}

# Автоэкспорт PB-объекта из PBL через pbldump
function Export-PbObject {
    param([string]$ObjectName, [string]$LibraryName, [string]$SourceDir, [string]$TargetExportDir)
    $pbldumpExe = $cfg.paths.pbl_dump
    if (-not $pbldumpExe -or -not (Test-Path $pbldumpExe)) {
        Write-Host "  pbldump не найден: $pbldumpExe" -ForegroundColor DarkYellow
        return $false
    }
    # Поиск PBL по имени библиотеки
    $pblName = "$LibraryName.pbl"
    $pblFile = Get-ChildItem $SourceDir -Recurse -File -Filter $pblName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $pblFile) {
        Write-Host "  PBL '$pblName' не найден в $SourceDir" -ForegroundColor DarkYellow
        return $false
    }
    # Создаём целевую папку
    $targetDir = Join-Path $TargetExportDir $LibraryName
    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
    # Определяем расширение (пробуем srw/srd/sru через поиск в другом экспорте)
    $ext = ".srw"
    $otherDir = if ($TargetExportDir -eq $cfg.paths.pb_current_export) { $cfg.paths.pb_main_export } else { $cfg.paths.pb_current_export }
    $foundInOther = Get-ChildItem $otherDir -Recurse -File -Filter "$ObjectName.sr*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($foundInOther) { $ext = $foundInOther.Extension }
    Push-Location $targetDir
    try {
        Write-Host "  Экспорт pbldump: $ObjectName из $($pblFile.Name)..." -ForegroundColor Yellow
        & $pbldumpExe -esu $pblFile.FullName "$ObjectName.*" 2>&1 | Out-Null
        $exported = Get-ChildItem $targetDir -Filter "$ObjectName.sr*" -File | Select-Object -First 1
        if ($exported) {
            Write-Host "  Экспортирован: $($exported.Name)" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  pbldump не создал файл для $ObjectName" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "  pbldump ошибка: $_" -ForegroundColor Red
        return $false
    } finally { Pop-Location }
}

# Автоэкспорт SQL-объекта через isql
function Export-SqlObject {
    param([string]$ObjectName, [string]$Server, [string]$Database, [string]$TargetDir, [string]$SqlPassword)
    $isql = "isql"
    try { $null = Get-Command $isql -ErrorAction Stop } catch {
        Write-Host "  isql не найден в PATH" -ForegroundColor DarkYellow
        return $false
    }
    # Определяем тип объекта по структуре папок
    $typeDirs = @("Procedure", "Functions", "Triggers", "Tables", "Indexes", "PK", "FK", "Grants")
    $objType = $null
    foreach ($td in $typeDirs) {
        $testPath = Join-Path (Split-Path $TargetDir -Parent) $td
        $existing = Get-ChildItem $testPath -Filter "$ObjectName.sql" -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($existing) {
            $objType = $td
            $targetDir = $existing.DirectoryName
            break
        }
    }
    if (-not $objType) {
        # Пробуем все подпапки TargetDir верхнего уровня
        $parent = Split-Path $TargetDir -Parent
        $found = Get-ChildItem $parent -Recurse -File -Filter "$ObjectName.sql" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $targetDir = $found.DirectoryName
            $objType = $found.Directory.Name
        } else {
            # По умолчанию - Procedure
            $objType = "Procedure"
            $targetDir = Join-Path $parent "Procedure"
            if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        }
    }
    $outFile = Join-Path $targetDir "$ObjectName.sql"
    $tmpSql = Join-Path (Split-Path $TargetDir -Parent) "LOGS\_export_$ObjectName.sql"
    $tmpDir = Split-Path $tmpSql -Parent
    if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }
    $query = "set nocount on`nselect text from syscomments where id=object_id('$ObjectName') order by number, colid`ngo"
    try {
        [System.IO.File]::WriteAllText($tmpSql, $query, [Text.Encoding]::UTF8)
        $login = "vchaga"
        $logFile = Join-Path (Split-Path $TargetDir -Parent) "LOGS\_export_$ObjectName.log"
        & $isql -S $Server -U $login -P $SqlPassword -D $Database -b -h-1 -i $tmpSql -o $outFile 2>&1 | Out-Null
        if ((Test-Path $outFile) -and ((Get-Item $outFile).Length -gt 10)) {
            Write-Host "  Экспортирован SQL: $ObjectName ($objType)" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  isql не создал файл для $ObjectName" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "  isql ошибка: $_" -ForegroundColor Red
        return $false
    } finally { if (Test-Path $tmpSql) { Remove-Item $tmpSql -Force -ErrorAction SilentlyContinue } }
}

# ========== Валидация + автоэкспорт ==========

$validationResults = @()

foreach ($obj in $pbSorted) {
    $libName = Get-PbLibraryName -ObjectName $obj.Name
    # NEWPB -> PB_Current
    $curFile = Get-ChildItem $cfg.paths.pb_current_export -Recurse -File -Filter "$($obj.Name).sr*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $curFile) {
        Write-Host "PB_Current: $($obj.Name) не найден, экспорт из Current..." -ForegroundColor Yellow
        if (Export-PbObject -ObjectName $obj.Name -LibraryName $libName -SourceDir $cfg.paths.pb_current_source -TargetExportDir $cfg.paths.pb_current_export) {
            $curFile = Get-ChildItem $cfg.paths.pb_current_export -Recurse -File -Filter "$($obj.Name).sr*" -ErrorAction SilentlyContinue | Select-Object -First 1
        }
    }
    $validationResults = Add-ValidationResult -Results $validationResults -ObjName $obj.Name -Type "NEWPB" -ExpectedSource "PB_Current" -ExpectedDir $cfg.paths.pb_current_export -ActualPath $obj.Path -FilePattern "$($obj.Name).sr*"
    
    # OLDPB -> Git_* → VSS → PB_Main
    $oldPbPath = Get-GitObjectPath -ObjectName $obj.Name -Pattern "$($obj.Name).sr*"
    $oldPbSource = if ($oldPbPath) { "Git_*" } else { $null }
    if (-not $oldPbPath -and $VssDb -and $VssUser -and $VssPass) {
        $vssResult = Find-VssOldPbPath -ObjectName $obj.Name -Library $libName -TaskPath $taskPath -VssDb $VssDb -VssUser $VssUser -VssPass $VssPass -CurrentUserName $VssUser
        if ($vssResult.Path) { $oldPbPath = $vssResult.Path; $oldPbSource = $vssResult.Source }
    }
    if (-not $oldPbPath) {
        $mainFile = Get-ChildItem $cfg.paths.pb_main_export -Recurse -File -Filter "$($obj.Name).sr*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($mainFile) { $oldPbPath = $mainFile.FullName; $oldPbSource = "PB_Main" }
    }
    if ($oldPbPath) {
        $mainFile = Get-ChildItem $cfg.paths.pb_main_export -Recurse -File -Filter "$($obj.Name).sr*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $mainFile) {
            Write-Host "PB_Main: $($obj.Name) не найден, экспорт из Main..." -ForegroundColor Yellow
            if (Export-PbObject -ObjectName $obj.Name -LibraryName $libName -SourceDir $cfg.paths.pb_main_source -TargetExportDir $cfg.paths.pb_main_export) {
                $mainFile = Get-ChildItem $cfg.paths.pb_main_export -Recurse -File -Filter "$($obj.Name).sr*" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($mainFile) { $oldPbPath = $mainFile.FullName }
            }
        }
        # Валидация OLDPB против PB_Main (только если OLDPB не из PB_Main)
        if ($oldPbSource -ne "PB_Main") {
            $validationResults = Add-ValidationResult -Results $validationResults -ObjName $obj.Name -Type "OLDPB" -ExpectedSource "PB_Main" -ExpectedDir $cfg.paths.pb_main_export -ActualPath $oldPbPath -FilePattern "$($obj.Name).sr*"
        }
    }
}

foreach ($obj in $sqlSorted) {
    # NEWSQL -> BD/dev_golden
    $sqlFile = Get-ChildItem $cfg.paths.bd_current_export -Recurse -File -Filter "$($obj.Name).sql" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $sqlFile -and $DbPassword) {
        Write-Host "BD/dev_golden: $($obj.Name) не найден, экспорт из dev_golden..." -ForegroundColor Yellow
        if (Export-SqlObject -ObjectName $obj.Name -Server $sqlServer -Database $sqlDb -TargetDir $cfg.paths.bd_current_export -SqlPassword $DbPassword) {
            $sqlFile = Get-ChildItem $cfg.paths.bd_current_export -Recurse -File -Filter "$($obj.Name).sql" -ErrorAction SilentlyContinue | Select-Object -First 1
        }
    }
    $validationResults = Add-ValidationResult -Results $validationResults -ObjName $obj.Name -Type "NEWSQL" -ExpectedSource "BD/dev_golden" -ExpectedDir $cfg.paths.bd_current_export -ActualPath $obj.Path -FilePattern "$($obj.Name).sql"
    
    $oldSqlPath = Get-GitObjectPath -ObjectName $obj.Name -Pattern "$($obj.Name).sql"
    if ($oldSqlPath -and $DbPassword) {
        $sqlFileMain = Get-ChildItem $cfg.paths.bd_current_export -Recurse -File -Filter "$($obj.Name).sql" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $sqlFileMain) {
            Write-Host "BD/galaxy: $($obj.Name) не найден, экспорт из galaxy..." -ForegroundColor Yellow
            if (Export-SqlObject -ObjectName $obj.Name -Server $cfg.paths.bd_main_server -Database $sqlDb -TargetDir $cfg.paths.bd_main_export -SqlPassword $DbPassword) {
                $sqlFileMain = Get-ChildItem $cfg.paths.bd_main_export -Recurse -File -Filter "$($obj.Name).sql" -ErrorAction SilentlyContinue | Select-Object -First 1
            }
        }
        $validationResults = Add-ValidationResult -Results $validationResults -ObjName $obj.Name -Type "OLDSQL" -ExpectedSource "BD/galaxy" -ExpectedDir $cfg.paths.bd_main_export -ActualPath $oldSqlPath -FilePattern "$($obj.Name).sql"
    }
}

Write-Host "=== Валидация объектов ===" -ForegroundColor Cyan
$failures = $validationResults | Where-Object { $_.Статус -ne "Совпадает" }
if ($failures.Count -eq 0) {
    Write-Host "Всё в порядке, объекты соответствуют эталонам" -ForegroundColor Green
} else {
    Write-Host "Найдено несовпадений: $($failures.Count)" -ForegroundColor Yellow
}
$validationResults | Format-Table Object, Тип, Ожидаемый, Статус -AutoSize | Out-String | ForEach-Object { Write-Host $_ -NoNewline }

# Определение сервера и БД для SQL-объектов
$sqlCurrentExport = $cfg.paths.bd_current_export
$sqlParts = $sqlCurrentExport -split '\\'
$sqlServer = if ($sqlParts.Count -ge 2) { $sqlParts[-2] } else { "dev_golden" }
$sqlDb = if ($sqlParts.Count -ge 1) { $sqlParts[-1] } else { "golden" }

$sb = New-Object System.Text.StringBuilder

# Формирование Jira wiki таблицы (без || в двойных кавычках — баг PS 5.1)
$pipe = [string][char]0x7C
$dpipe = $pipe + $pipe

[void]$sb.AppendLine(("h3. Состав релиза по задаче {0}" -f $TaskName))
[void]$sb.AppendLine()

[void]$sb.AppendLine(("{0}Проект/Сервер{0}Библиотека/БД{0}Наименование объекта{0}Информация{0}" -f $dpipe))

$pbSorted = $pbObjects.Values | Sort-Object Library, Name
# Разрешаем неизвестные библиотеки и пересортируем
foreach ($obj in $pbSorted) { if (-not $obj.Library) { $obj.Library = Get-PbLibraryName -ObjectName $obj.Name } }
$pbSorted = $pbSorted | Sort-Object Library, Name
foreach ($obj in $pbSorted) {
    $libName = $obj.Library
    $pbName = "{color:#00008B}*$($obj.Name)*{color}"

    # Поиск OLDPB: если занят мной → VSS; иначе Git_* → PB_Main
    $oldPbPath = $null
    $oldPbSource = $null
    $isCheckedOutByMe = $false
    if ($VssDb -and $VssUser -and $VssPass) {
        $vssPath = "`$/SRC125/gold/$libName/$($obj.Name).sr*"
        $coInfo = Get-VssCheckoutInfo -VssPath $vssPath -VssDb $VssDb -VssUser $VssUser -VssPass $VssPass
        if ($coInfo.CheckedOut -and $coInfo.User -eq $VssUser) {
            $isCheckedOutByMe = $true
            $vssResult = Find-VssOldPbPath -ObjectName $obj.Name -Library $libName -TaskPath $taskPath -VssDb $VssDb -VssUser $VssUser -VssPass $VssPass -CurrentUserName $VssUser
            if ($vssResult.Path -and (Test-Path $vssResult.Path)) {
                $oldPbPath = $vssResult.Path
                $oldPbSource = $vssResult.Source
                Write-Host "  OLDPB из $($vssResult.Source) ($($vssResult.HistoryUser))" -ForegroundColor Cyan
            }
        }
    }
    if (-not $oldPbPath -and -not $isCheckedOutByMe) {
        $oldPbPath = Get-GitObjectPath -ObjectName $obj.Name -Pattern "$($obj.Name).sr*"
        $oldPbSource = "Git_*"
    }
    if (-not $oldPbPath) {
        # PB_Main fallback
        $mainFile = Get-ChildItem $cfg.paths.pb_main_export -Recurse -File -Filter "$($obj.Name).sr*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($mainFile) {
            $tempDate = Get-Date -Format 'yyyy_MM_dd'
            $tempDir = Join-Path $taskPath "TEMP_$tempDate\PB\$libName"
            if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
            $tempFile = Join-Path $tempDir "$($obj.Name)$($mainFile.Extension)"
            Copy-Item $mainFile.FullName $tempFile -Force
            $oldPbPath = $tempFile
            $oldPbSource = "PB_Main (через TEMP)"
            Write-Host "  OLDPB из PB_Main: $($mainFile.Name)" -ForegroundColor Green
        }
    }

    $info = Get-PbDiffInfo -NewPath $obj.Path -OldPath $oldPbPath -ObjectName $obj.Name
    if ([string]::IsNullOrWhiteSpace($info)) { $info = if ($oldPbPath) { "Изменений нет" } else { "Новый объект" } }
    [void]$sb.AppendLine(("{0}{1}{0}{2}{0}{3}{0}{4}{0}" -f $pipe, $ProjectName, $libName, $pbName, $info))
    Write-Host ("###PB_OBJ###{0}|{1}|{2}" -f $obj.Name, $libName, $obj.File)
    if ($info -and $info.Trim() -ne "") { Write-Host ("  Информация: {0}" -f $info) -ForegroundColor Gray }
}

$sqlSorted = $sqlObjects.Values | Sort-Object Name
foreach ($obj in $sqlSorted) {
    $sqlName = "{color:#5C4033}*$($obj.Name)*{color}"
    $oldSqlPath = Get-GitObjectPath -ObjectName $obj.Name -Pattern "$($obj.Name).sql"
    $info = Get-SqlDiffInfo -NewPath $obj.Path -OldPath $oldSqlPath -ObjectName $obj.Name
    if ([string]::IsNullOrWhiteSpace($info)) { $info = if ($oldSqlPath) { "Изменений нет" } else { "Новый объект" } }
    [void]$sb.AppendLine(("{0}{1}{0}{2}{0}{3}{0}{4}{0}" -f $pipe, $sqlServer, $sqlDb, $sqlName, $info))
    Write-Host ("###SQL_OBJ###{0}|{1}|{2}" -f $obj.Name, $sqlServer, $sqlServer)
    if ($info -and $info.Trim() -ne "") { Write-Host ("  Информация: {0}" -f $info) -ForegroundColor Gray }
}

[void]$sb.AppendLine()
[void]$sb.AppendLine(("Всего: {0} объектов (PB: {1}, SQL: {2})" -f ($pbObjects.Count + $sqlObjects.Count), $pbObjects.Count, $sqlObjects.Count))
[void]$sb.AppendLine("_Автоматически сформировано скриптом Add-ReleaseComment.ps1_")

$commentBody = $sb.ToString()

Write-Host ""
Write-Host "=== Таблица для комментария ===" -ForegroundColor Cyan
Write-Host ""
Write-Host $commentBody
Write-Host ""

if (-not $Force) {
    $answer = Read-Host "Добавить комментарий к задаче '$TaskName'? (д/Н)"
    if ($answer -ne "д" -and $answer -ne "Д" -and $answer -ne "y" -and $answer -ne "Y") {
        Write-Host "Отменено." -ForegroundColor Yellow
        exit 0
    }
}

if ($DryRun) {
    Write-Host ""
    Write-Host "=== Сухой прогон (Dry Run) — комментарий НЕ отправлен ===" -ForegroundColor Yellow
    Write-Host ("  Задача: $TaskName")
    Write-Host ("  Всего объектов: {0}" -f ($pbObjects.Count + $sqlObjects.Count)) -ForegroundColor Yellow
    exit 0
}

Write-Host "Отправка комментария в задачу $TaskName..." -ForegroundColor Yellow

$commentPayload = @{ body = $commentBody }
try {
    $result = Invoke-Jira -Method POST -Endpoint ("issue/{0}/comment" -f $TaskName) -Body $commentPayload
    Write-Host ""
    Write-Host "=== Комментарий успешно добавлен ===" -ForegroundColor Green
    Write-Host ("  Задача: {0}/browse/{1}" -f $jiraBase, $TaskName) -ForegroundColor Green
    Write-Host ("  Всего объектов: {0}" -f ($pbObjects.Count + $sqlObjects.Count)) -ForegroundColor Green
} catch {
    Write-Host ("Ошибка при добавлении комментария: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}

exit 0


