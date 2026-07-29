@echo off
chcp 1251 >nul
setlocal enabledelayedexpansion

set "READY_FOLDER=C:\Temp\TestReady_SQL"
set PASSWORD=
set /p PASSWORD="Enter Sybase password: "
set TASK_NAME=
set /p TASK_NAME="Enter task name (e.g. SYBASE-19337): "
set LOGIN=vchaga

echo READY_FOLDER=%READY_FOLDER%
echo TASK_NAME=%TASK_NAME%
echo.

for /r "%READY_FOLDER%" %%F in (*.sql) do (
    echo Found: %%F
    set "FULL_PATH=%%F"
    call :ProcessFile "%%F"
)
pause
exit /b 0

:ProcessFile
setlocal
set "FULL_PATH=%~1"
set "FNAME=%~n1"
echo FNAME=!FNAME!

if "!FNAME!"=="" (
    echo FNAME is EMPTY!
    endlocal & goto :eof
)

set "REL=%~1"
echo BEFORE substitution: REL=!REL!
echo READY_FOLDER=!READY_FOLDER!
set "REL=!REL:%READY_FOLDER%\=!"
echo AFTER substitution: REL=!REL!

for /f "tokens=1,2,3 delims=\" %%a in ("!REL!") do (
    set "SRV=%%a"
    set "DB=%%b"
    set "TYPE=%%c"
)

if "!SRV!"=="" set "SRV=dev_golden"
if "!DB!"=="" set "DB=golden"
if "!TYPE!"=="" set "TYPE=Procedure"

echo SRV=!SRV! DB=!DB! TYPE=!TYPE!
echo.

set ISQL=isql -S !SRV! -U %LOGIN% -P %PASSWORD% -D !DB! -b -h-1
echo Running: !ISQL! -i SQL_FILE -o %~1

echo set nocount on > "%TEMP%\_sql_debug.sql"
echo select text from syscomments where id=object_id('!FNAME!') order by number, colid >> "%TEMP%\_sql_debug.sql"
echo go >> "%TEMP%\_sql_debug.sql"

echo SQL file content:
type "%TEMP%\_sql_debug.sql"
echo.

!ISQL! -i "%TEMP%\_sql_debug.sql" -o "%~1"

if errorlevel 1 (
    echo [FAIL] !FNAME! - errorlevel=!errorlevel!
) else (
    echo [OK]   !FNAME!
)

echo.
endlocal
goto :eof
