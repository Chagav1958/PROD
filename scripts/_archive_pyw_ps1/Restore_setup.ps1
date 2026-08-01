param(
    [string]$ConfigName = "opencode.jsonc",
    [switch]$Quiet
)

# Restore_setup.ps1 — восстановление настроек OpenCode из последнего архива
# Запуск: powershell -NoProfile -File scripts\Restore_setup.ps1
# Восстанавливает: opencode.jsonc из последней архивной копии (archives\SNAPSHOT\*)

$projectRoot = Split-Path $PSCommandPath -Parent | Split-Path -Parent
$archiveRoot = Join-Path $projectRoot "archives\SNAPSHOT"
$backupDir = Join-Path $projectRoot "temp\restore_backup"
$configPath = Join-Path $projectRoot $ConfigName

$host.UI.RawUI.ForegroundColor = "White"

# Проверка наличия архивов
if (-not (Test-Path $archiveRoot)) {
    Write-Host "ОШИБКА: Папка архивов не найдена: $archiveRoot" -ForegroundColor Red
    Write-Host "Создайте архив через СОХР (Save-Snapshot.ps1) перед использованием Restore_setup." -ForegroundColor Yellow
    exit 1
}

# Поиск последнего архива
$lastSnapshot = Get-ChildItem $archiveRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1

if (-not $lastSnapshot) {
    Write-Host "ОШИБКА: В $archiveRoot нет ни одного архива." -ForegroundColor Red
    exit 1
}

Write-Host "Последний архив: $($lastSnapshot.Name)" -ForegroundColor Cyan
Write-Host "Дата: $($lastSnapshot.CreationTime)" -ForegroundColor Gray

# Проверяем наличие configName в архиве
$archivedConfig = Join-Path $lastSnapshot.FullName $ConfigName
if (-not (Test-Path $archivedConfig)) {
    Write-Host "ВНИМАНИЕ: $ConfigName не найден в корне архива. Ищу в подпапках..." -ForegroundColor Yellow
    $archivedConfig = Get-ChildItem $lastSnapshot.FullName -Recurse -Filter $ConfigName | Select-Object -First 1 -ExpandProperty FullName
    if (-not $archivedConfig) {
        Write-Host "ОШИБКА: $ConfigName не найден в архиве $($lastSnapshot.Name)" -ForegroundColor Red
        exit 1
    }
    Write-Host "Найден: $archivedConfig" -ForegroundColor Green
}

# Создаём backup текущего (сломанного) конфига
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
$backupStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupFile = Join-Path $backupDir "${ConfigName}_${backupStamp}_broken"

if (Test-Path $configPath) {
    Copy-Item -LiteralPath $configPath -Destination $backupFile -Force
    Write-Host "Создан backup старого конфига: $backupFile" -ForegroundColor Gray
} else {
    Write-Host "Текущий конфиг отсутствует (OpenCode не был настроен)" -ForegroundColor Yellow
}

# Восстанавливаем
try {
    Copy-Item -LiteralPath $archivedConfig -Destination $configPath -Force
    Write-Host "ГОТОВО: $ConfigName восстановлен из $($lastSnapshot.Name)" -ForegroundColor Green
} catch {
    Write-Host "ОШИБКА копирования: $_" -ForegroundColor Red
    exit 1
}

# Также восстанавливаем ключевые файлы, если есть
$extraFiles = @("config\config.json", "config\abbreviations_data.json", "config\report_layout.json")
foreach ($ef in $extraFiles) {
    $efPath = Join-Path $projectRoot $ef
    $efArchived = Join-Path $lastSnapshot.FullName $ef.Replace('\', '/')
    if (-not (Test-Path $efArchived)) {
        $efArchived = Get-ChildItem $lastSnapshot.FullName -Recurse -Filter (Split-Path $ef -Leaf) | Select-Object -First 1 -ExpandProperty FullName
    }
    if ($efArchived -and (Test-Path $efArchived)) {
        $efDir = Split-Path $efPath -Parent
        if (-not (Test-Path $efDir)) { New-Item -ItemType Directory -Path $efDir -Force | Out-Null }
        $efBackup = Join-Path $backupDir "$(Split-Path $ef -Leaf)_${backupStamp}_broken"
        if (Test-Path $efPath) { Copy-Item -LiteralPath $efPath -Destination $efBackup -Force }
        Copy-Item -LiteralPath $efArchived -Destination $efPath -Force
        Write-Host "  Восстановлен: $ef" -ForegroundColor Gray
    }
}

# Проверка результата
if ((Get-Content $configPath -Raw -Encoding UTF8) -match '"model"\s*:\s*"') {
    Write-Host "ПРОВЕРКА: $ConfigName содержит model — файл корректен." -ForegroundColor Green
} else {
    Write-Host "ПРЕДУПРЕЖДЕНИЕ: Восстановленный $ConfigName не содержит model. Проверьте вручную." -ForegroundColor Yellow
}

Write-Host "`nПерезапустите OpenCode для применения восстановленных настроек." -ForegroundColor Cyan
Write-Host "Если OpenCode всё ещё не работает — используйте backup: $backupFile" -ForegroundColor Gray
