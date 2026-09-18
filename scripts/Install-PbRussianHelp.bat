@echo off
REM ============================================================
REM Install-PbRussianHelp.bat
REM Installs Russian CHM documentation for PowerBuilder 12.5
REM - Creates a backup of the current Help folder
REM - Copies Russian CHM files from C:\AIS\AI\PB\docs\chm_out
REM - Removes the search index file (.chw) - it will be rebuilt
REM
REM Usage: Install-PbRussianHelp.bat
REM
REM Rollback: Rollback-PbRussianHelp.bat
REM ============================================================

setlocal EnableExtensions

set "HELP_DIR=C:\Users\Public\Documents\Sybase\PowerBuilder 12.5\Help"
set "RU_SRC=C:\AIS\AI\PB\docs\chm_out"
set "BACKUP_ROOT=C:\AIS\AI\PB\docs"
set "LAST_BACKUP_FILE=C:\AIS\AI\Prod\scripts\PbHelp-LastBackup.txt"
set "RU_FILES=pbext125.chm pbman125.chm pbni125.chm pbtutor.chm pbusr125.chm"
set "INDEX_FILE=pbman125.chw"

REM ----- Timestamps -----
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value 2^>nul') do set "LDT=%%I"
set "STAMP=%LDT:~0,8%__%LDT:~8,6%"
set "BACKUP_DIR=%BACKUP_ROOT%\chm_en_backup_%STAMP%"

if not exist "%HELP_DIR%" (
  echo ERROR: Help directory not found: %HELP_DIR%
  exit /b 1
)
if not exist "%RU_SRC%" (
  echo ERROR: Russian source directory not found: %RU_SRC%
  exit /b 1
)
if exist "%BACKUP_DIR%" (
  echo ERROR: Backup already exists: %BACKUP_DIR%
  exit /b 1
)

REM ----- Step 1: backup current Help folder -----
echo [1/3] Creating backup: %BACKUP_DIR%
mkdir "%BACKUP_DIR%" 1>nul 2>nul
if errorlevel 1 (
  echo ERROR: cannot create backup directory.
  exit /b 1
)
xcopy "%HELP_DIR%\*.*" "%BACKUP_DIR%\" /Y /Q 1>nul 2>nul
if errorlevel 1 (
  echo ERROR: backup copy failed.
  exit /b 1
)

REM ----- Step 2: copy Russian CHM files -----
echo [2/3] Installing Russian CHM files
for %%F in (%RU_FILES%) do (
  if not exist "%RU_SRC%\%%F" (
    echo ERROR: missing Russian source file: %%F
    exit /b 1
  )
  copy /Y "%RU_SRC%\%%F" "%HELP_DIR%\%%F" 1>nul
  if errorlevel 1 (
    echo ERROR: failed to copy %%F
    exit /b 1
  )
  echo       installed %%F
)

REM ----- Step 3: remove search index (will be rebuilt) -----
echo [3/3] Removing search index: %INDEX_FILE%
if exist "%HELP_DIR%\%INDEX_FILE%" del /F /Q "%HELP_DIR%\%INDEX_FILE%"

REM ----- Write last-backup pointer -----
> "%LAST_BACKUP_FILE%" echo %BACKUP_DIR%

echo.
echo ============================================================
echo Russian documentation installed.
echo Backup: %BACKUP_DIR%
echo To rollback: Rollback-PbRussianHelp.bat
echo Restart PowerBuilder IDE and press F1.
echo ============================================================
exit /b 0
