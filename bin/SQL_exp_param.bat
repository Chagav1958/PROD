@echo off
chcp 1251 >nul
setlocal enabledelayedexpansion

if "%~1"=="" goto usage
if "%~2"=="" goto usage
if "%~3"=="" goto usage

set SERVER=%~1
set DATABASE=%~2
set PASSWORD=%~3
set TASK_NAME=%~4
set EXPORT_PATH=%~5
set OBJECT_TYPE=%~6
set LOGIN=vchaga
set SCRIPT_DIR=%~dp0
set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%
if not "%EXPORT_PATH%"=="" ( set BASEDIR=%EXPORT_PATH% ) else ( set BASEDIR=%SCRIPT_DIR%\..\BD\%SERVER%\%DATABASE% )
:: Ð£Ð´Ð°Ð»ÐµÐ½Ð¸Ðµ ÐºÐ¾Ð½Ñ†ÐµÐ²Ñ‹Ñ… Ð¿Ñ€Ð¾Ð±ÐµÐ»Ð¾Ð²
:trimBase
if "!BASEDIR:~-1!"==" " set BASEDIR=!BASEDIR:~0,-1!& goto trimBase
mkdir "%BASEDIR%\LOGS" 2>nul
set LOGFILE=%BASEDIR%\LOGS\export_objects.log

echo ============================================= > "%LOGFILE%"
echo  SQL OBJECTS EXPORT - FULL DDL >> "%LOGFILE%"
echo  Task: %TASK_NAME% >> "%LOGFILE%"
echo  Started: %DATE% %TIME% >> "%LOGFILE%"
echo ============================================= >> "%LOGFILE%"

echo =============================================
echo  SQL OBJECTS EXPORT - FULL DDL
echo  Task: %TASK_NAME%
echo  Started: %DATE% %TIME%
echo =============================================

echo [INFO] Base: %BASEDIR%
echo [INFO] Base: %BASEDIR% >> "%LOGFILE%"

mkdir "%BASEDIR%" 2>nul
mkdir "%BASEDIR%\Procedure" 2>nul
mkdir "%BASEDIR%\Functions" 2>nul
mkdir "%BASEDIR%\Triggers"  2>nul
mkdir "%BASEDIR%\Tables"    2>nul
mkdir "%BASEDIR%\Views"     2>nul
mkdir "%BASEDIR%\Indexes"   2>nul
mkdir "%BASEDIR%\PK"        2>nul
mkdir "%BASEDIR%\FK"        2>nul
mkdir "%BASEDIR%\Grants"    2>nul
mkdir "%BASEDIR%\LOGS"      2>nul


where isql >nul 2>nul
if %errorlevel% neq 0 (
    echo FATAL: isql not found >> "%LOGFILE%"
    echo FATAL: isql not found
    exit /b 1
)

echo. >> "%LOGFILE%"
echo [1] TEST CONNECTION >> "%LOGFILE%"
echo.
echo [1] TEST CONNECTION

(echo set nocount on & echo select 1 & echo go) > "%BASEDIR%\LOGS\test.sql"
isql -S %SERVER% -U %LOGIN% -P %PASSWORD% -D %DATABASE% -b -h-1 -i "%BASEDIR%\LOGS\test.sql" -o "%BASEDIR%\LOGS\test.out"
if %errorlevel% neq 0 (
    echo FATAL: isql failed >> "%LOGFILE%"
    echo FATAL: isql failed
    exit /b 1
)
set /p RES=<"%BASEDIR%\LOGS\test.out"
set RES=%RES: =%
if "%RES%"=="1" (
    echo [OK] Connected >> "%LOGFILE%"
    echo [OK] Connected
) else (
    echo FATAL: connection check failed >> "%LOGFILE%"
    echo FATAL: connection check failed
    exit /b 1
)

set ISQL=isql -S %SERVER% -U %LOGIN% -P %PASSWORD% -D %DATABASE% -b -h-1

:: Ôèëüòð ïî òèïó îáúåêòà
if /i "%OBJECT_TYPE%"=="Procedure" goto export_proc
if /i "%OBJECT_TYPE%"=="Functions" goto export_func
if /i "%OBJECT_TYPE%"=="Triggers" goto export_trig
if /i "%OBJECT_TYPE%"=="Tables" goto export_tables
if /i "%OBJECT_TYPE%"=="Views" goto export_views
if /i "%OBJECT_TYPE%"=="Indexes" goto export_indexes
if /i "%OBJECT_TYPE%"=="PK" goto export_pk
if /i "%OBJECT_TYPE%"=="FK" goto export_fk
if /i "%OBJECT_TYPE%"=="Grants" goto export_grants
if "%OBJECT_TYPE%"=="" goto export_all
if not "%OBJECT_TYPE%"=="" (
    echo FATAL: Unknown OBJECT_TYPE: %OBJECT_TYPE% >> "%LOGFILE%"
    echo FATAL: Unknown OBJECT_TYPE: %OBJECT_TYPE%
    exit /b 1
)

:: ========== PROCEDURES ==========
echo. >> "%LOGFILE%"
:export_proc
echo [2] EXPORT PROCEDURES >> "%LOGFILE%"
echo.
:export_proc
echo [2] EXPORT PROCEDURES

echo set nocount on > "%BASEDIR%\LOGS\get_procs.sql"
echo select rtrim(name^) from sysobjects where type='P' and user_name(uid^)='dbo' order by name >> "%BASEDIR%\LOGS\get_procs.sql"
echo go >> "%BASEDIR%\LOGS\get_procs.sql"
%ISQL% -i "%BASEDIR%\LOGS\get_procs.sql" -o "%BASEDIR%\LOGS\procs.txt"

:: Count procedures for progress bar
for /f %%a in ('type "%BASEDIR%\LOGS\procs.txt" 2^>nul ^| find /c /v ""') do set P_TOTAL=%%a
echo ###PHASE###Procedures^|!P_TOTAL!###
echo ###PHASE###Procedures^|!P_TOTAL!### >> "%LOGFILE%"

set P_CNT=0& set P_OK=0
for /f "tokens=*" %%i in ('type "%BASEDIR%\LOGS\procs.txt"') do (
    set "ONAME=%%i" & set "ONAME=!ONAME: =!"
    if defined ONAME (
        echo   Exporting proc: !ONAME!
        echo set nocount on>"%BASEDIR%\LOGS\_tp.sql"
        echo select convert^(varbinary^(255^)^, text^) as hx, number, colid from syscomments where id=object_id^('!ONAME!'^) order by number, colid>>"%BASEDIR%\LOGS\_tp.sql"
        echo go>>"%BASEDIR%\LOGS\_tp.sql"
        isql -S %SERVER% -U %LOGIN% -P %PASSWORD% -D %DATABASE% -b -h-1 -w 65535 -i "%BASEDIR%\LOGS\_tp.sql" -o "%BASEDIR%\LOGS\_frags.txt"
        powershell -NoLogo -ExecutionPolicy RemoteSigned -File "%SCRIPT_DIR%\..\scripts\Rebuild-Object.ps1" -Frags "%BASEDIR%\LOGS\_frags.txt" -Out "%BASEDIR%\LOGS\_body.tmp"
        echo USE %DATABASE%>"%BASEDIR%\Procedure\!ONAME!.sql"
        echo go>>"%BASEDIR%\Procedure\!ONAME!.sql"
        echo IF OBJECT_ID^('dbo.!ONAME!'^) IS NOT NULL>>"%BASEDIR%\Procedure\!ONAME!.sql"
        echo BEGIN>>"%BASEDIR%\Procedure\!ONAME!.sql"
        echo     DROP PROCEDURE dbo.!ONAME!>>"%BASEDIR%\Procedure\!ONAME!.sql"
        echo     IF OBJECT_ID^('dbo.!ONAME!'^) IS NOT NULL>>"%BASEDIR%\Procedure\!ONAME!.sql"
        echo         PRINT '^<^<^< FAILED DROPPING PROCEDURE dbo.!ONAME! ^>^>^>'>>"%BASEDIR%\Procedure\!ONAME!.sql"
        echo     ELSE>>"%BASEDIR%\Procedure\!ONAME!.sql"
        echo         PRINT '^<^<^< DROPPED PROCEDURE dbo.!ONAME! ^>^>^>'>>"%BASEDIR%\Procedure\!ONAME!.sql"
        echo END>>"%BASEDIR%\Procedure\!ONAME!.sql"
        echo go>>"%BASEDIR%\Procedure\!ONAME!.sql"
        type "%BASEDIR%\LOGS\_body.tmp">>"%BASEDIR%\Procedure\!ONAME!.sql"
        echo go>>"%BASEDIR%\Procedure\!ONAME!.sql"
        echo EXEC sp_procxmode 'dbo.!ONAME!', 'unchained'>>"%BASEDIR%\Procedure\!ONAME!.sql"
        echo go>>"%BASEDIR%\Procedure\!ONAME!.sql"
        echo IF OBJECT_ID^('dbo.!ONAME!'^) IS NOT NULL>>"%BASEDIR%\Procedure\!ONAME!.sql"
        echo     PRINT '^<^<^< CREATED PROCEDURE dbo.!ONAME! ^>^>^>'>>"%BASEDIR%\Procedure\!ONAME!.sql"
        echo ELSE>>"%BASEDIR%\Procedure\!ONAME!.sql"
        echo     PRINT '^<^<^< FAILED CREATING PROCEDURE dbo.!ONAME! ^>^>^>'>>"%BASEDIR%\Procedure\!ONAME!.sql"
        echo go>>"%BASEDIR%\Procedure\!ONAME!.sql"
        rem Grant from sysprotects
        echo set nocount on>"%BASEDIR%\LOGS\_gen.sql"
        echo if object_id^(N'##gen_gobj'^) is not null drop table ##gen_gobj>>"%BASEDIR%\LOGS\_gen.sql"
        echo go>>"%BASEDIR%\LOGS\_gen.sql"
        echo select '!ONAME!' as objname into ##gen_gobj>>"%BASEDIR%\LOGS\_gen.sql"
        echo go>>"%BASEDIR%\LOGS\_gen.sql"
        type "%SCRIPT_DIR%\gen_single_grant.sql">>"%BASEDIR%\LOGS\_gen.sql"
        isql -S %SERVER% -U %LOGIN% -P %PASSWORD% -D %DATABASE% -b -h-1 -i "%BASEDIR%\LOGS\_gen.sql" -o "%BASEDIR%\LOGS\_grants.tmp"
        type "%BASEDIR%\LOGS\_grants.tmp">>"%BASEDIR%\Procedure\!ONAME!.sql"
        del "%BASEDIR%\LOGS\_grants.tmp" 2>nul
        if not errorlevel 1 set /a P_OK+=1
        set /a P_CNT+=1
        echo ###STEP###
        echo ###STEP### >> "%LOGFILE%"
    )
)
echo   Procs: found=%P_CNT% ok=%P_OK%
echo   Procs: found=%P_CNT% ok=%P_OK% >> "%LOGFILE%"
goto :sect_done

:: ========== FUNCTIONS ==========
echo. >> "%LOGFILE%"
:export_func
echo [3] EXPORT FUNCTIONS >> "%LOGFILE%"
echo.
:export_func
echo [3] EXPORT FUNCTIONS

echo set nocount on > "%BASEDIR%\LOGS\get_funcs.sql"
echo select name from sysobjects where type in ('F','FN','SF','TF') and user_name(uid^)='dbo' order by name >> "%BASEDIR%\LOGS\get_funcs.sql"
echo go >> "%BASEDIR%\LOGS\get_funcs.sql"
%ISQL% -i "%BASEDIR%\LOGS\get_funcs.sql" -o "%BASEDIR%\LOGS\funcs.txt"

:: Count functions for progress bar
for /f %%a in ('type "%BASEDIR%\LOGS\funcs.txt" 2^>nul ^| find /c /v ""') do set F_TOTAL=%%a
echo ###PHASE###Functions^|!F_TOTAL!###
echo ###PHASE###Functions^|!F_TOTAL!### >> "%LOGFILE%"

set F_CNT=0& set F_OK=0
for /f "tokens=*" %%i in ('type "%BASEDIR%\LOGS\funcs.txt"') do (
    set "ONAME=%%i" & set "ONAME=!ONAME: =!"
    if defined ONAME (
        echo   Exporting func: !ONAME!
        echo set nocount on>"%BASEDIR%\LOGS\_tf.sql"
        echo select convert^(varbinary^(255^)^, text^) as hx, number, colid from syscomments where id=object_id^('!ONAME!'^) order by number, colid>>"%BASEDIR%\LOGS\_tf.sql"
        echo go>>"%BASEDIR%\LOGS\_tf.sql"
        isql -S %SERVER% -U %LOGIN% -P %PASSWORD% -D %DATABASE% -b -h-1 -w 65535 -i "%BASEDIR%\LOGS\_tf.sql" -o "%BASEDIR%\LOGS\_frags.txt"
        powershell -NoLogo -ExecutionPolicy RemoteSigned -File "%SCRIPT_DIR%\..\scripts\Rebuild-Object.ps1" -Frags "%BASEDIR%\LOGS\_frags.txt" -Out "%BASEDIR%\LOGS\_body.tmp"
        echo USE %DATABASE%>"%BASEDIR%\Functions\!ONAME!.sql"
        echo go>>"%BASEDIR%\Functions\!ONAME!.sql"
        echo IF OBJECT_ID^('dbo.!ONAME!'^) IS NOT NULL>>"%BASEDIR%\Functions\!ONAME!.sql"
        echo BEGIN>>"%BASEDIR%\Functions\!ONAME!.sql"
        echo     DROP FUNCTION dbo.!ONAME!>>"%BASEDIR%\Functions\!ONAME!.sql"
        echo     IF OBJECT_ID^('dbo.!ONAME!'^) IS NOT NULL>>"%BASEDIR%\Functions\!ONAME!.sql"
        echo         PRINT '^<^<^< FAILED DROPPING FUNCTION dbo.!ONAME! ^>^>^>'>>"%BASEDIR%\Functions\!ONAME!.sql"
        echo     ELSE>>"%BASEDIR%\Functions\!ONAME!.sql"
        echo         PRINT '^<^<^< DROPPED FUNCTION dbo.!ONAME! ^>^>^>'>>"%BASEDIR%\Functions\!ONAME!.sql"
        echo END>>"%BASEDIR%\Functions\!ONAME!.sql"
        echo go>>"%BASEDIR%\Functions\!ONAME!.sql"
        type "%BASEDIR%\LOGS\_body.tmp">>"%BASEDIR%\Functions\!ONAME!.sql"
        echo go>>"%BASEDIR%\Functions\!ONAME!.sql"
        echo IF OBJECT_ID^('dbo.!ONAME!'^) IS NOT NULL>>"%BASEDIR%\Functions\!ONAME!.sql"
        echo     PRINT '^<^<^< CREATED FUNCTION dbo.!ONAME! ^>^>^>'>>"%BASEDIR%\Functions\!ONAME!.sql"
        echo ELSE>>"%BASEDIR%\Functions\!ONAME!.sql"
        echo     PRINT '^<^<^< FAILED CREATING FUNCTION dbo.!ONAME! ^>^>^>'>>"%BASEDIR%\Functions\!ONAME!.sql"
        echo go>>"%BASEDIR%\Functions\!ONAME!.sql"
        rem Grant from sysprotects
        echo set nocount on>"%BASEDIR%\LOGS\_gen.sql"
        echo if object_id^(N'##gen_gobj'^) is not null drop table ##gen_gobj>>"%BASEDIR%\LOGS\_gen.sql"
        echo go>>"%BASEDIR%\LOGS\_gen.sql"
        echo select '!ONAME!' as objname into ##gen_gobj>>"%BASEDIR%\LOGS\_gen.sql"
        echo go>>"%BASEDIR%\LOGS\_gen.sql"
        type "%SCRIPT_DIR%\gen_single_grant.sql">>"%BASEDIR%\LOGS\_gen.sql"
        isql -S %SERVER% -U %LOGIN% -P %PASSWORD% -D %DATABASE% -b -h-1 -i "%BASEDIR%\LOGS\_gen.sql" -o "%BASEDIR%\LOGS\_grants.tmp"
        type "%BASEDIR%\LOGS\_grants.tmp">>"%BASEDIR%\Functions\!ONAME!.sql"
        del "%BASEDIR%\LOGS\_grants.tmp" 2>nul
        if not errorlevel 1 set /a F_OK+=1
        set /a F_CNT+=1
        echo ###STEP###
        echo ###STEP### >> "%LOGFILE%"
    )
)
echo   Funcs: found=%F_CNT% ok=%F_OK%
echo   Funcs: found=%F_CNT% ok=%F_OK% >> "%LOGFILE%"
goto :sect_done

:: ========== TRIGGERS ==========
echo. >> "%LOGFILE%"
:export_trig
echo [4] EXPORT TRIGGERS >> "%LOGFILE%"
echo.
:export_trig
echo [4] EXPORT TRIGGERS

echo set nocount on > "%BASEDIR%\LOGS\get_trigs.sql"
echo select name from sysobjects where type='TR' and user_name(uid^)='dbo' order by name >> "%BASEDIR%\LOGS\get_trigs.sql"
echo go >> "%BASEDIR%\LOGS\get_trigs.sql"
%ISQL% -i "%BASEDIR%\LOGS\get_trigs.sql" -o "%BASEDIR%\LOGS\trigs.txt"

:: Count triggers for progress bar
for /f %%a in ('type "%BASEDIR%\LOGS\trigs.txt" 2^>nul ^| find /c /v ""') do set T_TOTAL=%%a
echo ###PHASE###Triggers^|!T_TOTAL!###
echo ###PHASE###Triggers^|!T_TOTAL!### >> "%LOGFILE%"

set T_CNT=0& set T_OK=0
for /f "tokens=*" %%i in ('type "%BASEDIR%\LOGS\trigs.txt"') do (
    set "ONAME=%%i" & set "ONAME=!ONAME: =!"
    if defined ONAME (
        echo   Exporting trig: !ONAME!
        echo set nocount on>"%BASEDIR%\LOGS\_tt.sql"
        echo select convert^(varbinary^(255^)^, text^) as hx, number, colid from syscomments where id=object_id^('!ONAME!'^) order by number, colid>>"%BASEDIR%\LOGS\_tt.sql"
        echo go>>"%BASEDIR%\LOGS\_tt.sql"
        isql -S %SERVER% -U %LOGIN% -P %PASSWORD% -D %DATABASE% -b -h-1 -w 65535 -i "%BASEDIR%\LOGS\_tt.sql" -o "%BASEDIR%\LOGS\_frags.txt"
        powershell -NoLogo -ExecutionPolicy RemoteSigned -File "%SCRIPT_DIR%\..\scripts\Rebuild-Object.ps1" -Frags "%BASEDIR%\LOGS\_frags.txt" -Out "%BASEDIR%\LOGS\_body.tmp"
        echo USE %DATABASE%>"%BASEDIR%\Triggers\!ONAME!.sql"
        echo go>>"%BASEDIR%\Triggers\!ONAME!.sql"
        echo IF OBJECT_ID^('dbo.!ONAME!'^) IS NOT NULL>>"%BASEDIR%\Triggers\!ONAME!.sql"
        echo BEGIN>>"%BASEDIR%\Triggers\!ONAME!.sql"
        echo     DROP TRIGGER dbo.!ONAME!>>"%BASEDIR%\Triggers\!ONAME!.sql"
        echo     IF OBJECT_ID^('dbo.!ONAME!'^) IS NOT NULL>>"%BASEDIR%\Triggers\!ONAME!.sql"
            echo         PRINT '^<^<^< FAILED DROPPING TRIGGER dbo.!ONAME! ^>^>^>'>>"%BASEDIR%\Triggers\!ONAME!.sql"
        echo     ELSE>>"%BASEDIR%\Triggers\!ONAME!.sql"
        echo         PRINT '^<^<^< DROPPED TRIGGER dbo.!ONAME! ^>^>^>'>>"%BASEDIR%\Triggers\!ONAME!.sql"
        echo END>>"%BASEDIR%\Triggers\!ONAME!.sql"
        echo go>>"%BASEDIR%\Triggers\!ONAME!.sql"
        type "%BASEDIR%\LOGS\_body.tmp">>"%BASEDIR%\Triggers\!ONAME!.sql"
        echo go>>"%BASEDIR%\Triggers\!ONAME!.sql"
        echo IF OBJECT_ID^('dbo.!ONAME!'^) IS NOT NULL>>"%BASEDIR%\Triggers\!ONAME!.sql"
        echo     PRINT '^<^<^< CREATED TRIGGER dbo.!ONAME! ^>^>^>'>>"%BASEDIR%\Triggers\!ONAME!.sql"
        echo ELSE>>"%BASEDIR%\Triggers\!ONAME!.sql"
        echo     PRINT '^<^<^< FAILED CREATING TRIGGER dbo.!ONAME! ^>^>^>'>>"%BASEDIR%\Triggers\!ONAME!.sql"
        echo go>>"%BASEDIR%\Triggers\!ONAME!.sql"
        if not errorlevel 1 set /a T_OK+=1
        set /a T_CNT+=1
        echo ###STEP###
        echo ###STEP### >> "%LOGFILE%"
    )
)
echo   Trigs: found=%T_CNT% ok=%T_OK%
echo   Trigs: found=%T_CNT% ok=%T_OK% >> "%LOGFILE%"
goto :sect_done

:: ========== TABLES ==========
echo. >> "%LOGFILE%"
:export_tables
echo [5] EXPORT TABLES >> "%LOGFILE%"
echo.
:export_tables
echo [5] EXPORT TABLES
echo set nocount on > "%BASEDIR%\LOGS\get_tables.sql"
echo select name from sysobjects where type='U' and user_name(uid^)='dbo' order by name >> "%BASEDIR%\LOGS\get_tables.sql"
echo go >> "%BASEDIR%\LOGS\get_tables.sql"
%ISQL% -i "%BASEDIR%\LOGS\get_tables.sql" -o "%BASEDIR%\LOGS\tables.txt"

for /f %%a in ('type "%BASEDIR%\LOGS\tables.txt" 2^>nul ^| find /c /v ""') do set T_TOTAL=%%a
echo ###PHASE###Tables^|!T_TOTAL!###
echo ###PHASE###Tables^|!T_TOTAL!### >> "%LOGFILE%"

set TB_CNT=0& set TB_OK=0
for /f "tokens=*" %%i in ('type "%BASEDIR%\LOGS\tables.txt"') do (
    set "ONAME=%%i" & set "ONAME=!ONAME: =!"
    if defined ONAME (
        echo   Exporting table: !ONAME!
        echo set nocount on > "%BASEDIR%\LOGS\_tbl.sql"
        echo if object_id^(N'##gen_tname'^) is not null drop table ##gen_tname >> "%BASEDIR%\LOGS\_tbl.sql"
        echo go >> "%BASEDIR%\LOGS\_tbl.sql"
        echo select tname = '!ONAME!' into ##gen_tname >> "%BASEDIR%\LOGS\_tbl.sql"
        echo go >> "%BASEDIR%\LOGS\_tbl.sql"
        type "%SCRIPT_DIR%\gen_create_table.sql" >> "%BASEDIR%\LOGS\_tbl.sql"
        isql -S %SERVER% -U %LOGIN% -P %PASSWORD% -D %DATABASE% -b -h-1 -i "%BASEDIR%\LOGS\_tbl.sql" -o "%BASEDIR%\Tables\!ONAME!.sql"
        if not errorlevel 1 set /a TB_OK+=1
        set /a TB_CNT+=1
        echo ###STEP###
        echo ###STEP### >> "%LOGFILE%"
    )
)
echo   Tables: found=%TB_CNT% ok=%TB_OK%
echo   Tables: found=%TB_CNT% ok=%TB_OK% >> "%LOGFILE%"
goto :sect_done

:: ========== VIEWS ==========
echo. >> "%LOGFILE%"
:export_views
echo [5a] EXPORT VIEWS >> "%LOGFILE%"
echo.
:export_views
echo [5a] EXPORT VIEWS
echo set nocount on > "%BASEDIR%\LOGS\get_views.sql"
echo select name from sysobjects where type='V' and user_name(uid^)='dbo' order by name >> "%BASEDIR%\LOGS\get_views.sql"
echo go >> "%BASEDIR%\LOGS\get_views.sql"
%ISQL% -i "%BASEDIR%\LOGS\get_views.sql" -o "%BASEDIR%\LOGS\views.txt"

for /f %%a in ('type "%BASEDIR%\LOGS\views.txt" 2^>nul ^| find /c /v ""') do set V_TOTAL=%%a
echo ###PHASE###Views^|!V_TOTAL!###
echo ###PHASE###Views^|!V_TOTAL!### >> "%LOGFILE%"

set V_CNT=0& set V_OK=0
for /f "tokens=*" %%i in ('type "%BASEDIR%\LOGS\views.txt"') do (
    set "ONAME=%%i" & set "ONAME=!ONAME: =!"
    if defined ONAME (
        echo   Exporting view: !ONAME!
        echo set nocount on>"%BASEDIR%\LOGS\_tv.sql"
        echo select convert^(varbinary^(255^)^, text^) as hx, number, colid from syscomments where id=object_id^('!ONAME!'^) order by number, colid>>"%BASEDIR%\LOGS\_tv.sql"
        echo go>>"%BASEDIR%\LOGS\_tv.sql"
        isql -S %SERVER% -U %LOGIN% -P %PASSWORD% -D %DATABASE% -b -h-1 -w 65535 -i "%BASEDIR%\LOGS\_tv.sql" -o "%BASEDIR%\LOGS\_frags.txt"
        powershell -NoLogo -ExecutionPolicy RemoteSigned -File "%SCRIPT_DIR%\..\scripts\Rebuild-Object.ps1" -Frags "%BASEDIR%\LOGS\_frags.txt" -Out "%BASEDIR%\LOGS\_body.tmp"
        echo USE %DATABASE%>"%BASEDIR%\Views\!ONAME!.sql"
        echo go>>"%BASEDIR%\Views\!ONAME!.sql"
        echo IF OBJECT_ID^('dbo.!ONAME!'^) IS NOT NULL>>"%BASEDIR%\Views\!ONAME!.sql"
        echo BEGIN>>"%BASEDIR%\Views\!ONAME!.sql"
        echo     DROP VIEW dbo.!ONAME!>>"%BASEDIR%\Views\!ONAME!.sql"
        echo     IF OBJECT_ID^('dbo.!ONAME!'^) IS NOT NULL>>"%BASEDIR%\Views\!ONAME!.sql"
        echo         PRINT '^<^<^< FAILED DROPPING VIEW dbo.!ONAME! ^>^>^>'>>"%BASEDIR%\Views\!ONAME!.sql"
        echo     ELSE>>"%BASEDIR%\Views\!ONAME!.sql"
        echo         PRINT '^<^<^< DROPPED VIEW dbo.!ONAME! ^>^>^>'>>"%BASEDIR%\Views\!ONAME!.sql"
        echo END>>"%BASEDIR%\Views\!ONAME!.sql"
        echo go>>"%BASEDIR%\Views\!ONAME!.sql"
        type "%BASEDIR%\LOGS\_body.tmp">>"%BASEDIR%\Views\!ONAME!.sql"
        echo go>>"%BASEDIR%\Views\!ONAME!.sql"
        echo IF OBJECT_ID^('dbo.!ONAME!'^) IS NOT NULL>>"%BASEDIR%\Views\!ONAME!.sql"
        echo     PRINT '^<^<^< CREATED VIEW dbo.!ONAME! ^>^>^>'>>"%BASEDIR%\Views\!ONAME!.sql"
        echo ELSE>>"%BASEDIR%\Views\!ONAME!.sql"
        echo     PRINT '^<^<^< FAILED CREATING VIEW dbo.!ONAME! ^>^>^>'>>"%BASEDIR%\Views\!ONAME!.sql"
        echo go>>"%BASEDIR%\Views\!ONAME!.sql"
        rem Grant from sysprotects
        echo set nocount on>"%BASEDIR%\LOGS\_gen.sql"
        echo if object_id^(N'##gen_gobj'^) is not null drop table ##gen_gobj>>"%BASEDIR%\LOGS\_gen.sql"
        echo go>>"%BASEDIR%\LOGS\_gen.sql"
        echo select '!ONAME!' as objname into ##gen_gobj>>"%BASEDIR%\LOGS\_gen.sql"
        echo go>>"%BASEDIR%\LOGS\_gen.sql"
        type "%SCRIPT_DIR%\gen_single_grant.sql">>"%BASEDIR%\LOGS\_gen.sql"
        isql -S %SERVER% -U %LOGIN% -P %PASSWORD% -D %DATABASE% -b -h-1 -i "%BASEDIR%\LOGS\_gen.sql" -o "%BASEDIR%\LOGS\_grants.tmp"
        type "%BASEDIR%\LOGS\_grants.tmp">>"%BASEDIR%\Views\!ONAME!.sql"
        del "%BASEDIR%\LOGS\_grants.tmp" 2>nul
        if not errorlevel 1 set /a V_OK+=1
        set /a V_CNT+=1
        echo ###STEP###
        echo ###STEP### >> "%LOGFILE%"
    )
)
echo   Views: found=%V_CNT% ok=%V_OK%
echo   Views: found=%V_CNT% ok=%V_OK% >> "%LOGFILE%"
goto :sect_done

:: ========== INDEXES ==========
echo. >> "%LOGFILE%"
:export_indexes
echo [6] EXPORT INDEXES >> "%LOGFILE%"
echo.
:export_indexes
echo [6] EXPORT INDEXES
echo ###PHASE###Indexes^|1###
echo ###PHASE###Indexes^|1### >> "%LOGFILE%"
%ISQL% -i "%SCRIPT_DIR%\gen_indexes.sql" -o "%BASEDIR%\Indexes\all_indexes.sql"
echo ###STEP###
echo ###STEP### >> "%LOGFILE%"
echo   Indexes: ok
echo   Indexes: ok >> "%LOGFILE%"
set I_OK=1& set I_CNT=1
goto :sect_done

:: ========== PRIMARY KEYS ==========
echo. >> "%LOGFILE%"
:export_pk
echo [7] EXPORT PRIMARY KEYS >> "%LOGFILE%"
echo.
:export_pk
echo [7] EXPORT PRIMARY KEYS
echo ###PHASE###PrimaryKeys^|1###
echo ###PHASE###PrimaryKeys^|1### >> "%LOGFILE%"
%ISQL% -i "%SCRIPT_DIR%\gen_pk.sql" -o "%BASEDIR%\PK\all_pk.sql"
echo ###STEP###
echo ###STEP### >> "%LOGFILE%"
echo   PK: ok
echo   PK: ok >> "%LOGFILE%"
set PK_OK=1& set PK_CNT=1
goto :sect_done

:: ========== FOREIGN KEYS ==========
echo. >> "%LOGFILE%"
:export_fk
echo [8] EXPORT FOREIGN KEYS >> "%LOGFILE%"
echo.
:export_fk
echo [8] EXPORT FOREIGN KEYS
echo ###PHASE###ForeignKeys^|1###
echo ###PHASE###ForeignKeys^|1### >> "%LOGFILE%"
%ISQL% -i "%SCRIPT_DIR%\gen_fk.sql" -o "%BASEDIR%\FK\all_fk.sql"
echo ###STEP###
echo ###STEP### >> "%LOGFILE%"
echo   FK: ok
echo   FK: ok >> "%LOGFILE%"
set FK_OK=1& set FK_CNT=1
goto :sect_done

:: ========== GRANTS ==========
echo. >> "%LOGFILE%"
:export_grants
echo [9] EXPORT GRANTS >> "%LOGFILE%"
echo.
:export_grants
echo [9] EXPORT GRANTS
echo ###PHASE###Grants^|1###
echo ###PHASE###Grants^|1### >> "%LOGFILE%"
%ISQL% -i "%SCRIPT_DIR%\gen_grants.sql" -o "%BASEDIR%\Grants\all_grants.sql"
echo ###STEP###
echo ###STEP### >> "%LOGFILE%"
echo   Grants: ok
echo   Grants: ok >> "%LOGFILE%"
set G_OK=1& set G_CNT=1
goto :sect_done

:sect_done
if defined EXPORT_ALL (goto :eof) else (goto :export_cleanup)

:export_all
set EXPORT_ALL=1
call :export_proc
call :export_func
call :export_trig
call :export_tables
call :export_views
call :export_indexes
call :export_pk
call :export_fk
call :export_grants
set EXPORT_ALL=
goto :export_cleanup

:export_cleanup
:: Cleanup temp SQL files
del "%BASEDIR%\LOGS\_tp.sql" "%BASEDIR%\LOGS\_tf.sql" "%BASEDIR%\LOGS\_tt.sql" "%BASEDIR%\LOGS\_tv.sql" "%BASEDIR%\LOGS\_tbl.sql" 2>nul
del "%BASEDIR%\LOGS\get_procs.sql" "%BASEDIR%\LOGS\get_funcs.sql" "%BASEDIR%\LOGS\get_trigs.sql" "%BASEDIR%\LOGS\get_views.sql" "%BASEDIR%\LOGS\get_tables.sql" 2>nul
del "%BASEDIR%\LOGS\test.*" 2>nul

echo Converting to UTF-8 BOM (CRLF)...
powershell -NoLogo -ExecutionPolicy RemoteSigned -File "%SCRIPT_DIR%\..\scripts\Convert-ExportEncoding.ps1" -Path "%BASEDIR%" -Extensions "*.sql"

set /a TOTAL_OK=P_OK+F_OK+T_OK+TB_OK+V_OK+I_OK+PK_OK+FK_OK+G_OK
set /a TOTAL_CNT=P_CNT+F_CNT+T_CNT+TB_CNT+V_CNT+I_CNT+PK_CNT+FK_CNT+G_CNT
set /a TOTAL_FAIL=TOTAL_CNT-TOTAL_OK

echo. >> "%LOGFILE%"
echo ============================================= >> "%LOGFILE%"
echo  EXPORT SUMMARY >> "%LOGFILE%"
echo  Task: %TASK_NAME% >> "%LOGFILE%"
echo  Found: %TOTAL_CNT%   OK: %TOTAL_OK% >> "%LOGFILE%"
echo. >> "%LOGFILE%"
echo  Procs:   %BASEDIR%\Procedure\ >> "%LOGFILE%"
echo  Funcs:   %BASEDIR%\Functions\ >> "%LOGFILE%"
echo  Trigs:   %BASEDIR%\Triggers\ >> "%LOGFILE%"
echo  Tables:  %BASEDIR%\Tables\ >> "%LOGFILE%"
echo  Views:   %BASEDIR%\Views\ >> "%LOGFILE%"
echo  Indexes: %BASEDIR%\Indexes\ >> "%LOGFILE%"
echo  PK:      %BASEDIR%\PK\ >> "%LOGFILE%"
echo  FK:      %BASEDIR%\FK\ >> "%LOGFILE%"
echo  Grants:  %BASEDIR%\Grants\ >> "%LOGFILE%"
echo  Log:     %LOGFILE% >> "%LOGFILE%"
echo ============================================= >> "%LOGFILE%"
echo  Finished: %DATE% %TIME% >> "%LOGFILE%"
echo ============================================= >> "%LOGFILE%"

echo.
echo =============================================
echo  EXPORT SUMMARY
echo  Task: %TASK_NAME%
echo  Found: %TOTAL_CNT%   OK: %TOTAL_OK%
echo.
echo  Procs:   %BASEDIR%\Procedure\
echo  Funcs:   %BASEDIR%\Functions\
echo  Trigs:   %BASEDIR%\Triggers\
echo  Tables:  %BASEDIR%\Tables\
echo  Views:   %BASEDIR%\Views\
echo  Indexes: %BASEDIR%\Indexes\
echo  PK:      %BASEDIR%\PK\
echo  FK:      %BASEDIR%\FK\
echo  Grants:  %BASEDIR%\Grants\
echo  Log:   %LOGFILE%
echo =============================================
echo  Finished: %DATE% %TIME%
echo =============================================
exit /b %TOTAL_FAIL%

:export_done
endlocal
:usage

echo Usage: %~nx0 Server Database Password TaskName [ExportPath]
echo.
echo Parameters:
echo   Server      - Sybase ASE server name (e.g. dev_golden)
echo   Database    - Database name (e.g. golden)
echo   Password    - Sybase password for login vchaga
echo   TaskName    - Jira task identifier (e.g. SYBASE-19337)
echo   ExportPath  - Optional full path for export (overrides default BD\Server\Database)
echo.
echo Example: %~nx0 dev_golden golden PASSWORD SYBASE-19337
exit /b 1
endlocal
