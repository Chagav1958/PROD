@echo off
chcp 1251 >nul
title Export Service - AIS Release Preparation
echo === Export Service ===
echo.
echo Копирование проекта с заменой конфиденциальных данных
echo.
set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."
set "SCRIPT=%PROJECT_ROOT%\scripts\Export-Service.ps1"
set "CONFIG=%PROJECT_ROOT%\config\config.json"

if not exist "%SCRIPT%" (
    echo Ошибка: скрипт не найден: %SCRIPT%
    pause
    exit /b 1
)

:: Чтение путей из config.json
:: Используем PowerShell для извлечения путей
for /f "usebackq tokens=*" %%a in (`powershell -NoProfile -Command "$c=Get-Content '%CONFIG%' -Raw -Encoding UTF8|ConvertFrom-Json; if($c.export_service.source_path){$c.export_service.source_path}else{'C:\AIS\AI\Prod'}"`) do set "SRC=%%a"
for /f "usebackq tokens=*" %%a in (`powershell -NoProfile -Command "$c=Get-Content '%CONFIG%' -Raw -Encoding UTF8|ConvertFrom-Json"; if($c.export_service.dest_path){$c.export_service.dest_path}else{'Z:\AI\Prod'}"`) do set "DST=%%a"

echo Источник: %SRC%
echo Назначение: %DST%
echo.
echo Будут исключены папки: BD, PB_Current, PB_Main
echo.
echo ВНИМАНИЕ: логины, пароли и токены будут заменены на заглушки!
echo.

set /p CONFIRM="Продолжить? (д/Н): "
if /i not "%CONFIRM%"=="д" if /i not "%CONFIRM%"=="y" (
    echo Отменено.
    pause
    exit /b 0
)

echo.
echo Запуск экспорта...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -SourcePath "%SRC%" -DestPath "%DST%" -Force

if %ERRORLEVEL% equ 0 (
    echo.
    echo Экспорт успешно завершён.
) else (
    echo.
    echo Ошибка при выполнении экспорта (код: %ERRORLEVEL%^)
)

pause
exit /b %ERRORLEVEL%
