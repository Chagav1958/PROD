@echo off
start "" powershell -NoLogo -ExecutionPolicy RemoteSigned -File "%~dp0..\scripts\Show-ProdObr-GUI.ps1" %*
