<#
.SYNOPSIS
    Применение изменений дизайна ко всем UI-элементам указанного тира.
.DESCRIPTION
    ИЗМДИЗАЙН — команда для синхронизации дизайна всех окон проекта.
    Анализирует и/или применяет шаблонные изменения дизайна к окнам
    указанного тира (APPL2, APPL, Standard).

    Параметры дизайна читаются из config/ui_design_registry.json.
.PARAMETER Tier
    Тип дизайна: APPL2, APPL3, APPL, Standard, или ALL (все)
.PARAMETER Action
    ShowReport — показать отчёт о текущем состоянии (по умолчанию)
    ApplyTemplate — применить шаблонные изменения
.PARAMETER Changes
    Путь к JSON-файлу с описанием изменений в формате:
    {
        "APPL2_CornerRadius": "50",
        "APPL_GlossyTop": "#3A6090",
        ...
    }
    Если не указан — используется config/ui_design_registry.json (_meta.design_params)
.PARAMETER ShowAll
    Показать окна всех типов (true) или только указанного (false)
.EXAMPLE
    .\Apply-DesignChanges.ps1 -Tier APPL -Action ShowReport
.EXAMPLE
    .\Apply-DesignChanges.ps1 -Tier ALL -Action ShowReport
.EXAMPLE
    .\Apply-DesignChanges.ps1 -Tier APPL2 -Action ApplyTemplate
#>

param(
    [string]$Tier = "ALL",
    [ValidateSet("ShowReport", "ApplyTemplate")]
    [string]$Action = "ShowReport",
    [string]$Changes = "",
    [switch]$ShowAll
)

$ErrorActionPreference = "Continue"

# ── Helper ──
function Write-Title { param([string]$Text) Write-Host "`n$Text" -ForegroundColor Cyan }
function Write-OK   { param([string]$Text) Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host "  [!] $Text" -ForegroundColor Yellow }
function Write-Info { param([string]$Text) Write-Host "    $Text" -ForegroundColor Gray }

# ── Load registry ──
$registryPath = Join-Path $PSScriptRoot "..\config\ui_design_registry.json"
if (-not (Test-Path $registryPath)) {
    Write-Host "ОШИБКА: Реестр дизайна не найден: $registryPath" -ForegroundColor Red
    Write-Host "Запустите сначала инвентаризацию или создайте файл вручную." -ForegroundColor Yellow
    exit 1
}
$registry = Get-Content $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json

$targetTiers = if ($Tier -eq "ALL") { @("APPL2", "APPL3", "APPL", "Standard") } else { @($Tier) }

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  ИЗМДИЗАЙН - Apply Design Changes" -ForegroundColor Cyan
Write-Host "  Действие: $Action" -ForegroundColor Cyan
Write-Host "  Тиры: $($targetTiers -join ', ')" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# ── Parse changes if provided ──
$changeMap = @{}
if ($Changes -and (Test-Path $Changes)) {
    $changeData = Get-Content $Changes -Raw -Encoding UTF8 | ConvertFrom-Json
    $changeData.PSObject.Properties | ForEach-Object { $changeMap[$_.Name] = "$($_.Value)" }
    Write-OK "Загружены изменения из: $Changes ($($changeMap.Keys.Count) параметров)"
}

if ($Action -eq "ShowReport") {
    # ── REPORT MODE ──
    foreach ($tierName in $targetTiers) {
        $tierInfo = $registry._meta.tiers.$tierName
        Write-Title "=== $tierName ==="
        if ($tierInfo) { Write-Info "$tierInfo" }

        $windows = $registry.$tierName
        if (-not $windows -or $windows.Count -eq 0) {
            Write-Warn "Нет окон в тире $tierName"
            continue
        }

        # Show design params for this tier
        $tierParams = @{}
        $registry._meta.design_params.PSObject.Properties | Where-Object {
            $_.Name -like "${tierName}_*"
        } | ForEach-Object { $tierParams[$_.Name] = "$($_.Value)" }

        if ($tierParams.Keys.Count -gt 0) {
            Write-Host "  Параметры дизайна:" -ForegroundColor Yellow
            foreach ($k in ($tierParams.Keys | Sort-Object)) {
                Write-Info "$k = $($tierParams[$k])"
            }
        }

        Write-Host "  Окна ($($windows.Count)):" -ForegroundColor Yellow
        foreach ($w in $windows) {
            $fn = if ($w.function) { " [$($w.function)]" } else { "" }
            $notes = if ($w.notes) { " ($($w.notes))" } else { "" }
            $scrolls = if ($w.scrollbars) { " | Скроллы: $($w.scrollbars.Count)" } else { " | Скроллы: нет" }
            Write-OK "$($w.name)$fn ($($w.file):$($w.line_start))$notes$scrolls"
        }
    }

    # Summary
    $total = 0
    foreach ($tierName in $targetTiers) {
        $cnt = ($registry.$tierName | Measure-Object).Count
        $total += $cnt
        Write-Host "  ${tierName}: $($cnt) окон" -ForegroundColor Gray
    }
    Write-Host "`n  Всего: $total окон" -ForegroundColor Cyan
}

elseif ($Action -eq "ApplyTemplate") {
    # ── APPLY MODE ──
    Write-Title "=== Применение шаблонных изменений ==="

    $currentParams = @{}
    $registry._meta.design_params.PSObject.Properties | ForEach-Object { $currentParams[$_.Name] = "$($_.Value)" }

    # Build change list: compare current params with requested changes
    $realChanges = @{}
    foreach ($k in $changeMap.Keys) {
        if ($currentParams.ContainsKey($k)) {
            if ($currentParams[$k] -ne $changeMap[$k]) {
                $realChanges[$k] = @{ Old = $currentParams[$k]; New = $changeMap[$k] }
            }
        } else {
            Write-Warn "Неизвестный параметр: $k (нет в registry._meta.design_params)"
        }
    }

    if ($realChanges.Keys.Count -eq 0) {
        Write-Warn "Нет изменений для применения (все параметры совпадают с текущими)"
        Write-Info "Укажите JSON-файл с новыми значениями через -Changes"
        exit 0
    }

    Write-Host "  Будет применено $($realChanges.Keys.Count) изменений:" -ForegroundColor Yellow
    foreach ($k in ($realChanges.Keys | Sort-Object)) {
        Write-Host "    ${k}: $($realChanges[$k]['Old']) -> $($realChanges[$k]['New'])" -ForegroundColor Gray
    }

    # Apply changes to each affected window
    $appliedCount = 0
    $skipCount = 0
    foreach ($tierName in $targetTiers) {
        $windows = $registry.$tierName
        foreach ($w in $windows) {
            $filePath = Join-Path $PSScriptRoot "..\$($w.file)"
            if (-not (Test-Path $filePath)) {
                Write-Warn "Файл не найден: $filePath (пропуск)"
                continue
            }
            $content = Get-Content $filePath -Raw -Encoding UTF8

            # Determine which params apply to this tier
            $tierPrefix = $tierName + "_"
            $relevantChanges = @{}
            foreach ($k in $realChanges.Keys) {
                if ($k -like "${tierPrefix}*") { $relevantChanges[$k] = $realChanges[$k] }
            }

            if ($relevantChanges.Keys.Count -eq 0) { continue }

            $modified = $false
            foreach ($k in $relevantChanges.Keys) {
                $propName = $k.Substring($tierPrefix.Length)
                $oldVal = $relevantChanges[$k].Old
                $newVal = $relevantChanges[$k].New

                # CornerRadius changes
                if ($propName -eq "CornerRadius") {
                    # Search for exact CornerRadius matches within this tier's windows
                    $pattern = 'CornerRadius\s*=\s*' + [regex]::Escape($oldVal)
                    $replacement = "CornerRadius = $newVal"
                    if ($content -match $pattern) {
                        $content = $content -replace $pattern, $replacement
                        $c = [regex]::Matches($content, $pattern).Count
                        Write-Info "  $($w.name): заменено CornerRadius $oldVal -> $newVal (найдено: $c)"
                        $modified = $true
                    }
                }

                # Glossy/Gradient color changes
                if ($propName -match "^(Glossy|Gray|Color)") {
                    $pattern = [regex]::Escape($oldVal)
                    if ($content -match $pattern) {
                        $content = $content -replace $pattern, $newVal
                        $c = [regex]::Matches($content, $pattern).Count
                        Write-Info "  $($w.name): заменён цвет $propName $oldVal -> $newVal (найдено: $c)"
                        $modified = $true
                    }
                }

                # Other numeric/bool params
                if ($propName -match "^(TitleBar|ButtonAlpha)") {
                    $pattern = $propName -replace '([a-z])([A-Z])', '$1[_\s]?$2'
                    if ($content -match $pattern) {
                        $content = $content -replace $pattern, $newVal
                        Write-Info "  $($w.name): заменён $propName -> $newVal"
                        $modified = $true
                    }
                }
            }

            if ($modified) {
                [System.IO.File]::WriteAllText($filePath, $content, [System.Text.Encoding]::UTF8)
                Write-OK "  $($w.name): изменения применены"
                $appliedCount++
            } else {
                $skipCount++
            }
        }
    }

    Write-Host "`n  Применено: $appliedCount окон, пропущено: $skipCount" -ForegroundColor Cyan
    Write-Info "После применения изменений запустите тесты: test_gui_params.ps1"
}

