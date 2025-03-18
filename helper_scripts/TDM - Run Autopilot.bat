@echo off
:: Check if the script is running as an administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo This script requires administrator privileges.
    echo Please run as administrator.
    pause
    exit /b
)

:: Set the initial directory and run PowerShell as administrator
powershell -NoProfile -NoExit -Command "& {Start-Process PowerShell -ArgumentList \"-NoProfile -NoExit -ExecutionPolicy Bypass -Command `\"Set-Location -Path 'C:\Git\Demos\TDM-Autopilot'; & .\run-tdm-autopilot.ps1 -skipAuth -autopilotAllDatabases`\"\" -Verb RunAs}"