@echo off
rem Nemotron-Watchdog.bat — запуск opencode с автопродолжением при "Streaming response failed"
rem Использование: Nemotron-Watchdog.bat [аргументы opencode]

chcp 65001 >nul
powershell -NoLogo -ExecutionPolicy RemoteSigned -File "%~dp0Nemotron-Watchdog.ps1" %*