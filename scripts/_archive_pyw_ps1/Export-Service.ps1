<#
.SYNOPSIS
    Экспорт проекта AIS с заменой конфиденциальных данных.
.DESCRIPTION
    Копирует файлы из SourcePath в DestPath, исключая архивы, журналы, копии объектов.
    Выгружаются: функционал (bin, scripts), настройки (config), документация (docs),
    файлы-правил (rules, .opencode, AGENTS.md).
    В неисполняемых файлах заменяет логины, пароли и токены на заглушки.
.PARAMETER SourcePath
    Путь к исходной папке проекта
.PARAMETER DestPath
    Путь к папке назначения
.PARAMETER ConfigPath
    Путь к config.json
.PARAMETER Force
    Без подтверждения
.EXAMPLE
    .\Export-Service.ps1 -SourcePath C:\AIS\AI\Prod -DestPath Z:\AI\Prod
#>

param(
    [string]$SourcePath,
    [string]$DestPath,
    [string]$ConfigPath = "C:\AIS\AI\Prod\config\config.json",
    [switch]$Force
)

$ErrorActionPreference = "Continue"

Write-Host "=== Export Service: выгрузка проекта ===" -ForegroundColor Cyan
Write-Host "Источник: $SourcePath" -ForegroundColor Cyan
Write-Host "Назначение: $DestPath" -ForegroundColor Cyan
Write-Host ""

# Проверка путей
if (-not (Test-Path $SourcePath)) { throw "Папка источника не найдена: $SourcePath" }
if (-not (Test-Path $DestPath)) {
    Write-Host "Папка назначения не существует. Создаю..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $DestPath -Force | Out-Null
}

# Исключаемые папки (архивы, журналы, копии объектов, модели, кеши)
$excludeFolders = @("BD", "PB_Current", "PB_Main", "archives", "temp", "reports",
    "Log", "Test Output", "ttemp", "ReadyMerged", "__pycache__",
    "models", "Old", "SNAPSHOT")

# Запрос подтверждения
if (-not $Force) {
    $answer = Read-Host "Скопировать '$SourcePath' в '$DestPath' (исключая $($excludeFolders -join ', '))? (д/Н)"
    if ($answer -ne "д" -and $answer -ne "Д" -and $answer -ne "y" -and $answer -ne "Y") {
        Write-Host "Отменено." -ForegroundColor Yellow
        exit 0
    }
}

# ── Шаг 1: Сбор известных учётных данных для замены ──
Write-Host "Сбор учётных данных для замены..." -ForegroundColor Yellow

$replacements = @{}
if (Test-Path $ConfigPath) {
    try {
        $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        
        if ($config.vss.user)           { $replacements[$config.vss.user] = "Логин" }
        if ($config.vss.db_path)        { $replacements[$config.vss.db_path] = "\\\\server\\VSS\\srcsafe.ini" }
        if ($config.jira.jira_email)    { $replacements[$config.jira.jira_email] = "Логин" }
        if ($config.jira.base_url)      { $replacements[$config.jira.base_url] = "https://jira.company.com" }
        
        # Расшифровка паролей/токенов
        try {
            $settingsModule = Join-Path (Split-Path $ConfigPath -Parent) "Settings-Module.ps1"
            if (Test-Path $settingsModule) {
                . $settingsModule
                $masterKey = Get-MasterKey -ConfigPath $ConfigPath
                if ($masterKey) {
                    if ($config.vss.password_encrypted) {
                        $plain = Decrypt-Password -Encrypted $config.vss.password_encrypted -Key $masterKey
                        if ($plain) { $replacements[$plain] = "Пароль" }
                    }
                    if ($config.jira.api_token_encrypted) {
                        $plain = Decrypt-Password -Encrypted $config.jira.api_token_encrypted -Key $masterKey
                        if ($plain) { $replacements[$plain] = "Токен" }
                    } elseif ($config.jira.token_encrypted) {
                        $plain = Decrypt-Password -Encrypted $config.jira.token_encrypted -Key $masterKey
                        if ($plain) { $replacements[$plain] = "Токен" }
                    }
                }
            }
        } catch {
            Write-Host "  (не удалось расшифровать пароли: $($_.Exception.Message))" -ForegroundColor DarkYellow
        }
    } catch {
        Write-Host "  (не удалось прочитать config.json: $($_.Exception.Message))" -ForegroundColor DarkYellow
    }
}

# Сортируем ключи по длине (убывание) — чтобы длинные заменялись раньше коротких
$sortedKeys = $replacements.Keys | Sort-Object { $_.Length } -Descending
Write-Host "Найдено значений для замены: $($sortedKeys.Count)" -ForegroundColor Gray
foreach ($k in $sortedKeys) {
    $v = $replacements[$k]
    $display = if ($k.Length -gt 20) { $k.Substring(0, 10) + "..." + $k.Substring($k.Length - 5) } else { $k }
    Write-Host "  '$display' -> $v" -ForegroundColor Gray
}

# ── Шаг 2: Копирование файлов ──
Write-Host ""
Write-Host "Копирование файлов..." -ForegroundColor Yellow

$robocopyArgs = @(
    "`"$SourcePath`"", "`"$DestPath`"", "/E", "/COPY:DAT", "/R:1", "/W:1",
    "/XD"
)
foreach ($ex in $excludeFolders) { $robocopyArgs += $ex }
$robocopyArgs += @("/NDL", "/NJH", "/NJS")

& "robocopy.exe" $robocopyArgs
$robocopyExit = $LASTEXITCODE

if ($robocopyExit -ge 8) {
    Write-Host "Ошибка копирования (robocopy exit: $robocopyExit)" -ForegroundColor Red
} else {
    Write-Host "Копирование завершено (robocopy exit: $robocopyExit)" -ForegroundColor Green
}

# ── Шаг 3: Сантайзинг файлов ──
Write-Host ""
Write-Host "Сантайзинг конфиденциальных данных..." -ForegroundColor Yellow

$execExtensions = @(".ps1", ".psm1", ".psd1", ".bat", ".cmd", ".exe", ".com", ".dll")
$sanitizedCount = 0
$skippedCount = 0

Get-ChildItem $DestPath -Recurse -File | ForEach-Object {
    $ext = $_.Extension.ToLower()
    if ($ext -in $execExtensions) {
        $skippedCount++
        return
    }
    
    # Пропускаем бинарные файлы (изображения, бинарные форматы)
    $binaryExts = @(".png", ".jpg", ".jpeg", ".gif", ".bmp", ".ico", ".pdf", ".zip", ".7z", ".rar")
    if ($ext -in $binaryExts) {
        $skippedCount++
        return
    }
    
    $filePath = $_.FullName
    try {
        $content = Get-Content $filePath -Raw -Encoding UTF8
        if (-not $content) { $skippedCount++; return }
        
        $modified = $false
        foreach ($key in $sortedKeys) {
            if ($content -match [regex]::Escape($key)) {
                $content = $content -replace [regex]::Escape($key), $replacements[$key]
                $modified = $true
            }
        }
        
        if ($modified) {
            # Сохраняем с BOM для .ps1 и .json, UTF8 для остальных
            if ($ext -eq ".json" -or $ext -eq ".ps1") {
                Set-Content -Path $filePath -Value $content -Encoding UTF8
            } else {
                [System.IO.File]::WriteAllText($filePath, $content, [System.Text.Encoding]::UTF8)
            }
            $sanitizedCount++
        } else {
            $skippedCount++
        }
    } catch {
        Write-Host "  Ошибка обработки $filePath : $($_.Exception.Message)" -ForegroundColor DarkYellow
        $skippedCount++
    }
}

# ── Шаг 4: Очистка config.json в целевой папке ──
Write-Host ""
Write-Host "Очистка config.json..." -ForegroundColor Yellow
$destConfig = Join-Path $DestPath "config\config.json"
if (Test-Path $destConfig) {
    try {
        $cfg = Get-Content $destConfig -Raw -Encoding UTF8 | ConvertFrom-Json
        $cfg.jira.jira_email = "Логин"
        $cfg.jira.api_token_encrypted = ""
        $cfg.jira.token_encrypted = ""
        $cfg.vss.user = "Логин"
        $cfg.vss.password_encrypted = ""
        $cfg.vss.db_path = "\\\\server\\VSS\\srcsafe.ini"
        $cfg.jira.base_url = "https://jira.company.com"
        $cfgJson = $cfg | ConvertTo-Json -Depth 10
        Set-Content -Path $destConfig -Value $cfgJson -Encoding UTF8
        Write-Host "  config.json очищен" -ForegroundColor Green
    } catch {
        Write-Host "  Ошибка очистки config.json: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ── Шаг 5: Очистка AGENTS.md в целевой папке ──
$destAgents = Join-Path $DestPath "AGENTS.md"
if (Test-Path $destAgents) {
    try {
        $agentsContent = Get-Content $destAgents -Raw -Encoding UTF8
        # Применяем общие замены
        foreach ($key in $sortedKeys) {
            $agentsContent = $agentsContent -replace [regex]::Escape($key), $replacements[$key]
        }
        Set-Content -Path $destAgents -Value $agentsContent -Encoding UTF8
        Write-Host "  AGENTS.md очищен" -ForegroundColor Green
    } catch {
        Write-Host "  Ошибка очистки AGENTS.md: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Итог
Write-Host ""
Write-Host "=== Экспорт завершён ===" -ForegroundColor Green
Write-Host "  Сантайзировано файлов: $sanitizedCount"
Write-Host "  Пропущено (исполняемые/бинарные/без совпадений): $skippedCount"
Write-Host "Источник: $SourcePath"
Write-Host "Назначение: $DestPath"
exit 0

