# Message Type	            Color	     Usage Example
# Failure                   Red	        Write-Host "Error: XYZ"
# Success  	                Green	    Write-Host "Connected to DB"
# > Prompt / User Input	    Yellow	    Write-Host "Enter DB name:"
# CMD: Commands / Scripts	Blue	     Write-Host "Run: ..."
# INFO: Info / Status 	    DarkCyan     Write-Host "Using: sqlInstance = X"

###################################################################################################
# PARAMETERS - Update below to improve default script logic
###################################################################################################
param (
    $sqlInstance = "localhost", # SQL Server instance to connect to (e.g., "MyServer\SQLInstance")
    $sqlUser = "", # SQL Server username (blank = use Windows Authentication)
    $sqlPassword = "", # SQL Server password (required if using SQL Authentication)
    $output = "C:\temp\tdm-autopilot", # Directory to output logs and generated files
    $trustCert = $true, # Trust self-signed SQL Server certificates
    $encryptConnection = $true, # Encrypt connection to target SQL Server
    $backupPath = "", # Optional path to a .bak file for restore
    $databaseName = "Autopilot", # Name of the target database
    $sampleDatabase = "", # Type of database setup: "Autopilot", "Autopilot_Full", or "Backup"
    $logLevel = "Information", # Logging level: Debug, Verbose, Information, Warning, Error, Fatal
    $noRestore = $false, # Set to $true to skip database restore/setup (This assumes the databases already exist)
    $acceptAllDefaults = $false, # Set to $true to accept the default configuration
    [switch]$autoContinue, # Run in non-interactive mode (for pipelines)
    [switch]$skipAuth, # Skip CLI authentication (assumes already logged in)
    [switch]$iAgreeToTheRedgateEula # Required agreement to Redgate's EULA
)

###################################################################################################
# IMPORT FUNCTIONS & VALIDATE DEPENDENCIES
###################################################################################################
$installTdmClisScript = "$PSScriptRoot\Setup_Files\installTdmClis.ps1"
$helperFunctions = "$PSScriptRoot\Setup_Files\helper-functions.psm1"

Write-Output "  Importing helper functions"
import-module $helperFunctions

# === Validate Required Functions ===
$requiredFunctions = @(
    "Install-Dbatools",
    "New-SampleDatabases",
    "New-SampleDatabasesAutopilotFull",
    "Restore-StagingDatabasesFromBackup"
)
$requiredFunctions | ForEach-Object {
    if (-not (Get-Command $_ -ErrorAction SilentlyContinue)){
        Write-Error "  Error: Required function $_ not found. Please review any errors above."
        exit
    }
    else {
        Write-Output "    $_ found."
    }
}

###################################################################################################
# CONFIGURE DATABASE VARIABLES BASED ON $sampleDatabase
###################################################################################################
if ($sampleDatabase -eq 'Autopilot_Full') {
    # Full Autopilot setup with all staging DBs
    $databaseName = "Autopilot"
    $sourceDb = "AutopilotProd_FullRestore"
    $targetDb = "Autopilot_Treated"
    $schemaCreateScript = "$PSScriptRoot\Setup_Files\Sample_Database_Scripts\CreateAutopilotDatabaseSchemaOnly.sql"
    $productionDataInsertScript = "$PSScriptRoot\Setup_Files\Sample_Database_Scripts\CreateAutopilotDatabaseProductionData.sql"
    $testDataInsertScript = "$PSScriptRoot\Setup_Files\Sample_Database_Scripts\CreateAutopilotDatabaseTestData.sql"
    $subsetterOptionsFile = "$PSScriptRoot\Setup_Files\Data_Treatments_Options_Files\rgsubset-options-autopilot.json"

} elseif ($sampleDatabase -eq 'Autopilot') {
    # Standard Autopilot setup
    $databaseName = "Autopilot"
    $sourceDb = "AutopilotProd_FullRestore"
    $targetDb = "Autopilot_Treated"
    $schemaCreateScript = "$PSScriptRoot\Setup_Files\Sample_Database_Scripts\CreateAutopilotDatabaseSchemaOnly.sql"
    $productionDataInsertScript = "$PSScriptRoot\Setup_Files\Sample_Database_Scripts\CreateAutopilotDatabaseProductionData.sql"
    $testDataInsertScript = "$PSScriptRoot\Setup_Files\Sample_Database_Scripts\CreateAutopilotDatabaseTestData.sql"
    $subsetterOptionsFile = "$PSScriptRoot\Setup_Files\Data_Treatments_Options_Files\rgsubset-options-autopilot.json"

} elseif (([string]::IsNullOrWhiteSpace($sampleDatabase) -and -not [string]::IsNullOrWhiteSpace($backupPath)) -or ($sampleDatabase -eq 'backup')) {
    # Use backup file if path provided or sampleDatabase = "backup"
    $databaseName = "Backup"
    $sourceDb = "${databaseName}_FullRestore"
    $targetDb = "${databaseName}_Subset"
    $subsetterOptionsFile = "$PSScriptRoot\Setup_Files\Data_Treatments_Options_Files\rgsubset-options-backup.json"

    if (-not [string]::IsNullOrWhiteSpace($backupPath)) {
        Write-Host "INFO:   Using backup path provided: $backupPath" -ForegroundColor DarkCyan
    }
    else {
        # Prompt user for backup path if not already set
        do {
            $backupPath = Get-ValidatedInput `
                -PromptMessage "> Please enter the full path to the backup file (.bak)" `
                -ErrorMessage "> Please enter a valid path to a .bak file"
            $backupPath = $backupPath.Trim('"')
        } until ($backupPath -match '\.bak$' -and (Test-Path $backupPath))

        if (-not (Test-Path $backupPath)) {
            Write-Error "The path you entered does not exist. Please check the path and try again."
            break
        }
        Write-Host "INFO: Backup path set to: $backupPath" -ForegroundColor DarkCyan
    }

    Write-Host "INFO: Custom source/target DBs will be: $sourceDb and $targetDb" -ForegroundColor DarkCyan

} else {
    # Default fallback (Autopilot)
    $databaseName = "Autopilot"
    $sourceDb = "AutopilotProd_FullRestore"
    $targetDb = "Autopilot_Treated"
    $schemaCreateScript = "$PSScriptRoot\Setup_Files\Sample_Database_Scripts\CreateAutopilotDatabaseSchemaOnly.sql"
    $productionDataInsertScript = "$PSScriptRoot\Setup_Files\Sample_Database_Scripts\CreateAutopilotDatabaseProductionData.sql"
    $testDataInsertScript = "$PSScriptRoot\Setup_Files\Sample_Database_Scripts\CreateAutopilotDatabaseTestData.sql"
    $subsetterOptionsFile = "$PSScriptRoot\Setup_Files\Data_Treatments_Options_Files\rgsubset-options-autopilot.json"
}

###################################################################################################
# CONTINUES WITH: PowerShell Edition Detection, EULA Agreement, dbatools Install, CLI Auth...
###################################################################################################

###################################################################################################
# ENVIRONMENT SETUP AND SAFETY CHECKS
###################################################################################################

# Detect whether running in Windows PowerShell (5.1) or PowerShell 7+ (pwsh)
$isPwsh = $PSVersionTable.PSEdition -eq "Core"
Write-Host "INFO: Detected PowerShell Edition: $($PSVersionTable.PSEdition)" -ForegroundColor DarkCyan

# Unblock all files (especially required if downloaded as a zip)
Get-ChildItem -Path $PSScriptRoot -Recurse | Unblock-File

###################################################################################################
# REDGATE EULA AGREEMENT
###################################################################################################

if (-not $iAgreeToTheRedgateEula){
    if ($autoContinue){
        Write-Error 'If using the -autoContinue parameter, the -iAgreeToTheRedgateEula parameter is also required.'
        break
    }
    else {
        do {
            $eulaResponse = Get-ValidatedInput -PromptMessage "> Do you agree to the Redgate End User License Agreement (EULA)? (y/n)" -ErrorMessage "> Do you agree to the Redgate End User License Agreement (EULA)? (y/n)"
            $eulaResponse = $eulaResponse.ToUpper()
        } until ($eulaResponse -match "^(Y|N)$")
        if ($eulaResponse -notlike "y") {
            Write-output 'Response not like "y". Terminating script.'
            break
        }
    }
}

###################################################################################################
# DEFAULT VALUES CHECK
###################################################################################################

# Validate Step - Should Script Default Be Used
if (-not $autoContinue -and -not $acceptAllDefaults) {
    Write-Host "Default Configuration Detected" -ForegroundColor DarkCyan
    Write-Host "The current default values are:" -ForegroundColor DarkCyan
    Write-Host "  - Target SQL Instance:             $sqlInstance" -ForegroundColor DarkCyan
    Write-Host "  - Source Database:                 $sourceDb" -ForegroundColor DarkCyan
    Write-Host "  - Target Database:                 $targetDb" -ForegroundColor DarkCyan
    if (-not [string]::IsNullOrWhiteSpace($backupPath)) {
        Write-Host "  - Backup Path:               $backupPath" -ForegroundColor DarkCyan
    }
    Write-Host "  - Use Windows Authentication?:     $winAuth" -ForegroundColor DarkCyan
    if (-not [string]::IsNullOrWhiteSpace($sqlUser)) {
        Write-Host "  - Username:               $sqlUser" -ForegroundColor DarkCyan
    }
    Write-Host "  - Trust Server Certificate?:       $trustCert" -ForegroundColor DarkCyan
    Write-Host "  - Encrypt Connection?:             $encryptConnection" -ForegroundColor DarkCyan
    Write-Host "  - Skip Database Creation?:         $noRestore" -ForegroundColor DarkCyan
    Write-Host "" 
    Write-Host "> Would you like to accept the above configuration? (Y/N) [Default: Y]" -ForegroundColor Yellow
    $acceptAllDefaults = Read-Host
    $acceptAllDefaults = if ([string]::IsNullOrWhiteSpace($acceptAllDefaults)) { "Y" } else { $acceptAllDefaults.ToUpper() }

    if ($acceptAllDefaults -eq "Y") {
        Write-Host "Default configuration accepted" -ForegroundColor Green
        $acceptAllDefaults  = $acceptAllDefaults -eq "Y"
    } else {
        $acceptAllDefaults  = $acceptAllDefaults -eq "Y"
    }
}

###################################################################################################
# CHECK AND INSTALL dbatools MODULE IF NEEDED
###################################################################################################

if (-not (Get-Module -ListAvailable -Name dbatools)) {
    Write-Host ""
    Write-Warning "The required module 'dbatools' is not currently installed."
    Write-Host "It is needed to continue running this script."

    if ($autoContinue -or $acceptAllDefaults){
        $installNow = "Y"
    } else {
        do {
            $installNow = Get-ValidatedInput -PromptMessage "> Would you like to install it now? (Y/N)" -ErrorMessage "> Input cannot be left blank, please try again. Would you like to install it now? (Y/N)"
            $installNow = $installNow.ToUpper()
            } until ($installNow -match "^(Y|N)$")
    }

    if ($installNow -match '^(Y|y)$') {
        try {
            Install-Dbatools -autoContinue:$autoContinue -trustCert:$trustCert
            Write-Host "INFO: dbatools has been installed successfully." -ForegroundColor Green
        }
        catch {
            Write-Error "[ERROR] Failed to install dbatools. Please install it manually or run this script as Administrator."
            exit 1
        }
    }
    else {
        Write-Warning "Skipping installation of dbatools. Please ensure it is installed before continuing."
        Write-Host "INFO: You can install it manually by running:" -ForegroundColor DarkCyan
        Write-Host "CMD: Install-Module dbatools -Scope CurrentUser -AllowClobber" -ForegroundColor Blue
        do {
            $continueAnyway = Get-ValidatedInput -PromptMessage "> Would you like to continue anyway? (Y/N)" -ErrorMessage "> Input cannot be left blank, please try again. Would you like to continue anyway? (Y/N)"
            $continueAnyway = $continueAnyway.ToUpper()
            } until ($continueAnyway -match "^(Y|N)$")

        if ($continueAnyway -notmatch '^(Y|y)$') {
            Write-Host "INFO: Exiting setup. Please install dbatools and re-run the script." -ForegroundColor Yellow
            exit 1
        }
    }
}
else {
    Write-Host "dbatools module is already installed." -ForegroundColor Green
}

###################################################################################################
# AUTHENTICATION SETUP (Windows or SQL Auth)
###################################################################################################
if (-not $autoContinue -and -not $acceptAllDefaults) {
    $validInputReceived = $false
    Write-Host "INFO: The current SQL Server instance is set to: $sqlInstance" -ForegroundColor DarkCyan
    do {
        Write-Host "> Enter the SQL Server instance to connect to (press Enter to keep the current value):" -ForegroundColor Yellow
        $newSqlInstance = Read-Host

        if ($newSqlInstance -match "/") {
            Write-Host "INFO: Invalid character detected: forward slashes are not allowed in SQL Server instance names." -ForegroundColor Red
            Write-Host "INFO: Please use the format 'hostname\instance'." -ForegroundColor Yellow
        }
        else {
            $validInputReceived = $true
        }

    } until ($validInputReceived)

    if (-not [string]::IsNullOrWhiteSpace($newSqlInstance)) {
        $sqlInstance = $newSqlInstance
        Write-Host "SQL Server instance updated to: $sqlInstance" -ForegroundColor Green
    } else {
        Write-Host "Keeping the current SQL Server instance: $sqlInstance" -ForegroundColor Green
    }
}

if (-not $autoContinue -and -not $acceptAllDefaults) {
    Write-Host "INFO: Trust Server Certificate is currently set to: $trustCert" -ForegroundColor DarkCyan
    do {
        Write-Host "> Do you want to trust the SQL Server's certificate? (Y/N) [Default: Y]" -ForegroundColor Yellow
        $trustCertResponse = Read-Host
        $trustCertResponse = if ([string]::IsNullOrWhiteSpace($trustCertResponse)) { "Y" } else { $trustCertResponse.Trim().ToUpper() }
    } until ($trustCertResponse -match '^(Y|N)$')

    $trustCert = $trustCertResponse -eq "Y"
    $trustCertValue = if ($trustCert) { "yes" } else { "no" } # Sets variable to yes or no for use in the connection string logic
    Write-Host "Trust Server Certificate Set to $trustCert" -ForegroundColor Green
    Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $trustCert
}

if (-not $autoContinue -and -not $acceptAllDefaults) {
    Write-Host "INFO: Encrypt Connection is currently set to: $encryptConnection" -ForegroundColor DarkCyan
    do {
        Write-Host "> Do you want to Encrypt Connection? (Y/N) [Default: Y]" -ForegroundColor Yellow
        $encryptConnectionResponse = Read-Host
        $encryptConnectionResponse = if ([string]::IsNullOrWhiteSpace($encryptConnectionResponse)) { "Y" } else { $encryptConnectionResponse.Trim().ToUpper() }
    } until ($encryptConnectionResponse -match '^(Y|N)$')

    $encryptConnection = $encryptConnectionResponse -eq "Y"
    Write-Host "Encrypt Connection Set to $encryptConnection" -ForegroundColor Green
    Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $encryptConnection
}

if ($autoContinue -or $acceptAllDefaults) {
    Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $trustCert
    Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $encryptConnection
    $trustCertValue = if ($trustCert) { "yes" } else { "no" } # Sets variable to yes or no for use in the connection string logic
}

# === Connection String Construction ===
$sourceConnectionString = ""
$targetConnectionString = ""

# Determine if Windows Auth should be used
if ([string]::IsNullOrWhiteSpace($sqlUser) -and [string]::IsNullOrWhiteSpace($sqlPassword)) {
    if (-not $autoContinue -and -not $acceptAllDefaults) {
        Write-Host "INFO: No SQL credentials provided. Assuming Windows Authentication." -ForegroundColor DarkCyan
        Write-Host "> Do you want to proceed with Windows Authentication? (Y/N) [Default: Y]" -ForegroundColor Yellow
        $confirmWinAuth = Read-Host
        $confirmWinAuth = if ([string]::IsNullOrWhiteSpace($confirmWinAuth)) { "Y" } else { $confirmWinAuth.Trim().ToUpper() }

        if ($confirmWinAuth -ne "Y") {
            Write-Host "INFO: Windows Authentication not confirmed. Falling back to SQL Authentication..." -ForegroundColor Yellow
            $useWindowsAuth = $false
        } else {
            Write-Host "Windows Authentication Set to True" -ForegroundColor Green
            $useWindowsAuth = $true
        }
    } else {
        $useWindowsAuth = $true
    }
} else {
    $useWindowsAuth = $false
}

# === Handle authentication ===
if ($useWindowsAuth) {
    $winAuth = $true
    $sourceConnectionString = "`"server=$sqlInstance;database=$sourceDb;Trusted_Connection=yes;TrustServerCertificate=$trustCertValue`""
    $targetConnectionString = "`"server=$sqlInstance;database=$targetDb;Trusted_Connection=yes;TrustServerCertificate=$trustCertValue`""

    $sourceConnectionStringDisplay = $sourceConnectionString
    $targetConnectionStringDisplay = $targetConnectionString
}
else {
    $winAuth = $false

    if (-not $autoContinue -and -not $acceptAllDefaults -and ([string]::IsNullOrWhiteSpace($sqlUser) -or [string]::IsNullOrWhiteSpace($sqlPassword))) {
        Write-Host ""
        Write-Host "INFO:   SQL Authentication has been selected, but username and/or password are not provided." -ForegroundColor Yellow
        Write-Host "   You have two options:" -ForegroundColor Yellow
        Write-Host "     Edit 'run-tdm-autopilot.ps1' directly and set the -sqlUser and -sqlPassword parameters." -ForegroundColor DarkCyan
        Write-Host "     Enter the SQL credentials below (they will not be saved):" -ForegroundColor DarkCyan

        Write-Host "> Enter SQL username:" -ForegroundColor Yellow
        $sqlUser = Read-Host

        Write-Host "> Enter SQL password (input hidden):" -ForegroundColor Yellow
        $securePassword = Read-Host -AsSecureString
        $SqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $sqlUser, $securePassword
        $plainPassword = [System.Net.NetworkCredential]::new("", $securePassword).Password
    }
    else {
        $SqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $sqlUser, (ConvertTo-SecureString $sqlPassword -AsPlainText -Force)
        $plainPassword = $sqlPassword
    }

    $sourceConnectionString = "server=$sqlInstance;database=$sourceDb;TrustServerCertificate=$trustCertValue;UID=$sqlUser;Password=$plainPassword;"
    $targetConnectionString = "server=$sqlInstance;database=$targetDb;TrustServerCertificate=$trustCertValue;UID=$sqlUser;Password=$plainPassword;"

    # Redacted versions for logging/output only
    $sourceConnectionStringDisplay = "server=$sqlInstance;database=$sourceDb;TrustServerCertificate=$trustCertValue;UID=$sqlUser;Password=***;"
    $targetConnectionStringDisplay = "server=$sqlInstance;database=$targetDb;TrustServerCertificate=$trustCertValue;UID=$sqlUser;Password=***;"
}

###################################################################################################
# CONFIGURATION SUMMARY
###################################################################################################
if (-not $acceptAllDefaults) {
    Write-Host "Configuration:" -ForegroundColor DarkCyan
    Write-Host "  - Target SQL Instance:             $sqlInstance" -ForegroundColor DarkCyan
    Write-Host "  - Source Database:                 $sourceDb" -ForegroundColor DarkCyan
    Write-Host "  - Target Database:                 $targetDb" -ForegroundColor DarkCyan
    if (-not [string]::IsNullOrWhiteSpace($backupPath)) {
    Write-Host "  - Backup Path:                     $backupPath" -ForegroundColor DarkCyan
    }
    Write-Host "  - Use Windows Authentication?:     $winAuth" -ForegroundColor DarkCyan
    if (-not [string]::IsNullOrWhiteSpace($sqlUser)) {
    Write-Host "  - Username:                        $sqlUser" -ForegroundColor DarkCyan
    }
    Write-Host "  - Trust Server Certificate?:       $trustCert" -ForegroundColor DarkCyan
    Write-Host "  - Encrypt Connection?:             $encryptConnection" -ForegroundColor DarkCyan
    Write-Host "  - Source Connection String:        $sourceConnectionStringDisplay" -ForegroundColor DarkCyan
    Write-Host "  - Target Connection String:        $targetConnectionStringDisplay" -ForegroundColor DarkCyan
    Write-Host "  - Skip Database Creation?:         $noRestore" -ForegroundColor DarkCyan
    Write-Host "" 
}

###################################################################################################
# INSTALL / VALIDATE TDM CLI TOOLS
###################################################################################################

if (-not $autoContinue -and -not $acceptAllDefaults) {
    do {
        $tdmInstallResponse = Get-ValidatedInput -PromptMessage "> Do you want to install the latest version of TDM Data Treatments? (Y/N)" -ErrorMessage "> Please enter Y or N"
        $tdmInstallResponse = $tdmInstallResponse.ToUpper()
    } until ($tdmInstallResponse -match "^(Y|N)$")
} else {
    $tdmInstallResponse = "y"
}

if ($tdmInstallResponse -like "y") {
    Write-Host "  Ensuring Redgate CLIs rgsubset and rganonymize are installed and up to date" -ForegroundColor DarkCyan
    powershell -File $installTdmClisScript 
} else {
    Write-Host 'Skipping TDM Data Treatments Install Step' -ForegroundColor DarkCyan
}

# Refresh environment variables to include CLI path
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Check for CLI presence
$rganonymizeExe = (Get-Command rganonymize).Source
$rgsubsetExe = (Get-Command rgsubset).Source
if (-not $rganonymizeExe){
    Write-Warning "Warning: Failed to install rganonymize."
}
if (-not $rgsubsetExe) {
    Write-Warning "Warning: Failed to install rgsubset."
}
if (-not ($rganonymizeExe -and $rgsubsetExe)){
    Write-Error "Error: rgsubset and/or rganonymize CLIs not found. This script should have installed them. Please review any errors/warnings above."
    break
}

###################################################################################################
# AUTHENTICATE CLI TOOLS (unless skipped)
###################################################################################################

if (-not $skipAuth) {
    # Check for offline permit using both User and Machine scopes
    $offlinePermitPath = [Environment]::GetEnvironmentVariable("REDGATE_LICENSING_PERMIT_PATH", "User")
    if (-not $offlinePermitPath) {
        $offlinePermitPath = [Environment]::GetEnvironmentVariable("REDGATE_LICENSING_PERMIT_PATH", "Machine")
    }

    $skipBecauseOfPermit = $false

    if ($offlinePermitPath) {
        Write-Host "INFO: Offline permit detected at: $offlinePermitPath" -ForegroundColor Yellow

        if (-not $autoContinue) {
            do {
                Write-Host "> Do you want to skip online login and use the offline permit? (Y/N) [Default: Y]" -ForegroundColor Yellow
                $permitResponse = Read-Host
                $permitResponse = if ([string]::IsNullOrWhiteSpace($permitResponse)) { "Y" } else { $permitResponse.Trim().ToUpper() }
            } until ($permitResponse -match "^(Y|N)$")

            if ($permitResponse -eq "Y") {
                $skipBecauseOfPermit = $true
                Write-Host "Skipping login step and using offline permit." -ForegroundColor Green
            }
        } else {
            # Auto-skip in CI/CD if permit is found
            $skipBecauseOfPermit = $true
            Write-Host "Skipping login step and using offline permit (auto mode)." -ForegroundColor Green
        }
    }

    if (-not $skipBecauseOfPermit) {
        Write-Host "INFO:  Authorizing rgsubset, and starting a trial (if not already started):"
        Write-Host "CMD:    rgsubset auth login --i-agree-to-the-eula --start-trial" -ForegroundColor Blue
        & rgsubset auth login --i-agree-to-the-eula --start-trial

        Write-Host ""
        Write-Host "INFO:  Authorizing rganonymize:"
        Write-Host "CMD:    rganonymize auth login --i-agree-to-the-eula" -ForegroundColor Blue
        & rganonymize auth login --i-agree-to-the-eula
    }
}

# Log current CLI versions
$rgsubsetVersion = rgsubset --version
$rganonymizeVersion = rganonymize --version

Write-Host ""
Write-Host "rgsubset version is: $rgsubsetVersion" -ForegroundColor DarkCyan
Write-Host "rganonymize version is: $rganonymizeVersion" -ForegroundColor DarkCyan
Write-Host ""

###################################################################################################
# DATABASE PROVISIONING (Restore/Create/Skip)
###################################################################################################

if (-not $noRestore -and -not $autoContinue) {
    Write-Host ""
    Write-Host "INFO: Database provisioning step is about to begin." -ForegroundColor DarkCyan
    Write-Host "       This step will restore or create the following databases:" -ForegroundColor DarkCyan
    Write-Host "         $sourceDb" -ForegroundColor Blue
    Write-Host "         $targetDb" -ForegroundColor Blue
    Write-Host "       On the SQL Server instance: $sqlInstance" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "If these databases already exist (e.g. on Azure SQL or have been pre-created), you can choose to skip this step." -ForegroundColor Yellow

    do {
        Write-Host "> Do you want to create or restore the databases now? (Y/N) [Default: Y]" -ForegroundColor Yellow
        $provisionResponse = Read-Host
        $provisionResponse = if ([string]::IsNullOrWhiteSpace($provisionResponse)) { "Y" } else { $provisionResponse.Trim().ToUpper() }
    } until ($provisionResponse -match "^(Y|N)$")

    if ($provisionResponse -eq "N") {
        $noRestore = $true
        Write-Host "Skipping database provisioning. Ensure $sourceDb and $targetDb already exist on $sqlInstance." -ForegroundColor Green
    } else {
        Write-Host "Continuing with database provisioning..." -ForegroundColor Green
    }
}

if ($noRestore) {
    Write-Output "*********************************************************************************************************"
    Write-Output "Skipping database restore and creation."
    Write-Output "Ensure $sourceDb and $targetDb already exist on server: $sqlInstance"
    Write-Output "*********************************************************************************************************"
}
elseif ($backupPath) {
    # Write-Host ""
    # Write-Host "You are about to restore $sourceDb and $targetDb from a backup file located at:" -ForegroundColor Yellow
    # Write-Host "$backupPath" -ForegroundColor DarkCyan
    # if (-not $autoContinue) {
    #     do {
    #         $confirmRestore = Get-ValidatedInput -PromptMessage "> Do you want to proceed? (Y/N)" -ErrorMessage "> Please enter Y or N"
    #         $confirmRestore = $confirmRestore.ToUpper()
    #     } until ($confirmRestore -match "^(Y|N)$")
    #     if ($confirmRestore -ne "Y") {
    #         Write-Host "User opted out of database restore from backup. Exiting..." -ForegroundColor Red
    #         break
    #     }
    # }

    Write-Output "  Building $sourceDb and $targetDb from backup file at $BackupPath."
    $dbCreateSuccessful = Restore-StagingDatabasesFromBackup -WinAuth:$winAuth -sqlInstance:$sqlInstance -sourceDb:$sourceDb -targetDb:$targetDb -sourceBackupPath:$backupPath -SqlCredential:$SqlCredential
    if ($dbCreateSuccessful){
        Write-Host "Databases created successfully." -ForegroundColor Green
    } else {
        Write-Error "Error: Failed to create databases."
        break
    }
}
elseif ($sampleDatabase -eq "Autopilot_Full") {
    # Write-Host ""
    # Write-Host "INFO: You are about to create ALL Autopilot databases using predefined schema and data scripts." -ForegroundColor DarkCyan
    # Write-Host "INFO: This will create or update the Autopilot suite of databases in the target instance" -ForegroundColor DarkCyan
    # if (-not $autoContinue) {
    #     do {
    #         $confirmFullCreate = Get-ValidatedInput -PromptMessage "> Do you want to proceed with database creation? (Y/N)" -ErrorMessage "> Please enter Y or N"
    #         $confirmFullCreate = $confirmFullCreate.ToUpper()
    #     } until ($confirmFullCreate -match "^(Y|N)$")
    #     if ($confirmFullCreate -ne "Y") {
    #         Write-Host "User opted out of full Autopilot database creation. Exiting..." -ForegroundColor Red
    #         break
    #     }
    # }

    Write-Host "INFO: Starting full database creation process..."
    New-SampleDatabasesAutopilotFull -WinAuth:$winAuth -sqlInstance:$sqlInstance -sourceDb:$sourceDb -targetDb:$targetDb -schemaCreateScript:$schemaCreateScript -productionDataInsertScript:$productionDataInsertScript -testDataInsertScript:$testDataInsertScript -SqlCredential:$SqlCredential | Tee-Object -Variable dbCreateSuccessful
    if ($dbCreateSuccessful){
        Write-Host "All databases created successfully." -ForegroundColor Green
    } else {
        Write-Error "Error: Failed to create databases."
        break
    }
}
elseif ($sampleDatabase -eq "Autopilot") {
    # Write-Host ""
    # Write-Host "INFO: You are about to create standard Autopilot databases from schema and data scripts." -ForegroundColor DarkCyan
    # Write-Host "INFO: This will create or update the databases: $sourceDb and $targetDb" -ForegroundColor DarkCyan
    # if (-not $autoContinue) {
    #     do {
    #         $confirmStandardCreate = Get-ValidatedInput -PromptMessage "> Do you want to proceed with the database creation? (Y/N)" -ErrorMessage "> Please enter Y or N"
    #         $confirmStandardCreate = $confirmStandardCreate.ToUpper()
    #     } until ($confirmStandardCreate -match "^(Y|N)$")
    #     if ($confirmStandardCreate -ne "Y") {
    #         Write-Host "User opted out of standard Autopilot database creation. Exiting..." -ForegroundColor Red
    #         break
    #     }
    # }

    Write-Host "INFO: Starting sample database creation process..." -ForegroundColor DarkCyan
    New-SampleDatabasesAutopilot -WinAuth:$winAuth -sqlInstance:$sqlInstance -sourceDb:$sourceDb -targetDb:$targetDb -schemaCreateScript:$schemaCreateScript -productionDataInsertScript:$productionDataInsertScript -testDataInsertScript:$testDataInsertScript -SqlCredential:$SqlCredential | Tee-Object -Variable dbCreateSuccessful
    if ($dbCreateSuccessful){
        Write-Host "All databases created successfully." -ForegroundColor Green
    } else {
        Write-Error "Error: Failed to create databases."
        break
    }
}
else {
    # Fallback to default setup
    # Write-Host ""
    # Write-Host "INFO: You are about to create the Autopilot databases." -ForegroundColor DarkCyan
    # Write-Host "INFO: This will create or update the databases: $sourceDb and $targetDb" -ForegroundColor DarkCyan
    # if (-not $autoContinue) {
    #     do {
    #         $confirmFallbackCreate = Get-ValidatedInput -PromptMessage "> Do you want to proceed with the database creation? (y/n)" -ErrorMessage "> Please enter Y or N"
    #         $confirmFallbackCreate = $confirmFallbackCreate.ToUpper()
    #     } until ($confirmFallbackCreate -match "^(Y|N)$")
    #     if ($confirmFallbackCreate -ne "Y") {
    #         Write-Host "User opted out of default database creation. Exiting..." -ForegroundColor Red
    #         break
    #     }
    # }

    Write-Host "Starting default database creation process..." -ForegroundColor DarkCyan
    New-SampleDatabasesAutopilot -WinAuth:$winAuth -sqlInstance:$sqlInstance -sourceDb:$sourceDb -targetDb:$targetDb -schemaCreateScript:$schemaCreateScript -productionDataInsertScript:$productionDataInsertScript -testDataInsertScript:$testDataInsertScript -SqlCredential:$SqlCredential | Tee-Object -Variable dbCreateSuccessful
    if ($dbCreateSuccessful){
        Write-Host "All databases created successfully." -ForegroundColor Green
    } else {
        Write-Error "Error: Failed to create databases."
        break
    }
}

###################################################################################################
# OUTPUT FOLDER CLEANUP AND PREPARATION
###################################################################################################

###################################################################################################
# OUTPUT FOLDER CLEANUP AND PREPARATION
###################################################################################################

# Always use a timestamped subfolder for the current run
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$output = Join-Path $output $timestamp

# Try cleaning up the *parent* output folder if it exists
$parentOutput = Split-Path $output -Parent
if (Test-Path $parentOutput) {
    Write-Host "INFO: Attempting to delete existing output directory..." -ForegroundColor DarkCyan
    try {
        Remove-Item -Recurse -Force $parentOutput -ErrorAction Stop | Out-Null
        Write-Host "Successfully cleaned the output directory." -ForegroundColor Green
    } 
    catch {
        Write-Host "INFO: Skipping cleanup due to insufficient permissions. Previous subfolders may remain in '$parentOutput'" -ForegroundColor DarkCyan
    }
}

# Ensure the timestamped subfolder exists
if (-not (Test-Path $output)) {
    Write-Host "INFO: Creating output directory: $output" -ForegroundColor DarkCyan
    try {
        New-Item -ItemType Directory -Path $output -Force | Out-Null
        Write-Host "Output directory created." -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: Failed to create output directory '$output'" -ForegroundColor Red
        Write-Host "Please check permissions or specify a different path using -output." -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "INFO: Output directory already exists: $output" -ForegroundColor Yellow
}


###################################################################################################
# CONTINUES WITH: Subsetting, Classifying, Masking...
# (You’re now fully set up to proceed with CLI-based test data handling)
###################################################################################################

###################################################################################################
# OBSERVATION / VALIDATION POINT – BEFORE SUBSETTING
###################################################################################################

Write-Host ""
Write-Host "*********************************************************************************************************"
Write-Host "Observe:"
Write-Host "There should now be two databases on the $sqlInstance server: $sourceDb and $targetDb" -ForegroundColor DarkCyan
Write-Host "$sourceDb should contain some data" -ForegroundColor DarkCyan
if ($backupPath){
    Write-Host "$targetDb should be identical. In an ideal world, it would be schema identical, but empty of data." -ForegroundColor DarkCyan
}
else {
    Write-Host "$targetDb should have an identical schema, but no data"
    Write-Host ""
    Write-Host "Copy and run the below SQL in blue to validate the '$sourcedb' and '$targetDb' databases:"
    Write-Host "  USE $sourceDb" -ForegroundColor Blue  -BackgroundColor Black 
    Write-Host "  --USE $targetDb -- Uncomment to run on target" -ForegroundColor Blue  -BackgroundColor Black 
    Write-Host "  SELECT COUNT (*) AS TotalOrders FROM Sales.Orders;" -ForegroundColor Blue  -BackgroundColor Black  
    Write-Host "  SELECT TOP 20 o.OrderID, o.CustomerID, o.ShipAddress AS 'o.ShipAddress', o.ShipCity AS 'o.ShipCity', c.Address AS 'c.Address', c.City AS 'c.City', c.ContactName AS 'c.ContactName'" -ForegroundColor Blue  -BackgroundColor Black 
    Write-Host "  FROM Sales.Customers c JOIN Sales.Orders o ON o.CustomerID = c.CustomerID" -ForegroundColor Blue  -BackgroundColor Black
    Write-Host "  ORDER BY o.OrderID ASC;" -ForegroundColor Blue  -BackgroundColor Black  
}

###################################################################################################
# SUBSETTING: Run rgsubset to copy a subset of data from source → target
###################################################################################################

Write-Host ""
Write-Host "Next:" -ForegroundColor DarkCyan
Write-Host "We will run rgsubset to copy a subset of the data from $sourceDb to $targetDb." -ForegroundColor DarkCyan
Write-Host "The rgsubset CLI command can be found below in blue for reference:" -ForegroundColor DarkCyan
if ($backupPath){
    Write-Host "  rgsubset run --database-engine=sqlserver --source-connection-string=$sourceConnectionStringDisplay --target-connection-string=$targetConnectionStringDisplay --target-database-write-mode Overwrite" -ForegroundColor Blue  -BackgroundColor Black 
}
else {
    Write-Host "  rgsubset run --database-engine=sqlserver --source-connection-string=$sourceConnectionStringDisplay --target-connection-string=$targetConnectionStringDisplay --options-file `"$subsetterOptionsFile`" --target-database-write-mode Overwrite" -ForegroundColor Blue  -BackgroundColor Black 
    Write-Host "This will include only relevant tables as defined in: $subsetterOptionsFile"
}
Write-Output "*********************************************************************************************************"
Write-Output ""

# Prompt for confirmation (unless running in automated mode)
if (-not $autoContinue) {
    do {
        $continueSubset = Get-ValidatedInput -PromptMessage "> Would you like to continue? (Y/N)" -ErrorMessage "> Would you like to continue? (y/n)"
        $continueSubset = $continueSubset.ToUpper()
    } until ($continueSubset -match "^(Y|N)$")
    if ($continueSubset -notlike "y") {
        Write-Host 'Response not like "y". Terminating script.' -ForegroundColor Red
        break
    }
}

# === Run rgsubset (PowerShell 5 or pwsh) ===
Write-Output ""
Write-Output "Running rgsubset to copy data..."

if ($backupPath){
    if (-not $isPwsh) {
        & rgsubset run `
            --database-engine=sqlserver `
            --source-connection-string="$sourceConnectionString" `
            --target-connection-string="$targetConnectionString" `
            --target-database-write-mode=Overwrite `
            --log-level $logLevel | Tee-Object -Variable rgsubsetOutput
    } else {
        $arguments = @(
            'run'
            '--database-engine=sqlserver'
            "--source-connection-string=$sourceConnectionString"
            "--target-connection-string=$targetConnectionString"
            '--target-database-write-mode=Overwrite'
            "--log-level=$logLevel"
        )
        Start-Process -FilePath "rgsubset" -ArgumentList $arguments -NoNewWindow -Wait | Tee-Object -Variable rgsubsetOutput
    }
} else {
    if (-not $isPwsh) {
        & rgsubset run `
            --database-engine=sqlserver `
            --source-connection-string="$sourceConnectionString" `
            --target-connection-string="$targetConnectionString" `
            --options-file="$subsetterOptionsFile" `
            --target-database-write-mode=Overwrite `
            --log-level $logLevel | Tee-Object -Variable rgsubsetOutput
    } else {
        $arguments = @(
            'run'
            '--database-engine=sqlserver'
            "--source-connection-string=$sourceConnectionString"
            "--target-connection-string=$targetConnectionString"
            "--options-file=$subsetterOptionsFile"
            '--target-database-write-mode=Overwrite'
            "--log-level=$logLevel"
        )
        Start-Process -FilePath "rgsubset" -ArgumentList $arguments -NoNewWindow -Wait | Tee-Object -Variable rgsubsetOutput
    }
}

# Error check
if ($LASTEXITCODE -ne 0 -or ($rgsubsetOutput -match "ERROR")) {
    throw "rgsubset failed with exit code $LASTEXITCODE."
}
Write-Host "rgsubset completed successfully" -ForegroundColor Green

###################################################################################################
# CLASSIFY: Create classification.json with PII locations
###################################################################################################

Write-Host ""
Write-Host "*********************************************************************************************************"
Write-Host "Observe:" -ForegroundColor DarkCyan
Write-Host "Classification JSON will be created at $output to document discovered PII in $targetDb" -ForegroundColor DarkCyan
Write-Host "The next step uses the Classify feature of the rganonymize CLI. This detects sensitive columns in the target database." -ForegroundColor DarkCyan
Write-Host "See below for the reference CLI command:" -ForegroundColor DarkCyan
Write-Host "  rganonymize classify --database-engine SqlServer --connection-string $targetConnectionStringDisplay --classification-file `"$output\classification.json`" --output-all-columns" -ForegroundColor Blue  -BackgroundColor Black 
Write-Host "*********************************************************************************************************"
Write-Host ""

if (-not $autoContinue) {
    do {
        $continueClassify = Get-ValidatedInput -PromptMessage "> Would you like to continue? (Y/N)" -ErrorMessage "> Would you like to continue? (y/n)"
        $continueClassify = $continueClassify.ToUpper()
    } until ($continueClassify -match "^(Y|N)$")
    if ($continueClassify -notlike "y") {
        Write-Host 'Response not like "y". Terminating script.' -ForegroundColor Red
        break
    }
}

Write-Host "Creating classification.json in $output" -ForegroundColor DarkCyan

if (-not $isPwsh) {
    & rganonymize classify `
        --database-engine "SqlServer" `
        --connection-string "$targetConnectionString" `
        --classification-file "$output\classification.json" `
        --output-all-columns `
        --log-level $logLevel | Tee-Object -Variable rganonymizeClassifyOutput
} else {
    $arguments = @(
        'classify'
        '--database-engine=sqlserver'
        "--connection-string=$targetConnectionString"
        "--classification-file=$output\classification.json"
        '--output-all-columns'
        "--log-level $logLevel"
    )
    Start-Process -FilePath "rganonymize" -ArgumentList $arguments -NoNewWindow -Wait | Tee-Object -Variable rganonymizeClassifyOutput
}

if ($LASTEXITCODE -ne 0 -or ($rganonymizeClassifyOutput -match "ERROR")) {
    Write-Error "rganonymize (Classify) failed with exit code $LASTEXITCODE."
    exit $LASTEXITCODE
}
Write-Host "rganonymize (Classify) completed successfully" -ForegroundColor Green



###################################################################################################
# MAP: Create masking.json based on the classification file
###################################################################################################

Write-Host ""
Write-Host "*********************************************************************************************************"
Write-Host "Observe:" -ForegroundColor DarkCyan
Write-Host "Next step will generate a masking.json based on classification.json" -ForegroundColor DarkCyan
Write-Host "The next step uses the 'map' feature of the rganonymize CLI. This maps sensitively classified columns to a corresponding dataset." -ForegroundColor DarkCyan
Write-Host "See below for the reference CLI command in blue:" -ForegroundColor DarkCyan
Write-Host "  rganonymize map --classification-file `"$output\classification.json`" --masking-file `"$output\masking.json`"" -ForegroundColor Blue  -BackgroundColor Black 
Write-Host "*********************************************************************************************************"
Write-Host ""

if (-not $autoContinue) {
    do {
        $continueMap = Get-ValidatedInput -PromptMessage "> Would you like to continue? (Y/N)" -ErrorMessage "> Would you like to continue? (Y/N)"
        $continueMap = $continueMap.ToUpper()
    } until ($continueMap -match "^(Y|N)$")
    if ($continueMap -notlike "y") {
        Write-Host 'Response not like "y". Terminating script.' -ForegroundColor Red
        break
    }
}

Write-Output "Creating masking.json in $output"

if (-not $isPwsh) {
    & rganonymize map `
        --classification-file "$output\classification.json" `
        --masking-file="$output\masking.json" `
        --log-level $logLevel | Tee-Object -Variable rganonymizeMapOutput
} else {
    $arguments = @(
        'map'
        "--masking-file=$output\masking.json"
        "--classification-file=$output\classification.json"
        "--log-level=$logLevel"
    )
    Start-Process -FilePath "rganonymize" -ArgumentList $arguments -NoNewWindow -Wait | Tee-Object -Variable rganonymizeMapOutput
}

if ($LASTEXITCODE -ne 0 -or ($rganonymizeMapOutput -match "ERROR")) {
    Write-Error "rganonymize (Mapping) failed with exit code $LASTEXITCODE."
    exit $LASTEXITCODE
}
Write-Host "rganonymize (Mapping) completed successfully" -ForegroundColor Green

###################################################################################################
# MASK: Apply the masking.json to the target database
###################################################################################################

Write-Host ""
Write-Host "*********************************************************************************************************"
Write-Host "Observe:" -ForegroundColor DarkCyan
Write-Host "The data in $targetDb will now be masked based on masking.json" -ForegroundColor DarkCyan
Write-Host "The final step uses the 'mask' feature of the rganonymize CLI. This step puts the plan into action and masks the target databases date." -ForegroundColor DarkCyan
Write-Host "See below for the reference CLI command:" -ForegroundColor DarkCyan
Write-Host "  rganonymize mask --database-engine SqlServer --connection-string $targetConnectionStringDisplay --masking-file `"$output\masking.json`"" -ForegroundColor Blue  -BackgroundColor Black 
Write-Host "*********************************************************************************************************"
Write-Host ""

if (-not $autoContinue) {
    do {
        $continueMask = Get-ValidatedInput -PromptMessage "> Would you like to continue? (Y/N)" -ErrorMessage "> Would you like to continue? (Y/N)"
        $continueMask = $continueMask.ToUpper()
    } until ($continueMask -match "^(Y|N)$")
    if ($continueMask -notlike "y") {
        Write-Host 'Response not like "y". Terminating script.' -ForegroundColor Red
        break
    }
}

Write-Host "Applying masking to $targetDb using masking.json" -ForegroundColor DarkCyan

if (-not $isPwsh) {
    & rganonymize mask `
        --database-engine SqlServer `
        --connection-string "$targetConnectionString" `
        --masking-file "$output\masking.json" `
        --log-level $logLevel | Tee-Object -Variable rganonymizeMaskOutput
} else {
    $arguments = @(
        'mask'
        '--database-engine=sqlserver'
        "--connection-string=$targetConnectionString"
        "--masking-file=$output\masking.json"
        "--log-level $logLevel"
    )
    Start-Process -FilePath "rganonymize" -ArgumentList $arguments -NoNewWindow -Wait | Tee-Object -Variable rganonymizeMaskOutput
}

if ($LASTEXITCODE -ne 0 -or ($rganonymizeMaskOutput -match "ERROR")) {
    Write-Error "rganonymize (Masking) failed with exit code $LASTEXITCODE."
    exit $LASTEXITCODE
}
Write-Host "rganonymize (Masking) completed successfully" -ForegroundColor Green

###################################################################################################
# FINAL THOUGHTS / CALL TO ACTION
###################################################################################################

Write-Host ""
Write-Host "*********************************************************************************************************"
Write-Host "Observe:"
Write-Host "$targetDb should now be masked."
Write-Host "Compare $sourceDb and $targetDb to validate successful subsetting and masking."
Write-Host "Inspect 'notes' fields, column dependencies, and confirm that classification + masking worked as expected."
Write-Host ""
Write-Host "Next:"
Write-Host "- Review rgsubset-options.json examples in ./Setup_Files"
Write-Host "- Visit Redgate TDM docs for deeper customizations:"
Write-Host "  https://documentation.red-gate.com/testdatamanager/command-line-interface-cli"
Write-Host ""
Write-Host "Want help? Contact Redgate or email sales@red-gate.com"
Write-Host ""
Write-Host "**************************************   FINISHED!   **************************************"
Write-Host "CONGRATULATIONS! You've completed a minimal viable Test Data Manager proof of concept."
Write-Host ""

if (-not $autoContinue) {
    try {
        Write-Host ""
        Write-Host "> Press any key to exit..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    catch {
        Write-Host "> Press Enter to exit..." -ForegroundColor Yellow
        Read-Host
    }
}
