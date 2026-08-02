@echo off
rem OpenCode-GUI-Watchdog-v2.bat — монитор v2: только последнее сообщение, ввод в поле ввода
rem Использование: OpenCode-GUI-Watchdog-v2.bat [интервал_сек] [-Verbose]

chcp 65001 >nul
powershell -NoLogo -ExecutionPolicy RemoteSigned -File "%~dp0OpenCode-GUI-Watchdog-v2.ps1" %*