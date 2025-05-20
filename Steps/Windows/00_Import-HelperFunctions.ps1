# ===========================
# File Name: 00_Import-HelperFunctions.ps1
# Version: 1.0.1
# Author: Redgate Software Ltd
# Last Updated: 2025-05-16
# Description: Import Helper Functions into PowerShell Session
# Last Update Comment: Added confirmation message in blue on success
# ===========================

###################################################################################################
# IMPORT FUNCTIONS & VALIDATE DEPENDENCIES
###################################################################################################
# Get root directory of the project from environment (set in Run-Autopilot.ps1)
$rootDir = [System.Environment]::GetEnvironmentVariable("TDM_AUTOPILOT_ROOT")
if (-not $rootDir) {
    Write-Error "TDM_AUTOPILOT_ROOT not set. Please run via Run-Autopilot.ps1."
    exit 1
}

$helperFunctions = Join-Path $rootDir "Setup_Files\helper-functions.psm1"

Import-Module $helperFunctions

# === Validate Required Functions ===
$requiredFunctions = @(
    "Install-Dbatools",
    "New-SampleDatabases",
    "New-SampleDatabasesAutopilotFull",
    "Restore-StagingDatabasesFromBackup"
)
$requiredFunctions | ForEach-Object {
    if (-not (Get-Command $_ -ErrorAction SilentlyContinue)) {
        Write-Error "  Error: Required function $_ not found. Please review any errors above."
        exit 1
    }
}

# === Confirmation message ===
Write-Host "INFO: All helper functions successfully loaded." -ForegroundColor DarkCyan
