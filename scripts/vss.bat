@echo off
REM VSS Utilities - Quick access to Visual SourceSafe commands
REM Usage: vss.bat <command> [project] [comment]
REM Commands: get, status, who, checkout, checkin

setlocal

set SS_EXE="C:\Program Files (x86)\Microsoft Visual SourceSafe\ss.exe"
set SSDIR=%~1
set USERNAME=%~2
set PASSWORD=%~3
set COMMAND=%~4
set PROJECT=%~5
set COMMENT=%~6

if "%SSDIR%"=="" (
    echo Usage: vss.bat ^<SSDIR^> ^<Username^> ^<Password^> ^<Command^> [^<Project^>] [^<Comment^>]
    echo.
    echo Commands:
    echo   get      - Get latest version from VSS
    echo   status   - Check file status (Checked In/Out)
    echo   who      - Find who is using a file
    echo   checkout - Checkout file for editing
    echo   checkin  - Checkin file after editing
    echo.
    echo Example:
    echo   vss.bat "\\server\vss\srcsafe.ini" user pass get $/Project
    exit /b 1
)

set SSDIR=%SSDIR%

%SS_EXE% %COMMAND% %PROJECT% -Y%USERNAME%,%PASSWORD% -C"%COMMENT%"

endlocal
