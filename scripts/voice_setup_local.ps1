<#
.SYNOPSIS
  Установка голосового ввода на ЛОКАЛЬНОМ ПК (без админа)
  Копирует voice.py + voice.ahk и скачивает AHK + Python embeddable
#>

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$base = Join-Path $env:LOCALAPPDATA "VoiceInput"
$ahkDir = Join-Path $base "AutoHotkey"
$pyDir = Join-Path $base "Python"
$ahkExe = Join-Path $ahkDir "AutoHotkey.exe"
$pyExe = Join-Path $pyDir "python.exe"

$base, $ahkDir, $pyDir | ForEach-Object { if (!(Test-Path $_)) { New-Item -ItemType Directory -Path $_ | Out-Null } }

# 1. AutoHotKey portable
if (!(Test-Path $ahkExe)) {
    Write-Host "Загрузка AutoHotKey v2..." -ForegroundColor Yellow
    $zip = Join-Path $env:TEMP "ahk.zip"
    Invoke-WebRequest "https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.18/AutoHotkey_2.0.18.zip" -OutFile $zip -UseBasicParsing
    Expand-Archive $zip -DestinationPath $ahkDir -Force
    $f = Get-ChildItem $ahkDir -Recurse -Filter "AutoHotkey.exe" | Select-Object -First 1
    if ($f) { Move-Item $f.FullName $ahkExe -Force }
    Remove-Item $zip -Force
    Write-Host "  AHK — готово" -ForegroundColor Green
}

# 2. Python embeddable
if (!(Test-Path $pyExe)) {
    Write-Host "Загрузка Python 3.11 embeddable..." -ForegroundColor Yellow
    $zip = Join-Path $env:TEMP "py.zip"
    Invoke-WebRequest "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip" -OutFile $zip -UseBasicParsing
    Expand-Archive $zip -DestinationPath $pyDir -Force
    $pth = Join-Path $pyDir "python311._pth"
    if (Test-Path $pth) { (Get-Content $pth) -replace '^#(import site)', '$1' | Set-Content $pth }
    Remove-Item $zip -Force
    Write-Host "  Python — готово" -ForegroundColor Green
}

# 3. Install pip for embeddable Python
if (Test-Path $pyExe) {
    Write-Host "Установка pip..." -ForegroundColor Yellow
    $getPip = Join-Path $env:TEMP "get-pip.py"
    Invoke-WebRequest "https://bootstrap.pypa.io/get-pip.py" -OutFile $getPip -UseBasicParsing
    & $pyExe $getPip --quiet 2>&1 | Out-Null
    Remove-Item $getPip -Force
    Write-Host "  pip — готово" -ForegroundColor Green

    Write-Host "Установка пакетов..." -ForegroundColor Yellow
    & $pyExe -m pip install --no-warn-script-location --disable-pip-version-check faster-whisper numpy sounddevice 2>&1 | ForEach-Object { Write-Host "  $_" }
    Write-Host "  Пакеты — готово" -ForegroundColor Green
}

# 4. Copy voice.py
$srcPy = Join-Path $PSScriptRoot "voice.py"
$dstPy = Join-Path $base "voice.py"
Copy-Item $srcPy $dstPy -Force

# 5. Create voice.ahk
$sc = Join-Path $base "voice.ahk"
@"
#Requires AutoHotkey v2.0
#SingleInstance Force
#NoEnv
^!v:: {
  global
  try {
    RunWait('"'`$pyExe`" "'`$dstPy`"', , "Hide")
  } catch e {
    MsgBox("Voice Error: " e.Message)
  }
}
"@ | Set-Content $sc -Encoding UTF8

# 6. Shortcuts
$ws = New-Object -ComObject WScript.Shell
$lk = Join-Path $base "Start-VoiceInput.lnk"
$s = $ws.CreateShortcut($lk)
$s.TargetPath = $ahkExe
$s.Arguments = "`"$sc`""
$s.WorkingDirectory = $base
$s.Save()

$sl = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
if (Test-Path $sl) {
    $s2 = $ws.CreateShortcut((Join-Path $sl "VoiceInput.lnk"))
    $s2.TargetPath = $ahkExe
    $s2.Arguments = "`"$sc`""
    $s2.WorkingDirectory = $base
    $s2.Save()
    Write-Host "Автозапуск добавлен" -ForegroundColor Green
}

Write-Host "`n=== ГОТОВО ===" -ForegroundColor Cyan
Write-Host "AHK: $ahkExe" -ForegroundColor Gray
Write-Host "Python: $pyExe" -ForegroundColor Gray
Write-Host "Script: $sc" -ForegroundColor Gray
Write-Host "Код Python: $dstPy" -ForegroundColor Gray
Write-Host ""
Write-Host "ИСПОЛЬЗОВАНИЕ:" -ForegroundColor Yellow
Write-Host "  RDP-окно в фокусе -> Ctrl+Alt+V -> говорите 5 сек" -ForegroundColor White
Write-Host ""
if ((Read-Host "Запустить сейчас? (Д/Н)") -match '^[Yy]') {
    Start-Process $ahkExe -ArgumentList "`"$sc`"" -WorkingDirectory $base
    Write-Host "Запущен (иконка H в трее)" -ForegroundColor Green
}

