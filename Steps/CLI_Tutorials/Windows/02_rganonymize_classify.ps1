# Classify data using rganonymize
# This script demonstrates how to run the rganonymize CLI command with example values.
# For more details, visit: https://documentation.red-gate.com/testdatamanager
#
# Key Options:
#   --database-engine: The database engine to use (e.g., SqlServer, PostgreSql).
#   --connection-string: Connection string for the database.
#   --classification-file: Path to the JSON file containing classification rules.
#   --log-level: Logging level (e.g., Verbose, Info, Error).

# Example values
$DB_ENGINE = "SqlServer"
$CONNECTION_STRING = "Server=Localhost;Database=Autopilot_Treated;Trusted_Connection=true;Trust Server Certificate=true;"
$CLASSIFICATION_FILE = "..\classification.json"
$LOG_LEVEL = "Verbose"

Write-Host "Running classification for database engine: $DB_ENGINE"

rganonymize classify `
  --database-engine $DB_ENGINE `
  --connection-string "$CONNECTION_STRING" `
  --classification-file $CLASSIFICATION_FILE `
  --output-all-columns `
  --log-level $LOG_LEVEL