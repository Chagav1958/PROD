<#
.SYNOPSIS
    Строит каталог объектов проекта AIS (PB + SQL) с извлечением зависимостей.
.DESCRIPTION
    Обходит выгрузки PB_Current/PB_Main и BD Current/Main, извлекает для каждого объекта:
      - имя, тип, библиотеку/папку, источник (current/main)
      - для SQL: таблицы (from/join/insert/update/delete) и вызовы процедур (exec usp_/fn_)
      - для PB: упоминания SQL-объектов (по совпадению имён) и PB-ссылок (w_/u_/f_/n_/m_/s_/uf_/of_)
    Результат пишется в rules/object_catalog.jsonl (по одному JSON-объекту на строку).
.PARAMETER ProjectRoot
    Корень проекта AIS Release Preparation.
.PARAMETER CatalogPath
    Путь к выходному каталогу (по умолчанию rules/object_catalog.jsonl).
#>
param(
    [string]$ProjectRoot = "C:\AIS\AI\Prod",
    [string]$CatalogPath
)

$ErrorActionPreference = "Stop"

if (-not $CatalogPath) { $CatalogPath = Join-Path $ProjectRoot "rules\object_catalog.jsonl" }

$cfg = Get-Content (Join-Path $ProjectRoot "config\config.json") -Raw -Encoding UTF8 | ConvertFrom-Json

$sources = @(
    @{ sql = $cfg.paths.bd_current_export; pb = $cfg.paths.pb_current_export; tag = 'current' },
    @{ sql = $cfg.paths.bd_main_export;    pb = $cfg.paths.pb_main_export;    tag = 'main' }
)

Write-Host "Источники:"
foreach ($s in $sources) { Write-Host ("  SQL=$( $s.sql )  PB=$( $s.pb )  [$( $s.tag )]") }

# ---------- 1. SQL объекты ----------
$sqlTypes = @{ Procedure='Procedure'; Functions='Function'; Triggers='Trigger'; Tables='Table'; Views='View'; Indexes='Index'; PK='PK'; FK='FK'; Grants='Grant' }

$sqlObjects = @{}
foreach ($s in $sources) {
    if (-not (Test-Path $s.sql)) { Write-Host "  (нет SQL-папки: $($s.sql))"; continue }
    $sqlFiles = Get-ChildItem $s.sql -Recurse -File -Filter "*.sql" -ErrorAction SilentlyContinue
    Write-Host ("Найдено SQL-файлов [$($s.tag)]: " + $sqlFiles.Count)
    foreach ($f in $sqlFiles) {
        $type = if ($sqlTypes.ContainsKey($f.Directory.Name)) { $sqlTypes[$f.Directory.Name] } else { 'Unknown' }
        $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $key = "$name|$($s.tag)"
        $sqlObjects[$key] = @{ name=$name; src=$s.tag; kind='SQL'; objType=$type; lib=$f.Directory.Name; file=$f.FullName; tables=@(); calls=@() }
    }
}

# Извлечение зависимостей SQL
$idx = 0
foreach ($key in @($sqlObjects.Keys)) {
    $idx++
    if ($idx % 1000 -eq 0) { Write-Host ("  SQL зависимости: $idx / $($sqlObjects.Count)") }
    $f = Get-Item $sqlObjects[$key].file
    $txt = $null
    try { $txt = Get-Content $f.FullName -Raw -Encoding Default } catch { $txt = $null }
    if ($null -eq $txt) { $txt = '' }
    $tables = @{}; $calls = @{}; $triggerTables = @{}
    foreach ($m in [regex]::Matches($txt, '(?i)\b(?:from|join|into|update|delete\s+from)\s+([a-z_][a-z0-9_]*)')) {
        $tables[$m.Groups[1].Value.ToLower()] = $true
    }
    foreach ($m in [regex]::Matches($txt, '(?i)\bexec\s+([a-z_][a-z0-9_]*)')) {
        $calls[$m.Groups[1].Value.ToLower()] = $true
    }
    foreach ($m in [regex]::Matches($txt, '(?i)\b(usp_[a-z0-9_]+|fn[a-z0-9_]+)')) {
        $calls[$m.Groups[1].Value.ToLower()] = $true
    }
    # Триггеры: извлекаем таблицы, на которые ссылается триггер (inserted/deleted, update/insert/delete на таблицу)
    if ($sqlObjects[$key].objType -eq 'Trigger') {
        foreach ($m in [regex]::Matches($txt, '(?i)\b(?:inserted|deleted)\b')) { $triggerTables[$m.Value.ToLower()] = $true }
        foreach ($m in [regex]::Matches($txt, '(?i)\b(?:update|insert\s+into|delete\s+from)\s+([a-z_][a-z0-9_]*)')) {
            $triggerTables[$m.Groups[1].Value.ToLower()] = $true
        }
    }
    $sqlObjects[$key].tables = @($tables.Keys)
    $sqlObjects[$key].calls  = @($calls.Keys)
    if ($sqlObjects[$key].objType -eq 'Trigger') { $sqlObjects[$key].linkedTables = @($triggerTables.Keys) }
}

# ---------- 2. PB объекты ----------
$pbExtType = @{ sru='UserObject'; srw='Window'; srd='DataWindow'; srf='Function'; srp='Pipeline'; srs='Structure'; srm='Menu'; srj='Project'; sra='Application' }
$pbObjects = @{}
$sqlNameSet = New-Object 'System.Collections.Generic.HashSet[string]'(,[string[]]@($sqlObjects.Keys))

foreach ($s in $sources) {
    if (-not (Test-Path $s.pb)) { Write-Host "  (нет PB-папки: $($s.pb))"; continue }
    $pbFiles = Get-ChildItem $s.pb -Recurse -File -Filter "*.sr*" -ErrorAction SilentlyContinue
    Write-Host ("Найдено PB-файлов [$($s.tag)]: " + $pbFiles.Count)
    $idx = 0
    foreach ($f in $pbFiles) {
        $idx++
        if ($idx % 500 -eq 0) { Write-Host ("  PB обработка [$($s.tag)]: $idx / $($pbFiles.Count)") }
        $ext = $f.Extension.TrimStart('.').ToLower()
        $type = if ($pbExtType.ContainsKey($ext)) { $pbExtType[$ext] } else { $ext }
        $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $lib  = $f.Directory.Name
        $txt = $null
        try { $txt = Get-Content $f.FullName -Raw -Encoding Unicode } catch { $txt = $null }
        if ($null -eq $txt) { $txt = '' }
        $sqlRefs = @{}; $pbRefs = @{}; $srdExprs = @{}; $srdDynSQL = @{}; $srdValid = @{}; $srdMasks = @{}; $srdComputed = @{}; $srdFilters = @{}
        if ($txt.Length -gt 0) {
            # Общие PB-ссылки
            foreach ($m in [regex]::Matches($txt, '\b([a-z_][a-z0-9_]{2,60})\b')) {
                $tok = $m.Groups[1].Value.ToLower()
                if ($sqlNameSet.Contains($tok)) { $sqlRefs[$tok] = $true }
            }
            foreach ($m in [regex]::Matches($txt, '\b([uwfnmos][a-z0-9_]{2,60})\b')) {
                $pbRefs[$m.Groups[1].Value.ToLower()] = $true
            }
            # DataWindow (.srd) специфичные извлечения
            if ($ext -eq 'srd') {
                # DynamicSQL / SelectCommand
                foreach ($m in [regex]::Matches($txt, '(?is)(?:dataobject\.sqlca\.selectcommand|modify\([\'"]datawindow\.select)[\s\S]{0,500}?(select\s+.+?\s+from\s+\w+)')) {
                    $srdDynSQL[$m.Groups[1].Value.Trim()] = $true
                }
                # Expressions в колонках
                foreach ($m in [regex]::Matches($txt, '(?i)expression\s*=\s*[\'"]([^\'"]+)[\'"]')) {
                    $srdExprs[$m.Groups[1].Value] = $true
                }
                # Validation rules
                foreach ($m in [regex]::Matches($txt, '(?i)validation\s*=\s*[\'"]([^\'"]+)[\'"]')) {
                    $srdValid[$m.Groups[1].Value] = $true
                }
                # Edit masks
                foreach ($m in [regex]::Matches($txt, '(?i)editmask\s*=\s*[\'"]([^\'"]+)[\'"]')) {
                    $srdMasks[$m.Groups[1].Value] = $true
                }
                # Computed fields
                foreach ($m in [regex]::Matches($txt, '(?i)computed_field.*?expression\s*=\s*[\'"]([^\'"]+)[\'"]')) {
                    $srdComputed[$m.Groups[1].Value] = $true
                }
                # Filters
                foreach ($m in [regex]::Matches($txt, '(?i)filter\s*=\s*[\'"]([^\'"]+)[\'"]')) {
                    $srdFilters[$m.Groups[1].Value] = $true
                }
            }
        }
        $key = "$name|$($s.tag)"
        $pbObjects[$key] = @{ 
            name=$name; src=$s.tag; kind='PB'; objType=$type; lib=$lib; file=$f.FullName; 
            sqlRefs=@($sqlRefs.Keys); pbRefs=@($pbRefs.Keys);
            srdExprs=@($srdExprs.Keys); srdDynSQL=@($srdDynSQL.Keys); srdValid=@($srdValid.Keys); srdMasks=@($srdMasks.Keys); srdComputed=@($srdComputed.Keys); srdFilters=@($srdFilters.Keys)
        }
    }
}
            foreach ($m in [regex]::Matches($txt, '\b([uwfnmos][a-z0-9_]{2,60})\b')) {
                $pbRefs[$m.Groups[1].Value.ToLower()] = $true
            }
        }
        $key = "$name|$($s.tag)"
        $pbObjects[$key] = @{ name=$name; src=$s.tag; kind='PB'; objType=$type; lib=$lib; file=$f.FullName; sqlRefs=@($sqlRefs.Keys); pbRefs=@($pbRefs.Keys) }
    }
}

# ---------- 3. Запись каталога (JSONL) ----------
$lines = @()
foreach ($o in $sqlObjects.Values) { $lines += ($o | ConvertTo-Json -Compress) }
foreach ($o in $pbObjects.Values) { $lines += ($o | ConvertTo-Json -Compress) }

Set-Content $CatalogPath -Value $lines -Encoding UTF8

Write-Host ""
Write-Host ("=== Каталог построен ===") -ForegroundColor Cyan
Write-Host ("Объектов: " + $lines.Count)
Write-Host ("SQL: " + $sqlObjects.Count + "  PB: " + $pbObjects.Count)
Write-Host ("Файл: " + $CatalogPath)
