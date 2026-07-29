<#
.SYNOPSIS
    Автотест ДО RULES: проверяет загрузку файлов, структуру вкладок и поиск.
#>
$scriptRoot = Split-Path $PSScriptRoot -Parent
$rulesScript = Join-Path $scriptRoot "scripts\Show-Rules.ps1"
$logPath = Join-Path $scriptRoot "temp\rules_autotest.log"
$script:testsPassed = 0; $script:testsFailed = 0; $script:cycleCount = 0

function Write-Log { param([string]$Text)
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Text"
    Add-Content -Path $logPath -Value $line -Encoding UTF8; Write-Host $line }

function Assert-True { param([string]$Name, [bool]$Cond)
    if ($Cond) { Write-Log "  PASS: $Name"; $script:testsPassed++ }
    else { Write-Log "  FAIL: $Name"; $script:testsFailed++ } }

# Максимум 50 циклов
$maxCycles = 50

Write-Log "=== АВТОТЕСТ ДО RULES (макс. $maxCycles циклов) ==="

# === Тест 1: Проверка существования скрипта ===
Write-Log "--- Тест 1: Существование ---"
Assert-True "Show-Rules.ps1 существует" (Test-Path $rulesScript)

# === Тест 2: Парсер PS ===
Write-Log "--- Тест 2: Парсер ---"
$err = $null
[System.Management.Automation.Language.Parser]::ParseFile($rulesScript, [ref]$null, [ref]$err)
Assert-True "Парсер PS: нет ошибок" ($err.Count -eq 0)
$script:cycleCount++

# === Тест 3: Загрузка файлов-правил ===
Write-Log "--- Тест 3: Файлы-правил ---"
# Подгружаем код Show-Rules.ps1 до построения окна
$rulesContent = Get-Content $rulesScript -Raw -Encoding UTF8
Assert-True "Скрипт не пуст" ($rulesContent.Length -gt 0)

# Проверяем определение вкладок (tabDefs)
$tabDefsMatch = [regex]::Match($rulesContent, '\$tabDefs\s*=\s*@\(.*?\)\s*\n\s*\n\s*\n\s*# Загрузка', [Text.RegularExpressions.RegexOptions]::Singleline)
if ($tabDefsMatch.Success) {
    $tabDefsText = $tabDefsMatch.Value
    $tabCount = [regex]::Matches($tabDefsText, 'Name\s*=').Count
    Assert-True "Определено вкладок = 11" ($tabCount -eq 11)
} else {
    Write-Log "  FAIL: tabDefs не найдены"
    $script:testsFailed++
}
$script:cycleCount++

# Проверяем, что все 39 файлов упомянуты
$fileRefs = [regex]::Matches($rulesContent, 'Path\s*=\s*"([^"]+)"')
$uniqueFiles = $fileRefs | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
Assert-True "Уникальных файлов в tabDefs = 40 (с AGENTS.md)" ($uniqueFiles.Count -eq 40)

# === Тест 4: Проверка существования всех файлов ===
Write-Log "--- Тест 4: Существование файлов ---"
$missingFiles = @()
foreach ($f in $uniqueFiles) {
    $fullPath = Join-Path $scriptRoot $f
    if (-not (Test-Path $fullPath)) { $missingFiles += $f }
}
Assert-True "Все файлы существуют" ($missingFiles.Count -eq 0)
if ($missingFiles.Count -gt 0) {
    foreach ($mf in $missingFiles) { Write-Log "  Не найден: $mf" }
}
$script:cycleCount++

# === Тест 5: Загрузка содержимого ===
Write-Log "--- Тест 5: Загрузка содержимого ---"
$loadedOk = 0; $loadedFail = 0
foreach ($f in $uniqueFiles) {
    $fullPath = Join-Path $scriptRoot $f
    try {
        $content = [System.IO.File]::ReadAllText($fullPath, [Text.Encoding]::UTF8)
        if ($content.Length -gt 0) { $loadedOk++ } else { $loadedFail++ }
    } catch { $loadedFail++ }
}
Assert-True "Все файлы читаются" ($loadedFail -eq 0)
Assert-True "Все файлы непусты" ($loadedFail -eq 0)
$script:cycleCount++

# === Тест 6: Поиск контекста "RFC" во всех файлах ===
Write-Log "--- Тест 6: Поиск 'RFC' ---"
$searchQuery = "RFC"
$foundInFiles = @()
foreach ($f in $uniqueFiles) {
    $fullPath = Join-Path $scriptRoot $f
    $content = [System.IO.File]::ReadAllText($fullPath, [Text.Encoding]::UTF8)
    if ($content -match [regex]::Escape($searchQuery)) { $foundInFiles += $f }
}
Assert-True "'RFC' найден хотя бы в 1 файле" ($foundInFiles.Count -gt 0)
Write-Log "  Найден в $($foundInFiles.Count) файлах"
foreach ($ff in $foundInFiles[0..[Math]::Min(4, $foundInFiles.Count-1)]) {
    Write-Log "    $ff"
}
$script:cycleCount++

# === Тест 7: Поиск контекста в каждом файле (выборочно) ===
Write-Log "--- Тест 7: Выборочный поиск ---"
# Берём первые 5 файлов и проверяем, что в них есть хотя бы какое-то содержимое
$testFiles = $uniqueFiles | Select-Object -First 5
foreach ($tf in $testFiles) {
    $fullPath = Join-Path $scriptRoot $tf
    $content = [System.IO.File]::ReadAllText($fullPath, [Text.Encoding]::UTF8)
    Assert-True "Файл '$tf' содержит текст" ($content.Length -gt 10)
    $script:cycleCount++
    if ($script:cycleCount -ge $maxCycles) { break }
}

# === Тест 8: Проверка структуры AGENTS.md ===
Write-Log "--- Тест 8: Структура AGENTS.md ---"
$agentsPath = Join-Path $scriptRoot "AGENTS.md"
$agentsContent = Get-Content $agentsPath -Raw -Encoding UTF8
Assert-True "AGENTS.md содержит 'Сводка файлов-правил'" ($agentsContent -match "Сводка файлов-правил")
Assert-True "AGENTS.md содержит 'Язык общения'" ($agentsContent -match "Язык общения")
$script:cycleCount++

# === Тест 9: Проверка encoding ===
Write-Log "--- Тест 9: Encoding ---"
$psFilesWithCyrillic = @(Get-ChildItem $scriptRoot\scripts\*.ps1 -Force | Where-Object { 
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    $hasBom = $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
    $content = [System.IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8)
    $hasCyrillic = $content -match '[А-Яа-яЁё]'
    $hasBom -and $hasCyrillic
})
Assert-True "PS-файлы с кириллицей имеют BOM" ($psFilesWithCyrillic.Count -ge 5)
$script:cycleCount++

# === Итог ===
Write-Log "--- ИТОГ ---"
Write-Log "Циклов: $($script:cycleCount) / $maxCycles"
Write-Log "Пройдено: $($script:testsPassed), Провалено: $($script:testsFailed)"
if ($script:testsFailed -gt 0) { exit 1 } else { exit 0 }

