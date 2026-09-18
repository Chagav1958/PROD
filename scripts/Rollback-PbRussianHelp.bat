@echo off
REM ============================================================
REM Rollback-PbRussianHelp.bat
REM Restores English CHM documentation from the latest backup.
REM
REM Usage: Rollback-PbRussianHelp.bat
REM ============================================================

setlocal EnableExtensions

set "HELP_DIR=C:\Users\Public\Documents\Sybase\PowerBuilder 12.5\Help"
set "LAST_BACKUP_FILE=C:\AIS\AI\Prod\scripts\PbHelp-LastBackup.txt"
set "BACKUP_ROOT=C:\AIS\AI\PB\docs"

REM ----- Determine backup directory -----
set "BACKUP_DIR="
if exist "%LAST_BACKUP_FILE%" (
  for /f "usebackq delims=" %%L in ("%LAST_BACKUP_FILE%") do (
    set "BACKUP_DIR=%%L"
  )
)
if not defined BACKUP_DIR (
  REM Fallback: pick the newest chm_en_backup_* folder
  for /f "delims=" %%D in ('dir /b /ad /o-n "%BACKUP_ROOT%\chm_en_backup_*" 2^>nul') do (
    if not defined BACKUP_DIR set "BACKUP_DIR=%BACKUP_ROOT%\%%D"
  )
)
if not defined BACKUP_DIR (
  echo ERROR: backup not found.
  echo Set pointer: %LAST_BACKUP_FILE% or create folder %BACKUP_ROOT%\chm_en_backup_*
  exit /b 1
)
if not exist "%BACKUP_DIR%" (
  echo ERROR: backup directory missing: %BACKUP_DIR%
  exit /b 1
)

echo Restoring English documentation from:
echo   %BACKUP_DIR%
echo into:
echo   %HELP_DIR%

xcopy "%BACKUP_DIR%\*.*" "%HELP_DIR%\" /Y /Q 1>nul 2>nul
if errorlevel 1 (
  echo ERROR: rollback copy failed.
  exit /b 1
)

echo.
echo ============================================================
echo Rollback complete. English CHM restored.
echo Restart PowerBuilder IDE and press F1.
echo ============================================================
exit /b 0
