###################################################################################################
# STEP 3a: Build and Export Source/Target Connection Strings for SQL Server
###################################################################################################

# ===========================
# File Name: 03a_Create-ConnectionStrings.ps1
# Version: 1.0.0
# Author: Redgate Software Ltd
# Last Updated: 2025-04-23
# Description: TDM CLI Connection Strings Creation Script
# Last Update Comment:
# ===========================

# === VARIABLE SETUP ===
# These values are expected to come from environment variables (Ensure secure information is not outlined in plaintext)

# Whether to use Windows Authentication (true if no SQL username/password provided)
$winAuth = [string]::IsNullOrWhiteSpace($env:sqlUser) -and [string]::IsNullOrWhiteSpace($env:sqlPassword)
# Whether to trust the SQL Server's SSL certificate (affects both DbaTools and connection strings)
$trustCert = [System.Convert]::ToBoolean($env:trustCert)
# Whether to encrypt the connection to SQL Server
$encryptConnection = [System.Convert]::ToBoolean($env:encryptConnection)
# The SQL Server instance name or address
$sqlInstance = $env:sqlInstance
# The name of the source (input) database
$sourceDb = $env:sourceDb
# The name of the target (output) database
$targetDb = $env:targetDb
# SQL Authentication username (if not using Windows Authentication)
$sqlUser = $env:sqlUser
# SQL Authentication password (if not using Windows Authentication)
$sqlPassword = $env:sqlPassword

# Apply DbaTools configuration
#Write-Host "INFO: Setting Trust Server Certificate to $trustCert" -ForegroundColor DarkCyan
Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $trustCert 
#Write-Host "INFO: Setting Encrypt Connection to $encryptConnection" -ForegroundColor DarkCyan
Set-DbatoolsConfig -FullName sql.connection.encrypt    -Value $encryptConnection

# Set connection string values
$trustCertValue = if ($trustCert) { "yes" } else { "no" }
$encryptValue   = if ($encryptConnection) { "yes" } else { "no" }

if ($winAuth) {
    $sourceConn = "server=$sqlInstance;database=$sourceDb;Trusted_Connection=yes;TrustServerCertificate=$trustCertValue;Encrypt=$encryptValue"
    $targetConn = "server=$sqlInstance;database=$targetDb;Trusted_Connection=yes;TrustServerCertificate=$trustCertValue;Encrypt=$encryptValue"
} else {
    $sourceConn = "server=$sqlInstance;database=$sourceDb;UID=$sqlUser;Password=$sqlPassword;TrustServerCertificate=$trustCertValue;Encrypt=$encryptValue"
    $targetConn = "server=$sqlInstance;database=$targetDb;UID=$sqlUser;Password=$sqlPassword;TrustServerCertificate=$trustCertValue;Encrypt=$encryptValue"
}

# Export to environment for downstream steps
[System.Environment]::SetEnvironmentVariable("sourceConnectionString", $sourceConn)
[System.Environment]::SetEnvironmentVariable("targetConnectionString", $targetConn)

# Show result
Write-Host "INFO: Source and target connection strings generated." -ForegroundColor DarkCyan
