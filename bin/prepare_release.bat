@echo off
chcp 1251 >nul
setlocal enabledelayedexpansion

title PREPARE RELEASE - AIS->PROD

echo ============================================
echo   PREPARE RELEASE - ???????????????????? ?? ????????????
echo   PowerBuilder + SQL Sybase ASE 15.5
echo ============================================
echo.

:: ?"??"? ?'?????? ???????????????????? ?"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"?
set PASSWORD=
set /p PASSWORD="Enter Sybase password: "
set TASK_NAME=
set /p TASK_NAME="Enter task name (e.g. SYBASE-19337): "

if "%TASK_NAME%"=="" (
    echo [ERROR] Task name cannot be empty
    pause
    exit /b 1
)

echo.
echo Task: %TASK_NAME%
echo.

:: ?"??"? ???????? ?"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"??"?
:MENU
cls
echo ============================================
echo   Task: %TASK_NAME%
echo ============================================
echo.
echo   1 - Full SQL export  (Current: dev_golden.golden)
echo   2 - Full SQL export  (Main:    galaxy.golden)
echo   3 - SQL export from Ready folder
echo   4 - Compare && Verify (Compare-Export.ps1)
echo   5 - Create RFC in Jira
echo   0 - Exit
echo.
set CHOICE=
set /p CHOICE="Select action: "

if "%CHOICE%"=="1" goto FullCurrent
if "%CHOICE%"=="2" goto FullMain
if "%CHOICE%"=="3" goto ReadyExport
if "%CHOICE%"=="4" goto CompareVerify
if "%CHOICE%"=="5" goto CreateRFC
if "%CHOICE%"=="0" goto End
goto Menu

:FullCurrent
echo.
echo [Full Export] Server: dev_golden, Database: golden
echo.
call "%~dp0SQL_exp_param.bat" dev_golden golden %PASSWORD% %TASK_NAME%
pause
goto Menu

:FullMain
echo.
echo [Full Export] Server: galaxy, Database: golden
echo.
call "%~dp0SQL_exp_param.bat" galaxy golden %PASSWORD% %TASK_NAME%
pause
goto Menu

:ReadyExport
echo.
echo [Export from Ready folder]
echo.
set READY_PATH=
set /p READY_PATH="Enter path to ReadyMerged folder: "
if "%READY_PATH%"=="" (
    echo [ERROR] Path required
    pause
    goto Menu
)
echo.
call "%~dp0SQL_exp_ready.bat" "%READY_PATH%" %PASSWORD% %TASK_NAME%
pause
goto Menu

:CompareVerify
echo.
echo [Compare && Verify]
echo.
echo Starting Compare-Export.ps1...
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0Compare-Export.ps1" -Password %PASSWORD% -TaskName %TASK_NAME%
pause
goto Menu

:CreateRFC
echo.
echo [Create RFC in Jira]
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0Create-RFC.ps1" -TaskName %TASK_NAME%
pause
goto Menu

:End
endlocal
exit /b 0

