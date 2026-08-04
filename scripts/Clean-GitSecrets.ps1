# Clean-GitSecrets.ps1 — удаление секретов из GitHub-истории, локальные файлы остаются
# Требуется: Python + git-filter-repo (pip install git-filter-repo)

param(
    [switch]$DryRun,        # Только показать что будет удалено, без push
    [switch]$Force           # Пропустить подтверждение
)

$ErrorActionPreference = "Stop"
$RepoPath = "C:\AIS\AI\Prod"
$TempClone = "$RepoPath`_clean"
$GitHubRemote = "origin"

# Файлы для удаления из всей истории GitHub
$SensitiveFiles = @(
    "config/config.json",
    "config/settings_history.json",
    "config/oc-config-manager.json",
    "scripts/ais_catalog_mcp/knowledge.db",
    "scripts/opencode_mcp/knowledge.db",
    "scripts/ais_objects_mcp/objects.db"
)

Write-Host "=== ЧИСТКА СЕКРЕТОВ ИЗ GITHUB-ИСТОРИИ ===" -ForegroundColor Yellow
Write-Host "Локальные файлы останутся на диске, удаляются только из git-истории." -ForegroundColor Yellow
Write-Host ""

# Проверка git-filter-repo
$filt = Get-Command git-filter-repo -ErrorAction SilentlyContinue
if (-not $filt) {
    Write-Host "ОШИБКА: git-filter-repo не установлен." -ForegroundColor Red
    Write-Host "Установи: pip install git-filter-repo" -ForegroundColor Red
    Write-Host "Или: python -m pip install git-filter-repo" -ForegroundColor Red
    exit 1
}

# Проверка, что мы не в temp-клоне
$currentDir = (Get-Location).Path
if ($currentDir -eq $TempClone) {
    Write-Host "ОШИБКА: скрипт запущен из временного клона. Запусти из $RepoPath" -ForegroundColor Red
    exit 1
}

# Подтверждение (кроме --Force)
if (-not $Force -and -not $DryRun) {
    Write-Host "Будут удалены из ВСЕЙ истории (всех коммитов):" -ForegroundColor Red
    foreach ($f in $SensitiveFiles) { Write-Host "  - $f" -ForegroundColor Red }
    Write-Host ""
    Write-Host "ВАЖНО: после push ВСЕ пароли/токены, бывшие в истории, нужно СМЕНИТЬ!" -ForegroundColor Red
    Write-Host ""
    $confirm = Read-Host "Продолжить? (ДА/нет)"
    if ($confirm -ne "ДА") {
        Write-Host "Отмена." -ForegroundColor Yellow
        exit 0
    }
}

# Шаг 1: удалить старый temp-клон если есть
if (Test-Path $TempClone) {
    Write-Host "Удаляю старый клон $TempClone ..." -ForegroundColor Gray
    Remove-Item -Recurse -Force $TempClone
}

# Шаг 2: клонировать
Write-Host "Клонирую $RepoPath -> $TempClone ..." -ForegroundColor Cyan
git clone --no-local $RepoPath $TempClone 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ОШИБКА клонирования" -ForegroundColor Red
    exit 1
}

Push-Location $TempClone

try {
    # Шаг 3: фильтрация
    $pathArgs = @()
    foreach ($f in $SensitiveFiles) {
        $pathArgs += "--path"
        $pathArgs += $f
    }

    Write-Host "Запускаю git-filter-repo (удаление файлов из истории)..." -ForegroundColor Cyan
    git filter-repo --invert-paths @pathArgs --force 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ОШИБКА filter-repo" -ForegroundColor Red
        exit 1
    }
    Write-Host "История очищена." -ForegroundColor Green

    if ($DryRun) {
        Write-Host "" -ForegroundColor Yellow
        Write-Host "DRY-RUN: проверь историю в $TempClone" -ForegroundColor Yellow
        Write-Host "  cd $TempClone" -ForegroundColor Yellow
        Write-Host "  git log --all --oneline -- config/config.json  (должно быть пусто)" -ForegroundColor Yellow
        Write-Host "Для реальной очистки запусти без -DryRun" -ForegroundColor Yellow
        exit 0
    }

    # Шаг 4: проверить remote
    Write-Host ""
    Write-Host "Текущие remote:" -ForegroundColor Cyan
    git remote -v 2>&1

    Write-Host ""
    Write-Host "=== СЛЕДУЮЩИЙ ШАГ — ВЫПОЛНИ ВРУЧНУЮ ===" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Добавь remote к GitHub (если нет):" -ForegroundColor White
    Write-Host "   cd $TempClone" -ForegroundColor White
    Write-Host "   git remote add origin <url>" -ForegroundColor White
    Write-Host ""
    Write-Host "2. Force push в GitHub:" -ForegroundColor White
    Write-Host "   git push --force --all origin" -ForegroundColor White
    Write-Host "   git push --force --tags origin" -ForegroundColor White
    Write-Host ""
    Write-Host "3. Вернись в исходный репозиторий и синхронизируй:" -ForegroundColor White
    Write-Host "   cd $RepoPath" -ForegroundColor White
    Write-Host "   git fetch origin" -ForegroundColor White
    Write-Host "   git reset --mixed origin/main   (файлы на диске останутся)" -ForegroundColor White
    Write-Host ""
    Write-Host "4. Проверь, что чувствительные файлы на месте (на диске):" -ForegroundColor White
    Write-Host "   dir config\config.json" -ForegroundColor White
    Write-Host ""
    Write-Host "5. СМЕНИ ВСЕ пароли и токены, которые были в истории!" -ForegroundColor Red
}
finally {
    Pop-Location
}
