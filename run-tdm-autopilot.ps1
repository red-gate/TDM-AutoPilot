param (
    $sqlInstance = "localhost", # The SQL Server instance to connect to (e.g., "MyServer\SQLInstance")
    $sqlUser = "", # SQL Server username (leave blank for Windows Authentication)
    $sqlPassword = "", # SQL Server password (only required if using SQL Authentication - Provide secure environment variable for added security)
    $output = "C:\temp\tdm-autopilot", # Temporary directory for log files and outputs
    $trustCert = $true, # Set to $true to trust self-signed SQL Server certificates
    $backupPath = "", # Optional: Specify a .bak file path to restore the database from a backup
    $databaseName = "Autopilot", # The target database name to be created or used
    $sampleDatabase = "", # Choose a predefined sample database setup:
                          # "Autopilot" - Standard Autopilot setup
                          # "Autopilot_Full" - Full Autopilot with all staging databases
                          # "Backup" - Use a backup file (requires -backupPath). User prompt will be given if backupPath is empty
                          # Leave blank to default to "Autopilot"
    $logLevel = "Information", # Logging verbosity level. Options:
                               # "Debug" - Most detailed logs, useful for troubleshooting
                               # "Error" - Logs only errors
                               # "Fatal" - Logs only critical failures
                               # "Information" - Standard logging (default)
                               # "Verbose" - Extra logging details for debugging
                               # "Warning" - Logs warnings and above
    [switch]$autoContinue, # Enable non-interactive mode (useful for automated pipelines)
    [switch]$skipAuth, # Skip authentication steps (Assumes user has pre-configured access. E.g offline permit)
    [switch]$noRestore, # Skip database provisioning; assumes databases already exist
    [switch]$iAgreeToTheRedgateEula # Required to acknowledge the Redgate EULA before execution
)

$installTdmClisScript = "$PSScriptRoot\Setup_Files\installTdmClis.ps1"
$helperFunctions = "$PSScriptRoot\Setup_Files\helper-functions.psm1"

# Importing helper functions
Write-Output "  Importing helper functions"
import-module $helperFunctions
$requiredFunctions = @(
    "Install-Dbatools",
    "New-SampleDatabases",
    "New-SampleDatabasesAutopilot",
    "New-SampleDatabasesAutopilotFull",
    "Restore-StagingDatabasesFromBackup"
)
# Testing that all the required functions are available
$requiredFunctions | ForEach-Object {
    if (-not (Get-Command $_ -ErrorAction SilentlyContinue)){
        Write-Error "  Error: Required function $_ not found. Please review any errors above."
        exit
    }
    else {
        Write-Output "    $_ found."
    }
}

# Configuration block based on $sampleDatabase selection
if ($sampleDatabase -eq 'Autopilot_Full') {
    $databaseName = "Autopilot"
    $sourceDb = "AutopilotProd_FullRestore"
    $targetDb = "Autopilot_Treated"
    $schemaCreateScript = "$PSScriptRoot\Setup_Files\Sample_Database_Scripts\CreateAutopilotDatabaseSchemaOnly.sql"
    $productionDataInsertScript = "$PSScriptRoot\Setup_Files\Sample_Database_Scripts\CreateAutopilotDatabaseProductionData.sql"
    $testDataInsertScript = "$PSScriptRoot\Setup_Files\Sample_Database_Scripts\CreateAutopilotDatabaseTestData.sql"
    $subsetterOptionsFile = "$PSScriptRoot\Setup_Files\Data_Treatments_Options_Files\rgsubset-options-autopilot.json"

} elseif ($sampleDatabase -eq 'Autopilot') {
    $databaseName = "Autopilot"
    $sourceDb = "AutopilotProd_FullRestore"
    $targetDb = "Autopilot_Treated"
    $schemaCreateScript = "$PSScriptRoot\Setup_Files\Sample_Database_Scripts\CreateAutopilotDatabaseSchemaOnly.sql"
    $productionDataInsertScript = "$PSScriptRoot\Setup_Files\Sample_Database_Scripts\CreateAutopilotDatabaseProductionData.sql"
    $testDataInsertScript = "$PSScriptRoot\Setup_Files\Sample_Database_Scripts\CreateAutopilotDatabaseTestData.sql"
    $subsetterOptionsFile = "$PSScriptRoot\Setup_Files\Data_Treatments_Options_Files\rgsubset-options-autopilot.json"

} elseif ((-not $sampleDatabase -and -not [string]::IsNullOrWhiteSpace($backupPath)) -or ($sampleDatabase -eq 'backup')) {
    # If backupPath is provided or sampleDatabase set to backup use Custom Backup Method
    $databaseName = "Backup"
    $sourceDb = "${databaseName}_FullRestore"
    $targetDb = "${databaseName}_Subset"
    $subsetterOptionsFile = "$PSScriptRoot\Setup_Files\Data_Treatments_Options_Files\rgsubset-options-backup.json"

    # Check if backupPath is already set
    if (-not [string]::IsNullOrWhiteSpace($backupPath)) {
        Write-Host "   Using backup path provided: $backupPath"
    }

    else {
        # Prompt user to enter backup path
        do {
            $backupPath = Get-ValidatedInput `
                -PromptMessage "Please enter the full path to the backup file (.bak)" `
                -ErrorMessage "Please enter a valid path to a .bak file"
        
            $backupPath = $backupPath.Trim('"') # Remove accidental quotes
        
        } until ($backupPath -match '\.bak$' -and (Test-Path $backupPath))
        
        if (-not (Test-Path $backupPath)) {
            Write-Error "The path you entered does not exist. Please check the path and try again."
            break
        }
        Write-Host "   Backup path set to: $backupPath"
    }

    Write-Host "   Custom source/target DBs will be: $sourceDb → $targetDb"

} else {
    # Default fallback behavior
    $databaseName = "Autopilot"
    $sourceDb = "AutopilotProd_FullRestore"
    $targetDb = "Autopilot_Treated"
    $schemaCreateScript = "$PSScriptRoot\Setup_Files\Sample_Database_Scripts\CreateAutopilotDatabaseSchemaOnly.sql"
    $productionDataInsertScript = "$PSScriptRoot\Setup_Files\Sample_Database_Scripts\CreateAutopilotDatabaseProductionData.sql"
    $testDataInsertScript = "$PSScriptRoot\Setup_Files\Sample_Database_Scripts\CreateAutopilotDatabaseTestData.sql"
    $subsetterOptionsFile = "$PSScriptRoot\Setup_Files\Data_Treatments_Options_Files\rgsubset-options-autopilot.json"
}

$winAuth = $true
$sourceConnectionString = ""
$targetConnectionString = ""
if (($sqlUser -like "") -and ($sqlPassword -like "")){    
    $sourceConnectionString = "`"server=$sqlInstance;database=$sourceDb;Trusted_Connection=yes;TrustServerCertificate=yes`""
    $targetConnectionString = "`"server=$sqlInstance;database=$targetDb;Trusted_Connection=yes;TrustServerCertificate=yes`""
}
else {
    $winAuth = $false
    $SqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $sqlUser, (ConvertTo-SecureString $sqlPassword -AsPlainText -Force)
    $sourceConnectionString = "server=$sqlInstance;database=$sourceDb;TrustServerCertificate=yes;UID=$sqlUser;Password=$sqlPassword;"
    $targetConnectionString = "server=$sqlInstance;database=$targetDb;TrustServerCertificate=yes;UID=$sqlUser;Password=$sqlPassword;"
}


Write-Output "Configuration:"
Write-Output "- sqlInstance:             $sqlInstance"
Write-Output "- databaseName:            $databaseName"
Write-Output "- sourceDb:                $sourceDb"
Write-Output "- targetDb:                $targetDb"  
if (-not [string]::IsNullOrWhiteSpace($backupPath)) {
# Don't output any script paths if a backup is provided
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
Write-Output "- installTdmClisScript:    $installTdmClisScript"
Write-Output "- helperFunctions:         $helperFunctions"
Write-Output "- subsetterOptionsFile:    $subsetterOptionsFile"
Write-Output "- Using Windows Auth:      $winAuth"
Write-Output "- sourceConnectionString:  $sourceConnectionString"
Write-Output "- targetConnectionString:  $targetConnectionString"
Write-Output "- output:                  $output"
Write-Output "- trustCert:               $trustCert"
Write-Output "- sampleDatabase:          $sampleDatabase"
Write-Output "- noRestore:               $noRestore"
Write-Output ""
Write-Output "Initial setup:"

# Detect whether running in Windows PowerShell (5.1) or PowerShell 7+ (pwsh)
$isPwsh = $PSVersionTable.PSEdition -eq "Core"

Write-Output "Detected PowerShell Edition: $($PSVersionTable.PSEdition)"

# Unblocking all files in thi repo (typically required if code is downloaded as zip)
Get-ChildItem -Path $PSScriptRoot -Recurse | Unblock-File

# Userts must agree to the Redgate Eula, either by using the -iAgreeToTheRedgateEula parameter, or by responding to a prompt
if (-not $iAgreeToTheRedgateEula){
    if ($autoContinue){
        Write-Error 'If using the -autoContinue parameter, the -iAgreeToTheRedgateEula parameter is also required.'
        break
    }
    else {
        do { $eulaResponse = Get-ValidatedInput -PromptMessage "Do you agree to the Redgate End User License Agreement (EULA)? (y/n)" -ErrorMessage "Do you agree to the Redgate End User License Agreement (EULA)? (y/n)"
             $eulaResponse = $eulaResponse.ToUpper()
            } until ($eulaResponse -match "^(Y|N)$")
    if ($eulaResponse -notlike "y") {
        Write-output 'Response not like "y". Teminating script.'
        break
        }
    }
}

# Check if dbatools is installed
if (-not (Get-Module -ListAvailable -Name dbatools)) {
    Write-Host ""
    Write-Warning "The required module 'dbatools' is not currently installed."
    Write-Host "It is needed to continue running this script."
    Write-Host ""
    Write-Host "Installing dbatools requires administrative privileges." -ForegroundColor Yellow
    if ($autoContinue){
        $installNow = "Y"
    } else {
    $installNow = Read-Host "Would you like to install it now? (Y/N)"
    }

    if ($installNow -match '^(Y|y)$') {
        try {
            # Attempt to install with elevated privileges
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
        Write-Host ""
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

if (-not $autoContinue) {
    do {
        $tdmInstallResponse = Get-ValidatedInput -PromptMessage "Do you want to install the latest version of TDM Data Treatments? (y/n)" -ErrorMessage "Do you want to install the latest version of TDM Data Treatments? Please enter Y or N"
        $tdmInstallResponse = $tdmInstallResponse.ToUpper()
    } until ($tdmInstallResponse -match "^(Y|N)$")
} else {
    $tdmInstallResponse = "y"  # Auto-set response to "y" for CI/CD pipelines
}

if ($tdmInstallResponse -like "y"){
    # Download/update rgsubset and rganonymize CLIs
    Write-Output "  Ensuring the following Redgate Test Data Manager CLIs are installed and up to date: rgsubset, rganonymize"
    powershell -File  $installTdmClisScript 
}
    if ($tdmInstallResponse -notlike "y"){
        Write-output 'Skipping TDM Data Treatments Install Step'
}

# Refreshing the environment variables so that the new path is available
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Verifying that the CLIs are both available
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

# Start trial
if (-not $skipAuth){
    Write-Output "  Authorizing rgsubset, and starting a trial (if not already started):"
    Write-Output "    rgsubset auth login --i-agree-to-the-eula --start-trial"
    rgsubset auth login --i-agree-to-the-eula --start-trial
    Write-Output "  Authorizing rganonymize:"
    Write-Output "    rganonymize auth login --i-agree-to-the-eula"
    rganonymize auth login --i-agree-to-the-eula
}

# Logging the CLI versions for reference
Write-Output ""
Write-Output "rgsubset version is:"
rgsubset --version
Write-Output "rganonymize version is:"
rganonymize --version
Write-Output ""

# Skipping restore, user has created databases
if ($noRestore){
    Write-Output "*********************************************************************************************************"
    Write-Output "Skipping database restore and creation."
    Write-Output "Please ensure that the source and target databases are already created and available on the $sqlInstance server."
    Write-Output "*********************************************************************************************************"
}
elseif ($backupPath) {
    # Using the Restore-StagingDatabasesFromBackup function in helper-functions.psm1 to build source and target databases from an existing backup
    Write-Output "  Building $sourceDb and $targetDb databases from backup file saved at $BackupPath."
    $dbCreateSuccessful = Restore-StagingDatabasesFromBackup -WinAuth:$winAuth -sqlInstance:$sqlInstance -sourceDb:$sourceDb -targetDb:$targetDb -sourceBackupPath:$backupPath -SqlCredential:$SqlCredential
    if ($dbCreateSuccessful){
        Write-Output "    Source and target databases created successfully."
    }
    else {
        Write-Error "    Error: Failed to create the source and target databases. Please review any errors above."
        break
    }
}
elseif ($sampleDatabase -eq "Autopilot_Full") {
    # Using the Build-SampleDatabases function in helper-functions.psm1, and provided sql create scripts, to build sample source and target databases
    # Used to restore ALL autopilot databases, rather than just two which is the default
    Write-Output "  Starting database creation process..."
    New-SampleDatabasesAutopilotFull -WinAuth:$winAuth -sqlInstance:$sqlInstance -sourceDb:$sourceDb -targetDb:$targetDb -schemaCreateScript:$schemaCreateScript -productionDataInsertScript:$productionDataInsertScript -testDataInsertScript:$testDataInsertScript -SqlCredential:$SqlCredential | Tee-Object -Variable dbCreateSuccessful
    if ($dbCreateSuccessful){
        Write-Host "All databases created and validated successfully." -ForegroundColor Green
    }
    else {
        Write-Error "    Error: Failed to create the source and target databases. Please review any errors above."
        break
    }
}
elseif ($sampleDatabase -eq "Autopilot") {
    # Using the Build-SampleDatabases function in helper-functions.psm1, and provided sql create scripts, to build sample source and target databases
    # Used to restore ALL autopilot databases, rather than just two which is the default
    Write-Output "  Starting database creation process..."
    New-SampleDatabasesAutopilot -WinAuth:$winAuth -sqlInstance:$sqlInstance -sourceDb:$sourceDb -targetDb:$targetDb -schemaCreateScript:$schemaCreateScript -productionDataInsertScript:$productionDataInsertScript -testDataInsertScript:$testDataInsertScript -SqlCredential:$SqlCredential | Tee-Object -Variable dbCreateSuccessful
    if ($dbCreateSuccessful){
        Write-Host "All databases created and validated successfully." -ForegroundColor Green
    }
    else {
        Write-Error "    Error: Failed to create the source and target databases. Please review any errors above."
        break
    }
}
else {
    # Default to Autopilot databases
    # Using the Build-SampleDatabases function in helper-functions.psm1, and provided sql create scripts, to build sample source and target databases
    # Used to restore ALL autopilot databases, rather than just two which is the default
    Write-Output "  Starting database creation process..."
    New-SampleDatabasesAutopilot -WinAuth:$winAuth -sqlInstance:$sqlInstance -sourceDb:$sourceDb -targetDb:$targetDb -schemaCreateScript:$schemaCreateScript -productionDataInsertScript:$productionDataInsertScript -testDataInsertScript:$testDataInsertScript -SqlCredential:$SqlCredential | Tee-Object -Variable dbCreateSuccessful
    if ($dbCreateSuccessful){
        Write-Host "All databases created and validated successfully." -ForegroundColor Green
    }
    else {
        Write-Error "    Error: Failed to create the source and target databases. Please review any errors above."
        break
    }
}

# Check if directory exists
if (Test-Path $output) {
    Write-Output "    Attempting to delete the existing output directory..."

    try {
        # Try to delete the directory
        Remove-Item -Recurse -Force $output -ErrorAction Stop | Out-Null
        Write-Host "Successfully cleaned the output directory." -ForegroundColor Green
    } 
    catch {
        # If deletion fails, show a friendly warning
        Write-Host "Skipping directory cleaning due to insufficient permissions. Consider manually cleaning '$output' if needed." -ForegroundColor Yellow
    }
}

# Create temporary log directory if not already exists
if (-not (Test-Path $output)) {
    Write-Output "    Creating a clean output directory."
    New-Item -ItemType Directory -Path $output | Out-Null
} else {
    Write-Output "    Directory already exists. Skipping creation."
}

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
    Write-Host "For example, you could run the following script in your prefered IDE:"
    Write-Host ""
    Write-Host "  USE $sourceDb" -ForegroundColor Blue  -BackgroundColor Black 
    Write-Host "  --USE $targetDb -- Uncomment to run the same query on the target database" -ForegroundColor Blue  -BackgroundColor Black
    Write-Host "  "
    Write-Host "  SELECT COUNT (*) AS TotalOrders" -ForegroundColor Blue  -BackgroundColor Black 
    Write-Host "  FROM   Sales.Orders;" -ForegroundColor Blue  -BackgroundColor Black 
    Write-Host "  "
    Write-Host "  SELECT   TOP 20 o.OrderID AS 'o.OrderId' ," -ForegroundColor Blue  -BackgroundColor Black 
    Write-Host "                  o.CustomerID AS 'o.CustomerID' ," -ForegroundColor Blue  -BackgroundColor Black 
    Write-Host "                  o.ShipAddress AS 'o.ShipAddress' ," -ForegroundColor Blue  -BackgroundColor Black 
    Write-Host "                  o.ShipCity AS 'o.ShipCity' ," -ForegroundColor Blue  -BackgroundColor Black 
    Write-Host "                  c.Address AS 'c.Address' ," -ForegroundColor Blue  -BackgroundColor Black 
    Write-Host "                  c.City AS 'c.ShipCity' ," -ForegroundColor Blue  -BackgroundColor Black 
    Write-Host "                  c.ContactName AS 'c.ContactName'" -ForegroundColor Blue  -BackgroundColor Black 
    Write-Host "  FROM     Sales.Customers c" -ForegroundColor Blue  -BackgroundColor Black 
    Write-Host "           JOIN Sales.Orders o ON o.CustomerID = c.CustomerID" -ForegroundColor Blue  -BackgroundColor Black 
    Write-Host "  ORDER BY o.OrderID ASC;" -ForegroundColor Blue  -BackgroundColor Black 
}

Write-Output ""
Write-Output "Next:"
Write-Output "We will run the following rgsubset command to copy a subset of the data from $sourceDb to $targetDb."
if ($backupPath){
    Write-Host "  rgsubset run --database-engine=sqlserver --source-connection-string=$sourceConnectionString --target-connection-string=$targetConnectionString --target-database-write-mode Overwrite" -ForegroundColor Blue  -BackgroundColor Black 
}
else {
    Write-Host "  rgsubset run --database-engine=sqlserver --source-connection-string=$sourceConnectionString --target-connection-string=$targetConnectionString --options-file `"$subsetterOptionsFile`" --target-database-write-mode Overwrite" -ForegroundColor Blue  -BackgroundColor Black 
    Write-Host "The subset will include data from the starting table, based on the options set here: $subsetterOptionsFile."
}
Write-Output "*********************************************************************************************************"
Write-Output ""

# Creating the function for Y/N prompt
if (-not $autoContinue) {
    do { $continueSubset = Get-ValidatedInput -PromptMessage "Would you like to continue? (y/n)" -ErrorMessage "Would you like to continue? (y/n)"
    $continueSubset = $continueSubset.ToUpper()
        } until ($continueSubset -match "^(Y|N)$")
    if ($continueSubset -notlike "y") {
        Write-Host 'Response not like "y". Teminating script.' -ForegroundColor Red
        break
    }
}

# Running Subset
Write-Output ""
Write-Output "Running rgsubset to copy a subset of the data from $sourceDb to $targetDb."

if ($backupPath){
    if (-not $isPwsh) {
        # Run rgsubset using standard CLI method (Windows PowerShell 5.1 or below)
        & rgsubset run `
            --database-engine=sqlserver `
            --source-connection-string="$sourceConnectionString" `
            --target-connection-string="$targetConnectionString" `
            --target-database-write-mode=Overwrite `
            --log-level $logLevel | Tee-Object -Variable rgsubsetOutput

        
         # Check for failure
        if ($LASTEXITCODE -ne 0 -or ($rgsubsetOutput -match "ERROR")) {
            throw "rgsubset failed with exit code $LASTEXITCODE."
        }
    
        Write-Host "rgsubset completed successfully" -ForegroundColor Green
    }
    else {
        # Running in PowerShell 7+ (pwsh) → Use Argument List method
        
        $arguments = @(
            'run'
            '--database-engine=sqlserver'
            "--source-connection-string=$sourceConnectionString"
            "--target-connection-string=$targetConnectionString"
            '--target-database-write-mode=Overwrite'
            "--log-level=$logLevel"
        )

        Start-Process -FilePath "rgsubset" -ArgumentList $arguments -NoNewWindow -Wait | Tee-Object -Variable rgsubsetOutput

            # Check for failure
        if ($LASTEXITCODE -ne 0 -or ($rgsubsetOutput -match "ERROR")) {
            throw "rgsubset failed with exit code $LASTEXITCODE."
        }

        Write-Host "rgsubset completed successfully" -ForegroundColor Green
    }
}
else {
    if (-not $isPwsh) {
        # Run rgsubset using standard CLI method (Windows PowerShell 5.1 or below)
        & rgsubset run `
            --database-engine=sqlserver `
            --source-connection-string="$sourceConnectionString" `
            --target-connection-string="$targetConnectionString" `
            --options-file="$subsetterOptionsFile" `
            --target-database-write-mode=Overwrite `
            --log-level $logLevel | Tee-Object -Variable rgsubsetOutput

        
         # Check for failure
        if ($LASTEXITCODE -ne 0 -or ($rgsubsetOutput -match "ERROR")) {
            throw "rgsubset failed with exit code $LASTEXITCODE."
        }
    
        Write-Host "rgsubset completed successfully" -ForegroundColor Green
    }
    else {
        # Running in PowerShell 7+ (pwsh) → Use Argument List method
        
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

            # Check for failure
        if ($LASTEXITCODE -ne 0 -or ($rgsubsetOutput -match "ERROR")) {
            throw "rgsubset failed with exit code $LASTEXITCODE."
        }

        Write-Host "rgsubset completed successfully" -ForegroundColor Green
    }
}


Write-Host ""
Write-Host "*********************************************************************************************************"
Write-Host "Observe:"
Write-Host "$targetDb should contain a subset of the data from $sourceDb."
Write-Host ""
Write-Host "Next:"
Write-Host "We will run rganonymize classify to create a classification.json file, documenting the location of any PII:"
Write-Host "  rganonymize classify --database-engine SqlServer --connection-string $targetConnectionString --classification-file `"$output\classification.json`" --output-all-columns" -ForegroundColor Blue  -BackgroundColor Black 
Write-Host "*********************************************************************************************************"
Write-Host ""

# Creating the function for Y/N prompt
if (-not $autoContinue) {
    do { $continueClassify = Get-ValidatedInput -PromptMessage "Would you like to continue? (y/n)" -ErrorMessage "Would you like to continue? (y/n)"
    $continueClassify = $continueClassify.ToUpper()
        } until ($continueClassify -match "^(Y|N)$")
    if ($continueClassify -notlike "y") {
        Write-Host 'Response not like "y". Teminating script.' -ForegroundColor Red
        break
    }
}

Write-Output "Creating a classification.json file in $output"
if (-not $isPwsh) {
        # Run rganonymize using standard CLI method
        & rganonymize classify `
        --database-engine "SqlServer" `
        --connection-string "$targetConnectionString" `
        --classification-file "$output\classification.json" `
        --output-all-columns `
        --log-level $logLevel | Tee-Object -Variable rganonymizeClassifyOutput

        if ($LASTEXITCODE -ne 0 -or ($rganonymizeClassifyOutput -match "ERROR")) {
            Write-Error "rganonymize (Classify) failed with exit code $LASTEXITCODE."
            exit $LASTEXITCODE
        }
    
        Write-Host "rganonymize (Classify) completed successfully" -ForegroundColor Green
    }
    else {
        $arguments = @(
            'classify'
            '--database-engine=sqlserver'
            "--connection-string=$targetConnectionString"
            "--classification-file=$output\classification.json"
            '--output-all-columns'
            "--log-level $logLevel"
        )
    
        Start-Process -FilePath "rganonymize" -ArgumentList $arguments -NoNewWindow -Wait | Tee-Object -Variable rganonymizeClassifyOutput

        if ($LASTEXITCODE -ne 0 -or ($rganonymizeClassifyOutput -match "ERROR")) {
            Write-Error "rganonymize (Classify) failed with exit code $LASTEXITCODE."
            exit $LASTEXITCODE
        }
        
        Write-Host "rganonymize (Classify) completed successfully" -ForegroundColor Green
    }


Write-Host ""
Write-Host "*********************************************************************************************************"
Write-Host "Observe:"
Write-Host "Review the classification.json file save at: $output"
Write-Host "This file documents any PII that has been found automatically in the $targetDb database."
Write-Host "You can tweak this file as necessary and keep it in source control to inform future masking runs."
Write-Host "You could even create CI builds that cross reference this file against your database source code,"
Write-Host "  to ensure developers always add appropriate classifications for new columns before they get"
Write-Host "  deployed to production."
Write-Host ""
Write-Host "Next:"
Write-Host "We will run the rganonymize map command to create a masking.json file, defining how the PII will be masked:"
Write-Host "  rganonymize map --classification-file `"$output\classification.json`" --masking-file `"$output\masking.json`"" -ForegroundColor Blue  -BackgroundColor Black 
Write-Host "*********************************************************************************************************"
Write-Host ""

# Creating the function for Y/N prompt
if (-not $autoContinue) {
    do { $continueMap = Get-ValidatedInput -PromptMessage "Would you like to continue? (y/n)" -ErrorMessage "Would you like to continue? (y/n)"
    $continueMap = $continueMap.ToUpper()
        } until ($continueMap -match "^(Y|N)$")
    if ($continueMap -notlike "y") {
        Write-Host 'Response not like "y". Teminating script.' -ForegroundColor Red
        break
    }
}

Write-Output "Creating a masking.json file based on contents of classification.json in $output"

if (-not $isPwsh) {
        # Run rganonymize using standard CLI method
        & rganonymize map `
        --classification-file "$output\classification.json" `
        --masking-file="$output\masking.json" `
        --log-level $logLevel | Tee-Object -Variable rganonymizeMapOutput

        if ($LASTEXITCODE -ne 0 -or ($rganonymizeMapOutput -match "ERROR")) {
            Write-Error "rganonymize (Mapping) failed with exit code $LASTEXITCODE."
            exit $LASTEXITCODE
        }
    
        Write-Host "rganonymize (Mapping) completed successfully" -ForegroundColor Green
    }
    else {
        $arguments = @(
            'map'
            "--masking-file=$output\masking.json"
            "--classification-file=$output\classification.json"
            "--log-level=$logLevel"
        )
    
        Start-Process -FilePath "rganonymize" -ArgumentList $arguments -NoNewWindow -Wait | Tee-Object -Variable rganonymizeMapOutput

        if ($LASTEXITCODE -ne 0 -or ($rganonymizeMapOutput -match "ERROR")) {
            Write-Error "rganonymize (Mapping) failed with exit code $LASTEXITCODE."
            exit $LASTEXITCODE
        }
        Write-Host "rganonymize (Mapping) completed successfully" -ForegroundColor Green
    }


Write-Host ""
Write-Host "*********************************************************************************************************"
Write-Host "Observe:"
Write-Host "Review the masking.json file save at: $output"
Write-Host "This file defines how the PII found in the $targetDb database will be masked."
Write-Host "You can save this in source control, and set up an automated masking job to"
Write-Host "  create a fresh masked copy, with the latest data, on a nightly or weekly"
Write-Host "  basis, or at an appropriate point in your sprint/release cycle."
Write-Host ""
Write-Host "Next:"
Write-Host "We will run the rganonymize mask command to mask the PII in ${targetDb}:"
Write-Host "  rganonymize mask --database-engine SqlServer --connection-string $targetConnectionString --masking-file `"$output\masking.json`"" -ForegroundColor Blue  -BackgroundColor Black 
Write-Host "*********************************************************************************************************"
Write-Host ""

# Creating the function for Y/N prompt
if (-not $autoContinue) {
    do { $continueMask = Get-ValidatedInput -PromptMessage "Would you like to continue? (y/n)" -ErrorMessage "Would you like to continue? (y/n)"
    $continueMask = $continueMask.ToUpper()
        } until ($continueMask -match "^(Y|N)$")
    if ($continueMask -notlike "y") {
        Write-Host 'Response not like "y". Teminating script.' -ForegroundColor Red
        break
    }
}

Write-Output "Masking target database, based on contents of masking.json file in $output"
if (-not $isPwsh) {
        # Run rganonymize using standard CLI method
        & rganonymize mask `
        --database-engine SqlServer `
        --connection-string "$targetConnectionString" `
        --masking-file "$output\masking.json" `
        --log-level $logLevel | Tee-Object -Variable rganonymizeMaskOutput

        if ($LASTEXITCODE -ne 0 -or ($rganonymizeMaskOutput -match "ERROR")) {
            Write-Error "rganonymize (Masking) failed with exit code $LASTEXITCODE."
            exit $LASTEXITCODE
        }

        Write-Host "rganonymize (Masking) completed successfully" -ForegroundColor Green
    }
    else {
            $arguments = @(
                'mask'
                '--database-engine=sqlserver'
                "--connection-string=$targetConnectionString"
                "--masking-file=$output\masking.json"
                "--log-level $logLevel"
            )
        
            Start-Process -FilePath "rganonymize" -ArgumentList $arguments -NoNewWindow -Wait | Tee-Object -Variable rganonymizeMaskOutput

            if ($LASTEXITCODE -ne 0 -or ($rganonymizeMaskOutput -match "ERROR")) {
                Write-Error "rganonymize (Masking) failed with exit code $LASTEXITCODE."
                exit $LASTEXITCODE
            }

            Write-Host "rganonymize (Masking) completed successfully" -ForegroundColor Green

    }

Write-Host ""
Write-Host "*********************************************************************************************************"
Write-Host "Observe:"
Write-Host "The data in the $targetDb database should now be masked."
Write-Host "Review the data in the $sourceDb and $targetDb databases. Are you happy with the way they have been subsetted and masked?"
Write-Host "Things you may like to look out for:"
Write-Host "  - Notes fields (e.g. Employees.Notes)"
Write-Host "  - Dependencies (e.g. If using the sample database, observe the Orders.ShipAddress and Customers.Address, joined on the CustomerID column in each table"
Write-Host ""
Write-Host "Additional tasks:"
Write-Host "Review both rgsubset-options.json examples in ./Setup_Files, as well as this documentation about using options files:"
Write-Host "  https://documentation.red-gate.com/testdatamanager/command-line-interface-cli/subsetting/subsetting-configuration/subsetting-configuration-file"
Write-Host "To apply a more thorough mask on the notes fields, review this documentation, and configure this project to a Lorem Ipsum"
Write-Host "  masking rule for any 'notes' fields:"
Write-Host "  - Default classifications and datasets:"
Write-Host "    https://documentation.red-gate.com/testdatamanager/command-line-interface-cli/anonymization/default-classifications-and-datasets"
Write-Host "  - Applying custom classification rules:"
Write-Host "    https://documentation.red-gate.com/testdatamanager/command-line-interface-cli/anonymization/custom-configuration/classification-rules"
Write-Host "  - Using different or custom data sets:"
Write-Host "    https://documentation.red-gate.com/testdatamanager/command-line-interface-cli/anonymization/custom-configuration/using-different-or-custom-datasets"
Write-Host ""
Write-Host "Once you have verified that all the PII has been removed, you can backup this version of"
Write-Host "  the database, and share it with your developers for dev/test purposes."
Write-Host ""
Write-Host "**************************************   FINISHED!   **************************************"
Write-Host ""
Write-Host "CONGRATULATIONS!"
Write-Host "You've completed a minimal viable Test Data Manager proof of concept."
Write-Host "Next, review the following resources:"
Write-Host "  - Documentation:  https://documentation.red-gate.com/testdatamanager/command-line-interface-cli"
Write-Host "  - Training:       https://www.red-gate.com/hub/university/courses/test-data-management/cloning/overview/introduction-to-tdm"
Write-Host "Can you subset and mask one of your own databases?"
Write-Host ""
Write-Host "Want to learn more? If you have a Redgate account manager, they can help you get started."
Write-Host "Otherwise, email us, and let's start a conversation: sales@red-gate.com"
