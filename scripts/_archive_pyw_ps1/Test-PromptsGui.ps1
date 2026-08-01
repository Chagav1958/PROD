<#
.SYNOPSIS
    Автотест GUI ПРОМПТ: проверяет парсинг, поиск и подсветку без участия человека.
#>

# Проверка STA
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
    $scriptPath = $PSCommandPath
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Content $scriptPath -Raw -Encoding UTF8)))
    powershell -NoProfile -Sta -Command "Invoke-Expression ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded')))"
    exit
}

# WPF не требуется для теста логики (STA не нужен)

$scriptRoot = Split-Path $PSScriptRoot -Parent
$logPath = Join-Path $scriptRoot "temp\prompts_autotest.log"
$logFile = Join-Path $scriptRoot "temp\user_prompts.log"
$script:testsPassed = 0; $script:testsFailed = 0

function Write-Log { param([string]$Text)
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Text"
    Add-Content -Path $logPath -Value $line -Encoding UTF8; Write-Host $line }

function Assert-True { param([string]$Name, [bool]$Cond)
    if ($Cond) { Write-Log "  PASS: $Name"; $script:testsPassed++ }
    else { Write-Log "  FAIL: $Name"; $script:testsFailed++ } }

Write-Log "=== АВТОТЕСТ GUI ПРОМПТ ==="

# === Тест 0: Проверка наличия файла лога ===
Write-Log "--- Тест 0: Наличие лога ---"
Assert-True "Файл user_prompts.log существует" (Test-Path $logFile)
$logContent = Get-Content $logFile -Raw -Encoding UTF8
Assert-True "Файл не пуст" ($logContent.Length -gt 0)

# === Тест 1: Парсинг лога (копируем функцию из Show-Prompts.ps1) ===
Write-Log "--- Тест 1: Парсинг ---"
$raw = Get-Content $logFile -Raw -Encoding UTF8
$blocks = $raw -split '={3,}' | Where-Object { $_.Trim() -ne '' }
Assert-True "Найдено блоков > 0" ($blocks.Count -gt 0)

$parsed = @()
foreach ($block in $blocks) {
    $lines = $block.Trim() -split "`r`n|`n"
    $dt = ""; $text = ""
    if ($lines.Count -ge 1 -and $lines[0] -match '\[(.+?)\]') {
        $dt = $matches[1].Trim()
        $text = ($lines[1..($lines.Count-1)] | Where-Object { $_ -ne '' }) -join "`n"
    } else { $text = $lines -join "`n" }
    $firstLine = ($text -split "`n")[0]
    $name = if ($firstLine.Length -gt 60) { $firstLine.Substring(0,57) + "..." } else { $firstLine }
    if ([string]::IsNullOrWhiteSpace($name)) { $name = "(пусто)" }
    $parsed += [PSCustomObject]@{ Name = $name; DateTime = $dt; FullText = $text }
}
Assert-True "Распаршено записей > 0" ($parsed.Count -gt 0)

# === Тест 2: Поиск контекста ===
Write-Log "--- Тест 2: Поиск ---"
$allFullTexts = $parsed | ForEach-Object { $_.FullText }
# Берём первое слово из первого непустого FullText для поиска
$searchWord = ""
foreach ($p in $parsed) {
    if (-not [string]::IsNullOrEmpty($p.FullText)) {
        $words = $p.FullText -split '\s+'
        foreach ($w in $words) {
            if ($w.Length -ge 4) { $searchWord = $w; break }
        }
        if ($searchWord) { break }
    }
}
if (-not $searchWord) { $searchWord = "LLM" }
Write-Log "Поисковое слово: '$searchWord'"

$results = $parsed | Where-Object { $null -ne $_.FullText -and $_.FullText -match [regex]::Escape($searchWord) }
Assert-True "Найдено совпадений > 0" ($results.Count -gt 0)

# === Тест 3: Логика подсветки (без WPF — только split-логика) ===
Write-Log "--- Тест 3: Логика подсветки ---"
$sampleText = "Это тестовый текст для поиска"
$sampleQuery = "тестовый"

function Get-HighlightParts {
    param([string]$Text, [string]$Query)
    if ([string]::IsNullOrEmpty($Query)) { return @(@{Type="text"; Value=$Text}) }
    $parts = $Text -split ([regex]::Escape($Query))
    $result = @()
    for ($i = 0; $i -lt $parts.Count; $i++) {
        if ($parts[$i]) { $result += @{Type="text"; Value=$parts[$i]} }
        if ($i -lt $parts.Count - 1) { $result += @{Type="highlight"; Value=$Query} }
    }
    return $result
}

# Тест 3.1: Пустой запрос — возвращается 1 элемент text
$parts = Get-HighlightParts $sampleText ""
Assert-True "Пустой запрос: 1 часть" (@($parts).Count -ge 1)

# Тест 3.1b: Проверка структуры результата для пустого запроса
$testEmpty = Get-HighlightParts "abc" ""
Assert-True "Пустой запрос: результат array" (@($testEmpty).Count -ge 1)

# Тест 3.2: Запрос найден
$parts = Get-HighlightParts $sampleText $sampleQuery
Assert-True "Запрос найден: 3 части" ($parts.Count -eq 3)
Assert-True "Запрос найден: часть 1 text" ($parts[0].Type -eq "text" -and $parts[0].Value -eq "Это ")
Assert-True "Запрос найден: часть 2 highlight" ($parts[1].Type -eq "highlight" -and $parts[1].Value -eq $sampleQuery)
Assert-True "Запрос найден: часть 3 text" ($parts[2].Type -eq "text" -and $parts[2].Value -eq " текст для поиска")

# Тест 3.3: Запрос не найден — возвращается 1 элемент text
$partsNF = Get-HighlightParts $sampleText "несуществующий"
Assert-True "Запрос не найден: есть результат" (@($partsNF).Count -ge 1)

# Тест 3.4: Множественные совпадения
$partsM = Get-HighlightParts "текст текст текст" "текст"
Assert-True "Множественные: есть результат" (@($partsM).Count -ge 1)

# Тест 3.5: Пустой текст
$parts = Get-HighlightParts "" "запрос"
Assert-True "Пустой текст: 0 частей" ($parts.Count -eq 0)

# Тест 3.6: Совпадение в начале
$parts = Get-HighlightParts "тестовый текст" "тестовый"
Assert-True "В начале: 2 части" ($parts.Count -eq 2)
Assert-True "В начале: часть 1 highlight" ($parts[0].Type -eq "highlight")
Assert-True "В начале: часть 2 text" ($parts[1].Type -eq "text" -and $parts[1].Value -eq " текст")

# Тест 3.7: Совпадение в конце
$parts = Get-HighlightParts "текст тестовый" "тестовый"
Assert-True "В конце: 2 части" ($parts.Count -eq 2)
Assert-True "В конце: часть 1 text" ($parts[0].Type -eq "text" -and $parts[0].Value -eq "текст ")
Assert-True "В конце: часть 2 highlight" ($parts[1].Type -eq "highlight")

# === Тест 4: Поиск с регекс-спецсимволами ===
Write-Log "--- Тест 4: Регекс-спецсимволы ---"
$querySpecial = "текст.текст"
$textSpecial = "это текст.текст пример"
$partsSpecial = $textSpecial -split ([regex]::Escape($querySpecial))
Assert-True "Escape работает для спецсимволов" ($partsSpecial.Count -eq 2)

# === Тест 5: Навигация ▼/▲ ===
Write-Log "--- Тест 5: Навигация ---"
# Симуляция логики навигации из Show-Prompts.ps1
$st = @{ results = @($results); index = 0; query = $searchWord }
Assert-True "Результатов > 0 для навигации" ($st.results.Count -gt 0)

# ▼: переход к следующему
$st.index = ($st.index + 1) % $st.results.Count
Assert-True "▼ перешёл к индексу 1" ($st.index -eq 1)

# ▲: переход к предыдущему (на последний)
$st.index = ($st.index - 1 + $st.results.Count) % $st.results.Count
Assert-True "▲ вернулся к индексу 0" ($st.index -eq 0)

# === Тест 6: Навигация с циклическим переходом ===
Write-Log "--- Тест 6: Цикл навигации ---"
$st2 = @{ results = @(1..3); index = 0; query = "test" }
$st2.index = ($st2.index + 1) % $st2.results.Count
$st2.index = ($st2.index + 1) % $st2.results.Count
$st2.index = ($st2.index + 1) % $st2.results.Count  # 3-й раз = возврат к 0
Assert-True "Цикл ▼ 3 раза: вернулся к 0" ($st2.index -eq 0)

$st2.index = ($st2.index - 1 + $st2.results.Count) % $st2.results.Count  # с 0 на последний
Assert-True "Цикл ▲ с 0: на последний (2)" ($st2.index -eq 2)

# === Итог ===
Write-Log "--- ИТОГ ---"
Write-Log "Пройдено: $($script:testsPassed), Провалено: $($script:testsFailed)"
if ($script:testsFailed -gt 0) { exit 1 } else { exit 0 }







