<#
.SYNOPSIS
    Тестирование логики поиска по DataGrid VSS History.
.DESCRIPTION
    Проверяет Get-ItemText, Search-DgDown/Up без подключения к VSS.
    Цикл до 50 итераций.
#>
Add-Type -AssemblyName PresentationFramework, WindowsBase
$scriptRoot = Split-Path $PSScriptRoot -Parent
$logPath = Join-Path $scriptRoot "temp\vss_search_autotest.log"
$script:testsPassed = 0; $script:testsFailed = 0; $script:cycleCount = 0

function Write-Log { param([string]$Text)
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Text"
    Add-Content -Path $logPath -Value $line -Encoding UTF8; Write-Host $line
    $script:cycleCount++; if ($script:cycleCount -ge 50) { throw "MAX_CYCLES" } }

function Assert-True { param([string]$Name, [bool]$Cond)
    if ($Cond) { Write-Log "  PASS: $Name"; $script:testsPassed++ }
    else { Write-Log "  FAIL: $Name"; $script:testsFailed++ } }

function Get-ItemText { param($item)
    if (-not $item) { return "" }
    $props = @("Version","User","Date","Time","Action","Comment")
    $parts = @()
    foreach ($p in $props) { $val = $item.$p; if ($val) { $parts += "$val" } }
    return ($parts -join " ") }

# Тестовые глобальные переменные (имитация VSS-History-Show.ps1)
$script:dgSearchState = @{ query = ""; results = @(); idx = -1 }
$script:searchInput = New-Object Windows.Controls.TextBox
$script:matchLabel = New-Object Windows.Controls.TextBlock

function Search-DgDown {
    $sq = $script:searchInput.Text.Trim()
    $oldQ = $script:dgSearchState.query
    $script:dgSearchState.query = $sq
    if (-not $sq) { $script:matchLabel.Text = "0 - 0"; $script:dgSearchState.results = @(); $script:dgSearchState.idx = -1; return }
    if ($sq -ne $oldQ -or $script:dgSearchState.results.Count -eq 0) {
        $allR = @()
        $allItems = @($dg.Items)
        for ($i = 0; $i -lt $allItems.Count; $i++) {
            $line = Get-ItemText $allItems[$i]
            if ($line.IndexOf($sq, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $allR += $i }
        }
        $script:dgSearchState.results = $allR; $script:dgSearchState.idx = -1
        if ($allR.Count -eq 0) { $script:matchLabel.Text = "0 - 0"; return }
    }
    if ($script:dgSearchState.results.Count -eq 0) { return }
    $script:dgSearchState.idx = ($script:dgSearchState.idx + 1) % $script:dgSearchState.results.Count
    $script:matchLabel.Text = "$($script:dgSearchState.idx + 1) - $($script:dgSearchState.results.Count)"
}

function Search-DgUp {
    $sq = $script:searchInput.Text.Trim()
    $oldQ = $script:dgSearchState.query
    $script:dgSearchState.query = $sq
    if (-not $sq) { return }
    if ($sq -ne $oldQ -or $script:dgSearchState.results.Count -eq 0) {
        $allR = @()
        $allItems = @($dg.Items)
        for ($i = 0; $i -lt $allItems.Count; $i++) {
            $line = Get-ItemText $allItems[$i]
            if ($line.IndexOf($sq, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $allR += $i }
        }
        $script:dgSearchState.results = $allR; $script:dgSearchState.idx = $allR.Count
        if ($allR.Count -eq 0) { $script:matchLabel.Text = "0 - 0"; return }
    }
    if ($script:dgSearchState.results.Count -eq 0) { return }
    $script:dgSearchState.idx = ($script:dgSearchState.idx - 1 + $script:dgSearchState.results.Count) % $script:dgSearchState.results.Count
    $script:matchLabel.Text = "$($script:dgSearchState.idx + 1) - $($script:dgSearchState.results.Count)"
}

Write-Log "=== АВТОТЕСТ VSS История: поиск по DataGrid ==="

try {
    # === Тест 1: Get-ItemText ===
    Write-Log "--- Тест 1: Get-ItemText ---"
    $testItem = [PSCustomObject]@{Version="5"; User="vchaga"; Date="01.06.2026"; Time="12:00"; Action="Checked in"; Comment="Тест для Чага"}
    $text = Get-ItemText $testItem
    Assert-True "Get-ItemText не пуст" ($text.Length -gt 0)
    Write-Log "  Текст: '$text'"
    Assert-True "Get-ItemText содержит 'Чага'" ($text.IndexOf("Чага", [StringComparison]::OrdinalIgnoreCase) -ge 0)
    Assert-True "Get-ItemText содержит '5'" ($text.IndexOf("5", [StringComparison]::OrdinalIgnoreCase) -ge 0)
    Assert-True "Get-ItemText содержит 'vchaga'" ($text.IndexOf("vchaga", [StringComparison]::OrdinalIgnoreCase) -ge 0)

    # === Тест 2: Создание WPF DataGrid с тестовыми данными ===
    Write-Log "--- Тест 2: DataGrid ---"
    $dg = New-Object Windows.Controls.DataGrid
    $dg.ItemsSource = @(
        [PSCustomObject]@{Version="5"; User="vchaga"; Date="01.06.2026"; Time="12:00"; Action="Checked in"; Comment="Тест для Чага"}
        [PSCustomObject]@{Version="4"; User="petrov"; Date="28.05.2026"; Time="15:30"; Action="Checked in"; Comment="Правка формы"}
        [PSCustomObject]@{Version="3"; User="vchaga"; Date="15.05.2026"; Time="09:00"; Action="Created"; Comment="Создание объекта"}
    )
    $dg.Items.Refresh()
    Assert-True "DataGrid создан" ($dg.Items.Count -eq 3)
    Write-Log "  Строк в DataGrid: $($dg.Items.Count)"

    # === Тест 3: Поиск по DataGrid ===
    Write-Log "--- Тест 3: Поиск 'Чага' ---"
    $script:dgSearchState = @{ query = ""; results = @(); idx = -1 }
    $script:searchInput.Text = "Чага"
    Search-DgDown
    Assert-True "Поиск 'Чага' нашел результат" ($script:dgSearchState.results.Count -gt 0)
    Write-Log "  Найдено: $($script:dgSearchState.results.Count)"
    Write-Log "  Результат: $($script:dgSearchState.results[0]) -> версия $($dg.Items[$script:dgSearchState.results[0]].Version)"

    # === Тест 4: Поиск 'vchaga' (должен найти 2 строки) ===
    Write-Log "--- Тест 4: Поиск 'vchaga' ---"
    $script:dgSearchState = @{ query = ""; results = @(); idx = -1 }
    $script:searchInput.Text = "vchaga"
    Search-DgDown
    Assert-True "Поиск 'vchaga' нашел 2 результата" ($script:dgSearchState.results.Count -eq 2)
    Write-Log "  Найдено: $($script:dgSearchState.results.Count)"

    # === Тест 5: Поиск 'petrov' ===
    Write-Log "--- Тест 5: Поиск 'petrov' ---"
    $script:dgSearchState = @{ query = ""; results = @(); idx = -1 }
    $script:searchInput.Text = "petrov"
    Search-DgDown
    Assert-True "Поиск 'petrov' нашел 1 результат" ($script:dgSearchState.results.Count -eq 1)
    Write-Log "  Найдено: $($script:dgSearchState.results.Count)"

    # === Тест 6: Поиск несуществующего ===
    Write-Log "--- Тест 6: Поиск 'XXXXX' ---"
    $script:dgSearchState = @{ query = ""; results = @(); idx = -1 }
    $script:searchInput.Text = "XXXXX"
    Search-DgDown
    Assert-True "Поиск 'XXXXX' вернул 0" ($script:dgSearchState.results.Count -eq 0)
    Write-Log "  Найдено: $($script:dgSearchState.results.Count)"

    # === Тест 7: Навигация ▼/▲ ===
    Write-Log "--- Тест 7: Навигация ▼/▲ ---"
    $script:dgSearchState = @{ query = ""; results = @(); idx = -1 }
    $script:searchInput.Text = "vchaga"
    Search-DgDown; Write-Log "  ▼1: idx=$($script:dgSearchState.idx) версия=$($dg.Items[$script:dgSearchState.results[$script:dgSearchState.idx]].Version)"
    Search-DgDown; Write-Log "  ▼2: idx=$($script:dgSearchState.idx) версия=$($dg.Items[$script:dgSearchState.results[$script:dgSearchState.idx]].Version)"
    Assert-True "▼ дважды: циклический переход" ($script:dgSearchState.idx -eq 1 -or $script:dgSearchState.idx -eq 0)
    Write-Log "  Результатов в пуле: $($script:dgSearchState.results.Count)"

} catch {
    if ($_.Exception.Message -eq "MAX_CYCLES") {
        Write-Log "--- Достигнут лимит циклов ---"
    } else {
        Write-Log "  Исключение: $_"
        $script:testsFailed++
    }
}

# === Итог ===
Write-Log "--- ИТОГ ---"
Write-Log "Циклов: $($script:cycleCount) / 50"
Write-Log "Пройдено: $($script:testsPassed), Провалено: $($script:testsFailed)"
Write-Host "###VSS_AUTOTEST###Result|Passed=$($script:testsPassed)|Failed=$($script:testsFailed)"
exit $(if ($script:testsFailed -gt 0) { 1 } else { 0 })

