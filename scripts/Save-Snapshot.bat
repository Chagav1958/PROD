@echo off
setlocal
powershell -NoLogo -File "%~dp0Save-Snapshot.ps1" %*
exit /b %ERRORLEVEL%
