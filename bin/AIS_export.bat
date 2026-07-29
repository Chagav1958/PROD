@echo off
chcp 1251 >nul
setlocal EnableExtensions EnableDelayedExpansion

set "SRC=C:\SRC125\gold"
set "OUT=C:\AIS\AI\AIS\PB"
set "PBLDUMP=%~dp0pbldump-1.3.1stable\PblDump.exe"
set "LOG=%~dp0Log"
set "WORKLOG=%LOG%\work.log"
set "MIGLOG=%LOG%\gold_mig.log"
set "PS_CMD=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%SRC%\*" (
  echo [ERROR] SRC directory not found: "%SRC%"
  pause
  exit /b 1
)

if not exist "%PBLDUMP%" (
  echo [ERROR] pbldump not found: "%PBLDUMP%"
  pause
  exit /b 1
)

mkdir "%OUT%" 2>nul
mkdir "%LOG%" 2>nul

echo [%DATE% %TIME%] Start gold export > "%WORKLOG%"
echo [%DATE% %TIME%] Start gold export > "%MIGLOG%"
echo [%DATE% %TIME%] SRC=%SRC% >> "%WORKLOG%"
echo [%DATE% %TIME%] OUT=%OUT% >> "%WORKLOG%"
echo [%DATE% %TIME%] PBL=%PBLDUMP% >> "%WORKLOG%"
echo [%DATE% %TIME%] PBT_NAME=%PBT_NAME% >> "%WORKLOG%"

echo.
echo ==== 1/3. Clean previous export artifacts ====
echo [%DATE% %TIME%] 1/3. Cleaning artifacts... >> "%WORKLOG%"
"%PS_CMD%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0AIS_export.ps1" ^
  -MisRoot "%SRC%" ^
  -OutRoot "%OUT%" ^
  -LogDir "%LOG%" ^
  -CleanArtifactsOnly
if errorlevel 1 (
  echo [ERROR] Clean artifacts failed.
  exit /b 1
)
echo [%DATE% %TIME%] Clean done >> "%WORKLOG%"

echo.
echo ==== 2/3. Copy extra files (pbt, ini, cfg, ...) ====
echo [%DATE% %TIME%] 2/3. Copying extra files... >> "%WORKLOG%"
for %%E in (pbw pbt pbp pbr ini cfg txt log sql) do (
  if exist "%SRC%\*.%%E" (
    xcopy /Y /I "%SRC%\*.%%E" "%OUT%\" >> "%WORKLOG%" 2>&1
  )
)
echo [%DATE% %TIME%] Copy done >> "%WORKLOG%"

echo.
echo ==== 3/3. PBL export from LibList (%PBT_NAME%.pbt: 31 PBL + 1 PBD) ====
echo [%DATE% %TIME%] 3/3. Running pbldump (PBD will be skipped)... >> "%WORKLOG%"
echo [%DATE% %TIME%] PBT_NAME=%PBT_NAME% >> "%WORKLOG%"
"%PS_CMD%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0AIS_export.ps1" ^
  -MisRoot "%SRC%" ^
  -OutRoot "%OUT%" ^
  -PbldumpExe "%PBLDUMP%" ^
  -PbtPath "%SRC%\%PBT_NAME%.pbt" ^
  -LogDir "%LOG%"
set "EXIT_CODE=%ERRORLEVEL%"

del /f /q "%OUT%\%PBT_NAME%.pbt" 2>nul
del /f /q "%OUT%\gold_mig.log" 2>nul

echo [%DATE% %TIME%] Finish. Exit code: %EXIT_CODE% >> "%WORKLOG%"

echo.
if "%EXIT_CODE%"=="0" (
  echo ==== Done. Export successful ====
  echo Output: "%OUT%"
  echo Logs: "%LOG%"
) else (
  echo ==== Finished with errors (code: %EXIT_CODE%). See logs in "%LOG%" ====
)

endlocal
pause
