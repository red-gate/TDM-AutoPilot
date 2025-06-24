#!/bin/bash
# filepath:

# Mask data using rganonymize
# This script demonstrates how to run the rganonymize CLI command with example values.
# For more details, visit: https://documentation.red-gate.com/testdatamanager
#
# Key Options:
#   --database-engine: The database engine to use (e.g., SqlServer, PostgreSql).
#   --connection-string: Connection string for the database.
#   --masking-file: Path to the JSON file containing masking rules.
#   --log-level: Logging level (e.g., Verbose, Info, Error).

# Example Offline Licensing https://documentation.red-gate.com/testdatamanager/getting-started/licensing/activating-your-license # 
#REDGATE_LICENSING_PAT_EMAIL=""
#REDGATE_LICENSING_PAT_TOKEN=""

# Example values
DB_ENGINE="SqlServer"
CONNECTION_STRING="Server=Localhost;Database=Autopilot_Treated;User Id=TDMUser;Password=Password123;Trust Server Certificate=true;"
MASKING_FILE="../masking.json"
OPTIONS_FILE="../masking-options.json"
DETERMINISTIC_SEED="my-secret-seed" # Can be any string, but must be at least 4 characters long
LOG_LEVEL="Verbose"

echo "Running masking for database engine: $DB_ENGINE"

rganonymize mask \
  --database-engine "$DB_ENGINE" \
  --connection-string "$CONNECTION_STRING" \
  --masking-file "$MASKING_FILE" \
  --options-file "$OPTIONS_FILE" \
  --deterministic-seed "$DETERMINISTIC_SEED" \
  --log-level "$LOG_LEVEL"