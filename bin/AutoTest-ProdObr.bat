@echo off
chcp 65001 >nul
echo ====================================
echo  PRODOBR AUTOTEST v2 (Python)
echo  %DATE% %TIME%
echo ====================================
"C:\AIS\AI\Prod\scripts\ais_objects_mcp\.venv\Scripts\python.exe" "C:\AIS\AI\Prod\scripts\AutoTest-ProdObr.py"
set EXITCODE=%errorlevel%
echo.
echo Exit: %EXITCODE%
pause
exit /b %EXITCODE%
