@echo off
chcp 1251 > nul
setlocal enabledelayedexpansion

set BASE=%LOCALAPPDATA%\VoiceInput
set AHK_DIR=%BASE%\AutoHotkey
set PY_DIR=%BASE%\Python
set AHK_EXE=%AHK_DIR%\AutoHotkey.exe
set PY_EXE=%PY_DIR%\python.exe
set LOG=%BASE%\install.log
set ERR_COUNT=0

if not exist "%BASE%" mkdir "%BASE%"
echo ==================== > "%LOG%"
echo Install started %date% %time% >> "%LOG%"
echo ==================== >> "%LOG%"

echo === Установка Voice Input ===
echo.

:: 1. AutoHotKey
if not exist "%AHK_EXE%" (
    echo [1/5] Скачиваю AutoHotKey...
    echo [1] AHK download >> "%LOG%"
    powershell -NoProfile -Command "Invoke-WebRequest 'https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.18/AutoHotkey_2.0.18.zip' -OutFile '%TEMP%\ahk.zip' -UseBasicParsing" >> "%LOG%" 2>&1
    if !errorlevel! neq 0 (echo   ОШИБКА & set /a ERR_COUNT+=1) else (
        powershell -NoProfile -Command "Expand-Archive '%TEMP%\ahk.zip' -Dest '%AHK_DIR%' -Force; $f=Get-ChildItem '%AHK_DIR%' -Recurse -Filter 'AutoHotkey.exe'|Select -First 1; if($f){Move-Item $f.FullName '%AHK_EXE%' -Force}" >> "%LOG%" 2>&1
        if !errorlevel! neq 0 (echo   ОШИБКА распаковки & set /a ERR_COUNT+=1) else (echo   OK)
    )
) else (echo [1/5] AHK уже есть - OK)

:: 2. Python
if not exist "%PY_EXE%" (
    echo [2/5] Скачиваю Python...
    echo [2] Python download >> "%LOG%"
    powershell -NoProfile -Command "Invoke-WebRequest 'https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip' -OutFile '%TEMP%\py.zip' -UseBasicParsing" >> "%LOG%" 2>&1
    if !errorlevel! neq 0 (echo   ОШИБКА & set /a ERR_COUNT+=1) else (
        powershell -NoProfile -Command "Expand-Archive '%TEMP%\py.zip' -Dest '%PY_DIR%' -Force; $pth='%PY_DIR%\python311._pth'; if(Test-Path $pth){(Get-Content $pth)-replace '^#(import site)','$1'|Set-Content $pth}" >> "%LOG%" 2>&1
        if !errorlevel! neq 0 (echo   ОШИБКА распаковки & set /a ERR_COUNT+=1) else (echo   OK)
    )
) else (echo [2/5] Python уже есть - OK)

:: 3. Pip
if exist "%PY_EXE%" (
    echo [3/5] Устанавливаю pip...
    echo [3] pip install >> "%LOG%"
    powershell -NoProfile -Command "Invoke-WebRequest 'https://bootstrap.pypa.io/get-pip.py' -OutFile '%TEMP%\get-pip.py' -UseBasicParsing" >> "%LOG%" 2>&1
    if !errorlevel! neq 0 (echo   ОШИБКА скачивания get-pip.py & set /a ERR_COUNT+=1) else (
        "%PY_EXE%" "%TEMP%\get-pip.py" --quiet >> "%LOG%" 2>&1
        if !errorlevel! neq 0 (echo   ОШИБКА установки pip & set /a ERR_COUNT+=1) else (echo   OK)
    )
) else (echo [3/5] Python не найден - пропуск)

:: 4. Packages
if exist "%PY_EXE%" (
    echo [4/5] Устанавливаю пакеты (1-2 мин)...
    echo [4] packages >> "%LOG%"
    "%PY_EXE%" -m pip install --no-warn-script-location --disable-pip-version-check faster-whisper numpy sounddevice >> "%LOG%" 2>&1
    if !errorlevel! neq 0 (echo   ОШИБКА & set /a ERR_COUNT+=1) else (echo   OK)
)

:: 5. Файлы + автозапуск
echo [5/5] Настройка автозапуска...
if exist "%~dp0voice.py" copy /Y "%~dp0voice.py" "%BASE%\voice.py" > nul
if exist "%BASE%\voice.py" (echo   voice.py OK) else (echo   voice.py НЕ НАЙДЕН - скопируйте вручную в %BASE%)

set AHK_SCRIPT=%BASE%\voice.ahk
powershell -NoProfile -Command "$s='%AHK_SCRIPT%'; Set-Content $s \"#Requires AutoHotkey v2.0`r`n#SingleInstance Force`r`n#NoEnv`r`n^!v:: {`r`n  try { RunWait('\"%PY_EXE:\=\\%\" \"%BASE:\=\\%\\voice.py\"', , 'Hide') } catch e { MsgBox(e.Message) }`r`n}\" -Encoding UTF8" >> "%LOG%" 2>&1

:: Shortcut
powershell -NoProfile -Command "$ws=New-Object -ComObject WScript.Shell; $sc='%AHK_EXE%'; $lk='%BASE%\Start-VoiceInput.lnk'; $s=$ws.CreateShortcut($lk); $s.TargetPath=$sc; $s.Arguments='\"' + '%AHK_SCRIPT%' + '\"'; $s.WorkingDirectory='%BASE%'; $s.Save(); $sl=$env:APPDATA+'\Microsoft\Windows\Start Menu\Programs\Startup\VoiceInput.lnk'; $s2=$ws.CreateShortcut($sl); $s2.TargetPath=$sc; $s2.Arguments='\"' + '%AHK_SCRIPT%' + '\"'; $s2.WorkingDirectory='%BASE%'; $s2.Save()" >> "%LOG%" 2>&1

echo   Автозапуск OK
echo.

:: Итог
echo ====================
if %ERR_COUNT% gtr 0 (
    echo Ошибок: %ERR_COUNT%. Лог: %LOG%
) else (
    echo Установка завершена успешно!
)
echo ====================
echo.

if %ERR_COUNT% equ 0 (
    set /p LAUNCH="Запустить Voice Input сейчас? (Y/N): "
    if /i "!LAUNCH!"=="Y" (
        start "" "%AHK_EXE%" "%AHK_SCRIPT%"
        echo Запущено. Иконка H в трее.
        echo.
        echo Использование:
        echo   RDP-окно ^> Ctrl+Alt+V ^> говорите 5 сек
    )
) else (
    echo Исправьте ошибки и запустите заново.
    echo Лог: %LOG%
)

pause
