###################################################################################################
# PARAMETERS
###################################################################################################
param (
    $sqlInstance = "localhost", # SQL Server instance to connect to (e.g., "MyServer\SQLInstance")
    $sqlUser = "", # SQL Server username (blank = use Windows Authentication)
    $sqlPassword = "", # SQL Server password (required if using SQL Authentication)
    $output = "C:\temp\tdm-autopilot", # Directory to output logs and generated files
    $trustCert = $true, # Trust self-signed SQL Server certificates
    $backupPath = "", # Optional path to a .bak file for restore
    $databaseName = "Autopilot", # Name of the target database
    $sampleDatabase = "", # Type of database setup: "Autopilot", "Autopilot_Full", or "Backup"
    $logLevel = "Information", # Logging level: Debug, Verbose, Information, Warning, Error, Fatal
    [switch]$autoContinue, # Run in non-interactive mode (for pipelines)
    [switch]$skipAuth, # Skip CLI authentication (assumes already logged in)
    [switch]$noRestore, # Skip database restore/setup (assumes they already exist)
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
        Write-Host "   Using backup path provided: $backupPath"
    }
    else {
        # Prompt user for backup path if not already set
        do {
            $backupPath = Get-ValidatedInput `
                -PromptMessage "Please enter the full path to the backup file (.bak)" `
                -ErrorMessage "Please enter a valid path to a .bak file"
            $backupPath = $backupPath.Trim('"')
        } until ($backupPath -match '\.bak$' -and (Test-Path $backupPath))

        if (-not (Test-Path $backupPath)) {
            Write-Error "The path you entered does not exist. Please check the path and try again."
            break
        }
        Write-Host "   Backup path set to: $backupPath"
    }

    Write-Host "   Custom source/target DBs will be: $sourceDb → $targetDb"

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
# AUTHENTICATION SETUP (Windows or SQL Auth)
###################################################################################################
Write-Host "The current SQL Server instance is set to: $sqlInstance" -ForegroundColor Yellow
if (-not $autoContinue) {
    $newSqlInstance = Read-Host "Enter the SQL Server instance to connect to (press Enter to keep the current value)"
    if (-not [string]::IsNullOrWhiteSpace($newSqlInstance)) {
        $sqlInstance = $newSqlInstance
        Write-Host "SQL Server instance updated to: $sqlInstance" -ForegroundColor Green
    } else {
        Write-Host "Keeping the current SQL Server instance: $sqlInstance" -ForegroundColor Green
    }
}

# === Connection String Construction ===
$winAuth = $true
$sourceConnectionString = ""
$targetConnectionString = ""
if (($sqlUser -like "") -and ($sqlPassword -like "")) {
    Write-Host "No SQL credentials provided. Assuming Windows Authentication." -ForegroundColor Yellow
    if (-not $autoContinue) {
        $confirmWinAuth = Read-Host "Do you want to proceed with Windows Authentication? (Y/N)"
        if ($confirmWinAuth -notmatch '^(Y|y)$') {
            Write-Error "Windows Authentication not confirmed. Exiting script."
            exit 1
        }
    }
    $sourceConnectionString = "`"server=$sqlInstance;database=$sourceDb;Trusted_Connection=yes;TrustServerCertificate=yes`""
    $targetConnectionString = "`"server=$sqlInstance;database=$targetDb;Trusted_Connection=yes;TrustServerCertificate=yes`""
}
else {
    $winAuth = $false
    $SqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $sqlUser, (ConvertTo-SecureString $sqlPassword -AsPlainText -Force)
    $sourceConnectionString = "server=$sqlInstance;database=$sourceDb;TrustServerCertificate=yes;UID=$sqlUser;Password=$sqlPassword;"
    $targetConnectionString = "server=$sqlInstance;database=$targetDb;TrustServerCertificate=yes;UID=$sqlUser;Password=$sqlPassword;"
}

###################################################################################################
# CONFIGURATION SUMMARY
###################################################################################################
Write-Output "Configuration:"
Write-Output "- sqlInstance:             $sqlInstance"
Write-Output "- databaseName:            $databaseName"
Write-Output "- sourceDb:                $sourceDb"
Write-Output "- targetDb:                $targetDb"  
if (-not [string]::IsNullOrWhiteSpace($backupPath)) {
    Write-Output "- backupPath:              $backupPath"
}
elseif ($sampleDatabase -eq 'Autopilot_Full' -or $sampleDatabase -eq 'Autopilot') {
    Write-Output "- schemaScript:            $schemaCreateScript"
    Write-Output "- InsertScript:            $productionDataInsertScript"
}
else {
    Write-Output "- fullRestoreCreateScript: $fullRestoreCreateScript"
    Write-Output "- subsetCreateScript:      $subsetCreateScript"
}
Write-Output "- subsetterOptionsFile:    $subsetterOptionsFile"
Write-Output "- Using Windows Auth:      $winAuth"
Write-Output "- sourceConnectionString:  $sourceConnectionString"
Write-Output "- targetConnectionString:  $targetConnectionString"
Write-Output "- output:                  $output"
Write-Output "- trustCert:               $trustCert"
Write-Output "- sampleDatabase:          $sampleDatabase"
Write-Output "- noRestore:               $noRestore"
Write-Output ""

###################################################################################################
# CONTINUES WITH: PowerShell Edition Detection, EULA Agreement, dbatools Install, CLI Auth...
###################################################################################################

###################################################################################################
# ENVIRONMENT SETUP AND SAFETY CHECKS
###################################################################################################

# Detect whether running in Windows PowerShell (5.1) or PowerShell 7+ (pwsh)
$isPwsh = $PSVersionTable.PSEdition -eq "Core"
Write-Output "Detected PowerShell Edition: $($PSVersionTable.PSEdition)"

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
            $eulaResponse = Get-ValidatedInput -PromptMessage "Do you agree to the Redgate End User License Agreement (EULA)? (y/n)" -ErrorMessage "Do you agree to the Redgate End User License Agreement (EULA)? (y/n)"
            $eulaResponse = $eulaResponse.ToUpper()
        } until ($eulaResponse -match "^(Y|N)$")
        if ($eulaResponse -notlike "y") {
            Write-output 'Response not like "y". Terminating script.'
            break
        }
    }
}

###################################################################################################
# CHECK AND INSTALL dbatools MODULE IF NEEDED
###################################################################################################

if (-not (Get-Module -ListAvailable -Name dbatools)) {
    Write-Host ""
    Write-Warning "The required module 'dbatools' is not currently installed."
    Write-Host "It is needed to continue running this script."

    if ($autoContinue){
        $installNow = "Y"
    } else {
        $installNow = Read-Host "Would you like to install it now? (Y/N)"
    }

    if ($installNow -match '^(Y|y)$') {
        try {
            Install-Dbatools -autoContinue:$autoContinue -trustCert:$trustCert
            Write-Host "dbatools has been installed successfully." -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to install dbatools. Please install it manually or run this script as Administrator."
            exit 1
        }
    }
    else {
        Write-Warning "Skipping installation of dbatools. Please ensure it is installed before continuing."
        Write-Host "You can install it manually by running:"
        Write-Host "Install-Module dbatools -Scope CurrentUser -AllowClobber" -ForegroundColor Cyan
        $continueAnyway = Read-Host "Do you want to continue anyway? (Y/N)"
        if ($continueAnyway -notmatch '^(Y|y)$') {
            Write-Host "Exiting setup. Please install dbatools and re-run the script."
            exit 1
        }
    }
}
else {
    Write-Host "dbatools module is already installed." -ForegroundColor Green
}

###################################################################################################
# INSTALL / VALIDATE TDM CLI TOOLS
###################################################################################################

if (-not $autoContinue) {
    do {
        $tdmInstallResponse = Get-ValidatedInput -PromptMessage "Do you want to install the latest version of TDM Data Treatments? (y/n)" -ErrorMessage "Please enter Y or N"
        $tdmInstallResponse = $tdmInstallResponse.ToUpper()
    } until ($tdmInstallResponse -match "^(Y|N)$")
} else {
    $tdmInstallResponse = "y"
}

if ($tdmInstallResponse -like "y") {
    Write-Output "  Ensuring Redgate CLIs rgsubset and rganonymize are installed and up to date"
    powershell -File $installTdmClisScript 
} else {
    Write-output 'Skipping TDM Data Treatments Install Step'
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

if (-not $skipAuth){
    Write-Output "  Authorizing rgsubset, and starting a trial (if not already started):"
    Write-Output "    rgsubset auth login --i-agree-to-the-eula --start-trial"
    rgsubset auth login --i-agree-to-the-eula --start-trial
    Write-Output "  Authorizing rganonymize:"
    Write-Output "    rganonymize auth login --i-agree-to-the-eula"
    rganonymize auth login --i-agree-to-the-eula
}

# Log current CLI versions
Write-Output ""
Write-Output "rgsubset version is:"
rgsubset --version
Write-Output "rganonymize version is:"
rganonymize --version
Write-Output ""

###################################################################################################
# DATABASE PROVISIONING (Restore/Create/Skip)
###################################################################################################

if ($noRestore){
    Write-Output "*********************************************************************************************************"
    Write-Output "Skipping database restore and creation."
    Write-Output "Ensure $sourceDb and $targetDb already exist on server: $sqlInstance"
    Write-Output "*********************************************************************************************************"
}
elseif ($backupPath) {
    Write-Output "  Building $sourceDb and $targetDb from backup file at $BackupPath."
    $dbCreateSuccessful = Restore-StagingDatabasesFromBackup -WinAuth:$winAuth -sqlInstance:$sqlInstance -sourceDb:$sourceDb -targetDb:$targetDb -sourceBackupPath:$backupPath -SqlCredential:$SqlCredential
    if ($dbCreateSuccessful){
        Write-Output "    Databases created successfully."
    } else {
        Write-Error "    Error: Failed to create databases."
        break
    }
}
elseif ($sampleDatabase -eq "Autopilot_Full") {
    Write-Output "  Starting full database creation process..."
    New-SampleDatabasesAutopilotFull -WinAuth:$winAuth -sqlInstance:$sqlInstance -sourceDb:$sourceDb -targetDb:$targetDb -schemaCreateScript:$schemaCreateScript -productionDataInsertScript:$productionDataInsertScript -testDataInsertScript:$testDataInsertScript -SqlCredential:$SqlCredential | Tee-Object -Variable dbCreateSuccessful
    if ($dbCreateSuccessful){
        Write-Host "All databases created successfully." -ForegroundColor Green
    } else {
        Write-Error "    Error: Failed to create databases."
        break
    }
}
elseif ($sampleDatabase -eq "Autopilot") {
    Write-Output "  Starting sample database creation process..."
    New-SampleDatabasesAutopilot -WinAuth:$winAuth -sqlInstance:$sqlInstance -sourceDb:$sourceDb -targetDb:$targetDb -schemaCreateScript:$schemaCreateScript -productionDataInsertScript:$productionDataInsertScript -testDataInsertScript:$testDataInsertScript -SqlCredential:$SqlCredential | Tee-Object -Variable dbCreateSuccessful
    if ($dbCreateSuccessful){
        Write-Host "All databases created successfully." -ForegroundColor Green
    } else {
        Write-Error "    Error: Failed to create databases."
        break
    }
}
else {
    # Fallback to default setup
    Write-Output "  Starting default database creation process..."
    New-SampleDatabasesAutopilot -WinAuth:$winAuth -sqlInstance:$sqlInstance -sourceDb:$sourceDb -targetDb:$targetDb -schemaCreateScript:$schemaCreateScript -productionDataInsertScript:$productionDataInsertScript -testDataInsertScript:$testDataInsertScript -SqlCredential:$SqlCredential | Tee-Object -Variable dbCreateSuccessful
    if ($dbCreateSuccessful){
        Write-Host "All databases created successfully." -ForegroundColor Green
    } else {
        Write-Error "    Error: Failed to create databases."
        break
    }
}

###################################################################################################
# OUTPUT FOLDER CLEANUP AND PREPARATION
###################################################################################################

if (Test-Path $output) {
    Write-Output "    Attempting to delete existing output directory..."
    try {
        Remove-Item -Recurse -Force $output -ErrorAction Stop | Out-Null
        Write-Host "Successfully cleaned the output directory." -ForegroundColor Green
    } 
    catch {
        Write-Host "Skipping cleanup due to insufficient permissions. Consider manually cleaning '$output'" -ForegroundColor Yellow
    }
}

if (-not (Test-Path $output)) {
    Write-Output "    Creating output directory."
    New-Item -ItemType Directory -Path $output | Out-Null
} else {
    Write-Output "    Output directory already exists. Skipping creation."
}

###################################################################################################
# CONTINUES WITH: Subsetting, Classifying, Masking...
# (You’re now fully set up to proceed with CLI-based test data handling)
###################################################################################################

###################################################################################################
# OBSERVATION / VALIDATION POINT – BEFORE SUBSETTING
###################################################################################################

Write-Output ""
Write-Output "*********************************************************************************************************"
Write-Output "Observe:"
Write-Output "There should now be two databases on the $sqlInstance server: $sourceDb and $targetDb"
Write-Output "$sourceDb should contain some data"
if ($backupPath){
    Write-Host "$targetDb should be identical. In an ideal world, it would be schema identical, but empty of data."
}
else {
    Write-Host "$targetDb should have an identical schema, but no data"
    Write-Host ""
    Write-Host "You can run this example query to verify:"
    Write-Host "  USE $sourceDb"
    Write-Host "  --USE $targetDb -- Uncomment to run on target"
    Write-Host "  SELECT COUNT (*) AS TotalOrders FROM Sales.Orders;"
    Write-Host "  SELECT TOP 20 o.OrderID, o.CustomerID, o.ShipAddress, o.ShipCity, c.Address, c.City, c.ContactName"
    Write-Host "  FROM Sales.Customers c JOIN Sales.Orders o ON o.CustomerID = c.CustomerID"
    Write-Host "  ORDER BY o.OrderID ASC;"
}

###################################################################################################
# SUBSETTING: Run rgsubset to copy a subset of data from source → target
###################################################################################################

Write-Output ""
Write-Output "Next:"
Write-Output "We will run rgsubset to copy a subset of the data from $sourceDb to $targetDb."
if ($backupPath){
    Write-Host "  rgsubset run --database-engine=sqlserver --source-connection-string=$sourceConnectionString --target-connection-string=$targetConnectionString --target-database-write-mode Overwrite"
}
else {
    Write-Host "  rgsubset run --database-engine=sqlserver --source-connection-string=$sourceConnectionString --target-connection-string=$targetConnectionString --options-file `"$subsetterOptionsFile`" --target-database-write-mode Overwrite"
    Write-Host "This will include only relevant tables as defined in: $subsetterOptionsFile"
}
Write-Output "*********************************************************************************************************"
Write-Output ""

# Prompt for confirmation (unless running in automated mode)
if (-not $autoContinue) {
    do {
        $continueSubset = Get-ValidatedInput -PromptMessage "Would you like to continue? (y/n)" -ErrorMessage "Would you like to continue? (y/n)"
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

Write-Output ""
Write-Output "*********************************************************************************************************"
Write-Output "Observe:"
Write-Output "Classification JSON will be created at $output to document discovered PII in $targetDb"
Write-Output "Next step will use:"
Write-Host "  rganonymize classify --database-engine SqlServer --connection-string $targetConnectionString --classification-file `"$output\classification.json`" --output-all-columns"
Write-Output "*********************************************************************************************************"
Write-Output ""

if (-not $autoContinue) {
    do {
        $continueClassify = Get-ValidatedInput -PromptMessage "Would you like to continue? (y/n)" -ErrorMessage "Would you like to continue? (y/n)"
        $continueClassify = $continueClassify.ToUpper()
    } until ($continueClassify -match "^(Y|N)$")
    if ($continueClassify -notlike "y") {
        Write-Host 'Response not like "y". Terminating script.' -ForegroundColor Red
        break
    }
}

Write-Output "Creating classification.json in $output"

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

Write-Output ""
Write-Output "*********************************************************************************************************"
Write-Output "Observe:"
Write-Output "Next step will generate a masking.json based on classification.json"
Write-Host "  rganonymize map --classification-file `"$output\classification.json`" --masking-file `"$output\masking.json`""
Write-Output "*********************************************************************************************************"
Write-Output ""

if (-not $autoContinue) {
    do {
        $continueMap = Get-ValidatedInput -PromptMessage "Would you like to continue? (y/n)" -ErrorMessage "Would you like to continue? (y/n)"
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

Write-Output ""
Write-Output "*********************************************************************************************************"
Write-Output "Observe:"
Write-Output "The data in $targetDb will now be masked based on masking.json"
Write-Host "  rganonymize mask --database-engine SqlServer --connection-string $targetConnectionString --masking-file `"$output\masking.json`""
Write-Output "*********************************************************************************************************"
Write-Output ""

if (-not $autoContinue) {
    do {
        $continueMask = Get-ValidatedInput -PromptMessage "Would you like to continue? (y/n)" -ErrorMessage "Would you like to continue? (y/n)"
        $continueMask = $continueMask.ToUpper()
    } until ($continueMask -match "^(Y|N)$")
    if ($continueMask -notlike "y") {
        Write-Host 'Response not like "y". Terminating script.' -ForegroundColor Red
        break
    }
}

Write-Output "Applying masking to $targetDb using masking.json"

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
