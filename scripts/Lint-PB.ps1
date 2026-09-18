# Lint-PB.ps1 — СЕРВИС PB, мера M3: линтер объектов PB/SQL
#
# Назначение: сканирует папки (Test_/Diag_/готовые объекты) на типовые ошибки
# разработки, чтобы НЕ отправлять пользователю заведомо некорректные файлы:
#   1) запрещённые идиомы (iif(, ??, ?., =>, Switch( в PB/SQL-контексте);
#   2) выдуманные перечисляемые константы messageBox (например Warning!),
#      которых нет в проверенном списке проекта;
#   3) даты в формате ДД.ММ.ГГГГ (mdy-ловушка на galaxy) — вместо ISO YYYY-MM-DD;
#   4) подозрительные символы в кириллических строках (кракозябры) для .srw/.sql.
#
# Отчёт: temp/pb_lint_report.txt (UTF-8). Выход: 0 = чисто, 1 = есть находки.
#
# Использование:
#   powershell -NoLogo -File scripts\Lint-PB.ps1
#   powershell -NoLogo -File scripts\Lint-PB.ps1 -Dir "C:\AIS\1 Release\SUPRT-19100\Test_2026_09_16__13_50"
#   powershell -NoLogo -File scripts\Lint-PB.ps1 -Dir "C:\AIS\1 Release\SUPRT-19100\Diag_2026_09_16_13_50" -Out temp\pb_lint_report.txt

param(
    [string]$Dir,                     # папка для проверки (по умолчанию: поиск Test_* в C:\AIS\1 Release\SUPRT-19100)
    [string]$Out                       # файл отчёта (по умолчанию temp\pb_lint_report.txt)
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
$prodRoot = (Resolve-Path (Join-Path $scriptRoot "..")).Path
$taskRoot = "C:\AIS\1 Release\SUPRT-19100"

# Проверенный список констант messageBox в проекте (16.09.2026, grep по PB_Main)
$allowedIcons = @(
    'Information!', 'StopSign!', 'Exclamation!', 'Question!',
    'None!', 'Error!', 'Asterisk!', 'Hand!'
)
$knownBadIcons = @('Warning!', 'Warn!', 'WarningExclamation!')

# Запрещённые идиомы (нет в PowerScript/Transact-SQL)
$forbiddenIdioms = @(
    'iif(',
    '??',
    '?.',
    '=>',
    'Switch('
)

$extensions = @('.srw', '.sru', '.srd', '.sra', '.srs', '.srm', '.srf', '.sql')

function Find-TargetDirs {
    if ($Dir) {
        if (-not (Test-Path -LiteralPath $Dir)) { Write-Error "Папка не найдена: $Dir"; exit 1 }
        return @($Dir)
    }
    $dirs = @(Get-ChildItem -LiteralPath $taskRoot -Directory -Filter "Test_*" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    if ($dirs.Count -eq 0) { $dirs = @(Get-ChildItem -LiteralPath $taskRoot -Directory -Filter "Diag_*" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName) }
    if ($dirs.Count -eq 0) { Write-Error "Не найдено папок Test_*/Diag_* в $taskRoot. Укажите -Dir."; exit 1 }
    return @($dirs)
}

function Test-DateMdy {
    param([string]$Text)
    # Литералы дат вида '07.09.2026' / "07.09.2026" (ДД.ММ.ГГГГ) — mdy-ловушка на galaxy.
    $matches = [regex]::Matches($Text, "['\""]\d{2}\.\d{2}\.\d{4}['\""]")
    return @($matches | ForEach-Object { $_.Value })
}

function Test-BadChars {
    param([string]$Text, [string]$EncodingName)
    # Для UTF-8 файлов: наличие байт-последовательностей, которые читаются как �
    # (замена/кракозябры) — признак неверной кодировки.
    if ($EncodingName -ne 'UTF8') { return @() }
    $bad = [regex]::Matches($Text, "[\uFFFD\uFFFE\uFFFF]")
    return @($bad | ForEach-Object { $_.Value })
}

function Test-InsideString {
    param([string]$Text, [int]$Index)
    # Возвращает true, если позиция Index находится внутри строкового литерала
    # (в одинарных '...' или двойных "...") на той же строке.
    $lineStart = $Text.LastIndexOf("`n", $Index)
    if ($lineStart -lt 0) { $lineStart = 0 } else { $lineStart++ }
    $lineEnd = $Text.IndexOf("`n", $Index)
    if ($lineEnd -lt 0) { $lineEnd = $Text.Length }
    $line = $Text.Substring($lineStart, $lineEnd - $lineStart)
    $pos = $Index - $lineStart
    $singleOpen = $false
    $doubleOpen = $false
    for ($i = 0; $i -lt $pos -and $i -lt $line.Length; $i++) {
        $ch = $line[$i]
        if ($ch -eq "'" -and -not $doubleOpen) { $singleOpen = -not $singleOpen }
        elseif ($ch -eq '"' -and -not $singleOpen) { $doubleOpen = -not $doubleOpen }
    }
    return ($singleOpen -or $doubleOpen)
}

$targetDirs = Find-TargetDirs
$findings = New-Object System.Collections.Generic.List[string]
$filesScanned = 0

foreach ($d in $targetDirs) {
    $files = @(Get-ChildItem -LiteralPath $d -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $extensions -contains $_.Extension.ToLower() })
    foreach ($file in $files) {
        $filesScanned++
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)
        $encodingName = if ($hasBom) { 'UTF8' } else { 'ANSI' }
        $text = if ($hasBom) { [System.Text.Encoding]::UTF8.GetString($bytes) } else { [System.Text.Encoding]::GetEncoding(1251).GetString($bytes) }

        # 1) запрещённые идиомы (только вне строковых литералов)
        foreach ($idiom in $forbiddenIdioms) {
            $searchFrom = 0
            while ($true) {
                $idx = $text.IndexOf($idiom, $searchFrom)
                if ($idx -lt 0) { break }
                # Пропустить, если вхождение внутри строкового литерала (кавычки до него на той же строке)
                if (-not (Test-InsideString -Text $text -Index $idx)) {
                    $start = [Math]::Max(0, $idx - 20)
                    $len = [Math]::Min(60, $text.Length - $start)
                    $snippet = $text.Substring($start, $len)
                    $findings.Add("[$($file.FullName)] запрещённая идиома '$idiom': ...$snippet...")
                }
                $searchFrom = $idx + $idiom.Length
            }
        }

        # 2) выдуманные константы messageBox
        foreach ($bad in $knownBadIcons) {
            $idx = $text.IndexOf($bad)
            if ($idx -ge 0) {
                $snippet = $text.Substring([Math]::Max(0, $idx - 30), [Math]::Min(70, $text.Length - [Math]::Max(0, $idx - 30)))
                $findings.Add("[$($file.FullName)] выдуманная константа '$bad' (нет в проекте; используйте " + ($allowedIcons -join '/') + "): ...$snippet...")
            }
        }

        # 3) mdy-даты
        $mdy = Test-DateMdy -Text $text
        if ($mdy.Count -gt 0) {
            foreach ($dm in $mdy) {
                $findings.Add("[$($file.FullName)] дата в формате ДД.ММ.ГГГГ '$dm' — mdy-ловушка на galaxy; используйте ISO 'YYYY-MM-DD'")
            }
        }

        # 4) кракозябры (только UTF-8 файлы)
        if ($hasBom) {
            $badChars = Test-BadChars -Text $text -EncodingName 'UTF8'
            if ($badChars.Count -gt 0) {
                $findings.Add("[$($file.FullName)] обнаружены байты замены/кракозябры (неверная кодировка?)")
            }
        }
    }
}

# Отчёт
if (-not $Out) { $Out = Join-Path $prodRoot "temp\pb_lint_report.txt" }
$reportLines = New-Object System.Collections.Generic.List[string]
$reportLines.Add("=== PB LINT REPORT: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===")
$reportLines.Add("Папки: " + ($targetDirs -join '; '))
$reportLines.Add("Файлов проверено: $filesScanned")
$reportLines.Add("Находок: $($findings.Count)")
$reportLines.Add("")
if ($findings.Count -gt 0) {
    foreach ($f in $findings) { $reportLines.Add($f) }
} else {
    $reportLines.Add("ЧИСТО: замечаний нет.")
}

$outDir = Split-Path -Parent $Out
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
[System.IO.File]::WriteAllLines($Out, $reportLines, (New-Object System.Text.UTF8Encoding($false)))

# СЕРВИС PB M3: запись статистики в config/pb_service.json
try {
    $serviceCfg = Join-Path $prodRoot "config\pb_service.json"
    if (Test-Path -LiteralPath $serviceCfg) {
        $cfg = Get-Content -LiteralPath $serviceCfg -Raw -Encoding UTF8 | ConvertFrom-Json
        $cfg.stats.m3_lint_runs = [int]$cfg.stats.m3_lint_runs + 1
        $cfg.stats.m3_lint_findings = [int]$cfg.stats.m3_lint_findings + $findings.Count
        $entry = [ordered]@{ time = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); action = "линтер: $filesScanned файлов, $($findings.Count) находок" }
        $cfg.history = @($cfg.history) + @($entry)
        if ($cfg.history.Count -gt 100) { $cfg.history = @($cfg.history)[-100..-1] }
        [System.IO.File]::WriteAllText($serviceCfg, ($cfg | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    }
} catch { /* не блокируем при ошибке записи статистики */ }

# Вывод на консоль
foreach ($line in $reportLines) { Write-Output $line }

if ($findings.Count -gt 0) {
    Write-Output ""
    Write-Output "Найдены замечания. См. отчёт: $Out"
    exit 1
} else {
    Write-Output ""
    Write-Output "Линтер завершён чисто. Отчёт: $Out"
    exit 0
}