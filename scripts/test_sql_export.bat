@echo off
chcp 1251 >nul
setlocal enabledelayedexpansion

echo ============================================
echo   TEST: SQL_exp_ready.bat
echo   Verify export of SQL objects from Ready
echo ============================================
echo.

set PASSWORD=
set /p PASSWORD="Enter Sybase password: "
set TASK_NAME=
set /p TASK_NAME="Enter task name (e.g. SYBASE-19337): "
set LOGIN=vchaga

:: Test 1: check_agent (simple, no Russian)
echo [Test 1] Export check_agent from dev_golden.golden
echo.

if not exist "C:\Temp\TestReady_SQL\dev_golden\golden\Procedure\" mkdir "C:\Temp\TestReady_SQL\dev_golden\golden\Procedure\"
echo -- test marker > "C:\Temp\TestReady_SQL\dev_golden\golden\Procedure\check_agent.sql"

call :RunExport "C:\Temp\TestReady_SQL"

if "%ERRORLEVEL%"=="0" (
    echo [Test 1 PASS] Export completed
) else (
    echo [Test 1 FAIL] Export failed
    set /a FAILS+=1
)

:: Compare with original
fc /B "C:\AIS\AI\Prod\BD\dev_golden\golden\Procedure\check_agent.sql" "C:\Temp\TestReady_SQL\dev_golden\golden\Procedure\check_agent.sql" >nul 2>&1
if "%ERRORLEVEL%"=="0" (
    echo [Test 1 PASS] Binary match with original (check_agent)
) else (
    echo [Test 1 FAIL] Binary mismatch with original (check_agent)
    set /a FAILS+=1
)

echo.

:: Test 2: usp_add_entity_data (with Russian text)
echo [Test 2] Export usp_add_entity_data (Russian text check)
echo -- test marker > "C:\Temp\TestReady_SQL\dev_golden\golden\Procedure\usp_add_entity_data.sql"

call :RunExport "C:\Temp\TestReady_SQL"

:: Check Russian text using findstr
findstr /C:"посредника" "C:\Temp\TestReady_SQL\dev_golden\golden\Procedure\usp_add_entity_data.sql" >nul 2>&1
if "%ERRORLEVEL%"=="0" (
    echo [Test 2 PASS] Russian text found in exported file
) else (
    echo [Test 2 FAIL] Russian text missing from exported file
    set /a FAILS+=1
)

:: Check for mojibake
findstr /C:"?????" "C:\Temp\TestReady_SQL\dev_golden\golden\Procedure\usp_add_entity_data.sql" >nul 2>&1
if "%ERRORLEVEL%"=="1" (
    echo [Test 2 PASS] No mojibake detected
) else (
    echo [Test 2 FAIL] Mojibake found in exported file
    set /a FAILS+=1
)

echo.
echo ============================================
echo   RESULTS (Task: %TASK_NAME%)
echo ============================================
if "%FAILS%"=="" set FAILS=0
if "%FAILS%"=="0" (
    echo All tests PASSED
) else (
    echo %FAILS% test(s) FAILED
)
echo.
if not "%FAILS%"=="0" (
    pause
)
endlocal
exit /b %FAILS%

:RunExport
set "READY_DIR=%~1"
echo set nocount on > "%TEMP%\_sql_run.sql"
echo select text from syscomments where id=object_id('check_agent') order by number, colid >> "%TEMP%\_sql_run.sql"
echo go >> "%TEMP%\_sql_run.sql"
isql -S dev_golden -U %LOGIN% -P %PASSWORD% -D golden -b -h-1 -i "%TEMP%\_sql_run.sql" -o "%READY_DIR%\dev_golden\golden\Procedure\check_agent.sql"
echo set nocount on > "%TEMP%\_sql_run.sql"
echo select text from syscomments where id=object_id('usp_add_entity_data') order by number, colid >> "%TEMP%\_sql_run.sql"
echo go >> "%TEMP%\_sql_run.sql"
isql -S dev_golden -U %LOGIN% -P %PASSWORD% -D golden -b -h-1 -i "%TEMP%\_sql_run.sql" -o "%READY_DIR%\dev_golden\golden\Procedure\usp_add_entity_data.sql"
del "%TEMP%\_sql_run.sql" 2>nul
exit /b 0
