# 01_Install-TdmCliTools.ps1 - Ensures TDM CLI tools are installed and optionally up to date

# ===========================
# File Name: 01_Install-TDMCLI.ps1
# Version: 1.0.0
# Author: Redgate Software Ltd
# Last Updated: 2025-04-23
# Description: Validate and Install TDM Data Treatment CLIs
# Last Update Comment:
# ===========================

# === Fetch parameters from environment ===
$autoContinue        = [System.Convert]::ToBoolean($env:autoContinue) 2>$null
$acceptAllDefaults   = [System.Convert]::ToBoolean($env:acceptAllDefaults) 2>$null
$autopilotRootDir    = $env:TDM_AUTOPILOT_ROOT

Write-Host "INFO: Checking TDM CLI tool installation..." -ForegroundColor DarkCyan

# Define expected CLI tools
$expectedTools = @("rgsubset", "rganonymize")
$missingTools = @()

foreach ($tool in $expectedTools) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        $missingTools += $tool
    }
}

$installScriptPath = Join-Path $autopilotRootDir "Setup_Files\installTdmClis.ps1"

# === If all tools are installed, prompt to check for updates ===
if ($missingTools.Count -eq 0) {
    Write-Host "All required TDM CLI tools are already installed." -ForegroundColor Green

    $checkForUpdates = $false
    if ($autoContinue -or $acceptAllDefaults) {
        $checkForUpdates = $true
    } else {
        Write-Host "> Would you like to check for TDM CLI updates? (Y/N)" -ForegroundColor Yellow
        $response = Read-Host
        $cleanResponse = if ([string]::IsNullOrWhiteSpace($response)) { "Y" } else { $response.Trim().ToUpper() }
        $checkForUpdates = $cleanResponse -eq 'Y'
    }

    if ($checkForUpdates) {
        try {
            if (Test-Path $installScriptPath) {
                Write-Host "INFO: Running TDM CLI update script..." -ForegroundColor DarkCyan
                powershell -ExecutionPolicy Bypass -File $installScriptPath
                # Refresh environment variables
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            } else {
                throw "Update script not found at path: $installScriptPath"
            }
        } catch {
            Write-Error "[ERROR] Failed to update TDM CLI tools: $_"
            exit 1
        }
    }

    return
}

# === If tools are missing, prompt for installation ===
Write-Warning "The following TDM CLI tools are missing: $($missingTools -join ", ")"

$installNow = $false
if ($autoContinue -or $acceptAllDefaults) {
    $installNow = $true
} else {
    Write-Host "> Would you like to install them now? (Y/N)" -ForegroundColor Yellow
    $response = Read-Host
    $cleanResponse = if ([string]::IsNullOrWhiteSpace($response)) { "Y" } else { $response.Trim().ToUpper() }

    $installNow = $cleanResponse -eq 'Y'
}

if ($installNow) {
    try {
        if (Test-Path $installScriptPath) {
            Write-Host "INFO: Running TDM CLI install script..." -ForegroundColor DarkCyan
            powershell -ExecutionPolicy Bypass -File $installScriptPath
            Write-Host "INFO: TDM CLI tools installed successfully." -ForegroundColor Green
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        } else {
            throw "Install script not found at path: $installScriptPath"
        }
    } catch {
        Write-Error "[ERROR] Failed to install TDM CLI tools: $_"
        exit 1
    }
} else {
    Write-Warning "Skipping TDM CLI installation. Some functionality may be unavailable."
}
