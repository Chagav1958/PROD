<#
.SYNOPSIS
  Восстановление конфигов OpenCode из последнего снапшота.
  Для ярлыка на рабочем столе: кликнуть — восстановить.
.PARAMETER Date
  Дата/время снапшота в формате "20260717_130000".
  Если не указан — восстанавливается последний снапшот.
.EXAMPLE
  .\Restore-OpenCode.ps1
  .\Restore-OpenCode.ps1 -Date "20260717_130000"
#>

param(
    [string]$Date = ''
)

$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$projectRoot = Split-Path $scriptRoot -Parent
$archiveRoot = Join-Path $projectRoot 'archives\OpenCode'

# ============================================================
# ФУНКЦИИ
# ============================================================

function Get-FileTags {
    return @(
        @{ Prefix = 'GLOBAL_'; Target = Join-Path $env:USERPROFILE '.config\opencode\opencode.jsonc' }
        @{ Prefix = 'PROD_';   Target = Join-Path $projectRoot 'opencode.jsonc' }
    )
}

function Write-Msg {
    param([string]$Message, [string]$Color = 'White')
    Write-Host "[OC-Restore] $Message" -ForegroundColor $Color
}

# ============================================================
# ОСНОВНАЯ ЛОГИКА
# ============================================================

Write-Msg "Поиск снапшотов..." 'Cyan'

if (-not (Test-Path $archiveRoot)) {
    Write-Msg "Архив не найден: $archiveRoot" 'Red'
    Write-Host "Нажмите любую клавишу для выхода..."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}

$snapshots = Get-ChildItem $archiveRoot -Directory -Filter 'Snapshot_*' | Sort-Object Name -Descending

if ($snapshots.Count -eq 0) {
    Write-Msg "Нет снапшотов для восстановления" 'Yellow'
    Write-Host "Нажмите любую клавишу для выхода..."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}

$target = $null
if ($Date) {
    $target = $snapshots | Where-Object { $_.Name -like "*$Date*" } | Select-Object -First 1
    if (-not $target) {
        Write-Msg "Снапшот с датой '$Date' не найден" 'Red'
        Write-Host "Нажмите любую клавишу для выхода..."
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        exit 1
    }
} else {
    $target = $snapshots | Select-Object -First 1
}

Write-Msg "Снапшот: $($target.Name)" 'Green'

# --- Backup текущего состояния ---
$backupDir = Join-Path $archiveRoot "Auto_before_restore_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

$tags = Get-FileTags
foreach ($tag in $tags) {
    if (Test-Path $tag.Target) {
        $backupFile = Join-Path $backupDir "$($tag.Prefix)$(Split-Path $tag.Target -Leaf)"
        Copy-Item $tag.Target $backupFile -Force
    }
}

Write-Msg "Backup текущего состояния: $backupDir" 'Gray'

# --- Восстановление ---
$restored = 0
foreach ($tag in $tags) {
    $snapFiles = Get-ChildItem $target.FullName -File | Where-Object { $_.Name.StartsWith($tag.Prefix) }
    foreach ($snapFile in $snapFiles) {
        Copy-Item $snapFile.FullName $tag.Target -Force
        Write-Msg "Восстановлен: $($tag.Target)" 'Green'
        $restored++
    }
}

if ($restored -eq 0) {
    Write-Msg "Не найдено файлов для восстановления в снапшоте" 'Yellow'
} else {
    Write-Msg "Восстановлено: $restored файлов" 'Green'
}

# --- Проверка ---
Write-Msg "Проверка восстановленных файлов..." 'Cyan'
$hasError = $false
foreach ($tag in $tags) {
    if (Test-Path $tag.Target) {
        $content = Get-Content $tag.Target -Raw -Encoding UTF8
        try {
            $null = $content | ConvertFrom-Json -ErrorAction Stop
            Write-Msg "  $($tag.Target) — JSON OK" 'Green'
        } catch {
            Write-Msg "  $($tag.Target) — JSON ОШИБКА: $($_.Exception.Message)" 'Red'
            $hasError = $true
        }
    }
}

if ($hasError) {
    Write-Msg "Обнаружены ошибки! Проверьте логи." 'Red'
} else {
    Write-Msg "Восстановление завершено успешно. Перезапустите OpenCode." 'Green'
}

Write-Host ""
Write-Host "Нажмите любую клавишу для выхода..."
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
