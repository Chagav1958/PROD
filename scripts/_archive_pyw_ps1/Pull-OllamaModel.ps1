# Скачивание моделей Ollama — независимо от OpenCode
# Запуск из командной строки: powershell -File Pull-OllamaModel.ps1 -Model "qwen2.5-coder:32b-q3km"
# Или без параметра — покажет список установленных и доступных моделей

param(
    [string]$Model = "",
    [switch]$List
)

[Console]::OutputEncoding = [Text.Encoding]::UTF8

if ($List -or ($Model -eq "")) {
    Write-Host "=== Установленные модели Ollama ===" -ForegroundColor Cyan
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing -TimeoutSec 10
        $tags = ($r.Content | ConvertFrom-Json).models
        $tags | ForEach-Object {
            $sizeGB = [math]::Round($_.size / 1GB, 1)
            Write-Host "  $($_.name.PadRight(45)) ${sizeGB} GB" -ForegroundColor Green
        }
    } catch {
        Write-Host "  Ollama не запущен — запустите приложение Ollama" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Пример: Pull-OllamaModel.ps1 -Model 'qwen2.5-coder:32b-q3km'" -ForegroundColor Gray
    exit 0
}

Write-Host "Скачивание модели: $Model" -ForegroundColor Cyan
Write-Host "Не закрывайте окно. Размер моделей: 1-20 GB. Время: 5-30 минут." -ForegroundColor Yellow
Write-Host ""

$cmd = "ollama pull $Model"
Write-Host ">>> $cmd" -ForegroundColor DarkGray

try {
    Invoke-Expression $cmd
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "Модель $Model успешно скачана." -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "Ошибка при скачивании. Код: $LASTEXITCODE" -ForegroundColor Red
    }
} catch {
    Write-Host "Ошибка: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "Нажмите любую клавишу для выхода..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
