@echo off
chcp 1251 >nul
setlocal enabledelayedexpansion

if "%~1"=="" goto usage
if "%~2"=="" goto usage

set READY_FOLDER=%~1
set PASSWORD=%~2
set TASK_NAME=%~3
if "%TASK_NAME%"=="" set TASK_NAME=NONE

set LOGIN=vchaga
set SCRIPT_DIR=%~dp0
set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%

if not exist "%READY_FOLDER%\*" (
    echo [ERROR] Ready folder not found: "%READY_FOLDER%"
    exit /b 1
)

echo =============================================
echo  Export SQL objects listed in Ready folder
echo  Ready: %READY_FOLDER%
echo  Task: %TASK_NAME%
echo =============================================

where isql >nul 2>nul
if %errorlevel% neq 0 (
    echo FATAL: isql not found
    exit /b 1
)

set TOTAL_OK=0
set TOTAL_FAIL=0

:: Count files for progress bar
for /f %%a in ('dir /s /b "%READY_FOLDER%\*.sql" 2^>nul ^| find /c /v ""') do set TOTAL_FILES=%%a
if not defined TOTAL_FILES set TOTAL_FILES=0
echo ###PHASE###SQLObjects^|%TOTAL_FILES%###

for /r "%READY_FOLDER%" %%F in (*.sql) do (
    set "FULL_PATH=%%F"
    set "REL_PATH=%%F"
    call :ProcessFile "%%F"
)

echo =============================================
echo  Total OK: %TOTAL_OK%   Fail: %TOTAL_FAIL%
echo =============================================
exit /b %TOTAL_FAIL%

:ProcessFile
setlocal enabledelayedexpansion
set "FULL_PATH=%~1"
set "FNAME=%~n1"

if "!FNAME!"=="" endlocal & goto :eof

set "REL=%~1"
set "REL=!REL:%READY_FOLDER%\=!"
for /f "tokens=1,2,3 delims=\" %%a in ("!REL!") do (
    set "SRV=%%a"
    set "DB=%%b"
    set "TYPE=%%c"
)

if "!SRV!"=="" set "SRV=dev_golden"
if "!DB!"=="" set "DB=golden"
if "!TYPE!"=="" set "TYPE=Procedure"

set ISQL=isql -S !SRV! -U %LOGIN% -P %PASSWORD% -D !DB! -b -h-1

echo set nocount on > "%TEMP%\_sql_ready.sql"
echo select text from syscomments where id=object_id('!FNAME!') order by number, colid >> "%TEMP%\_sql_ready.sql"
echo go >> "%TEMP%\_sql_ready.sql"
%ISQL% -i "%TEMP%\_sql_ready.sql" -o "%~1"

echo ###STEP###
if errorlevel 1 (
    echo [FAIL] !FNAME! (!SRV!.!DB!.!TYPE!)
    set /a TOTAL_FAIL+=1
) else (
    echo [OK]   !FNAME! (!SRV!.!DB!.!TYPE!)
    set /a TOTAL_OK+=1
)

del "%TEMP%\_sql_ready.sql" 2>nul
endlocal & set TOTAL_OK=%TOTAL_OK% & set TOTAL_FAIL=%TOTAL_FAIL%
goto :eof

:usage
echo Usage: %~nx0 PathToReadyFolder Password [TaskName]
echo.
echo Parameters:
echo   PathToReadyFolder - Path to the merged Ready folder
echo   Password          - Sybase password for login vchaga
echo   TaskName          - Optional Jira task identifier
echo.
echo Example: %~nx0 C:\Temp\ReadyMerged\SYBASE-19337 PASSWORD SYBASE-19337
echo.
echo The script finds all .sql files in Ready folder subdirectories
echo and re-exports them from the corresponding server/database.
echo Folder structure expected: Server\Database\Type\ObjectName.sql
echo.
endlocal
