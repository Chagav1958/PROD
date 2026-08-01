<#
.SYNOPSIS
    Резервное копирование настроек OpenCode
.DESCRIPTION
    Создаёт архив с полными настройками OpenCode:
    - opencode.jsonc
    - .opencode\ (все файлы: правила, команды, плагины, mdc)
    - temp\user_prompts.log (история промптов)
    - archives\prompts\ (архив промптов)
#>

$projectRoot = "C:\AIS\AI\Prod"
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$backupDir = Join-Path $projectRoot "archives\opencode_backup\backup_$timestamp"

if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
}

Write-Host "=== Резервное копирование OpenCode ==="
Write-Host "Дата: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')"
Write-Host "Папка: $backupDir"
Write-Host ""

$src = Join-Path $projectRoot "opencode.jsonc"
$dst = Join-Path $backupDir "opencode.jsonc"
if (Test-Path $src) {
    Copy-Item $src $dst -Force
    Write-Host "[OK] opencode.jsonc"
}

$src = Join-Path $projectRoot ".opencode"
$dst = Join-Path $backupDir ".opencode"
if (Test-Path $src) {
    Copy-Item $src $dst -Recurse -Force
    Write-Host "[OK] .opencode (vse fayly)"
}

$src = Join-Path $projectRoot "temp\user_prompts.log"
$dst = Join-Path $backupDir "user_prompts.log"
if (Test-Path $src) {
    Copy-Item $src $dst -Force
    Write-Host "[OK] temp\user_prompts.log"
}

$src = Join-Path $projectRoot "archives\prompts"
$dst = Join-Path $backupDir "prompts_archive"
if (Test-Path $src) {
    Copy-Item $src $dst -Recurse -Force
    Write-Host "[OK] archives\prompts"
}

$zipPath = Join-Path $projectRoot "archives\opencode_backup\opencode_backup_$timestamp.zip"
Write-Host ""
Write-Host "Создание ZIP-архива..."
Compress-Archive -Path $backupDir -DestinationPath $zipPath -Force

Remove-Item $backupDir -Recurse -Force

Write-Host ""
Write-Host "=== Готово ==="
Write-Host "Архив: $zipPath"
Write-Host ""
Write-Host "Для восстановления:"
Write-Host "1. Распаковать архив в папку проекта"
Write-Host "2. Запустить scripts\Restore-OpenCode.ps1 с путём к архиву"
