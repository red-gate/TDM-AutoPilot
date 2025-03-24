param (
    $sqlInstance = "localhost",
    $sqlUser = "",
    $sqlPassword = "",
    $output = "C:\temp\tdm-autopilot", # Temporary location to write Autopilot log files to
    $trustCert = $true,
    $backupPath = "", # Optional - Pass in a backup file location to be used with Autopilot
    $databaseName = "Autopilot", # Set to your preferred target database name
    $sampleDatabase = "", # Set to either Autopilot/Autopilot_Full/Backup or leave blank for the default 'Autopilot' option
    [switch]$autoContinue, # Set to true to enable non-interactive mode (Valuable for pipeline automation)
    [switch]$skipAuth, # Set to true to skip the CLI authentication steps
    [switch]$noRestore, # Set to true to skip all database provisioning steps. Ensure Source and Target Database already present.
    [switch]$iAgreeToTheRedgateEula
)

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
        $backupPath = Read-Host "Please enter the full path to the backup file (.bak)"

        # Remove surrounding quotes if user included them
        $backupPath = $backupPath.Trim('"')
        
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

$installTdmClisScript = "$PSScriptRoot\Setup_Files\installTdmClis.ps1"
$helperFunctions = "$PSScriptRoot\Setup_Files\helper-functions.psm1"

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
    $sourceConnectionString = "server=$sqlInstance;database=$sourceDb;TrustServerCertificate=yes;User Id=$sqlUser;Password=$sqlPassword;"
    $targetConnectionString = "server=$sqlInstance;database=$targetDb;TrustServerCertificate=yes;User Id=$sqlUser;Password=$sqlPassword;"
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

# Unblocking all files in thi repo (typically required if code is downloaded as zip)
Get-ChildItem -Path $PSScriptRoot -Recurse | Unblock-File

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

# Clean output directory
Write-Output "    Cleaning the output directory at: $output"
if (Test-Path $output){
    Write-Output "    Recursively deleting the existing output directory, and any files from previous runs."
    Remove-Item -Recurse -Force $output | Out-Null
}
Write-Output "    Creating a clean output directory."
New-Item -ItemType Directory -Path $output | Out-Null

Write-Output ""
Write-Output "*********************************************************************************************************"
Write-Output "Observe:"
Write-Output "There should now be two databases on the $sqlInstance server: $sourceDb and $targetDb"
Write-Output "$sourceDb should contain some data"
if ($backupPath){
    Write-Output "$targetDb should be identical. In an ideal world, it would be schema identical, but empty of data."
}
else {
    Write-Output "$targetDb should have an identical schema, but no data"
    Write-Output ""
    Write-Output "For example, you could run the following script in your prefered IDE:"
    Write-Output ""
    Write-Output "  USE $sourceDb"
    Write-Output "  --USE $targetDb -- Uncomment to run the same query on the target database"
    Write-Output "  "
    Write-Output "  SELECT COUNT (*) AS TotalOrders"
    Write-Output "  FROM   Sales.Orders;"
    Write-Output "  "
    Write-Output "  SELECT   TOP 20 o.OrderID AS 'o.OrderId' ,"
    Write-Output "                  o.CustomerID AS 'o.CustomerID' ,"
    Write-Output "                  o.ShipAddress AS 'o.ShipAddress' ,"
    Write-Output "                  o.ShipCity AS 'o.ShipCity' ,"
    Write-Output "                  c.Address AS 'c.Address' ,"
    Write-Output "                  c.City AS 'c.ShipCity' ,"
    Write-Output "                  c.ContactName AS 'c.ContactName'"
    Write-Output "  FROM     Sales.Customers c"
    Write-Output "           JOIN Sales.Orders o ON o.CustomerID = c.CustomerID"
    Write-Output "  ORDER BY o.OrderID ASC;"
}

Write-Output ""
Write-Output "Next:"
Write-Output "We will run the following rgsubset command to copy a subset of the data from $sourceDb to $targetDb."
if ($backupPath){
    Write-Output "  rgsubset run --database-engine=sqlserver --source-connection-string=$sourceConnectionString --target-connection-string=$targetConnectionString --target-database-write-mode Overwrite"
}
else {
    Write-Output "  rgsubset run --database-engine=sqlserver --source-connection-string=$sourceConnectionString --target-connection-string=$targetConnectionString --options-file `"$subsetterOptionsFile`" --target-database-write-mode Overwrite"
    Write-Output "The subset will include data from the starting table, based on the options set here: $subsetterOptionsFile."
}
Write-Output "*********************************************************************************************************"
Write-Output ""

# Creating the function for Y/N prompt

function Prompt-Continue {

    if ($autoContinue) {
        Write-Output 'Auto-continue mode enabled. Proceeding without user input.'
    } else {
        $continueLoop = $true

        while ($continueLoop) {
            $continue = Read-Host "Continue? (y/n)"
            switch ($continue.ToLower()) {
                "y" { Write-Verbose 'User chose to continue.'; $continueLoop = $false }
                "n" { Write-Output 'User chose "n". Terminating script.'; exit }
                default { Write-Output 'Invalid response. Please enter "y" or "n".' }
            }
        }
    }
}


Prompt-Continue

# running subset
Write-Output ""
Write-Output "Running rgsubset to copy a subset of the data from $sourceDb to $targetDb."
if ($backupPath){
    rgsubset run --database-engine=sqlserver --source-connection-string="$sourceConnectionString" --target-connection-string="$targetConnectionString" --target-database-write-mode Overwrite
}
else {
    rgsubset run --database-engine="sqlserver" --source-connection-string="$sourceConnectionString" --target-connection-string="$targetConnectionString" --options-file="$subsetterOptionsFile" --target-database-write-mode=Overwrite
}


Write-Output ""
Write-Output "*********************************************************************************************************"
Write-Output "Observe:"
Write-Output "$targetDb should contain a subset of the data from $sourceDb."
Write-Output ""
Write-Output "Next:"
Write-Output "We will run rganonymize classify to create a classification.json file, documenting the location of any PII:"
Write-Output "  rganonymize classify --database-engine SqlServer --connection-string $targetConnectionString --classification-file `"$output\classification.json`" --output-all-columns"
Write-Output "*********************************************************************************************************"
Write-Output ""

Prompt-Continue

Write-Output "Creating a classification.json file in $output"
rganonymize classify --database-engine SqlServer --connection-string=$targetConnectionString --classification-file "$output\classification.json" --output-all-columns

Write-Output ""
Write-Output "*********************************************************************************************************"
Write-Output "Observe:"
Write-Output "Review the classification.json file save at: $output"
Write-Output "This file documents any PII that has been found automatically in the $targetDb database."
Write-Output "You can tweak this file as necessary and keep it in source control to inform future masking runs."
Write-Output "You could even create CI builds that cross reference this file against your database source code,"
Write-Output "  to ensure developers always add appropriate classifications for new columns before they get"
Write-Output "  deployed to production."
Write-Output ""
Write-Output "Next:"
Write-Output "We will run the rganonymize map command to create a masking.json file, defining how the PII will be masked:"
Write-Output "  rganonymize map --classification-file `"$output\classification.json`" --masking-file `"$output\masking.json`""
Write-Output "*********************************************************************************************************"
Write-Output ""

Prompt-Continue

Write-Output "Creating a masking.json file based on contents of classification.json in $output"
rganonymize map --classification-file="$output\classification.json" --masking-file="$output\masking.json"

Write-Output ""
Write-Output "*********************************************************************************************************"
Write-Output "Observe:"
Write-Output "Review the masking.json file save at: $output"
Write-Output "This file defines how the PII found in the $targetDb database will be masked."
Write-Output "You can save this in source control, and set up an automated masking job to"
Write-Output "  create a fresh masked copy, with the latest data, on a nightly or weekly"
Write-Output "  basis, or at an appropriate point in your sprint/release cycle."
Write-Output ""
Write-Output "Next:"
Write-Output "We will run the rganonymize mask command to mask the PII in ${targetDb}:"
Write-Output "  rganonymize mask --database-engine SqlServer --connection-string $targetConnectionString --masking-file `"$output\masking.json`""
Write-Output "*********************************************************************************************************"
Write-Output ""

Prompt-Continue

Write-Output "Masking target database, based on contents of masking.json file in $output"
rganonymize mask --database-engine SqlServer --connection-string=$targetConnectionString --masking-file="$output\masking.json"

Write-Output ""
Write-Output "*********************************************************************************************************"
Write-Output "Observe:"
Write-Output "The data in the $targetDb database should now be masked."
Write-Output "Review the data in the $sourceDb and $targetDb databases. Are you happy with the way they have been subsetted and masked?"
Write-Output "Things you may like to look out for:"
Write-Output "  - Notes fields (e.g. Employees.Notes)"
Write-Output "  - Dependencies (e.g. If using the sample database, observe the Orders.ShipAddress and Customers.Address, joined on the CustomerID column in each table"
Write-Output ""
Write-Output "Additional tasks:"
Write-Output "Review both rgsubset-options.json examples in ./Setup_Files, as well as this documentation about using options files:"
Write-Output "  https://documentation.red-gate.com/testdatamanager/command-line-interface-cli/subsetting/subsetting-configuration/subsetting-configuration-file"
Write-Output "To apply a more thorough mask on the notes fields, review this documentation, and configure this project to a Lorem Ipsum"
Write-Output "  masking rule for any 'notes' fields:"
Write-Output "  - Default classifications and datasets:"
Write-Output "    https://documentation.red-gate.com/testdatamanager/command-line-interface-cli/anonymization/default-classifications-and-datasets"
Write-Output "  - Applying custom classification rules:"
Write-Output "    https://documentation.red-gate.com/testdatamanager/command-line-interface-cli/anonymization/custom-configuration/classification-rules"
Write-Output "  - Using different or custom data sets:"
Write-Output "    https://documentation.red-gate.com/testdatamanager/command-line-interface-cli/anonymization/custom-configuration/using-different-or-custom-datasets"
Write-Output ""
Write-Output "Once you have verified that all the PII has been removed, you can backup this version of"
Write-output "  the database, and share it with your developers for dev/test purposes."
Write-Output ""
Write-Output "**************************************   FINISHED!   **************************************"
Write-Output ""
Write-Output "CONGRATULATIONS!"
Write-Output "You've completed a minimal viable Test Data Manager proof of concept."
Write-Output "Next, review the following resources:"
Write-Output "  - Documentation:  https://documentation.red-gate.com/testdatamanager/command-line-interface-cli"
Write-Output "  - Training:       https://www.red-gate.com/hub/university/courses/test-data-management/cloning/overview/introduction-to-tdm"
Write-Output "Can you subset and mask one of your own databases?"
Write-Output ""
Write-Output "Want to learn more? If you have a Redgate account manager, they can help you get started."
Write-Output "Otherwise, email us, and let's start a conversation: sales@red-gate.com"
