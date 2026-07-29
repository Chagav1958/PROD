param(
    [string]$TaskName,
    [string]$ReleaseRoot = "C:\AIS\1 Release",
    [string[]]$SqlObjects = @(),
    [string[]]$PbObjects = @()
)

$ErrorActionPreference = 'Stop'
if (-not $TaskName) { throw "Укажите -TaskName" }

$dateTag = Get-Date -Format 'yyyy_MM_dd'

# Поиск существующей папки: сначала префикс (правило TASK)
$found = Get-ChildItem $ReleaseRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$TaskName*" } | Sort-Object Name -Descending | Select-Object -First 1
if ($found) {
    $taskPath = $found.FullName
} else {
    $taskPath = Join-Path $ReleaseRoot $TaskName
}

# Создание папок
$gitDir   = Join-Path $taskPath "Git_$dateTag"
$testDir  = Join-Path $taskPath "Test_$dateTag"
$readyDir = Join-Path $taskPath "Ready_$dateTag"
$descDir  = Join-Path $taskPath "Describe"

foreach ($d in @($taskPath, $gitDir, $testDir, $readyDir, $descDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

Write-Host "=== TASK: $TaskName ==="
Write-Host "Папка: $taskPath"
Write-Host "Git_: $gitDir"
Write-Host ""

$configPath = "C:\AIS\AI\Prod\config\config.json"
$cfg = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$pbMainDir = $cfg.paths.pb_main_source
$pbCurDir  = $cfg.paths.pb_current_source
$sqlServer  = $cfg.paths.bd_current_server
$sqlDb      = $cfg.paths.bd_database

# === SQL export ===
if ($SqlObjects.Count -gt 0) {
    $sqlGitDir = Join-Path $gitDir "SQL"
    New-Item -ItemType Directory -Path $sqlGitDir -Force | Out-Null
    Write-Host "--- Экспорт SQL из $sqlServer ---"
    $bat = "C:\AIS\AI\Prod\bin\SQL_exp_single.bat"
    foreach ($obj in $SqlObjects) {
        $type = "Procedure"
        if ($obj -match '^fn_') { $type = "Function" }
        elseif ($obj -match '^td_') { $type = "Trigger" }
        elseif ($obj -match '^v_') { $type = "View" }
        
        $typeDir = Join-Path $sqlGitDir $type
        New-Item -ItemType Directory -Path $typeDir -Force | Out-Null
        
        Write-Host "  Экспорт: $obj ($type)"
        cmd /c "`"$bat`" $type $obj $sqlServer $sqlDb sqlsql 2>&1" | Out-Null
        
        $srcFile = "C:\AIS\AI\Prod\BD\$sqlServer\$sqlDb\$type\$obj.sql"
        if ($type -eq 'Function') { $srcFile = "C:\AIS\AI\Prod\BD\$sqlServer\$sqlDb\Functions\$obj.sql" }
        if ($type -eq 'Trigger')  { $srcFile = "C:\AIS\AI\Prod\BD\$sqlServer\$sqlDb\Triggers\$obj.sql" }
        if ($type -eq 'View')     { $srcFile = "C:\AIS\AI\Prod\BD\$sqlServer\$sqlDb\Views\$obj.sql" }
        if (Test-Path $srcFile) {
            Copy-Item $srcFile -Destination (Join-Path $typeDir "$obj.sql") -Force
            Write-Host "    -> $typeDir\$obj.sql" -ForegroundColor Green
        }
    }
}

# === PB copy ===
if ($PbObjects.Count -gt 0) {
    $pbGitDir = Join-Path $gitDir "PB"
    New-Item -ItemType Directory -Path $pbGitDir -Force | Out-Null
    Write-Host "--- Копирование PB ---"
    foreach ($obj in $PbObjects) {
        $copied = $false
        foreach ($srcDir in @($pbCurDir, $pbMainDir)) {
            if (-not (Test-Path $srcDir)) { continue }
            $found = Get-ChildItem $srcDir -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "$obj.*" } | Select-Object -First 1
            if ($found) {
                $libName = Split-Path (Split-Path $found.FullName -Parent) -Leaf
                $libDir = Join-Path $pbGitDir $libName
                New-Item -ItemType Directory -Path $libDir -Force | Out-Null
                Copy-Item $found.FullName -Destination (Join-Path $libDir $found.Name) -Force
                Write-Host "  $obj -> PB\$libName\$($found.Name)" -ForegroundColor Green
                $copied = $true
                break
            }
        }
        if (-not $copied) {
            Write-Host "  $obj : НЕ НАЙДЕН в PB_Current / PB_Main" -ForegroundColor Yellow
        }
    }
}

    # === Декодирование HEX (защита от $$HEX...$$ENDHEX$$ в русском тексте) ===
    $hexFix = Join-Path $PSScriptRoot "Fix-HexEncoding.ps1"
    if (Test-Path $hexFix) {
        & $hexFix -Path $pbGitDir -Recurse -Quiet
    }
}

# === Describe templates ===
$allObjects = @($SqlObjects) + @($PbObjects) | Select-Object -Unique
foreach ($obj in $allObjects) {
    $df = Join-Path $descDir "$obj.txt"
    if (-not (Test-Path $df)) {
        $type = if ($obj -like 'usp_*') { "SQL-процедура" }
                elseif ($obj -like 'fn_*') { "SQL-функция" }
                elseif ($obj -like 'w_*') { "PB-окно" }
                elseif ($obj -like 'u_*') { "PB-UserObject" }
                elseif ($obj -like 'd_*') { "PB-DataWindow" }
                else { "объект" }
        $template = "Объект: $obj`r`nТип: $type`r`nЗадача: $TaskName`r`n`r`nЧто изменено:`r`n`r`nПричина:`r`n"
        Set-Content -LiteralPath $df -Value $template -Encoding UTF8
        Write-Host "  Describe\$obj.txt — создан" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "=== ГОТОВО ===" -ForegroundColor Green
Write-Host "Git_:   $gitDir"
Write-Host "Test_:  $testDir"
Write-Host "Ready_: $readyDir"
Write-Host "Describe: $descDir"

