@echo off
chcp 1251 >nul
setlocal EnableExtensions EnableDelayedExpansion

if "%~1"=="" goto usage
if "%~2"=="" goto usage
if "%~3"=="" goto usage

set "SRC=%~1"
set "OUT=%~2"
set "PBT_NAME=%~3"

if not exist "%SRC%\*" (
  echo [ERROR] SRC directory not found: "%SRC%"
  pause
  exit /b 1
)

if not exist "%OUT%\*" (
  mkdir "%OUT%" 2>nul
)

if not exist "%~dp0pbldump-1.3.1stable\PblDump.exe" (
  echo [ERROR] pbldump not found: "%~dp0pbldump-1.3.1stable\PblDump.exe"
  pause
  exit /b 1
)

set "LOG=%~dp0Log"
set "WORKLOG=%LOG%\work.log"
set "MIGLOG=%LOG%\gold_mig.log"

echo [%DATE% %TIME%] Start export >> "%WORKLOG%"
echo [%DATE% %TIME%] Start export >> "%MIGLOG%"
echo [%DATE% %TIME%] SRC=%SRC% >> "%WORKLOG%"
echo [%DATE% %TIME%] OUT=%OUT% >> "%WORKLOG%"
echo [%DATE% %TIME%] PBT_NAME=%PBT_NAME% >> "%WORKLOG%"
echo [%DATE% %TIME%] SCRIPT_PATH=%~dp0AIS_export.ps1 >> "%WORKLOG%"
echo [%DATE% %TIME%] PBLDUMP_PATH=%~dp0pbldump-1.3.1stable\PblDump.exe >> "%WORKLOG%"

echo.
echo ==== 1/3. Clean previous export artifacts ====
echo [%DATE% %TIME%] 1/3. Cleaning artifacts... >> "%WORKLOG%"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0AIS_export.ps1" ^
  -MisRoot "%SRC%" ^
  -OutRoot "%OUT%" ^
  -PbtName "%PBT_NAME%" ^
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
echo ==== 3/3. PBL export from LibList (%PBT_NAME%.pbt) ====
echo [%DATE% %TIME%] 3/3. Running pbldump (%PBT_NAME%.pbt: 31 PBL + 1 PBD) ... >> "%WORKLOG%"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0AIS_export.ps1" ^
  -MisRoot "%SRC%" ^
  -OutRoot "%OUT%" ^
  -PblDumpExe "%~dp0pbldump-1.3.1stable\PblDump.exe" ^
  -PbtPath "%SRC%\%PBT_NAME%.pbt" ^
  -LogDir "%LOG%"

set "EXIT_CODE=%ERRORLEVEL%"

echo [%DATE% %TIME%] Finish. Exit code: %EXIT_CODE% >> "%WORKLOG%"

echo.
if "%EXIT_CODE%"=="0" (
  echo ==== Done. Export successful ====
  echo Output: "%OUT%"
  echo Logs: "%LOG%"
) else (
  echo ==== Finished with errors (code: %EXIT_CODE%). See logs in "%LOG%" ====
)

 
pause
:usage
echo Usage: Parameters to run the bat file  %~nx0  
echo 1st parameter - path to PowerBuilder libraries ( PBL )  
echo 2nd parameter - path to folder where exported PowerBuilder objects will be saved  
echo 3rd parameter - name of the *.pbt file containing the entire list of project libraries ( PBL )  
echo Example : %~nx0 C:\SRC125\gold C:\AIS\AI\AIS\PB gold 
echo , where C:\SRC125\gold - folder with PowerBuilder libraries ( PBL )  
echo          C:\AIS\AI\AIS\PB - folder where objects will be exported
 echo          gold - name of gold.pbt file containing the list of GOLD project libraries
endlocal
