# 01_Install-DbaTools.ps1 - Installs the dbatools module if needed

# ===========================
# File Name: 02_Install-DbaTools.ps1
# Version: 1.0.0
# Author: Redgate Software Ltd
# Last Updated: 2025-04-23
# Description: DBA Tools Module Installation Script
# Last Update Comment:
# ===========================

# Fetch parameters from environment variables if they exist
$autoContinue = [System.Convert]::ToBoolean($env:autoContinue) 2>$null
$acceptAllDefaults = [System.Convert]::ToBoolean($env:acceptAllDefaults) 2>$null


Write-Host "INFO: Starting dbatools module check..." -ForegroundColor DarkCyan

# Check for dbatools installation
if (-not (Get-Module -ListAvailable -Name dbatools)) {
    Write-Warning "The required module 'dbatools' is not currently installed."

    $installNow = $false

    if ($autoContinue -or $acceptAllDefaults) {
        $installNow = $true
    } else {
        Write-Host "> Would you like to install dbatools now? (Y/N)" -ForegroundColor Yellow
        $response = Read-Host
        if ($response.Trim().ToUpper() -eq 'Y') {
            $installNow = $true
        }
    }

    if ($installNow) {
        try {
            Install-Module dbatools -Scope CurrentUser -AllowClobber -Force -ErrorAction Stop
            Write-Host "INFO: dbatools installed successfully." -ForegroundColor Green
        } catch {
            Write-Error "[ERROR] Failed to install dbatools. Please install it manually."
            exit 1
        }
    } else {
        Write-Warning "Skipping dbatools installation. Some functionality may be limited."
    }
} else {
    Write-Host "INFO: dbatools module already installed." -ForegroundColor Green
}
