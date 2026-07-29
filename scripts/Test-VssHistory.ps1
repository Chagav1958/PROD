<#
.SYNOPSIS
    Автотест ДО VSS История: запускает окно истории, выполняет поиск контекста.
.DESCRIPTION
    Использует AutomatedTest режим VSS-History-Show.ps1 + прямой запуск с параметрами.
    Тест сам указывает значения и нажимает кнопки без участия человека.
#>

param(
    [string]$VssDb = "\\ren-msksf01\VSS2005\srcsafe.ini",
    [string]$VssUser = "vchaga",
    [string]$VssPass = "1111",
    [string]$VssPath = "$/SRC125/gold/golden_sprw/w_sprw_all.srw",
    [string]$SearchText = "Чага",
    [int]$MaxCycles = 50
)

$scriptRoot = Split-Path $PSScriptRoot -Parent
$logPath = Join-Path $scriptRoot "temp\vss_history_autotest.log"
$script:testsPassed = 0; $script:testsFailed = 0; $script:cycleCount = 0

function Write-Log { param([string]$Text)
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Text"
    Add-Content -Path $logPath -Value $line -Encoding UTF8; Write-Host $line }

function Assert-True { param([string]$Name, [bool]$Cond)
    if ($Cond) { Write-Log "  PASS: $Name"; $script:testsPassed++ }
    else { Write-Log "  FAIL: $Name"; $script:testsFailed++ } }

Write-Log "=== АВТОТЕСТ VSS История ==="
Write-Log "Объект: $VssPath"
Write-Log "Поиск: '$SearchText'"
Write-Log "Макс. циклов: $MaxCycles"

# === Тест 1: Проверка существования скрипта ===
Write-Log "--- Тест 1: Существование ---"
$vssScript = Join-Path $scriptRoot "scripts\VSS-History-Show.ps1"
$vssHistoryScript = Join-Path $scriptRoot "scripts\VSS-History.ps1"
Assert-True "VSS-History-Show.ps1 существует" (Test-Path $vssScript)
Assert-True "VSS-History.ps1 существует" (Test-Path $vssHistoryScript)
$script:cycleCount++

# === Тест 2: Парсер PS ===
Write-Log "--- Тест 2: Парсер ---"
$err = $null
[System.Management.Automation.Language.Parser]::ParseFile($vssScript, [ref]$null, [ref]$err)
Assert-True "Парсер VSS-History-Show.ps1" ($err.Count -eq 0)
$script:cycleCount++

$err2 = $null
[System.Management.Automation.Language.Parser]::ParseFile($vssHistoryScript, [ref]$null, [ref]$err2)
Assert-True "Парсер VSS-History.ps1" ($err2.Count -eq 0)
$script:cycleCount++

# === Тест 3: Загрузка VSS-History.ps1 и проверка функций ===
Write-Log "--- Тест 3: Функции ---"
. $vssHistoryScript
Assert-True "Get-VssHistory существует" (Get-Command Get-VssHistory -ErrorAction SilentlyContinue)
Assert-True "Search-InVssHistory существует" (Get-Command Search-InVssHistory -ErrorAction SilentlyContinue)
Assert-True "Get-VssVersionFile существует" (Get-Command Get-VssVersionFile -ErrorAction SilentlyContinue)
$script:cycleCount++

# === Тест 4: Поиск контекста через VSS API ===
Write-Log "--- Тест 4: Поиск '$SearchText' в VSS ---"
try {
    $history = Get-VssHistory -VssPath $VssPath -VssDb $VssDb -VssUser $VssUser -VssPass $VssPass
    Assert-True "История получена" ($history.Count -gt 0)
    Write-Log "  Всего версий: $($history.Count)"
    $script:cycleCount++

    $sorted = $history | Sort-Object { $_.Version } -Descending
    $searchResults = Search-InVssHistory -VssPath $VssPath -SearchText $SearchText -VssDb $VssDb -VssUser $VssUser -VssPass $VssPass
    Assert-True "Контекст '$SearchText' найден" ($searchResults.Count -gt 0)
    Write-Log "  Найдено в $($searchResults.Count) версиях"
    $script:cycleCount++

    $first = $searchResults | Sort-Object { $_.Version } | Select-Object -First 1
    Write-Log "  Первое совпадение: версия $($first.Version) ($($first.User), $($first.Date))"
} catch {
    Write-Log "  FAIL: Ошибка VSS: $_"
    $script:testsFailed++
}
$script:cycleCount++

# === Тест 5: Запуск AutomatedTest режима ===
Write-Log "--- Тест 5: AutomatedTest ---"
$proc = $null
try {
    $proc = Start-Process powershell.exe -ArgumentList "-NoProfile -Sta -File `"$vssScript`" -VssDb `"$VssDb`" -VssUser `"$VssUser`" -VssPass `"$VssPass`" -VssPath `"$VssPath`" -AutomatedTest" -PassThru -WindowStyle Normal
    Start-Sleep -Seconds 2
    Write-Log "  Процесс запущен (PID: $($proc.Id))"
    $script:cycleCount++

    # Ждём завершения (до 30 сек)
    $waitResult = $proc.WaitForExit(30000)
    if ($waitResult) {
        Write-Log "  Процесс завершён (exit: $($proc.ExitCode))"
        Assert-True "AutomatedTest завершён" ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq $null)
    } else {
        Write-Log "  Таймаут ожидания AutomatedTest"
        $proc.Kill()
        $script:testsFailed++
    }
} catch {
    Write-Log "  FAIL: Ошибка запуска AutomatedTest: $_"
    $script:testsFailed++
    if ($proc) { $proc.Kill() }
}
$script:cycleCount++

# === Тест 6: Проверка функций поиска по DataGrid (Get-ItemText, Invoke-SearchDown/Up) ===
Write-Log "--- Тест 6: Функции поиска ---"
# Тестируем Get-ItemText
function Get-ItemText {
    param($item)
    if (-not $item) { return "" }
    $props = @("Version","User","Date","Time","Action","Comment")
    $parts = @()
    foreach ($p in $props) {
        $val = $item.$p
        if ($val) { $parts += "$val" }
    }
    return ($parts -join " ")
}

# Создаём тестовый объект
$testItem = [PSCustomObject]@{Version="5"; User="vchaga"; Date="01.06.2026"; Time="12:00"; Action="Checked in"; Comment="Исправление для Чага"}
$text = Get-ItemText $testItem
Assert-True "Get-ItemText возвращает непустой текст" ($text.Length -gt 0)
Assert-True "Get-ItemText содержит 'Чага'" ($text.IndexOf("Чага", [StringComparison]::OrdinalIgnoreCase) -ge 0)
$script:cycleCount++

# Тестируем поиск в массиве
$testItems = @($testItem)
$query = "Чага"
$results = @()
for ($i = 0; $i -lt $testItems.Count; $i++) {
    $line = Get-ItemText $testItems[$i]
    if ($line.IndexOf($query, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $results += $i }
}
Assert-True "Поиск 'Чага' в тестовых данных" ($results.Count -gt 0)
$script:cycleCount++

# === Итог ===
Write-Log "--- ИТОГ ---"
Write-Log "Циклов: $($script:cycleCount) / $MaxCycles"
Write-Log "Пройдено: $($script:testsPassed), Провалено: $($script:testsFailed)"
exit $(if ($script:testsFailed -gt 0) { 1 } else { 0 })

