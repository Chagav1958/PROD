@echo off
chcp 1251 >nul
setlocal enabledelayedexpansion

if "%~1"=="" goto usage
if "%~2"=="" goto usage
if "%~3"=="" goto usage
if "%~4"=="" goto usage
if "%~5"=="" goto usage

set OBJ_TYPE=%~1
set OBJ_NAME=%~2
set SERVER=%~3
set DATABASE=%~4
set PASSWORD=%~5
set TASK_NAME=%~6
if "%TASK_NAME%"=="" set TASK_NAME=NONE

set LOGIN=vchaga
set SCRIPT_DIR=%~dp0
set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%
set BASEDIR=%SCRIPT_DIR%\..\BD\%SERVER%\%DATABASE%

if /i "%OBJ_TYPE%"=="Procedure" set OUTDIR=Procedure
if /i "%OBJ_TYPE%"=="Function" set OUTDIR=Functions
if /i "%OBJ_TYPE%"=="Trigger" set OUTDIR=Triggers
if /i "%OBJ_TYPE%"=="View" set OUTDIR=Views
if /i "%OBJ_TYPE%"=="Table" set OUTDIR=Tables
if /i "%OBJ_TYPE%"=="Index" set OUTDIR=Indexes
if /i "%OBJ_TYPE%"=="PK" set OUTDIR=PK
if /i "%OBJ_TYPE%"=="FK" set OUTDIR=FK
if /i "%OBJ_TYPE%"=="Grant" set OUTDIR=Grants

if "%OUTDIR%"=="" (
    echo [ERROR] Unknown object type: %OBJ_TYPE%
    echo Supported types: Procedure, Function, Trigger, Table, Index, PK, FK, Grant
    exit /b 1
)

mkdir "%BASEDIR%\%OUTDIR%" 2>nul
mkdir "%BASEDIR%\LOGS" 2>nul

where isql >nul 2>nul
if %errorlevel% neq 0 (
    echo FATAL: isql not found
    exit /b 1
)

set ISQL=isql -S %SERVER% -U %LOGIN% -P %PASSWORD% -D %DATABASE% -b -h-1 -w 65535

echo =============================================
echo  Export single %OBJ_TYPE%: %OBJ_NAME%
echo  Server: %SERVER%, Database: %DATABASE%
echo  Task: %TASK_NAME%
echo =============================================

if /i "%OBJ_TYPE%"=="Procedure" (
    (echo set nocount on & echo select text from syscomments where id=object_id('%OBJ_NAME%'^) order by number, colid & echo go) > "%BASEDIR%\LOGS\_single.sql"
    %ISQL% -i "%BASEDIR%\LOGS\_single.sql" -o "%BASEDIR%\LOGS\_body.tmp"
    > "%BASEDIR%\%OUTDIR%\%OBJ_NAME%.sql" (
        echo USE %DATABASE%
        echo go
        echo IF OBJECT_ID('dbo.%OBJ_NAME%') IS NOT NULL
        echo BEGIN
        echo     DROP PROCEDURE dbo.%OBJ_NAME%
        echo     IF OBJECT_ID('dbo.%OBJ_NAME%') IS NOT NULL
        echo         PRINT '^<^<^< FAILED DROPPING PROCEDURE dbo.%OBJ_NAME% ^>^>^>'
        echo     ELSE
        echo         PRINT '^<^<^< DROPPED PROCEDURE dbo.%OBJ_NAME% ^>^>^>'
        echo END
        echo go
        type "%BASEDIR%\LOGS\_body.tmp"
    )
    del "%BASEDIR%\LOGS\_body.tmp" 2>nul
)

if /i "%OBJ_TYPE%"=="Function" (
    (echo set nocount on & echo select text from syscomments where id=object_id('%OBJ_NAME%'^) order by number, colid & echo go) > "%BASEDIR%\LOGS\_single.sql"
    %ISQL% -i "%BASEDIR%\LOGS\_single.sql" -o "%BASEDIR%\LOGS\_body.tmp"
    > "%BASEDIR%\%OUTDIR%\%OBJ_NAME%.sql" (
        echo USE %DATABASE%
        echo go
        echo IF OBJECT_ID('dbo.%OBJ_NAME%') IS NOT NULL
        echo BEGIN
        echo     DROP FUNCTION dbo.%OBJ_NAME%
        echo     IF OBJECT_ID('dbo.%OBJ_NAME%') IS NOT NULL
        echo         PRINT '^<^<^< FAILED DROPPING FUNCTION dbo.%OBJ_NAME% ^>^>^>'
        echo     ELSE
        echo         PRINT '^<^<^< DROPPED FUNCTION dbo.%OBJ_NAME% ^>^>^>'
        echo END
        echo go
        type "%BASEDIR%\LOGS\_body.tmp"
    )
    del "%BASEDIR%\LOGS\_body.tmp" 2>nul
)

if /i "%OBJ_TYPE%"=="Trigger" (
    (echo set nocount on & echo select text from syscomments where id=object_id('%OBJ_NAME%'^) order by number, colid & echo go) > "%BASEDIR%\LOGS\_single.sql"
    %ISQL% -i "%BASEDIR%\LOGS\_single.sql" -o "%BASEDIR%\LOGS\_body.tmp"
    > "%BASEDIR%\%OUTDIR%\%OBJ_NAME%.sql" (
        echo USE %DATABASE%
        echo go
        echo IF OBJECT_ID('dbo.%OBJ_NAME%') IS NOT NULL
        echo BEGIN
        echo     DROP TRIGGER dbo.%OBJ_NAME%
        echo     IF OBJECT_ID('dbo.%OBJ_NAME%') IS NOT NULL
        echo         PRINT '^<^<^< FAILED DROPPING TRIGGER dbo.%OBJ_NAME% ^>^>^>'
        echo     ELSE
        echo         PRINT '^<^<^< DROPPED TRIGGER dbo.%OBJ_NAME% ^>^>^>'
        echo END
        echo go
        type "%BASEDIR%\LOGS\_body.tmp"
    )
    del "%BASEDIR%\LOGS\_body.tmp" 2>nul
)

if /i "%OBJ_TYPE%"=="View" (
    (echo set nocount on & echo select text from syscomments where id=object_id('%OBJ_NAME%'^) order by number, colid & echo go) > "%BASEDIR%\LOGS\_single.sql"
    %ISQL% -i "%BASEDIR%\LOGS\_single.sql" -o "%BASEDIR%\LOGS\_body.tmp"
    > "%BASEDIR%\%OUTDIR%\%OBJ_NAME%.sql" (
        echo USE %DATABASE%
        echo go
        echo IF OBJECT_ID('dbo.%OBJ_NAME%') IS NOT NULL
        echo BEGIN
        echo     DROP VIEW dbo.%OBJ_NAME%
        echo     IF OBJECT_ID('dbo.%OBJ_NAME%') IS NOT NULL
        echo         PRINT '^<^<^< FAILED DROPPING VIEW dbo.%OBJ_NAME% ^>^>^>'
        echo     ELSE
        echo         PRINT '^<^<^< DROPPED VIEW dbo.%OBJ_NAME% ^>^>^>'
        echo END
        echo go
        type "%BASEDIR%\LOGS\_body.tmp"
    )
    del "%BASEDIR%\LOGS\_body.tmp" 2>nul
)

if /i "%OBJ_TYPE%"=="Index" (
    for /f "tokens=1,2 delims=." %%a in ("%OBJ_NAME%") do (
        set TAB_NAME=%%a
        set IDX_NAME=%%b
    )
    if not defined IDX_NAME (
        echo [ERROR] For Index use format: TableName.IndexName
        exit /b 1
    )
    (
        echo declare @tabname varchar^(255^), @idxname varchar^(255^)
        echo select @tabname = '!TAB_NAME!', @idxname = '!IDX_NAME!'
        type "%SCRIPT_DIR%\gen_single_index.sql"
    ) > "%BASEDIR%\LOGS\_gen.sql"
    %ISQL% -i "%BASEDIR%\LOGS\_gen.sql" -o "%BASEDIR%\%OUTDIR%\%OBJ_NAME%.sql"
)

if /i "%OBJ_TYPE%"=="PK" (
    for /f "tokens=1,2 delims=." %%a in ("%OBJ_NAME%") do (
        set TAB_NAME=%%a
        set PK_NAME=%%b
    )
    if not defined PK_NAME (
        echo [ERROR] For PK use format: TableName.PKName
        exit /b 1
    )
    (
        echo declare @tabname varchar^(255^), @pkname varchar^(255^)
        echo select @tabname = '!TAB_NAME!', @pkname = '!PK_NAME!'
        type "%SCRIPT_DIR%\gen_single_pk.sql"
    ) > "%BASEDIR%\LOGS\_gen.sql"
    %ISQL% -i "%BASEDIR%\LOGS\_gen.sql" -o "%BASEDIR%\%OUTDIR%\%OBJ_NAME%.sql"
)

if /i "%OBJ_TYPE%"=="FK" (
    for /f "tokens=1,2 delims=." %%a in ("%OBJ_NAME%") do (
        set TAB_NAME=%%a
        set FK_NAME=%%b
    )
    if not defined FK_NAME (
        echo [ERROR] For FK use format: TableName.FKName
        exit /b 1
    )
    (
        echo declare @tabname varchar^(255^), @fkname varchar^(255^)
        echo select @tabname = '!TAB_NAME!', @fkname = '!FK_NAME!'
        type "%SCRIPT_DIR%\gen_single_fk.sql"
    ) > "%BASEDIR%\LOGS\_gen.sql"
    %ISQL% -i "%BASEDIR%\LOGS\_gen.sql" -o "%BASEDIR%\%OUTDIR%\%OBJ_NAME%.sql"
)

if /i "%OBJ_TYPE%"=="Grant" (
    (
        echo declare @objname varchar^(255^)
        echo select @objname = '%OBJ_NAME%'
        type "%SCRIPT_DIR%\gen_single_grant.sql"
    ) > "%BASEDIR%\LOGS\_gen.sql"
    %ISQL% -i "%BASEDIR%\LOGS\_gen.sql" -o "%BASEDIR%\%OUTDIR%\%OBJ_NAME%.sql"
)

if /i "%OBJ_TYPE%"=="Table" (
    echo set nocount on > "%BASEDIR%\LOGS\_single.sql"
    echo if object_id^(N'##gen_tname'^) is not null drop table ##gen_tname >> "%BASEDIR%\LOGS\_single.sql"
    echo go >> "%BASEDIR%\LOGS\_single.sql"
    echo select tname = '%OBJ_NAME%' into ##gen_tname >> "%BASEDIR%\LOGS\_single.sql"
    echo go >> "%BASEDIR%\LOGS\_single.sql"
    type "%SCRIPT_DIR%\gen_create_table.sql" >> "%BASEDIR%\LOGS\_single.sql"
    %ISQL% -i "%BASEDIR%\LOGS\_single.sql" -o "%BASEDIR%\%OUTDIR%\%OBJ_NAME%.sql"
)

del "%BASEDIR%\LOGS\_body.tmp" "%BASEDIR%\LOGS\_single.sql" "%BASEDIR%\LOGS\_gen.sql" 2>nul

if errorlevel 1 (
    echo [ERROR] Export failed for %OBJ_NAME%
) else (
    echo [OK] Exported to: %BASEDIR%\%OUTDIR%\%OBJ_NAME%.sql
)

echo =============================================
echo  Finished: %DATE% %TIME%
echo =============================================
exit /b %errorlevel%

:usage
echo Usage: %~nx0 ObjectType ObjectName Server Database Password [TaskName]
echo.
echo Parameters:
echo   ObjectType - Procedure, Function, Trigger, Table, Index, PK, FK, Grant
echo   ObjectName - Object name in database
echo   Server     - Sybase ASE server name
echo   Database   - Database name
echo   Password   - Sybase password for login vchaga
echo   TaskName   - Optional Jira task identifier
echo.
echo Example: %~nx0 Procedure check_agent dev_golden golden PASSWORD SYBASE-19337
echo Example: %~nx0 Function fn_reestr_type_id galaxy golden PASSWORD
echo Example: %~nx0 Index tablename.indexname dev_golden golden PASSWORD
echo Example: %~nx0 PK tablename.pkname dev_golden golden PASSWORD
echo Example: %~nx0 FK tablename.fkname galaxy golden PASSWORD
echo Example: %~nx0 Grant objectname galaxy golden PASSWORD
endlocal
