@echo off
setlocal
powershell -NoLogo -File "%~dp0Add-Bom.ps1" %*
exit /b %ERRORLEVEL%
