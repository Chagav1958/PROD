<#
.SYNOPSIS
    Compare SQL export sets: BD/dev_golden vs BD/galaxy.
    Lists objects that differ, are missing in Main, or missing in Current.
.DESCRIPTION
    Scans all .sql files in Procedure, Functions, Triggers subdirectories
    across all databases (golden, mis, etc.) on both servers.
    Compares by MD5 hash. Outputs to console and saves to a report file.
.PARAMETER ConfigPath
    Path to config.json (default: C:\AIS\AI\Prod\config.json)
.PARAMETER OutputFile
    Path for the comparison report (default: C:\AIS\AI\Prod\compare_sql_report.txt)
.EXAMPLE
    .\Compare-SQL.ps1
.EXAMPLE
    .\Compare-SQL.ps1 -OutputFile C:\Temp\sql_diff.txt
#>

param(
    [string]$ConfigPath = "C:\AIS\AI\Prod\config\config.json",
    [string]$OutputFile = "C:\AIS\AI\Prod\compare_sql_report.txt",
    [string]$TaskName = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ConfigPath)) { throw "Конфиг не найден: $ConfigPath" }
$cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

$bdRoot = Split-Path $cfg.paths.bd_current_export -Parent | Split-Path -Parent
$srvCurrent = "dev_golden"
$srvMain = "galaxy"

$bdCurrent = Join-Path $bdRoot $srvCurrent
$bdMain    = Join-Path $bdRoot $srvMain

if (-not (Test-Path $bdCurrent) -or -not (Test-Path $bdMain)) {
    throw "Пути BD не найдены: $bdCurrent или $bdMain"
}

Write-Host "=== Compare SQL: $srvCurrent (Current) vs $srvMain (Main) ===" -ForegroundColor Cyan
if ($TaskName) { Write-Host "Задача: $TaskName (только объекты из Ready_* папок)" -ForegroundColor Yellow }
Write-Host ""

# Get all databases on both servers
$dbCurrent = Get-ChildItem $bdCurrent -Directory | Select-Object -ExpandProperty Name
$dbMain    = Get-ChildItem $bdMain    -Directory | Select-Object -ExpandProperty Name
$commonDBs = $dbCurrent | Where-Object { $_ -in $dbMain }

Write-Host "Базы данных на $srvCurrent : $($dbCurrent -join ', ')" -ForegroundColor Gray
Write-Host "Базы данных на $srvMain    : $($dbMain -join ', ')" -ForegroundColor Gray
Write-Host "Общие базы данных: $($commonDBs -join ', ')" -ForegroundColor Yellow
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
        Write-Host "ОШИБКА: Папки Ready_* не найдены в $taskPath" -ForegroundColor Red
        return
    }
    Write-Host "Папки Ready: $($readyDirs.Count)" -ForegroundColor Gray
    $taskObjects = @{}
    foreach ($rd in $readyDirs) {
        Get-ChildItem $rd.FullName -Recurse -File | Where-Object { $_.Extension -match '\.sr|\.sql' } | ForEach-Object {
            $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            if (-not $taskObjects.ContainsKey($base)) { $taskObjects[$base] = $_.Name }
        }
    }
    Write-Host "Объектов в задаче: $($taskObjects.Count)" -ForegroundColor Yellow
}

$objectTypes = @("Procedure", "Functions", "Triggers")
$allResults = @()

foreach ($db in ($commonDBs | Sort-Object)) {
    Write-Host ""
    Write-Host "-- Database: $db --" -ForegroundColor Cyan

    foreach ($type in $objectTypes) {
        Write-Host "###PHASE###${type}-${db}|0###"
        $dirCR = Join-Path (Join-Path $bdCurrent $db) $type
        $dirMR = Join-Path (Join-Path $bdMain $db) $type

        if (-not (Test-Path $dirCR) -and -not (Test-Path $dirMR)) { continue }

        $filesCR = @()
        $filesMR = @()
        $lookupMR = @{}

        if (Test-Path $dirCR) { $filesCR = Get-ChildItem $dirCR -File -Filter "*.sql" }
        if (Test-Path $dirMR) {
            $filesMR = Get-ChildItem $dirMR -File -Filter "*.sql"
            foreach ($f in $filesMR) {
                $lookupMR[$f.Name] = $f
            }
        }
        
        # Filter by TaskName if specified
        if ($taskObjects) {
            $filesCR = $filesCR | Where-Object { $taskObjects.ContainsKey([System.IO.Path]::GetFileNameWithoutExtension($_.Name)) }
            $filesMR = $filesMR | Where-Object { $taskObjects.ContainsKey([System.IO.Path]::GetFileNameWithoutExtension($_.Name)) }
        }

        # Build lookup for Current too for NOT_IN_CURRENT check
        $lookupCR = @{}
        foreach ($f in $filesCR) { $lookupCR[$f.Name] = $f }

        # Compare Current -> Main
        foreach ($cf in $filesCR) {
            $name = $cf.Name
            $objName = [System.IO.Path]::GetFileNameWithoutExtension($name)

            if (-not $lookupMR.ContainsKey($name)) {
                $allResults += [PSCustomObject]@{
                    Server     = $srvCurrent
                    Database   = $db
                    Type       = $type
                    ObjectName = $objName
                    Status     = "NOT_IN_MAIN"
                    CurrentMD5 = (Get-FileHash $cf.FullName -Algorithm MD5).Hash
                    MainMD5    = "-"
                }
                Write-Host "###STEP###"
                continue
            }

            $mf = $lookupMR[$name]
            $ch = (Get-FileHash $cf.FullName -Algorithm MD5).Hash
            $mh = (Get-FileHash $mf.FullName -Algorithm MD5).Hash

            if ($ch -ne $mh) {
                $allResults += [PSCustomObject]@{
                    Server     = $srvCurrent
                    Database   = $db
                    Type       = $type
                    ObjectName = $objName
                    Status     = "DIFF"
                    CurrentMD5 = $ch
                    MainMD5    = $mh
                }
            }
            Write-Host "###STEP###"
        }

        # Compare Main -> Current (NOT_IN_CURRENT)
        foreach ($mf in $filesMR) {
            $name = $mf.Name
            $objName = [System.IO.Path]::GetFileNameWithoutExtension($name)

            if (-not $lookupCR.ContainsKey($name)) {
                $allResults += [PSCustomObject]@{
                    Server     = $srvMain
                    Database   = $db
                    Type       = $type
                    ObjectName = $objName
                    Status     = "NOT_IN_CURRENT"
                    CurrentMD5 = "-"
                    MainMD5    = (Get-FileHash $mf.FullName -Algorithm MD5).Hash
                }
            }
            Write-Host "###STEP###"
        }
    }
}

# Sort results
$allResults = $allResults | Sort-Object Status, Database, Type, ObjectName

# -- Display summary table --
Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan
Write-Host ""

$grp = $allResults | Group-Object Status
$totalD = 0; $totalNim = 0; $totalNic = 0
foreach ($g in $grp) {
    switch ($g.Name) {
        "DIFF"          { $totalD = $g.Count; Write-Host "РАЗЛИЧАЮТСЯ:      $($g.Count)" -ForegroundColor Red }
        "NOT_IN_MAIN"   { $totalNim = $g.Count; Write-Host "НЕТ В MAIN:        $($g.Count)" -ForegroundColor Yellow }
        "NOT_IN_CURRENT" { $totalNic = $g.Count; Write-Host "НЕТ В CURRENT:     $($g.Count)" -ForegroundColor Magenta }
    }
}
Write-Host "Всего различий: $($allResults.Count)" -ForegroundColor Cyan
Write-Host ""

# Display by DB / Type
Write-Host "По базе данных / типу:" -ForegroundColor Yellow
Write-Host ("{0,-15} {1,-12} {2,6} {3,13} {4,16} {5,7}" -f "База", "Тип", "ДИФФ", "НЕТ_MAIN", "НЕТ_CRNT", "ВСЕГО")
Write-Host ("="*72)
$dbGrp = $allResults | Group-Object Database, Type | Sort-Object Name
foreach ($g in $dbGrp) {
    $parts = $g.Name -split ', '
    $db = $parts[0]; $type = $parts[1]
    $d = @($g.Group | Where-Object { $_.Status -eq "DIFF" }).Count
    $nim = @($g.Group | Where-Object { $_.Status -eq "NOT_IN_MAIN" }).Count
    $nic = @($g.Group | Where-Object { $_.Status -eq "NOT_IN_CURRENT" }).Count
    Write-Host ("{0,-15} {1,-12} {2,6} {3,13} {4,16} {5,7}" -f $db, $type, $d, $nim, $nic, $g.Count)
}

# -- Display detailed list --
Write-Host ""
Write-Host "=== Detailed list ===" -ForegroundColor Cyan
$currentStatus = ""
foreach ($r in $allResults) {
    if ($r.Status -ne $currentStatus) {
        $currentStatus = $r.Status
        $color = @{"DIFF"="Red"; "NOT_IN_MAIN"="Yellow"; "NOT_IN_CURRENT"="Magenta"}[$r.Status]
        Write-Host "--- $($r.Status) ---" -ForegroundColor $color
    }
    Write-Host ("  {0,-15} {1,-10} {2,-30} {3}" -f ($r.Database+"\"+$r.Type), $r.Server, $r.ObjectName, $r.Status)
    # Генерация маркера для диалога сравнения TortoiseMerge
    $objFull = $r.Database+"\"+$r.Type+"\"+$r.ObjectName
    $basePath = if ($r.Status -eq "NOT_IN_CURRENT") { "" } else { Join-Path $bdCurrent ($r.Database+"\"+$r.Type+"\"+$r.ObjectName+".sql") }
    $readyPath = if ($r.Status -eq "NOT_IN_MAIN") { "" } else { Join-Path $bdMain ($r.Database+"\"+$r.Type+"\"+$r.ObjectName+".sql") }
    $compareType = if ($r.Status -eq "NOT_IN_MAIN") { "Current" } else { "Main" }
    "###DIFF_OBJECT###$objFull|$($r.Status)|$basePath|$readyPath|$compareType"
}

# -- Save report --
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("==============================================")
[void]$sb.AppendLine("  COMPARE SQL: $srvCurrent (Current) vs $srvMain (Main)")
[void]$sb.AppendLine("  Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
if ($TaskName) { [void]$sb.AppendLine("  Task: $TaskName") }
[void]$sb.AppendLine("==============================================")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Total differences: $($allResults.Count)")
[void]$sb.AppendLine("")

# Summary by DB/Type
[void]$sb.AppendLine(("{0,-15} {1,-12} {2,6} {3,13} {4,16} {5,7}" -f "Database", "Type", "DIFF", "NOT_IN_MAIN", "NOT_IN_CURRENT", "TOTAL"))
[void]$sb.AppendLine(("-"*72))
foreach ($g in $dbGrp) {
    $parts = $g.Name -split ', '
    $db = $parts[0]; $type = $parts[1]
    $d = @($g.Group | Where-Object { $_.Status -eq "DIFF" }).Count
    $nim = @($g.Group | Where-Object { $_.Status -eq "NOT_IN_MAIN" }).Count
    $nic = @($g.Group | Where-Object { $_.Status -eq "NOT_IN_CURRENT" }).Count
    [void]$sb.AppendLine(("{0,-15} {1,-12} {2,6} {3,13} {4,16} {5,7}" -f $db, $type, $d, $nim, $nic, $g.Count))
}
[void]$sb.AppendLine(("-"*72))
[void]$sb.AppendLine(("{0,-15} {1,-12} {2,6} {3,13} {4,16} {5,7}" -f "TOTAL", "", $totalD, $totalNim, $totalNic, $allResults.Count))
[void]$sb.AppendLine("")

# Detailed list
[void]$sb.AppendLine("=== Detailed list ===")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Server     Database      Type         Object                          Status")
[void]$sb.AppendLine("----------------------------------------------------------------------------")
foreach ($r in $allResults) {
    [void]$sb.AppendLine(("{0,-10} {1,-13} {2,-12} {3,-30} {4}" -f $r.Server, $r.Database, $r.Type, $r.ObjectName, $r.Status))
}

[System.IO.File]::WriteAllText($OutputFile, $sb.ToString(), [System.Text.Encoding]::Default)
Write-Host ""
Write-Host "Отчёт сохранён: $OutputFile" -ForegroundColor Green

