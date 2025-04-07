@echo off
setlocal

:: Get directory where this batch file lives, then go up one folder
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%\..") do set "PARENT_DIR=%%~fI"
set "SCRIPT_PATH=%PARENT_DIR%\run-tdm-autopilot.ps1"

:: Ask the user if they want to run as administrator
set /p runAsAdmin=Do you want to run PowerShell as administrator? - Recommended (Y/N): 

:: Trim and normalize input
set "runAsAdmin=%runAsAdmin:~0,1%"

:: Build the PowerShell argument string
set "ARG_STRING=-NoProfile -NoExit -ExecutionPolicy Bypass -File \"%SCRIPT_PATH%\" -sampleDatabase Autopilot"

if /I "%runAsAdmin%"=="Y" (
    powershell -NoProfile -Command ^
        "Start-Process PowerShell -Verb RunAs -ArgumentList '%ARG_STRING%'"
) else (
    powershell -NoProfile -Command ^
        "Start-Process PowerShell -ArgumentList '%ARG_STRING%'"
)

endlocal
