@echo off
powershell -NoLogo -ExecutionPolicy RemoteSigned -File "%~dp0..\scripts\Show-ObjectInfo-GUI.ps1" %*
