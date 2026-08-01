<#
.SYNOPSIS
  Голосовой ввод промпта через браузер (WebRTC) + faster-whisper
  Запускает локальный HTTP-сервер, открывает браузер, ждёт результат
#>
param(
    [string]$WhisperModelDir = "",
    [switch]$NoClipboard
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $scriptDir "Stells-HideConsole.ps1")
Invoke-StellsHide
$serverScript = Join-Path $scriptDir "voice_server.py"
$port = 8765
$resultFile = Join-Path (Split-Path $scriptDir -Parent) "temp" "voice_result.json"
$logFile = Join-Path $env:TEMP "voice_server.log"

# Удалить старый результат
if (Test-Path $resultFile) { Remove-Item $resultFile -Force }

# Запуск сервера
$env:WHISPER_MODEL_DIR = if ($WhisperModelDir) { $WhisperModelDir } else { "" }
$serverProc = Start-Process -FilePath "python" -ArgumentList $serverScript, $port -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 3

if ($serverProc.HasExited) {
    Write-Host "Ошибка: сервер не запустился" -ForegroundColor Red
    return
}

# Открыть браузер
Start-Process "http://localhost:$port"

Write-Host "`n=== ГОЛОСОВОЙ ВВОД ===" -ForegroundColor Cyan
Write-Host " 1. Браузер открыт на http://localhost:$port" -ForegroundColor Yellow
Write-Host " 2. Нажмите 'Запись' -> говорите -> 'Стоп'" -ForegroundColor Yellow
Write-Host " 3. Когда текст появится на странице - нажмите Enter здесь" -ForegroundColor Yellow
Write-Host " 4. Esc в браузере - отмена`n" -ForegroundColor Yellow

$null = [System.Console]::ReadLine()

# Остановка сервера
if (-not $serverProc.HasExited) { $serverProc.Kill() }

[Console]::OutputEncoding = [Text.Encoding]::UTF8

# Чтение результата
if (Test-Path $resultFile) {
    try {
        $result = Get-Content $resultFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($result.text) {
            Write-Host "`nРезультат:" -ForegroundColor Green
            Write-Host "$($result.text)" -ForegroundColor White
            if (-not $NoClipboard) {
                try {
                    $result.text | Set-Clipboard -ErrorAction Stop
                    Write-Host "`n(скопирован в буфер обмена)" -ForegroundColor Gray
                } catch {
                    Write-Host "`n(не удалось скопировать в буфер обмена)" -ForegroundColor Gray
                }
            }
        } elseif ($result.silence) {
            Write-Host "Тишина - ничего не сказано" -ForegroundColor Red
        } elseif ($result.error) {
            Write-Host "Ошибка: $($result.error)" -ForegroundColor Red
        }
    } catch {
        Write-Host "Ошибка чтения результата: $_" -ForegroundColor Red
    }
} else {
    Write-Host "Результат не получен" -ForegroundColor Red
}
