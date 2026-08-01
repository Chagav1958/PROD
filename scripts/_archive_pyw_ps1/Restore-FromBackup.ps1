param(
    [string]$ProjectRoot = 'C:\AIS\AI\Prod',
    [switch]$DryRun = $false,
    [switch]$Auto
)

$ErrorActionPreference = 'Stop'

# === Настройка путей ===
$binPath = Join-Path $ProjectRoot 'bin'
$scriptsPath = Join-Path $ProjectRoot 'scripts'
$configPath = Join-Path $ProjectRoot 'config\config.json'
$tempPath = Join-Path $ProjectRoot 'temp'

# === Источники восстановления (от свежих к старым) ===
$backupSources = @(
    @{ Path = Join-Path $ProjectRoot 'archives\SNAPSHOT'; Priority = 1 }
    @{ Path = Join-Path $ProjectRoot 'Restore'; Priority = 2 }
    @{ Path = Join-Path $ProjectRoot 'Restore\OLD'; Priority = 3 }
    @{ Path = Join-Path $ProjectRoot 'archives\FIX'; Priority = 4 }
    @{ Path = Join-Path $ProjectRoot 'archives\opencode_backup'; Priority = 5 }
    @{ Path = Join-Path $ProjectRoot 'archives\powershell_backup'; Priority = 6 }
)

# === Все известные архивы снапшотов (по дате в имени) ===
$snapshotArchives = Get-ChildItem $ProjectRoot\archives\SNAPSHOT -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending

foreach ($snap in $snapshotArchives) {
    $backupSources += @{ Path = $snap.FullName; Priority = 10 }
}

# === Критичные файлы для проверки/восстановления ===
$criticalFiles = @(
    'bin\Show-TimeFIX.ps1',
    'bin\Show-TimeFIX.vbs',
    'bin\Show-TimeFIX.bat',
    'bin\Prod-GUI.ps1',
    'bin\Prod-GUI.bat',
    'bin\OC-Config-Manager.ps1',
    'scripts\Add-Bom.ps1',
    'scripts\Add-Bom.bat',
    'scripts\Fix-HexEncoding.ps1',
    'scripts\Fix-HexEncoding.bat',
    'scripts\Preflight-Antivirus.ps1',
    'scripts\Preflight-Antivirus.bat',
    'scripts\VSS-History-Show.ps1',
    'scripts\VSS-History-Show.bat',
    'scripts\VSS-History.ps1',
    'scripts\ConvertTo-BatLauncher.ps1',
    'scripts\ConvertTo-BatLauncher.bat',
    'scripts\Init-Task.ps1',
    'scripts\Init-Task.bat',
    'scripts\Set-MetroTheme.ps1',
    'scripts\Stells-HideConsole.ps1',
    'scripts\Initialize-Project.ps1',
    'scripts\TaskPlan-Manager.ps1',
    'scripts\TaskPlan-Tracker.ps1',
    'scripts\Show-TaskPlanGUI.ps1',
    'scripts\Export-PB.ps1',
    'scripts\Compare-Export.ps1',
    'scripts\Compare-SQL-Task.ps1',
    'scripts\Add-ReleaseComment.ps1',
    'scripts\Save-UserPrompt.ps1',
    'scripts\Save-Analysis.ps1',
    'scripts\Save-Snapshot.ps1',
    'scripts\Remove-BomFromConfigs.ps1',
    'scripts\AIS_export.ps1',
    'scripts\AIS_export.bat',
    'scripts\Convert-Docs.ps1',
    'config\config.json',
    'config\vss_object_history.json',
    'config\task_name_history.json'
)

# === Скрипт для генерации .bat-лаунчера ===
$convertScript = Join-Path $scriptsPath 'ConvertTo-BatLauncher.ps1'

# === Поиск файла в источниках ===
function Find-FileInBackups {
    param([string]$RelativePath, [array]$Sources)
    
    $fileName = Split-Path $RelativePath -Leaf
    $subPath = Split-Path $RelativePath -Parent
    
    foreach ($source in ($Sources | Sort-Object Priority)) {
        $srcPath = $source.Path
        if (-not (Test-Path $srcPath)) { continue }
        
        # Сначала ищем по точному подпути
        $exactPath = Join-Path $srcPath $RelativePath
        if (Test-Path $exactPath) {
            return @{ Path = $exactPath; Source = $srcPath }
        }
        
        # Затем ищем только по имени файла (на случай если структура изменилась)
        $byName = Get-ChildItem $srcPath -Recurse -Filter $fileName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($byName) {
            return @{ Path = $byName.FullName; Source = $srcPath }
        }
    }
    
    return $null
}

# === Основной процесс восстановления ===
$restored = 0
$missing = 0
$skipped = 0
$report = @()

Write-Host "=== Проверка критичных файлов ===" -ForegroundColor Cyan
Write-Host ""

foreach ($relPath in $criticalFiles) {
    $fullPath = Join-Path $ProjectRoot $relPath
    $exists = Test-Path $fullPath
    
    $status = if ($exists) { 'OK' } else { 'MISS' }
    Write-Host ("  [{0}] {1}" -f $status, $relPath)
    
    if ($exists) {
        $skipped++
        continue
    }
    
    # Поиск в бэкапах
    $found = Find-FileInBackups -RelativePath $relPath -Sources $backupSources
    
    if ($found) {
        if ($DryRun) {
            Write-Host "    WOULD RESTORE from: $($found.Path)" -ForegroundColor Yellow
            $restored++
        } else {
            try {
                $destDir = Split-Path $fullPath -Parent
                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                Copy-Item $found.Path $fullPath -Force
                Write-Host "    RESTORED from: $($found.Path)" -ForegroundColor Green
                $restored++
            } catch {
                Write-Host "    FAILED: $($_.Exception.Message)" -ForegroundColor Red
                $missing++
            }
        }
    } else {
        Write-Host "    NOT FOUND in backups" -ForegroundColor Red
        $missing++
        $report += $relPath
    }
}

# === Генерация .bat-лаунчеров для восстановленных .ps1 ===
Write-Host ""
Write-Host "=== Регенерация .bat-лаунчеров ===" -ForegroundColor Cyan
if (Test-Path $convertScript) {
    $ps1Files = Get-ChildItem $binPath, $scriptsPath -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue
    foreach ($ps1 in $ps1Files) {
        $batPath = $ps1.FullName -replace '\.ps1$', '.bat'
        if (-not (Test-Path $batPath) -or (Get-Item $ps1).LastWriteTime -gt (Get-Item $batPath).LastWriteTime) {
            if ($DryRun) {
                Write-Host "  WOULD generate: $($batPath.Replace($ProjectRoot, ''))" -ForegroundColor Yellow
            } else {
                try {
                    & $convertScript $ps1.FullName $batPath 2>&1 | Out-Null
                    Write-Host "  Generated: $($batPath.Replace($ProjectRoot, ''))" -ForegroundColor Green
                } catch {
                    Write-Host "  Failed: $($ps1.Name) - $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    }
} else {
    Write-Host "  ConvertTo-BatLauncher.ps1 not found - skip" -ForegroundColor Yellow
}

# === Добавление BOM к .ps1 ===
Write-Host ""
Write-Host "=== Добавление BOM ===" -ForegroundColor Cyan
$addBomScript = Join-Path $scriptsPath 'Add-Bom.ps1'
if (Test-Path $addBomScript) {
    $ps1FilesWithoutBom = $ps1Files | Where-Object {
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        -not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    }
    foreach ($ps1 in $ps1FilesWithoutBom) {
        if ($DryRun) {
            Write-Host "  WOULD add BOM: $($ps1.Name)" -ForegroundColor Yellow
        } else {
            try {
                & $addBomScript $ps1.FullName 2>&1 | Out-Null
                Write-Host "  Added BOM: $($ps1.Name)" -ForegroundColor Green
            } catch {
                Write-Host "  Failed: $($ps1.Name) - $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

# === Итог ===
Write-Host ""
Write-Host "=== Итог ===" -ForegroundColor Cyan
Write-Host ("  Восстановлено: {0}" -f $restored) -ForegroundColor Green
Write-Host ("  Уже было: {0}" -f $skipped) -ForegroundColor Gray
Write-Host ("  Не найдено: {0}" -f $missing) -ForegroundColor $(if($missing -gt 0){'Red'}else{'Green'})

if ($report.Count -gt 0) {
    Write-Host ""
    Write-Host "=== Файлы не найдены в архивах ===" -ForegroundColor Red
    $report | ForEach-Object { Write-Host "  $_" }
}

# === Проверка префилайт ===
Write-Host ""
Write-Host "=== Префилайт (антивирус) ===" -ForegroundColor Cyan
$preflightScript = Join-Path $scriptsPath 'Preflight-Antivirus.ps1'
if (Test-Path $preflightScript) {
    & $preflightScript 2>&1 | Select-Object -First 5
}
