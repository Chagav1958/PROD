<#
.SYNOPSIS
    Инициализация портативного проекта AIS Release Preparation
.DESCRIPTION
    Скрипт устанавливает пути относительно корневой папки проекта
    и проверяет наличие необходимых компонентов.
.EXAMPLE
    .\Initialize-Project.ps1
#>

param(
    [switch]$SkipChecks
)

$ErrorActionPreference = "Stop"

# Определяем корневую папку проекта (с fallback для .bat-лаунчеров)
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot }
              elseif ($MyInvocation.MyCommand.Path) { Split-Path $MyInvocation.MyCommand.Path -Parent }
              else { (Get-Location).Path }
$ProjectRoot = if ($scriptRoot -match '[\\/]scripts$') { Split-Path $scriptRoot -Parent } else { $scriptRoot }
if (-not $ProjectRoot) { $ProjectRoot = 'C:\AIS\AI\Prod' }
Write-Host "Корень проекта: $ProjectRoot" -ForegroundColor Cyan

# Загружаем конфигурацию
$configPath = Join-Path $ProjectRoot "config\config.json"
if (-not (Test-Path $configPath)) {
    throw "Файл конфигурации не найден: $configPath"
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json

# Функция для разрешения относительных путей
function Resolve-RelativePath {
    param([string]$Path)
    
    if ($Path.StartsWith(".\")) {
        return Join-Path $ProjectRoot $Path.Substring(2)
    }
    return $Path
}

# Разрешаем все пути в конфигурации
Write-Host "Разрешение путей..." -ForegroundColor Yellow

$resolvedPaths = @{}
foreach ($prop in $config.paths.PSObject.Properties) {
    $resolvedPaths[$prop.Name] = Resolve-RelativePath $prop.Value
}

# Обновляем объект конфигурации
foreach ($key in $resolvedPaths.Keys) {
    $config.paths.$key = $resolvedPaths[$key]
}

# Сохраняем обновленную конфигурацию
$config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
Write-Host "Конфигурация обновлена с абсолютными путями" -ForegroundColor Green

# Проверка компонентов
if (-not $SkipChecks) {
    Write-Host "Проверка зависимостей..." -ForegroundColor Yellow
    
    $checks = @(
        @{ Name = "PowerShell 5.1+"; Test = { $PSVersionTable.PSVersion.Major -ge 5 } },
        @{ Name = "Sybase isql"; Test = { Get-Command isql -ErrorAction SilentlyContinue } },
        @{ Name = "Google Chrome"; Test = { Test-Path "C:\Program Files\Google\Chrome\Application\chrome.exe" } },
        @{ Name = "TortoiseMerge"; Test = { Test-Path $config.paths.tortoise_merge } }
    )
    
    foreach ($check in $checks) {
        try {
            $result = & $check.Test
            if ($result) {
                Write-Host "  [ЕСТЬ] $($check.Name)" -ForegroundColor Green
            } else {
                Write-Host "  [НЕТ] $($check.Name)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [НЕТ] $($check.Name)" -ForegroundColor Yellow
        }
    }
}

# Создаем необходимые папки
Write-Host "Создание каталогов..." -ForegroundColor Yellow

$dirs = @(
    "BD",
    "PB_Current",
    "PB_Main",
    "reports\logs",
    "tools"
)

foreach ($dir in $dirs) {
    $path = Join-Path $ProjectRoot $dir
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Write-Host "  Создан: $dir" -ForegroundColor Green
    } else {
        Write-Host "  Существует: $dir" -ForegroundColor Gray
    }
}

Write-Host "Инициализация завершена!" -ForegroundColor Green
Write-Host "Теперь можно запустить: .\bin\Prod-GUI.bat" -ForegroundColor Cyan
