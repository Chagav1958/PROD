<#
.SYNOPSIS
  Управление конфигами OpenCode: сохранение, восстановление, диагностика.
  Внешний скрипт (не зависит от OpenCode).
.DESCRIPTION
  Команды:
    save     - Сохранить снапшот всех конфигов
    restore  - Восстановить из последнего или указанного снапшота
    check    - Диагностика конфигов (BOM, JSON, env vars)
    list     - Показать доступные снапшоты
    diff     - Сравнить текущие конфиги с последним снапшотом
    autosave - Сохранить с меткой "auto_YYYYMMDD_HHMMSS"
  Параметры:
    -Name     "описание" (для save)
    -Date     "YYYYMMDD_HHMMSS" (для restore)
    -Project  "C:\AIS\AI\Prod" (для check/diff по конкретному проекту)
    -Verbose  Подробный вывод
.EXAMPLE
    .\OC-Config-Manager.ps1 save -Name "Перед правкой провайдеров"
    .\OC-Config-Manager.ps1 check -Verbose
    .\OC-Config-Manager.ps1 list
    .\OC-Config-Manager.ps1 restore -Date "20260717_121500"
#>

param(
    [ValidateSet('save','restore','check','list','diff','autosave','help')]
    [string]$Command = 'help',
    [string]$Name = '',
    [string]$Date = '',
    [string]$Project = '',
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

# ============================================================
# КОНФИГУРАЦИЯ
# ============================================================
$script:ConfigFile = [System.IO.Path]::Combine($PSScriptRoot, '..', 'config', 'oc-config-manager.json')

# Значения по умолчанию
$script:DefaultConfig = @{
    archiveRoot   = 'C:\AIS\AI\Prod\archives\OpenCode'
    globalConfig  = '{USERPROFILE}\.config\opencode\opencode.jsonc'
    projects      = @(
        @{ path = 'C:\AIS\AI\Prod';      name = 'PROD' }
    )
    checkItems    = @('bom','json','env','sections')
}

# ============================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ============================================================

function Write-Log {
    param([string]$Message, [string]$Color = 'Gray')
    $timestamp = Get-Date -Format 'HH:mm:ss'
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

function Read-Config {
    $cfgPath = $script:ConfigFile
    if (Test-Path $cfgPath) {
        try {
            $raw = Get-Content $cfgPath -Raw -Encoding UTF8
            $cfg = $raw | ConvertFrom-Json -ErrorAction Stop
            $result = @{}
            $result.archiveRoot  = if ($cfg.archiveRoot)  { $cfg.archiveRoot }  else { $script:DefaultConfig.archiveRoot }
            $result.globalConfig = if ($cfg.globalConfig) { $cfg.globalConfig.Replace('{USERPROFILE}', $env:USERPROFILE) } else { $script:DefaultConfig.globalConfig.Replace('{USERPROFILE}', $env:USERPROFILE) }
            $result.projects     = if ($cfg.projects)     { @($cfg.projects) }  else { $script:DefaultConfig.projects }
            $result.checkItems   = if ($cfg.checkItems)   { @($cfg.checkItems)} else { $script:DefaultConfig.checkItems }
            return $result
        } catch {
            Write-Log "Ошибка чтения конфига: $($_.Exception.Message). Использую значения по умолчанию." 'Yellow'
            return $script:DefaultConfig.Clone()
        }
    } else {
        Write-Log "Конфиг не найден: $cfgPath. Использую значения по умолчанию." 'Yellow'
        $d = $script:DefaultConfig.Clone()
        $d.globalConfig = $d.globalConfig.Replace('{USERPROFILE}', $env:USERPROFILE)
        return $d
    }
}

function Get-ConfigFiles {
    param($Cfg)
    $files = @()
    # Главный конфиг
    if (Test-Path $Cfg.globalConfig) {
        $files += @{
            Path = $Cfg.globalConfig
            Name = 'GLOBAL'
            Tag  = $Cfg.globalConfig
        }
    }
    # Проектные конфиги
    foreach ($proj in $Cfg.projects) {
        $projPath = $proj.path
        $projName = if ($proj.name) { $proj.name } else { Split-Path $projPath -Leaf }
        $variants = @()
        $variants += [System.IO.Path]::Combine($projPath, 'opencode.jsonc')
        $variants += [System.IO.Path]::Combine($projPath, '.opencode', 'opencode.jsonc')
        foreach ($vp in $variants) {
            if (Test-Path $vp) {
                $files += @{
                    Path = $vp
                    Name = $projName
                    Tag  = $projPath
                }
            }
        }
    }
    return $files
}

function Get-Timestamp {
    return Get-Date -Format 'yyyyMMdd_HHmmss'
}

function Get-SnapshotDir {
    param([string]$ArchiveRoot, [string]$Timestamp)
    return Join-Path $ArchiveRoot "Snapshot_$Timestamp"
}

function Test-Bom {
    param([string]$FilePath)
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    if ($bytes.Length -lt 3) { return $false }
    return ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

function Test-JsonFile {
    param([string]$FilePath)
    try {
        $raw = Get-Content $FilePath -Raw -Encoding UTF8
        $null = $raw | ConvertFrom-Json -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Get-JsonError {
    param([string]$FilePath)
    try {
        $raw = Get-Content $FilePath -Raw -Encoding UTF8
        $null = $raw | ConvertFrom-Json -ErrorAction Stop
        return ''
    } catch {
        return $_.Exception.Message
    }
}

function Test-EnvVarInConfig {
    param([string]$FilePath)
    $issues = @()
    $raw = Get-Content $FilePath -Raw -Encoding UTF8
    # Ищем ${VAR_NAME} и {env:VAR_NAME}
    $refs = [regex]::Matches($raw, '\$\{(\w+)\}|\{env:(\w+)\}')
    foreach ($ref in $refs) {
        $varName = if ($ref.Groups[1].Value) { $ref.Groups[1].Value } else { $ref.Groups[2].Value }
        $val = [Environment]::GetEnvironmentVariable($varName, 'Process')
        if ([string]::IsNullOrEmpty($val)) {
            $issues += "Переменная '$varName' не найдена в Process-окружении"
        }
    }
    return $issues
}

function Test-ConfigSections {
    param([string]$FilePath)
    $issues = @()
    try {
        $raw = Get-Content $FilePath -Raw -Encoding UTF8
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        $providerCount = if ($obj.provider) { ($obj.provider | Get-Member -MemberType NoteProperty).Count } else { 0 }
        $mcpCount = if ($obj.mcp) { ($obj.mcp | Get-Member -MemberType NoteProperty).Count } else { 0 }
        $pluginCount = if ($obj.plugin) { $obj.plugin.Count } else { 0 }
        if ($providerCount -eq 0) { $issues += "Нет ни одного провайдера (provider)" }
        if ($mcpCount -eq 0)     { $issues += "Нет MCP-серверов (mcp)" }
        if ($pluginCount -eq 0)  { $issues += "Нет плагинов (plugin)" }
    } catch {
        $issues += "Ошибка парсинга JSON"
    }
    return $issues
}

# ============================================================
# КОМАНДЫ
# ============================================================

function Invoke-Save {
    param([string]$SnapshotName)
    $cfg = Read-Config
    $ts = Get-Timestamp
    $label = if ($SnapshotName) { $SnapshotName } else { "auto_$ts" }
    $safeName = $label -replace '[^a-zA-Z0-9_.-]', '_'
    $snapDir = Get-SnapshotDir -ArchiveRoot $cfg.archiveRoot -Timestamp $safeName
    if (-not (Test-Path $snapDir)) {
        New-Item -ItemType Directory -Path $snapDir -Force | Out-Null
    }
    $files = Get-ConfigFiles -Cfg $cfg
    $savedCount = 0
    # Сохраняем метаданные
    $meta = @{
        timestamp = $ts
        label     = $label
        date      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        files     = @()
    }
    foreach ($f in $files) {
        $relPath = $f.Path -replace '^[A-Za-z]:', ''
        $relPath = $relPath -replace '^\\', ''
        $relPath = $relPath -replace '\\', '_'
        $dest = Join-Path $snapDir "$($f.Name)_$relPath"
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item $f.Path $dest -Force
        $meta.files += @{
            source = $f.Path
            dest   = $dest
            name   = $f.Name
        }
        $savedCount += 1
        Write-Log "  Сохранён: $($f.Path) -> $(Split-Path $dest -Leaf)" 'Gray'
    }
    # Сохраняем метаданные
    $meta | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $snapDir '_meta.json') -Encoding UTF8
    Write-Log "Снапшот '$label' сохранён: $snapDir ($savedCount файлов)" 'Green'
    return $snapDir
}

function Invoke-Restore {
    param([string]$SnapshotDate)
    $cfg = Read-Config
    $archiveRoot = $cfg.archiveRoot
    if (-not (Test-Path $archiveRoot)) {
        Write-Log "Архив не найден: $archiveRoot" 'Red'
        return
    }
    # Определяем снапшот
    $snapshots = Get-ChildItem $archiveRoot -Directory -Filter 'Snapshot_*' | Sort-Object Name -Descending
    if ($snapshots.Count -eq 0) {
        Write-Log "Нет снапшотов для восстановления" 'Yellow'
        return
    }
    $targetSnap = $null
    if ($SnapshotDate) {
        $targetSnap = $snapshots | Where-Object { $_.Name -like "*$SnapshotDate*" } | Select-Object -First 1
        if (-not $targetSnap) {
            Write-Log "Снапшот с датой '$SnapshotDate' не найден" 'Red'
            return
        }
    } else {
        $targetSnap = $snapshots | Select-Object -First 1
        Write-Log "Последний снапшот: $($targetSnap.Name)" 'Gray'
    }
    # Делаем autosave перед восстановлением
    Write-Log "Создаю backup текущего состояния перед восстановлением..." 'Yellow'
    Invoke-Save -SnapshotName "before_restore_$(Get-Timestamp)"
    # Восстанавливаем
    $restoredCount = 0
    $metaPath = Join-Path $targetSnap.FullName '_meta.json'
    if (Test-Path $metaPath) {
        $meta = Get-Content $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($f in $meta.files) {
            $src = $f.dest
            $dst = $f.source
            if (Test-Path $src) {
                Copy-Item $src $dst -Force
                Write-Log "  Восстановлен: $dst" 'Gray'
                $restoredCount += 1
            } else {
                Write-Log "  Не найден в снапшоте: $src" 'Yellow'
            }
        }
    } else {
        # Fallback: ищем файлы напрямую
        $snapFiles = Get-ChildItem $targetSnap.FullName -File -Recurse | Where-Object { $_.Name -ne '_meta.json' }
        # Пытаемся угадать путь по имени файла
        Write-Log "Метаданные не найдены, восстанавливаю по именам файлов..." 'Yellow'
        foreach ($sf in $snapFiles) {
            $originalFiles = Get-ConfigFiles -Cfg $cfg
            $matched = $false
            foreach ($of in $originalFiles) {
                $relPath = $of.Path -replace '^[A-Za-z]:', ''
                $relPath = $relPath -replace '^\\', ''
                $relPath = $relPath -replace '\\', '_'
                $expectedName = "$($of.Name)_$relPath"
                if ($sf.Name -eq $expectedName) {
                    Copy-Item $sf.FullName $of.Path -Force
                    Write-Log "  Восстановлен: $($of.Path)" 'Gray'
                    $restoredCount += 1
                    $matched = $true
                    break
                }
            }
            if (-not $matched) {
                Write-Log "  Пропущен (не удалось сопоставить): $($sf.Name)" 'DarkYellow'
            }
        }
    }
    Write-Log "Восстановление завершено: $restoredCount файлов из снапшота $($targetSnap.Name)" 'Green'
    # Проверяем после восстановления
    Write-Log "Запускаю проверку после восстановления..." 'Cyan'
    Invoke-Check
}

function Invoke-Check {
    $cfg = Read-Config
    $files = Get-ConfigFiles -Cfg $cfg
    $hasErrors = $false
    $logEntries = @()
    Write-Log "=== ДИАГНОСТИКА КОНФИГОВ OpenCode ===" 'Cyan'
    foreach ($f in $files) {
        Write-Log "--- $($f.Name): $($f.Path) ---" 'White'
        $entry = @{
            file    = $f.Path
            name    = $f.Name
            checks  = @{}
            errors  = @()
        }
        if ($cfg.checkItems -contains 'bom') {
            $hasBom = Test-Bom $f.Path
            $entry.checks.bom = if ($hasBom) { 'ЕСТЬ (НАРУШЕНИЕ!)' } else { 'НЕТ (OK)' }
            if ($hasBom) {
                $entry.errors += "BOM присутствует (нарушение для .jsonc)"
                Write-Log "  BOM: ЕСТЬ (НАРУШЕНИЕ!)" 'Red'
                $hasErrors = $true
            } else {
                Write-Log "  BOM: НЕТ (OK)" 'Green'
            }
        }
        if ($cfg.checkItems -contains 'json') {
            $isValid = Test-JsonFile $f.Path
            $entry.checks.json = if ($isValid) { 'OK' } else { 'ОШИБКА' }
            if ($isValid) {
                Write-Log "  JSON: валиден" 'Green'
            } else {
                $errMsg = Get-JsonError $f.Path
                $entry.errors += "JSON error: $errMsg"
                Write-Log "  JSON: ОШИБКА - $errMsg" 'Red'
                $hasErrors = $true
            }
        }
        if ($cfg.checkItems -contains 'env') {
            $envIssues = Test-EnvVarInConfig $f.Path
            if ($envIssues.Count -gt 0) {
                $entry.checks.env = "Проблемы: $($envIssues.Count)"
                $entry.errors += $envIssues
                foreach ($ei in $envIssues) {
                    Write-Log "  ENV: $ei" 'Yellow'
                }
                $hasErrors = $true
            } else {
                $entry.checks.env = 'OK'
                Write-Log "  ENV: все переменные найдены" 'Green'
            }
        }
        if ($cfg.checkItems -contains 'sections') {
            $secIssues = Test-ConfigSections $f.Path
            if ($secIssues.Count -gt 0) {
                $entry.checks.sections = "Проблемы: $($secIssues.Count)"
                $entry.errors += $secIssues
                foreach ($si in $secIssues) {
                    Write-Log "  СЕКЦИИ: $si" 'Yellow'
                }
            } else {
                $entry.checks.sections = 'OK'
                Write-Log "  СЕКЦИИ: провайдеры, MCP, плагины — все есть" 'Green'
            }
        }
        $logEntries += $entry
    }
    # Итог
    Write-Log "=== ИТОГ ===" 'Cyan'
    if ($hasErrors) {
        Write-Log "Обнаружены проблемы. Проверьте вывод выше." 'Yellow'
    } else {
        Write-Log "Все проверки пройдены успешно." 'Green'
    }
    # Сохраняем лог проверки
    $logDir = Join-Path (Get-Config).archiveRoot '..\..\logs'
    $logDir = Resolve-Path $logDir -ErrorAction SilentlyContinue
    if (-not $logDir) {
        $logDir = Join-Path $PSScriptRoot '..\logs'
    }
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $logFile = Join-Path $logDir "oc_diagnostic_$(Get-Timestamp).json"
    $logEntries | ConvertTo-Json -Depth 5 | Set-Content $logFile -Encoding UTF8
    Write-Log "Лог диагностики сохранён: $logFile" 'Gray'
    return @{ HasErrors = $hasErrors; LogFile = $logFile }
}

function Invoke-List {
    $cfg = Read-Config
    $archiveRoot = $cfg.archiveRoot
    if (-not (Test-Path $archiveRoot)) {
        Write-Log "Архив не найден: $archiveRoot" 'Yellow'
        return
    }
    $snapshots = Get-ChildItem $archiveRoot -Directory -Filter 'Snapshot_*' | Sort-Object Name -Descending
    if ($snapshots.Count -eq 0) {
        Write-Log "Нет снапшотов." 'Yellow'
        return
    }
    Write-Log "=== СНАПШОТЫ OpenCode ===" 'Cyan'
    Write-Log ("{0,-30} {1,-20} {2,-10} {3}" -f 'ИМЯ', 'ДАТА', 'ФАЙЛОВ', 'МЕТКА') 'White'
    Write-Log ('{0,-30} {1,-20} {2,-10} {3}' -f ('-'*28), ('-'*18), ('-'*8), ('-'*30)) 'Gray'
    foreach ($snap in $snapshots) {
        $snapName = $snap.Name
        $metaPath = Join-Path $snap.FullName '_meta.json'
        $label = ''
        $snapDate = $snap.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        $fileCount = (Get-ChildItem $snap.FullName -File -Recurse | Where-Object { $_.Name -ne '_meta.json' }).Count
        if (Test-Path $metaPath) {
            try {
                $meta = Get-Content $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $label = $meta.label
            } catch {}
        }
        Write-Log ("{0,-30} {1,-20} {2,-10} {3}" -f $snapName, $snapDate, $fileCount, $label) 'Gray'
    }
}

function Invoke-Diff {
    $cfg = Read-Config
    $archiveRoot = $cfg.archiveRoot
    if (-not (Test-Path $archiveRoot)) {
        Write-Log "Архив не найден: $archiveRoot" 'Yellow'
        return
    }
    $snapshots = Get-ChildItem $archiveRoot -Directory -Filter 'Snapshot_*' | Sort-Object Name -Descending
    if ($snapshots.Count -eq 0) {
        Write-Log "Нет снапшотов для сравнения" 'Yellow'
        return
    }
    $lastSnap = $snapshots | Select-Object -First 1
    Write-Log "=== СРАВНЕНИЕ: текущие конфиги vs $($lastSnap.Name) ===" 'Cyan'
    $files = Get-ConfigFiles -Cfg $cfg
    $diffCount = 0
    foreach ($f in $files) {
        # Ищем файл в снапшоте
        $relPath = $f.Path -replace '^[A-Za-z]:', ''
        $relPath = $relPath -replace '^\\', ''
        $relPath = $relPath -replace '\\', '_'
        $snapFile = Join-Path $lastSnap.FullName "$($f.Name)_$relPath"
        if (Test-Path $snapFile) {
            $currentContent = Get-Content $f.Path -Raw -Encoding UTF8
            $snapContent = Get-Content $snapFile -Raw -Encoding UTF8
            if ($currentContent -ne $snapContent) {
                Write-Log "  $($f.Name): ИЗМЕНЁН" 'Yellow'
                $diffCount += 1
            } else {
                Write-Log "  $($f.Name): без изменений" 'Green'
            }
        } else {
            Write-Log "  $($f.Name): НОВЫЙ (нет в снапшоте)" 'Cyan'
            $diffCount += 1
        }
    }
    Write-Log "Итого: $diffCount изменённых/новых конфигов" $(if ($diffCount -gt 0) { 'Yellow' } else { 'Green' })
}

function Show-Help {
    Write-Host @"

OC-Config-Manager.ps1 — управление конфигами OpenCode

ИСПОЛЬЗОВАНИЕ:
  powershell -File OC-Config-Manager.ps1 <команда> [параметры]

КОМАНДЫ:
  save     -Name "описание"   Сохранить снапшот всех конфигов
  restore  -Date "YYYYMMDD..." Восстановить из указанного снапшота
  restore                     Восстановить из последнего снапшота
  check    [-Verbose]         Диагностика конфигов
  list                        Показать список снапшотов
  diff                        Сравнить текущее с последним снапшотом
  autosave                    Сохранить с авто-меткой
  help                        Эта справка

ПРИМЕРЫ:
  powershell -File OC-Config-Manager.ps1 save -Name "Перед правкой"
  powershell -File OC-Config-Manager.ps1 check -Verbose
  powershell -File OC-Config-Manager.ps1 restore -Date "20260717_121500"
  powershell -File OC-Config-Manager.ps1 restore
  powershell -File OC-Config-Manager.ps1 list

КОНФИГУРАЦИЯ:
  config\oc-config-manager.json — список проектов и настройки
  archives\OpenCode\Snapshot_* — снапшоты конфигов

"@ -ForegroundColor Cyan
}

# ============================================================
# ТОЧКА ВХОДА
# ============================================================

function Get-Config {
    return Read-Config
}

switch ($Command) {
    'save' {
        Invoke-Save -SnapshotName $Name
    }
    'restore' {
        Invoke-Restore -SnapshotDate $Date
    }
    'check' {
        $null = Invoke-Check
    }
    'list' {
        Invoke-List
    }
    'diff' {
        Invoke-Diff
    }
    'autosave' {
        $ts = Get-Timestamp
        Invoke-Save -SnapshotName "auto_$ts"
    }
    'help' {
        Show-Help
    }
    default {
        Show-Help
    }
}
