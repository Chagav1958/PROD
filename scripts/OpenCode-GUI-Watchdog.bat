@echo off
rem OpenCode-GUI-Watchdog.bat — монитор GUI OpenCode для автопродолжения при "Streaming response failed"
rem Использование: OpenCode-GUI-Watchdog.bat [интервал_сек] [-Verbose]

chcp 65001 >nul
powershell -NoLogo -ExecutionPolicy RemoteSigned -File "%~dp0OpenCode-GUI-Watchdog.ps1" %*