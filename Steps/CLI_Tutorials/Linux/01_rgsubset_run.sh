#!/bin/bash
# filepath: c:\Redgate\GIT\Repos\GitHub\Autopilot\Development\TDM-Autopilot\Steps\Manual_CLI\Linux\01_rgsubset.sh

# Subset data using rgsubset
# This script demonstrates how to run the rgsubset CLI command with example values.
# For more details, visit: https://documentation.red-gate.com/testdatamanager
#
# Key Options:
#   --database-engine: The database engine to use (e.g., SqlServer, PostgreSql).
#   Connection String Documentation - https://documentation.red-gate.com/testdatamanager/command-line-interface-cli/database-connection-string-formats
#   --source-connection-string: Connection string for the source database.
#   --target-connection-string: Connection string for the target database.
#   --options-file: Path to the JSON file containing subset options.
#   --log-level: Logging level (e.g., Verbose, Info, Error).

# Example Offline Licensing https://documentation.red-gate.com/testdatamanager/getting-started/licensing/activating-your-license # 
# REDGATE_LICENSING_PAT_EMAIL=""
# REDGATE_LICENSING_PAT_TOKEN=""


# Example values
DB_ENGINE="SqlServer"
SOURCE_CONN_STRING="Server=Localhost;Database=AutopilotProd_FullRestore;User Id=TDMUser;Password=Password123;Trust Server Certificate=true;"
TARGET_CONN_STRING="Server=Localhost;Database=Autopilot_Treated;User Id=TDMUser;Password=Password123;Trust Server Certificate=true;"
OPTIONS_FILE="../subset-options.json"
OUTPUT_FILE="../subset_log.json"
# Perform a dry-run with no subsetting applied by turning to true
DRY_RUN="false"
# Set the log level to Verbose for detailed output
LOG_LEVEL="Verbose"


echo "Running subset for database engine: $DB_ENGINE"

rgsubset run \
  --database-engine "$DB_ENGINE" \
  --source-connection-string "$SOURCE_CONN_STRING" \
  --target-connection-string "$TARGET_CONN_STRING" \
  --target-database-write-mode Overwrite \
  --options-file "$OPTIONS_FILE" \
  --dry-run "$DRY_RUN" \
  --log-level "$LOG_LEVEL" \
  --output-file "$OUTPUT_FILE"