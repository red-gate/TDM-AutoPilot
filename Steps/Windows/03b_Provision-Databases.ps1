# 03_Provision-Databases.ps1 - Restore or create databases for TDM processing

# ===========================
# File Name: 03b_Provision_Database.ps1
# Version: 1.0.0
# Author: Redgate Software Ltd
# Last Updated: 2025-04-23
# Description: Provision Autopilot database against target environment
# Last Update Comment:
# ===========================

# === Fetch Parameters from Environment Variables ===

# SQL Server instance and database names
$sqlInstance        = $env:sqlInstance
$sqlUser            = $env:sqlUser
$sqlPassword        = $env:sqlPassword
$sourceDb           = $env:sourceDb
$targetDb           = $env:targetDb

# Backup and sample database-related inputs
$autopilotRootDir         = $env:TDM_AUTOPILOT_ROOT
$backupPath               = $env:backupPath
$sampleDatabase           = $env:sampleDatabase
$schemaCreateScript       = $env:schemaCreateScript
$productionDataInsertScript = $env:productionDataInsertScript
$testDataInsertScript     = $env:testDataInsertScript

# Boolean flags (with error suppression in case of unset/invalid values)
$noRestore         = [System.Convert]::ToBoolean($env:noRestore) 2>$null   # Skip provisioning if true
$winAuth           = [System.Convert]::ToBoolean($env:winAuth) 2>$null     # Use Windows Auth if true
$autoContinue      = [System.Convert]::ToBoolean($env:autoContinue) 2>$null # Non-interactive mode
$acceptAllDefaults = [System.Convert]::ToBoolean($env:acceptAllDefaults) 2>$null # Assume default answers for prompts
# Normalize relative paths from the config if they start with '.\' or './'
function Normalize-Path {
    param (
        [string]$path
    )
    if ($path -match '^[.][\\/]' ) {
        return Join-Path $autopilotRootDir ($path -replace '^[.][\\/]', '')
    }
    return $path
}


# Apply normalization
$schemaCreateScript        = Normalize-Path $schemaCreateScript
$productionDataInsertScript = Normalize-Path $productionDataInsertScript
$testDataInsertScript      = Normalize-Path $testDataInsertScript
$subsetterOptionsFile      = Normalize-Path $subsetterOptionsFile																		  
# If noRestore is true, skip this step
if ($noRestore) {
    Write-Host "INFO: Skipping database provisioning as -noRestore is set." -ForegroundColor Yellow
    return
}

if (-not [string]::IsNullOrWhiteSpace($sqlUser)) {
    Write-Host "INFO: Utilizing SQL Auth Credentials"

    # Convert password string to SecureString
    $securePassword = ConvertTo-SecureString $sqlPassword -AsPlainText -Force

    # Create credential object
    $SqlCredential = New-Object System.Management.Automation.PSCredential ($sqlUser, $securePassword)
}

Write-Host "INFO: Beginning database provisioning..." -ForegroundColor DarkCyan

if ($backupPath) {
    Write-Host "INFO: Restoring databases from backup: $backupPath" -ForegroundColor DarkCyan
    Restore-StagingDatabasesFromBackup -WinAuth:$winAuth -sqlInstance:$sqlInstance -sourceDb:$sourceDb -targetDb:$targetDb -sourceBackupPath:$backupPath -SqlCredential:$SqlCredential
    return
}

if ($sampleDatabase -eq "Autopilot_Full") {
    Write-Host "INFO: Creating full Autopilot suite of databases..." -ForegroundColor DarkCyan
    New-SampleDatabasesAutopilotFull -WinAuth:$winAuth -sqlInstance:$sqlInstance -sourceDb:$sourceDb -targetDb:$targetDb -schemaCreateScript:$schemaCreateScript -productionDataInsertScript:$productionDataInsertScript -testDataInsertScript:$testDataInsertScript -SqlCredential:$SqlCredential
    return
}

if ($sampleDatabase -eq "Autopilot") {
    Write-Host "INFO: Creating standard Autopilot databases..." -ForegroundColor DarkCyan
    New-SampleDatabasesAutopilot -WinAuth:$winAuth -sqlInstance:$sqlInstance -sourceDb:$sourceDb -targetDb:$targetDb -schemaCreateScript:$schemaCreateScript -productionDataInsertScript:$productionDataInsertScript -testDataInsertScript:$testDataInsertScript -SqlCredential:$SqlCredential
    return
}

# Fallback generic creation
Write-Host "INFO: Creating fallback Autopilot databases..." -ForegroundColor DarkCyan
New-SampleDatabasesAutopilot -WinAuth:$winAuth -sqlInstance:$sqlInstance -sourceDb:$sourceDb -targetDb:$targetDb -schemaCreateScript:$schemaCreateScript -productionDataInsertScript:$productionDataInsertScript -testDataInsertScript:$testDataInsertScript -SqlCredential:$SqlCredential
