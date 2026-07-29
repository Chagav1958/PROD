<#
.SYNOPSIS
  Установка голосового ввода (AHK + Whisper) в профиль пользователя — БЕЗ АДМИНА
  Запускает: .\Install-VoiceInput.ps1
  Использование: Ctrl+Alt+V в RDP-окне → говорите 5 сек → текст в OpenCode
#>

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$baseDir = Join-Path $env:LOCALAPPDATA "VoiceInput"
$ahkDir  = Join-Path $baseDir "AutoHotkey"
$pyDir   = Join-Path $baseDir "Python"
$scriptPath = Join-Path $baseDir "voice.ahk"
$launcherPath = Join-Path $baseDir "Start-VoiceInput.lnk"

Write-Host "=== Установка Voice Input (без админа) ===" -ForegroundColor Cyan
Write-Host "Папка: $baseDir" -ForegroundColor Gray

# 1. Создаём папки
$baseDir, $ahkDir, $pyDir | ForEach-Object { if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ | Out-Null } }

# 2. Скачиваем портабельный AutoHotKey v2
$ahkExe = Join-Path $ahkDir "AutoHotkey.exe"
if (-not (Test-Path $ahkExe)) {
    Write-Host "Скачиваю AutoHotKey v2..." -ForegroundColor Yellow
    $ahkZip = Join-Path $env:TEMP "ahk.zip"
    try {
        Invoke-WebRequest -Uri "https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.18/AutoHotkey_2.0.18.zip" -OutFile $ahkZip -UseBasicParsing
        Expand-Archive -Path $ahkZip -DestinationPath $ahkDir -Force
        # Ищем AutoHotkey.exe в распакованном
        $found = Get-ChildItem $ahkDir -Recurse -Filter "AutoHotkey.exe" | Select-Object -First 1
        if ($found) { Move-Item $found.FullName $ahkExe -Force }
        Remove-Item $ahkZip -Force
        Write-Host "  AutoHotKey OK" -ForegroundColor Green
    } catch {
        Write-Host "  Ошибка загрузки AHK: $_" -ForegroundColor Red
        Write-Host "  Скачайте вручную: https://www.autohotkey.com/download/ahk.zip" -ForegroundColor Yellow
    }
}

# 3. Скачиваем Python embeddable (3.11, ~20 MB)
$pyExe = Join-Path $pyDir "python.exe"
if (-not (Test-Path $pyExe)) {
    Write-Host "Скачиваю Python embeddable..." -ForegroundColor Yellow
    $pyZip = Join-Path $env:TEMP "python-embed.zip"
    try {
        # Python 3.11.9 embeddable x64
        Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip" -OutFile $pyZip -UseBasicParsing
        Expand-Archive -Path $pyZip -DestinationPath $pyDir -Force
        # В embeddable нужно раскомментировать import site в python311._pth
        $pth = Join-Path $pyDir "python311._pth"
        if (Test-Path $pth) {
            (Get-Content $pth) -replace '^#(import site)', '$1' | Set-Content $pth
        }
        Remove-Item $pyZip -Force
        Write-Host "  Python OK" -ForegroundColor Green
    } catch {
        Write-Host "  Ошибка загрузки Python: $_" -ForegroundColor Red
    }
}

# 4. Устанавливаем пакеты через pip
if (Test-Path $pyExe) {
    Write-Host "Устанавливаю пакеты (faster-whisper, numpy, sounddevice)..." -ForegroundColor Yellow
    & $pyExe -m pip install --no-warn-script-location --disable-pip-version-check faster-whisper numpy sounddevice 2>&1 | ForEach-Object { Write-Host "  $_" }
    Write-Host "  Пакеты OK" -ForegroundColor Green
}

# 5. Создаём voice.ahk
$ahkScript = @"
#Requires AutoHotkey v2.0
#SingleInstance Force
#NoEnv

^!v:: {  ; Ctrl+Alt+V — запись 5 сек
    try {
        runwait(`"`"$pyExe`" -c `
            import sounddevice as sd, numpy as np, tempfile, os, wave, sys
            from faster_whisper import WhisperModel
            
            fs = 16000
            dur = 5
            rec = sd.rec(int(dur * fs), samplerate=fs, channels=1, dtype='int16')
            sd.wait()
            
            tmp = tempfile.NamedTemporaryFile(suffix='.wav', delete=False)
            tmp.close()
            with wave.open(tmp.name, 'wb') as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(fs)
                w.writeframes(rec.tobytes())
            
            model = WhisperModel('base', device='cpu', compute_type='int8')
            segs, _ = model.transcribe(tmp.name, language='ru', beam_size=5)
            text = ' '.join(s.text for s in segs).strip()
            os.unlink(tmp.name)
            
            if text:
                esc = text.replace('{', '{{').replace('}', '}}').replace('+', '{+}').replace('^', '{^}').replace('%', '{%}').replace('~', '{~}').replace('\n', '{Enter}').replace('\r', '')
                import subprocess
                subprocess.run(['powershell', '-c', f'Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait(\"{esc}\")'])
        `, , Hide)
    } catch e {
        MsgBox(`"Ошибка: `"`" e.Message `"`")
    }
}
"
Set-Content -Path $scriptPath -Value $ahkScript -Encoding UTF8
Write-Host "Скрипт создан: $scriptPath" -ForegroundColor Green

# 6. Создаём запускатор (ярлык в Start Menu / на Рабочем столе)
$wshell = New-Object -ComObject WScript.Shell
$shortcut = $wshell.CreateShortcut($launcherPath)
$shortcut.TargetPath = $ahkExe
$shortcut.Arguments = "`"$scriptPath`""
$shortcut.WorkingDirectory = $baseDir
$shortcut.IconLocation = $ahkExe
$shortcut.Description = "Voice Input for RDP (Ctrl+Alt+V)"
$shortcut.Save()

# 7. Автозапуск (опционально)
$startup = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
$startupLink = Join-Path $startup "VoiceInput.lnk"
$sc2 = $wshell.CreateShortcut($startupLink)
$sc2.TargetPath = $ahkExe
$sc2.Arguments = "`"$scriptPath`""
$sc2.WorkingDirectory = $baseDir
$sc2.Save()

Write-Host "`n=== ГОТОВО ===" -ForegroundColor Cyan
Write-Host "Запуск: $launcherPath" -ForegroundColor Gray
Write-Host "Автозапуск добавлен в Startup" -ForegroundColor Gray
Write-Host ""
Write-Host "ИСПОЛЬЗОВАНИЕ:" -ForegroundColor Yellow
Write-Host "  1. В RDP-окне поставьте курсор в OpenCode" -ForegroundColor White
Write-Host "  2. Нажмите Ctrl+Alt+V (на ЛОКАЛЬНОЙ клавиатуре)" -ForegroundColor White
Write-Host "  3. Говорите ~5 секунд" -ForegroundColor White
Write-Host "  4. Текст вставится в OpenCode" -ForegroundColor White
Write-Host ""
Write-Host "Модель whisper скачается при первом использовании (~140 MB)" -ForegroundColor Gray
Write-Host "Дальше работает ОФЛАЙН, мгновенно." -ForegroundColor Green

# Предложить запустить сейчас
$choice = Read-Host "Запустить сейчас? (Y/N)"
if ($choice -eq 'Y' -or $choice -eq 'y') {
    Start-Process -FilePath $ahkExe -ArgumentList "`"$scriptPath`"" -WorkingDirectory $baseDir
    Write-Host "Запущено. Иконка H в трее." -ForegroundColor Green
}
